// Publikasikan update plugin ke server (Cloudflare): bangun .rbz dari src/, hitung SHA-256, unggah ke server lisensi.
//
//   node tools\publish-release.js "catatan perubahan"      (catatan opsional; kalau kosong dipakai pesan commit terakhir)
//   node tools\publish-release.js --dry-run                 (hanya membangun .rbz di dist\, tidak mengunggah)
//
// Versi diambil dari PLUGIN_VERSION di src\boosok_tools.rb. Pengguna yang berlisensi aktif akan melihat update ini
// lewat tombol "Cek update" di Boosok Tools. Token admin dibaca dari server\.secrets\admin_token.txt.
// Hanya untuk Windows (memakai tar.exe bawaan Windows untuk membuat zip).
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const root = path.resolve(__dirname, '..');
const url = (process.env.LICENSE_URL || 'https://boosok-license.boosok.workers.dev').replace(/\/+$/, '');
const dry = process.argv.includes('--dry-run');
const args = process.argv.slice(2).filter((a) => a !== '--dry-run');

const main = fs.readFileSync(path.join(root, 'src', 'boosok_tools.rb'), 'utf8');
const version = (main.match(/PLUGIN_VERSION\s*=\s*"([^"]+)"/) || [])[1];
if (!version) { console.error('PLUGIN_VERSION tidak ditemukan di src\\boosok_tools.rb'); process.exit(1); }

let changelog = args.join(' ').trim();
if (!changelog) {
  try { changelog = execFileSync('git', ['log', '-1', '--pretty=%s'], { cwd: root, encoding: 'utf8' }).trim(); } catch (e) { changelog = ''; }
}

// Bangun .rbz (zip): isi src\ langsung di root zip, tanpa file buatan plugin saat berjalan
const dist = path.join(root, 'dist');
fs.mkdirSync(dist, { recursive: true });
const zipPath = path.join(dist, `boosok_tools_v${version}.zip`);
const rbzPath = path.join(dist, `boosok_tools_v${version}.rbz`);
for (const f of [zipPath, rbzPath]) if (fs.existsSync(f)) fs.unlinkSync(f);
const tar = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'tar.exe');
const excludes = ['strings.js', 'session.js', 'titlebar.log', '.dev_mode'].flatMap((n) => ['--exclude', n]);
execFileSync(tar, ['-a', '-cf', zipPath, ...excludes, '-C', path.join(root, 'src'), 'boosok_tools.rb', 'boosok_tools']);
fs.renameSync(zipPath, rbzPath);

const buf = fs.readFileSync(rbzPath);
const sha = crypto.createHash('sha256').update(buf).digest('hex');
console.log(`Versi      : ${version}`);
console.log(`File       : ${rbzPath} (${(buf.length / 1024).toFixed(0)} KB)`);
console.log(`SHA-256    : ${sha}`);
console.log(`Changelog  : ${changelog || '(kosong)'}`);
if (dry) { console.log('\n--dry-run: tidak diunggah.'); process.exit(0); }

const tokenFile = path.join(root, 'server', '.secrets', 'admin_token.txt');
if (!fs.existsSync(tokenFile)) { console.error('Token admin tidak ditemukan: ' + tokenFile); process.exit(1); }
const token = fs.readFileSync(tokenFile, 'utf8').trim();

(async () => {
  const res = await fetch(`${url}/admin/release?version=${encodeURIComponent(version)}&changelog=${encodeURIComponent(changelog)}`, {
    method: 'PUT',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/octet-stream' },
    body: buf
  });
  const out = await res.json().catch(() => ({}));
  if (!res.ok || !out.ok) { console.error('\nGAGAL mengunggah:', res.status, JSON.stringify(out)); process.exit(1); }
  console.log(out.sha256 === sha ? '\nBERHASIL diunggah. Checksum di server cocok.' : '\nDiunggah, tetapi checksum berbeda dari lokal!');
  console.log('Versi terbaru di server: ' + out.version);
})();
