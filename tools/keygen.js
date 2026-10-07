// Buat kunci enkripsi AES-256-GCM dan kunci HMAC-SHA256 untuk publish-release.js.
// Jalankan SEKALI, simpan hasilnya di server/.secrets/ dan jaga kerahasiaannya.
// File .secrets/ sudah masuk .gitignore dan tidak akan ikut di-push ke GitHub.
//
// Penggunaan:
//   node tools\keygen.js
//   node tools\keygen.js --force     (timpa file yang sudah ada)

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const root = path.resolve(__dirname, '..');
const secretsDir = path.join(root, 'server', '.secrets');
const force = process.argv.includes('--force');

fs.mkdirSync(secretsDir, { recursive: true });

function genKey(filename, label) {
  const p = path.join(secretsDir, filename);
  if (fs.existsSync(p) && !force) {
    console.log(`[SKIP] ${label} sudah ada: ${p}  (pakai --force untuk menimpa)`);
    return;
  }
  const hex = crypto.randomBytes(32).toString('hex');
  fs.writeFileSync(p, hex + '\n', { mode: 0o600 });
  console.log(`[OK]   ${label} dibuat  : ${p}`);
  console.log(`       Nilai: ${hex}`);
}

genKey('encrypt_key.txt', 'Kunci AES-256-GCM (enkripsi payload)');
genKey('hmac_key.txt',    'Kunci HMAC-SHA256 (verifikasi integritas)');

console.log('\n⚠️  SIMPAN KUNCI INI DI TEMPAT AMAN! Server wajib punya kunci yang sama untuk mendekripsi.');
console.log('    Jangan pernah commit file di server/.secrets/ ke GitHub.');
