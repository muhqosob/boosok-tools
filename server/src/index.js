// Server lisensi Boosok Tools (Cloudflare Workers + D1).
//
// Alur:
//   POST /activate {key, hwid}  -> mengikat key ke perangkat (maks. max_devices), membalas token bertanda tangan
//   POST /check    {key, hwid}  -> memperbarui token untuk perangkat yang sudah terikat (dipanggil berkala oleh plugin)
//   POST /release  {key, hwid}  -> melepas perangkat dari key (pindah komputer)
//   /admin/*  (header Authorization: Bearer <ADMIN_TOKEN>)
//     POST /admin/keys {name, phone, note, max_devices}   -> buat key baru
//     GET  /admin/keys                       -> daftar key + perangkatnya
//     POST /admin/revoke {key, revoked}      -> cabut / pulihkan key
//     POST /admin/unbind {key, hwid}         -> lepas satu perangkat
//     POST /admin/update {key, name, phone, note, max_devices}
//
// Token = {payload, sig}. payload = string JSON; sig = RSA-SHA256 (PKCS#1 v1.5) base64 atas string payload itu persis.
// Plugin hanya menyimpan KUNCI PUBLIK, jadi tidak ada rahasia di dalam plugin.

const GRACE_DAYS = 14;               // masa toleransi offline (hari) yang tertulis di token
const KEY_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization'
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json', ...CORS } });
}

function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesToB64(buf) {
  let s = '';
  const bytes = new Uint8Array(buf);
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}

let cachedKey = null;
async function signingKey(env) {
  if (!cachedKey) {
    cachedKey = await crypto.subtle.importKey('pkcs8', b64ToBytes(env.PRIVATE_KEY_B64.trim()),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  }
  return cachedKey;
}

async function makeToken(env, key, hwid, used, max) {
  const now = Math.floor(Date.now() / 1000);
  const payload = JSON.stringify({ v: 1, k: key, hw: hwid, iat: now, exp: now + GRACE_DAYS * 86400, used: used, max: max });
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', await signingKey(env), new TextEncoder().encode(payload));
  return { payload: payload, sig: bytesToB64(sig) };
}

function normKey(k) {
  const clean = String(k || '').toUpperCase().replace(/[^0-9A-Z]/g, '');
  if (clean.length !== 20) return null;
  return clean.match(/.{5}/g).join('-');
}

function normHw(h) {
  const clean = String(h || '').toUpperCase().replace(/[^0-9A-Z]/g, '');
  if (clean.length < 8 || clean.length > 40) return null;
  return clean.match(/.{1,4}/g).join('-');
}

function randomKey() {
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  let raw = '';
  for (let i = 0; i < 20; i++) raw += KEY_ALPHABET[bytes[i] % KEY_ALPHABET.length];
  return raw.match(/.{5}/g).join('-');
}

async function readBody(request) {
  try { return await request.json(); } catch (e) { return {}; }
}

async function deviceCount(env, key) {
  const row = await env.DB.prepare('SELECT COUNT(*) AS n FROM devices WHERE key = ?').bind(key).first();
  return row ? row.n : 0;
}

// ── Endpoint untuk plugin ──
async function handleClient(path, request, env) {
  const body = await readBody(request);
  const key = normKey(body.key);
  const hwid = normHw(body.hwid);
  if (!key || !hwid) return json({ ok: false, error: 'bad_request' }, 400);

  const row = await env.DB.prepare('SELECT key, max_devices, revoked FROM keys WHERE key = ?').bind(key).first();
  if (!row) return json({ ok: false, error: 'invalid_key' }, 404);
  if (row.revoked) return json({ ok: false, error: 'revoked' }, 403);

  const now = Math.floor(Date.now() / 1000);
  const bound = await env.DB.prepare('SELECT hwid FROM devices WHERE key = ? AND hwid = ?').bind(key, hwid).first();

  if (path === '/release') {
    if (bound) await env.DB.prepare('DELETE FROM devices WHERE key = ? AND hwid = ?').bind(key, hwid).run();
    return json({ ok: true });
  }

  if (path === '/check') {
    if (!bound) return json({ ok: false, error: 'not_bound' }, 403);
    await env.DB.prepare('UPDATE devices SET last_seen = ? WHERE key = ? AND hwid = ?').bind(now, key, hwid).run();
    const used = await deviceCount(env, key);
    return json({ ok: true, token: await makeToken(env, key, hwid, used, row.max_devices) });
  }

  // /activate
  if (!bound) {
    const used = await deviceCount(env, key);
    if (used >= row.max_devices) return json({ ok: false, error: 'device_limit', used: used, max: row.max_devices }, 409);
    await env.DB.prepare('INSERT INTO devices (key, hwid, first_seen, last_seen) VALUES (?, ?, ?, ?)').bind(key, hwid, now, now).run();
  } else {
    await env.DB.prepare('UPDATE devices SET last_seen = ? WHERE key = ? AND hwid = ?').bind(now, key, hwid).run();
  }
  const used = await deviceCount(env, key);
  return json({ ok: true, token: await makeToken(env, key, hwid, used, row.max_devices) });
}

// ── Update plugin (file .rbz disimpan di Workers KV) ──
const VERSION_RE = /^[0-9A-Za-z][0-9A-Za-z.\-]{0,30}$/;

async function handleUpdate(path, request, env) {
  const url = new URL(request.url);
  if (path === '/update/latest') {
    const meta = await env.RELEASES.get('latest', 'json');
    if (!meta) return json({ ok: false, error: 'no_release' }, 404);
    // Bentuk sama dengan version.json di GitHub, supaya updater plugin memakai kode yang sama
    return json({ ...meta, ok: true, download_url: url.origin + '/update/download?version=' + encodeURIComponent(meta.version) });
  }

  // /update/download: hanya untuk key aktif yang perangkatnya terikat (sama seperti /check)
  const key = normKey(request.headers.get('X-License-Key'));
  const hwid = normHw(request.headers.get('X-Hardware-Id'));
  if (!key || !hwid) return json({ ok: false, error: 'bad_request' }, 400);
  const row = await env.DB.prepare('SELECT revoked FROM keys WHERE key = ?').bind(key).first();
  if (!row) return json({ ok: false, error: 'invalid_key' }, 404);
  if (row.revoked) return json({ ok: false, error: 'revoked' }, 403);
  const bound = await env.DB.prepare('SELECT hwid FROM devices WHERE key = ? AND hwid = ?').bind(key, hwid).first();
  if (!bound) return json({ ok: false, error: 'not_bound' }, 403);

  const meta = await env.RELEASES.get('latest', 'json');
  const version = url.searchParams.get('version') || (meta && meta.version);
  if (!version || !VERSION_RE.test(version)) return json({ ok: false, error: 'bad_request' }, 400);
  const buf = await env.RELEASES.get('rbz:' + version, 'arrayBuffer');
  if (!buf) return json({ ok: false, error: 'no_release' }, 404);
  await env.DB.prepare('UPDATE devices SET last_seen = ? WHERE key = ? AND hwid = ?').bind(Math.floor(Date.now() / 1000), key, hwid).run();
  return new Response(buf, { headers: { 'Content-Type': 'application/octet-stream', 'Content-Length': String(buf.byteLength), ...CORS } });
}

// Admin: PUT /admin/release?version=1.7.0&changelog=...  (body = isi .rbz)   DELETE /admin/release?version=...
async function handleRelease(request, env) {
  const url = new URL(request.url);
  const version = url.searchParams.get('version') || '';
  if (!VERSION_RE.test(version)) return json({ ok: false, error: 'bad_version' }, 400);

  if (request.method === 'DELETE') {
    await env.RELEASES.delete('rbz:' + version);
    const latest = await env.RELEASES.get('latest', 'json');
    if (latest && latest.version === version) await env.RELEASES.delete('latest');
    return json({ ok: true });
  }
  if (request.method !== 'PUT') return json({ ok: false, error: 'not_found' }, 404);

  const buf = await request.arrayBuffer();
  if (buf.byteLength < 1000 || buf.byteLength > 24 * 1024 * 1024) return json({ ok: false, error: 'bad_size', size: buf.byteLength }, 400);
  const digest = await crypto.subtle.digest('SHA-256', buf);
  const sha256 = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
  const meta = { version: version, changelog: (url.searchParams.get('changelog') || '').slice(0, 4000), sha256: sha256, size: buf.byteLength,
    published_at: Math.floor(Date.now() / 1000) };
  await env.RELEASES.put('rbz:' + version, buf);
  await env.RELEASES.put('latest', JSON.stringify(meta));
  return json({ ok: true, ...meta });
}

// ── Endpoint admin ──
async function handleAdmin(path, request, env) {
  const auth = request.headers.get('Authorization') || '';
  const adminToken = String(env.ADMIN_TOKEN || '').trim();
  if (!adminToken || auth !== 'Bearer ' + adminToken) return json({ ok: false, error: 'unauthorized' }, 401);

  if (path === '/admin/release') return await handleRelease(request, env);

  const now = Math.floor(Date.now() / 1000);
  if (path === '/admin/keys' && request.method === 'GET') {
    const keys = (await env.DB.prepare('SELECT key, name, phone, note, max_devices, revoked, created_at FROM keys ORDER BY created_at DESC').all()).results;
    const devs = (await env.DB.prepare('SELECT key, hwid, first_seen, last_seen FROM devices ORDER BY first_seen').all()).results;
    return json({ ok: true, keys: keys.map((k) => ({ ...k, devices: devs.filter((d) => d.key === k.key) })) });
  }

  const body = await readBody(request);
  if (path === '/admin/keys') {
    const max = Math.max(1, Math.min(10, parseInt(body.max_devices, 10) || 1));
    const key = randomKey();
    await env.DB.prepare('INSERT INTO keys (key, name, phone, note, max_devices, revoked, created_at) VALUES (?, ?, ?, ?, ?, 0, ?)')
      .bind(key, String(body.name || '').slice(0, 100), String(body.phone || '').replace(/[^0-9+]/g, '').slice(0, 20),
        String(body.note || '').slice(0, 200), max, now).run();
    return json({ ok: true, key: key, max_devices: max });
  }

  const key = normKey(body.key);
  if (!key) return json({ ok: false, error: 'bad_request' }, 400);
  if (path === '/admin/revoke') {
    await env.DB.prepare('UPDATE keys SET revoked = ? WHERE key = ?').bind(body.revoked === false ? 0 : 1, key).run();
    return json({ ok: true });
  }
  if (path === '/admin/unbind') {
    const hw = normHw(body.hwid);
    if (!hw) return json({ ok: false, error: 'bad_request' }, 400);
    await env.DB.prepare('DELETE FROM devices WHERE key = ? AND hwid = ?').bind(key, hw).run();
    return json({ ok: true });
  }
  if (path === '/admin/update') {
    if (body.max_devices !== undefined) {
      await env.DB.prepare('UPDATE keys SET max_devices = ? WHERE key = ?').bind(Math.max(1, Math.min(10, parseInt(body.max_devices, 10) || 1)), key).run();
    }
    if (body.note !== undefined) await env.DB.prepare('UPDATE keys SET note = ? WHERE key = ?').bind(String(body.note).slice(0, 200), key).run();
    if (body.name !== undefined) await env.DB.prepare('UPDATE keys SET name = ? WHERE key = ?').bind(String(body.name).slice(0, 100), key).run();
    if (body.phone !== undefined) await env.DB.prepare('UPDATE keys SET phone = ? WHERE key = ?').bind(String(body.phone).replace(/[^0-9+]/g, '').slice(0, 20), key).run();
    return json({ ok: true });
  }
  return json({ ok: false, error: 'not_found' }, 404);
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
    const path = new URL(request.url).pathname.replace(/\/+$/, '') || '/';
    try {
      if (path === '/') return json({ ok: true, service: 'boosok-license' });
      if (path.startsWith('/admin')) return await handleAdmin(path, request, env);
      if (request.method === 'GET' && ['/update/latest', '/update/download'].includes(path)) return await handleUpdate(path, request, env);
      if (request.method === 'POST' && ['/activate', '/check', '/release'].includes(path)) return await handleClient(path, request, env);
      return json({ ok: false, error: 'not_found' }, 404);
    } catch (e) {
      return json({ ok: false, error: 'server_error', message: String(e && e.message || e) }, 500);
    }
  }
};
