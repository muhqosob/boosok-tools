# Menambah bahasa

Satu bahasa = **satu file JSON** di folder ini. Tidak ada file lain yang perlu diubah.

## Langkah

1. Salin `en.json` menjadi `<kode>.json` — misalnya `fr.json` untuk Prancis.
2. Ubah tiga baris di atas:
   ```json
   "code": "fr",
   "name": "Français",
   "native_name": "Français",
   ```
3. Terjemahkan **nilai** di `"strings"` (kunci di sebelah kiri jangan diubah).
4. (Disarankan) Terjemahkan juga `"messages"` dan `"patterns"` — lihat di bawah.
5. Buka **Pengaturan → Bahasa** di Hub. Bahasa baru muncul di daftar dan bisa langsung dipilih.

Plugin membuat `js/strings.js` sendiri dari semua file di folder ini (saat SketchUp dibuka, saat Hub
dibuka, dan saat panel Bahasa dibuka). Jangan mengedit `js/strings.js` — akan ditimpa.

> Kalau mengedit file di folder plugin SketchUp (`%APPDATA%\SketchUp\...\Plugins\boosok_tools\locales`),
> simpan juga salinannya di `src/boosok_tools/locales/` supaya tidak tertimpa oleh `sync_to_sketchup.ps1`.

## Isi file

| Bagian | Fungsi |
|---|---|
| `code`, `name`, `native_name` | Kode bahasa dan nama yang tampil di daftar bahasa. |
| `strings` | Semua teks antarmuka: `"kunci": "teks"`. Kunci yang belum diterjemahkan otomatis memakai bahasa Indonesia. |
| `messages` | (opsional) Terjemahan pesan notifikasi dari Ruby yang **persis sama**. Kiri = pesan aslinya (Indonesia), kanan = terjemahan. |
| `patterns` | (opsional) Pesan yang mengandung angka/nama. `match` = regex untuk pesan Indonesia, `replace` = terjemahan dengan `$1`, `$2` untuk bagian yang ditangkap. Dicoba berurutan dari atas. |

Contoh `patterns`:
```json
{ "match": "^Terseleksi (\\d+) entitas\\.$", "replace": "$1 entités sélectionnées." }
```
(Di JSON, backslash ditulis dua kali: `\\d`.)

## Aturan penting

- Jangan ubah placeholder di dalam teks: `%{count}`, `{time}`, `{ver}`, dan tag HTML seperti `<b>…</b>`, `<strong>…</strong>`, `<br>`.
- Simpan file sebagai **UTF-8**.
- File yang JSON-nya rusak dilewati dan pesannya muncul di Ruby Console
  (`[Boosok Tools] Gagal membaca locale '…'`). Bahasa lain tetap jalan.
- `messages`/`patterns` yang kosong tidak membuat error — pesan notifikasi hanya tampil dalam bahasa Indonesia.
- Bahasa Indonesia (`id.json`) adalah bahasa sumber: teks bawaan HTML dan pesan dari Ruby aslinya berbahasa Indonesia,
  jadi `id.json` tidak memerlukan `messages`/`patterns`.
