// Publikasikan update plugin ke server (Cloudflare): hitung SHA-256 .rbz lalu unggah ke server lisensi.
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
let filePath = null;
const args = [];
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--dry-run') dry = true;
  else if (a === '--plain') plain = true;
  else if (a === '--github') github = true;
  else if (a === '--file') { filePath = argv[++i]; if (!filePath) die('--file butuh path ke .rbz'); }
  else if (a.startsWith('--')) die('Opsi tidak dikenal: ' + a);
  else args.push(a);
}

if (github && !filePath) die('--github hanya bisa bersama --file (paket hasil portal).');
if (github && plain) die('--github tidak boleh bersama --plain: GitHub bersifat publik, jangan mengunggah kode terbuka ke sana.');

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

async function ghApi(method, apiUrl, token, body, headers) {
  const res = await fetch(apiUrl, {
    method,
    headers: { Authorization: 'Bearer ' + token, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'boosok-publish-release', ...headers },
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
  const res = await fetch(`${url}/admin/release?version=${encodeURIComponent(version)}&changelog=${encodeURIComponent(changelog)}`, {
    method: 'PUT',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/octet-stream' },
    body: buf
  });
  const out = await res.json().catch(() => ({}));
  if (!res.ok || !out.ok) die('GAGAL mengunggah: ' + res.status + ' ' + JSON.stringify(out));
  console.log(out.sha256 === sha ? '\nBERHASIL diunggah. Checksum di server cocok.' : '\nDiunggah, tetapi checksum berbeda dari lokal!');
  console.log('Versi terbaru di server: ' + out.version);
  if (github) await publishGithub();
})().catch((e) => die('GAGAL: ' + e.message));
