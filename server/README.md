# Server lisensi Boosok Tools (Cloudflare Workers + D1, gratis)

Jalankan semua perintah di PowerShell dari folder `server\`:

```powershell
cd "C:\Users\FMMNH\Desktop\Boosok Tool\boosok-tools\server"
```

Kalau `npm` / `wrangler` ditolak karena "running scripts is disabled", jalankan sekali:
`Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`

## 1. Login ke Cloudflare (sekali)
```powershell
wrangler login
```

## 2. Buat database (sekali)
```powershell
wrangler d1 create boosok-license
```
Salin nilai `database_id` yang tercetak, lalu tempel ke `wrangler.toml` menggantikan `ISI_SETELAH_d1_create`.

Buat tabel:
```powershell
wrangler d1 execute boosok-license --remote --file=schema.sql
```

## 3. Simpan rahasia (sekali)
Kunci tanda tangan dan token admin sudah dibuat di `.secrets\` (folder itu TIDAK ikut git):
```powershell
Get-Content .secrets\private_key.b64 -Raw | wrangler secret put PRIVATE_KEY_B64
Get-Content .secrets\admin_token.txt -Raw | wrangler secret put ADMIN_TOKEN
```
(Kalau Wrangler menanyakan "create a new Worker?", jawab `Y`.)

## 4. Deploy
```powershell
wrangler deploy
```
Hasilnya alamat seperti `https://boosok-license.NAMAKAMU.workers.dev`. Cek di browser: harus tampil `{"ok":true,"service":"boosok-license"}`.

## 5. Pasang alamat di plugin
Di `src\boosok_tools\license.rb` ganti
`SERVER_URL = "https://boosok-license.ISI_ALAMAT_SERVER.workers.dev"` dengan alamat dari langkah 4, lalu jalankan `sync_to_sketchup.ps1`.
Selama masih `ISI_ALAMAT_SERVER`, plugin hanya menerima key lama (berbasis Hardware ID).

## 6. Kelola key
Buka `tools\license-admin\admin.html` di browser, isi alamat server dan token admin (isi file `.secrets\admin_token.txt`).
Dari situ: buat key baru, lihat perangkat yang terikat, lepas perangkat, cabut / pulihkan key, ubah batas perangkat.

## Ganti pengaturan
- Masa toleransi offline: `GRACE_DAYS` di `src\index.js` (default 14 hari). Lalu `wrangler deploy` lagi.
- Batas perangkat per key: dipilih saat membuat key (default 1), bisa diubah per key di panel admin.

## Cadangan
Simpan folder `.secrets\` di tempat aman. Kalau `private_key.b64` hilang dan Worker dibuat ulang, token lama tidak valid
(user hanya perlu aktivasi ulang), tapi kunci publik di `license.rb` harus ikut diganti dengan pasangan baru.

## Update plugin lewat server (pengganti GitHub Releases)
Update disimpan di Workers KV (namespace `RELEASES`) dan hanya bisa diunduh oleh key aktif yang perangkatnya terikat.

Rilis versi baru (dari folder root repo):
```powershell
# 1. naikkan PLUGIN_VERSION di src\boosok_tools.rb
# 2. bangun + unggah (catatan perubahan opsional)
node tools\publish-release.js "Catatan perubahan"
```
`node tools\publish-release.js --dry-run` hanya membangun `dist\boosok_tools_vX.rbz` tanpa mengunggah.

Plugin mengecek `GET /update/latest` (publik) dan mengunduh `GET /update/download` dengan header `X-License-Key` + `X-Hardware-Id`.
Trial, key lama (offline), dan key yang belum diaktifkan tidak bisa mengunduh update.

**Masa transisi:** plugin versi lama (<= 1.6.0) hanya mengenal GitHub, jadi rilis pertama yang membawa updater baru
(mis. v1.7.0) tetap harus dirilis di GitHub (workflow `release.yml`). Setelah pengguna sudah di versi baru:
1. set `GITHUB_FALLBACK = false` di `src\boosok_tools\updater.rb` (rilis berikutnya lewat server),
2. nonaktifkan workflow `.github\workflows\release.yml`,
3. baru jadikan repo privat.
