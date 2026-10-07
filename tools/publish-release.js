// Publikasikan update plugin ke server (Cloudflare): enkripsi .rbz lalu unggah ke server lisensi.
//
// Alur rilis (paket terenkripsi .rbe):
//   1. Naikkan PLUGIN_VERSION di src\boosok_tools.rb, jalankan check_sketchup.ps1
//   2. node tools\publish-release.js --dry-run                 -> membangun .rbz MENTAH di dist\ (jangan dipublikasikan)
//   3. Unggah .rbz mentah itu ke portal Extension Signing, unduh hasilnya (terenkripsi .rbe + bertanda tangan)
//   4. node tools\publish-release.js --file "C:\path\hasil_portal.rbz" "catatan perubahan"
//
//   --file <rbz>   unggah .rbz hasil portal (diperiksa dulu: harus berisi .rbe, tanpa .rb selain boosok_tools.rb,
//                  dan versinya harus sama dengan PLUGIN_VERSION di src)
//   --dry-run      tanpa --file: bangun .rbz mentah di dist\. Dengan --file: hanya memeriksa, tidak mengunggah
//   --plain        izinkan mengunggah paket tidak terenkripsi (bangun dari src\ atau --file yang masih .rb)
//   --github       setelah server, terbitkan juga ke GitHub Release + perbarui the_bosok\version.json supaya pengguna lama
//                  (v1.6.x ke bawah, yang hanya membaca GitHub) tetap mendapat update. Wajib dengan --file, tidak boleh
//                  dengan --plain. Menjalankan `git push` (commit yang belum terkirim ikut), membuat release, lalu commit
//                  + push version.json. Token GitHub: env GITHUB_TOKEN, atau `gh auth token`, atau kredensial git.
//   --no-encrypt   lewati enkripsi payload sebelum dikirim ke server (tidak direkomendasikan, hanya untuk debug)
//
// ENKRIPSI PAYLOAD (default aktif):
//   Sebelum dikirim ke server, isi .rbz dibungkus dengan AES-256-GCM menggunakan kunci enkripsi yang
//   dibaca dari server\.secrets\encrypt_key.txt (hex 64 karakter = 32 byte). Server wajib mendekripsi
//   sebelum menyimpan. Header tambahan dikirim: X-IV (hex 24 karakter) dan X-Auth-Tag (hex 32 karakter).
//   Selain itu, HMAC-SHA256 dari payload asli (sebelum enkripsi) dikirim di header X-Content-Hmac
//   menggunakan kunci HMAC yang dibaca dari server\.secrets\hmac_key.txt.
//
// Catatan perubahan opsional; kalau kosong dipakai pesan commit terakhir. Versi diambil dari PLUGIN_VERSION di
// src\boosok_tools.rb. Pengguna yang berlisensi aktif akan melihat update ini lewat tombol "Cek update" di Boosok Tools.
// Token admin dibaca dari server\.secrets\admin_token.txt. Hanya untuk Windows (memakai tar.exe bawaan Windows).

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const root = path.resolve(__dirname, '..');
const url = (process.env.LICENSE_URL || 'https://boosok-license.boosok.workers.dev').replace(/\/+$/, '');
const tar = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'tar.exe');

function die(msg) { console.error('\n' + msg); process.exit(1); }

let dry = false;
let plain = false;
let github = false;
let noEncrypt = false;
let filePath = null;
const args = [];
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--dry-run') dry = true;
  else if (a === '--plain') plain = true;
  else if (a === '--github') github = true;
  else if (a === '--no-encrypt') noEncrypt = true;
  else if (a === '--file') { filePath = argv[++i]; if (!filePath) die('--file butuh path ke .rbz'); }
  else if (a.startsWith('--')) die('Opsi tidak dikenal: ' + a);
  else args.push(a);
}

if (github && !filePath) die('--github hanya bisa bersama --file (paket hasil portal).');
if (github && plain) die('--github tidak boleh bersama --plain: GitHub bersifat publik, jangan mengunggah kode terbuka ke sana.');
if (noEncrypt) console.warn('\n⚠️  --no-encrypt aktif: payload dikirim tanpa enkripsi. Hanya untuk debug!\n');

const main = fs.readFileSync(path.join(root, 'src', 'boosok_tools.rb'), 'utf8');
const version = (main.match(/PLUGIN_VERSION\s*=\s*"([^"]+)"/) || [])[1];
if (!version) die('PLUGIN_VERSION tidak ditemukan di src\\boosok_tools.rb');

let changelog = args.join(' ').trim();
if (!changelog) {
  try { changelog = execFileSync('git', ['log', '-1', '--pretty=%s'], { cwd: root, encoding: 'utf8' }).trim(); } catch (e) { changelog = ''; }
}

let rbzPath;
if (filePath) {
  // .rbz hasil portal: periksa isinya sebelum boleh diunggah
  rbzPath = path.resolve(filePath);
  if (!fs.existsSync(rbzPath)) die('File tidak ditemukan: ' + rbzPath);
  if (!/\.rbz$/i.test(rbzPath)) die('File harus berekstensi .rbz: ' + rbzPath);

  let entries;
  try {
    entries = execFileSync(tar, ['-tf', rbzPath], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })
      .split(/\r?\n/).map((e) => e.trim().replace(/\\/g, '/').replace(/^\.\//, '')).filter(Boolean);
  } catch (e) { die('Gagal membaca isi .rbz (bukan zip yang valid?): ' + e.message); }

  const plainRb = entries.filter((e) => /\.rb$/i.test(e) && e.toLowerCase() !== 'boosok_tools.rb');
  const rbe = entries.filter((e) => /\.rbe$/i.test(e));
  if (!plain && (plainRb.length || !rbe.length)) {
    die('Paket ini TIDAK terenkripsi: ' + (rbe.length ? '' : 'tidak ada file .rbe; ') +
        (plainRb.length ? plainRb.length + ' file .rb terbuka (mis. ' + plainRb.slice(0, 3).join(', ') + ')' : '') +
        '\nIni bukan hasil portal Extension Signing. Unggah tetap? Tambahkan --plain.');
  }

  // Versi dibaca dari file root (tidak dienkripsi) dan harus sama dengan src\, supaya tidak salah mengunggah paket lama
  let rootRb = null;
  try { rootRb = execFileSync(tar, ['-xOf', rbzPath, 'boosok_tools.rb'], { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 }); } catch (e) { /* ditangani di bawah */ }
  const pkgVersion = rootRb && (rootRb.match(/PLUGIN_VERSION\s*=\s*"([^"]+)"/) || [])[1];
  if (!pkgVersion) die('boosok_tools.rb di dalam .rbz tidak ditemukan / tidak memuat PLUGIN_VERSION. Struktur zip dari portal berubah?');
  if (pkgVersion !== version) die(`Versi tidak cocok: .rbz berisi ${pkgVersion}, src\\ berisi ${version}. Unggah ulang .rbz yang benar ke portal.`);
  // File root tidak dienkripsi dan tidak diubah portal, jadi harus identik dengan src\. Berbeda = kode berubah sesudah
  // .rbz mentah dibangun / dikirim ke portal (versi sama, jadi pemeriksaan versi saja tidak menangkapnya).
  const norm = (s) => s.replace(/\r\n/g, '\n').trimEnd();
  if (norm(rootRb) !== norm(main)) die('boosok_tools.rb di dalam .rbz BERBEDA dari src\\boosok_tools.rb: kode berubah setelah paket dibangun.\n' +
      'Jalankan lagi `node tools\\publish-release.js --dry-run`, unggah .rbz mentah yang baru ke portal, lalu unduh hasilnya.');
} else {
  if (!dry && !plain) {
    die('Tanpa --file, skrip hanya boleh membangun paket MENTAH (kode terbuka). Untuk rilis:\n' +
        '  1) node tools\\publish-release.js --dry-run     (bangun .rbz mentah di dist\\)\n' +
        '  2) unggah ke portal Extension Signing, unduh hasilnya\n' +
        '  3) node tools\\publish-release.js --file "hasil_portal.rbz"\n' +
        'Atau tambahkan --plain bila memang sengaja merilis tanpa enkripsi.');
  }
  // Bangun .rbz (zip): isi src\ langsung di root zip, tanpa file buatan plugin saat berjalan
  const dist = path.join(root, 'dist');
  fs.mkdirSync(dist, { recursive: true });
  const zipPath = path.join(dist, `boosok_tools_v${version}.zip`);
  rbzPath = path.join(dist, `boosok_tools_v${version}.rbz`);
  for (const f of [zipPath, rbzPath]) if (fs.existsSync(f)) fs.unlinkSync(f);
  const excludes = ['strings.js', 'session.js', 'titlebar.log', '.dev_mode'].flatMap((n) => ['--exclude', n]);
  execFileSync(tar, ['-a', '-cf', zipPath, ...excludes, '-C', path.join(root, 'src'), 'boosok_tools.rb', 'boosok_tools']);
  fs.renameSync(zipPath, rbzPath);
}

const buf = fs.readFileSync(rbzPath);
const sha = crypto.createHash('sha256').update(buf).digest('hex');
console.log(`Versi      : ${version}`);
console.log(`File       : ${rbzPath} (${(buf.length / 1024).toFixed(0)} KB)${filePath ? '  [hasil portal, terenkripsi]' : '  [MENTAH]'}`);
console.log(`SHA-256    : ${sha}`);
console.log(`Changelog  : ${changelog || '(kosong)'}`);
if (dry) {
  console.log(filePath ? '\n--dry-run: paket lolos pemeriksaan, tidak diunggah.'
    : '\n--dry-run: tidak diunggah. File mentah ini dikirim ke portal untuk dienkripsi, JANGAN dipublikasikan.');
  if (github) console.log(`Dengan --github (tanpa --dry-run): git push, release v${version} di ${repoSlug()}, lalu version.json di-commit + push.`);
  process.exit(0);
}

const tokenFile = path.join(root, 'server', '.secrets', 'admin_token.txt');
if (!fs.existsSync(tokenFile)) die('Token admin tidak ditemukan: ' + tokenFile);
const token = fs.readFileSync(tokenFile, 'utf8').trim();

// ── Enkripsi payload (AES-256-GCM) + HMAC-SHA256 ────────────────────────────
//
// Struktur kunci:
//   server/.secrets/encrypt_key.txt  → 64 hex chars (32 byte), kunci AES-256-GCM
//   server/.secrets/hmac_key.txt     → 64 hex chars (32 byte), kunci HMAC-SHA256
//
// Format yang dikirim ke server:
//   Body          : ciphertext (Buffer)
//   X-IV          : IV hex (24 chars = 12 byte, acak per upload)
//   X-Auth-Tag    : GCM auth tag hex (32 chars = 16 byte)
//   X-Content-Hmac: HMAC-SHA256 dari plaintext asli (buf), hex 64 chars
//   X-Sha256      : SHA-256 dari plaintext asli (untuk referensi / double-check)
//
// Server perlu mendekripsi ciphertext dengan kunci + IV + auth-tag yang sama,
// lalu verifikasi HMAC sebelum menyimpan file. Kalau verifikasi gagal → tolak.

function readSecretKey(filename, label) {
  const p = path.join(root, 'server', '.secrets', filename);
  if (!fs.existsSync(p)) {
    die(`Kunci ${label} tidak ditemukan: ${p}\n` +
        `Buat file tersebut berisi 64 karakter hex (32 byte acak):\n` +
        `  node -e "console.log(require('crypto').randomBytes(32).toString('hex'))" > ${p}`);
  }
  const hex = fs.readFileSync(p, 'utf8').trim();
  if (!/^[0-9a-fA-F]{64}$/.test(hex)) die(`Format ${label} salah: harus 64 karakter hex di ${p}`);
  return Buffer.from(hex, 'hex');
}

function encryptPayload(plainBuf) {
  const key = readSecretKey('encrypt_key.txt', 'enkripsi AES-256-GCM');
  const hmacKey = readSecretKey('hmac_key.txt', 'HMAC-SHA256');

  const iv = crypto.randomBytes(12); // 96-bit IV (standar GCM)
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([cipher.update(plainBuf), cipher.final()]);
  const authTag = cipher.getAuthTag(); // 16 byte

  const hmac = crypto.createHmac('sha256', hmacKey).update(plainBuf).digest();

  console.log(`Enkripsi   : AES-256-GCM | IV: ${iv.toString('hex')} | Tag: ${authTag.toString('hex').slice(0, 8)}...`);
  console.log(`HMAC-SHA256: ${hmac.toString('hex').slice(0, 16)}...`);

  return { encrypted, iv, authTag, hmac };
}

// ── GitHub (untuk pengguna lama yang hanya membaca version.json di GitHub) ──
function git(gitArgs, opts = {}) {
  return execFileSync('git', gitArgs, { cwd: root, encoding: 'utf8', ...opts }).trim();
}

function repoSlug() {
  try {
    const m = git(['remote', 'get-url', 'origin']).match(/github\.com[:/]+([^/]+\/[^/]+?)(?:\.git)?$/);
    if (m) return m[1];
  } catch (e) { /* pakai bawaan */ }
  return 'muhqosob/boosok-tools';
}

function githubToken() {
  if (process.env.GITHUB_TOKEN) return process.env.GITHUB_TOKEN.trim();
  try { const t = execFileSync('gh', ['auth', 'token'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); if (t) return t; } catch (e) { /* gh tidak ada */ }
  try {
    const out = execFileSync('git', ['credential', 'fill'], { cwd: root, encoding: 'utf8', input: 'protocol=https\nhost=github.com\n\n', stdio: ['pipe', 'pipe', 'ignore'], env: { ...process.env, GIT_TERMINAL_PROMPT: '0' } });
    const m = out.match(/^password=(.+)$/m);
    if (m) return m[1].trim();
  } catch (e) { /* tidak ada kredensial tersimpan */ }
  return null;
}

async function ghApi(method, apiUrl, ghToken, body, headers) {
  const res = await fetch(apiUrl, {
    method,
    headers: { Authorization: 'Bearer ' + ghToken, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'boosok-publish-release', ...headers },
    body
  });
  const text = await res.text();
  let data = null;
  try { data = JSON.parse(text); } catch (e) { /* bukan JSON */ }
  if (!res.ok) { const err = new Error(`${method} ${apiUrl} -> ${res.status} ${(data && data.message) || text.slice(0, 200)}`); err.status = res.status; throw err; }
  return data;
}

async function publishGithub() {
  const ghToken = githubToken();
  if (!ghToken) die('Token GitHub tidak ditemukan. Isi env GITHUB_TOKEN (PAT dengan akses repo), pasang gh lalu `gh auth login`, atau login git ke github.com.');
  if (git(['status', '--porcelain', '--untracked-files=no'])) die('Ada perubahan yang belum di-commit. Commit dulu, supaya tag release menunjuk ke kode yang benar.');

  const slug = repoSlug();
  const api = `https://api.github.com/repos/${slug}`;
  const tag = 'v' + version;
  const assetName = `boosok_tools_v${version}.rbz`;

  console.log('\n[GitHub] git push ...');
  execFileSync('git', ['push'], { cwd: root, stdio: 'inherit' });
  const head = git(['rev-parse', 'HEAD']);

  // Release sudah ada (mis. mengulang setelah gagal di tengah jalan): dipakai ulang, aset lama diganti
  let rel = null;
  try { rel = await ghApi('GET', `${api}/releases/tags/${tag}`, ghToken); } catch (e) { if (e.status !== 404) throw e; }
  if (!rel) {
    rel = await ghApi('POST', `${api}/releases`, ghToken, JSON.stringify({ tag_name: tag, target_commitish: head, name: tag, body: changelog }), { 'Content-Type': 'application/json' });
    console.log(`[GitHub] release ${tag} dibuat.`);
  } else {
    console.log(`[GitHub] release ${tag} sudah ada, dipakai ulang.`);
  }
  for (const a of rel.assets || []) {
    if (a.name === assetName) await ghApi('DELETE', `${api}/releases/assets/${a.id}`, ghToken);
  }
  const asset = await ghApi('POST', `https://uploads.github.com/repos/${slug}/releases/${rel.id}/assets?name=${encodeURIComponent(assetName)}`, ghToken, buf, { 'Content-Type': 'application/octet-stream' });
  console.log(`[GitHub] aset diunggah: ${asset.browser_download_url}`);

  // version.json diperbarui SETELAH aset ada, supaya pengguna tidak mendapat link 404. Path & bentuknya dibaca
  // semua versi yang sudah terpasang, jangan diubah.
  fs.writeFileSync(path.join(root, 'the_bosok', 'version.json'),
    JSON.stringify({ version, download_url: asset.browser_download_url, changelog, sha256: sha }, null, 2));
  git(['add', 'the_bosok/version.json']);
  git(['commit', '-m', `chore(release): bump ${tag} [skip ci]`]);
  execFileSync('git', ['push'], { cwd: root, stdio: 'inherit' });
  console.log(`[GitHub] version.json diperbarui ke ${version}.`);
}

(async () => {
  // Siapkan body + headers berdasarkan mode enkripsi
  let uploadBody = buf;
  const extraHeaders = {
    'X-Sha256': sha, // SHA-256 plaintext, selalu dikirim
  };

  if (!noEncrypt) {
    const { encrypted, iv, authTag, hmac } = encryptPayload(buf);
    uploadBody = encrypted;
    extraHeaders['X-IV'] = iv.toString('hex');
    extraHeaders['X-Auth-Tag'] = authTag.toString('hex');
    extraHeaders['X-Content-Hmac'] = hmac.toString('hex');
    extraHeaders['X-Encrypted'] = '1'; // sinyal ke server bahwa body dienkripsi
    console.log(`Upload     : ${(encrypted.length / 1024).toFixed(0)} KB (terenkripsi AES-256-GCM)`);
  } else {
    extraHeaders['X-Encrypted'] = '0';
    console.log(`Upload     : ${(buf.length / 1024).toFixed(0)} KB (TIDAK terenkripsi, --no-encrypt aktif)`);
  }

  const res = await fetch(`${url}/admin/release?version=${encodeURIComponent(version)}&changelog=${encodeURIComponent(changelog)}`, {
    method: 'PUT',
    headers: {
      Authorization: 'Bearer ' + token,
      'Content-Type': 'application/octet-stream',
      ...extraHeaders,
    },
    body: uploadBody,
  });
  const out = await res.json().catch(() => ({}));
  if (!res.ok || !out.ok) die('GAGAL mengunggah: ' + res.status + ' ' + JSON.stringify(out));
  console.log(out.sha256 === sha ? '\nBERHASIL diunggah. Checksum di server cocok.' : '\nDiunggah, tetapi checksum berbeda dari lokal!');
  console.log('Versi terbaru di server: ' + out.version);
  if (github) await publishGithub();
})().catch((e) => die('GAGAL: ' + e.message));
