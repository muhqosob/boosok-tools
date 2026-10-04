# Changelog — Boosok Tools

Semua perubahan versi dicatat di sini.
Format mengikuti [Keep a Changelog](https://keepachangelog.com/id/1.0.0/).

---

## [1.7.4] — 2026-10-04

### ✨ Pembaruan UI — Resize Minimalis

- **Dialog lebih kecil dan ringkas**, nyaman dipakai di laptop kecil. Lebar dialog jadi 320 px, tombol, kolom isian, dan jarak antar elemen dirapatkan. Tinggi dialog dibatasi tinggi layar; bila isinya lebih panjang, dialog bisa di-scroll.
- **Keterangan penggunaan jadi keterangan mengambang.** Penjelasan toggle, opsi, langkah, dan catatan panjang muncul saat kursor berhenti di atasnya.
- **Hub:** menu tool 3 kolom (2 baris terlihat, sisanya di-scroll), statistik model pindah ke subjudul, kartu "terakhir dipakai" satu baris.
- **Purge:** selebar tool lain dengan tab Component / Material / Tag.
- **Menu pengaturan: Bahasa, Lisensi, Tentang.** Tentang berisi profil author; Lisensi berisi status, Hardware ID, dan aktivasi key.
- **Permintaan lisensi lewat email** muhqosob@gmail.com: Gmail terbuka di browser, pilih akun Google dulu, lalu email sudah terisi template.

### 🔧 Perbaikan

- **Slice tidak berfungsi.**

---

## [1.7.3] — 2026-10-03

### ✨ Fitur Baru

- **Lisensi aktif berlaku offline tanpa batas waktu.** Internet hanya dibutuhkan saat aktivasi, saat melepas lisensi untuk pindah PC, dan saat cek update. Masa toleransi 14 hari dihapus.
- **Cek lisensi ikut saat cek update** (saat SketchUp dibuka dan lewat tombol Cek update). Bila sedang offline, pengecekan dilewati.
- **Versi yang didukung: SketchUp 2021 ke atas di Windows.** Di versi atau platform lain, plugin menampilkan pesan dan tidak dimuat.

### 🗑️ Dihapus

- **Pengaturan Hotkey di Hub.** Atur shortcut langsung lewat SketchUp (Window → Preferences → Shortcuts, cari "Boosok Tools"). Shortcut yang sudah pernah dibuat tetap berlaku.

### 🔧 Perbaikan

- **Update dari versi lama membersihkan file kode lama** yang tertinggal di folder plugin, supaya hanya versi terenkripsi yang dipakai. Setelah update, restart SketchUp agar versi baru aktif.
- **Slice dan Trowel tidak berfungsi di SketchUp 2025** (dan versi sebelum 2026.2): deteksi solid memakai method yang baru ada di SketchUp 2026.2.
- **Masa trial lebih sulit di-reset:** data trial kini juga disimpan di luar registry SketchUp dan dipakai bersama semua versi SketchUp.
- **Lisensi terikat ke komputer:** pengaturan lisensi yang disalin ke PC lain tidak berlaku. Mengganti nama komputer tidak berpengaruh.
- Perbaikan peringatan konstanta pada Trowel saat plugin dimuat ulang.

---

## [1.7.2] — 2026-10-03

### ✨ Fitur Baru

- **QR DANA** di dialog Tentang untuk pembayaran lisensi (klik QR untuk memperbesar).

---

## [1.7.1] — 2026-10-03

### ✨ Fitur Baru

- **Dialog Tentang** menampilkan nama dan nomor HP terdaftar di server (nomor HP disamarkan).

### 🔧 Perbaikan

- Perbaikan sistem lisensi dan update lewat server.

---

## [1.7.0] — 2026-10-03

### ✨ Fitur Baru

- **Trowel** — Push/Pull dan Offset langsung di dalam group tanpa membukanya. Offset satu edge ke face mana pun
  (termasuk group lain), Offset seluruh garis tepi lalu otomatis lanjut Push/Pull, hasil bisa di dalam group atau
  group baru, group solid tetap solid saat bertabrakan, dan Shift + klik untuk menghapus edge di dalam face.
- **Slice** — memotong objek apa pun dengan satu atau banyak garis, hasil dua group atau satu group.
- **Void** — group sebagai pelubang di group solid lain, termasuk component pintu/jendela.
- **Purge** — bersihkan component, material, dan tag yang tidak terpakai.
- **Deep Properties** — mode Material (scan per material) dan **Ganti material** dengan material yang sudah ada di model.
- **Select Tool** — seleksi area dengan tahan klik kiri.
- **Lisensi online** — aktivasi lewat server, pindah komputer sendiri lewat Hapus Aktivasi (perlu internet), masa
  toleransi offline 14 hari. Pembayaran lewat QR DANA dan permintaan key lewat WhatsApp.
- **Update lewat server** — pengguna berlisensi aktif mengunduh update langsung dari server.

### 🔧 Perbaikan

- Struktur file dirapikan menjadi `ruby/free` dan `ruby/paid`; tool gratis: Selector, Replacer, Reset Scale, Group Cleaner, Untag & Paint, Purge.
- Replacer tidak lagi menampilkan notifikasi ganda.
- Hub: tool gratis dan berbayar dalam satu grid, dialog Tentang memakai ikon yang sama dengan header.

---

## [1.5.2] — 2026-09-30

### 🔧 Perbaikan

- **Fix: Highlight Nested Level 1 & 2 pada Select Tool**

  Highlight sebelumnya hanya berfungsi di nested level 0 (outermost group) atau deepest edge karena
  ketergantungan pada `InstancePath` yang mengembalikan transformasi identitas untuk intermediate instances.
  
  **Diperbaiki** dengan:
  - Mengakumulasikan transformasi hierarki dunia (`container_world_transform` & `parent_world_transform`)
    langsung dari rantai instance induk ke anak secara mandiri tanpa bug `InstancePath`.
  - Mengambil bounding box lokal (`definition.bounds` / `local_bounds`) dan mentransformasikannya secara
    akurat ke koordinat dunia di semua kedalaman level (0, 1, 2, dst.).
  - Triangulasi permukaan Face menggunakan `face.mesh` (`GL_TRIANGLES`) dengan sedikit offset ke arah kamera
    untuk mengeliminasi Z-fighting pada bidang opaque model.
  - Border Face digambar tegas menggunakan `GL_LINE_LOOP` warna solid pink (`line_width: 3`).

---

## [1.5.1] — 2026-09-30

### 🔧 Perbaikan

- **Fix: Error "custom_select tidak dikenal" setelah update plugin tanpa restart SketchUp**

  Konstanta `TOOL_PAGES` di `hub.rb` sebelumnya di-guard dengan `unless defined?(TOOL_PAGES)`.
  Akibatnya, saat plugin di-update ke versi yang menambahkan tool baru (misalnya `custom_select`),
  SketchUp tetap memakai versi lama konstanta dari memori — sehingga tool baru tidak pernah dikenali
  dan selalu memunculkan toast error.

  **Diperbaiki** dengan menambahkan `remove_const(:TOOL_PAGES)` sebelum re-assign, agar konstanta
  selalu fresh setiap kali `hub.rb` di-load, baik saat boot maupun hot-reload.

---

## [1.5.0] — 2026-09-30

### ✨ Fitur Baru

- **Redesain Hub — Grid 4 Kolom & Scalable**

  Tampilan launcher utama dirancang ulang agar skalabel untuk lebih banyak tool:
  - Grid tool berubah dari 2 kolom menjadi **4 kolom** dengan tile kompak (ikon + label).
  - Area grid kini **scrollable** — cukup scroll ke bawah untuk menemukan tool tambahan.
  - **Search bar** di bagian atas untuk mencari tool secara instan (filter client-side).
  - **Recent Tool** — tool terakhir yang dipakai tersimpan di `localStorage` dan ditampilkan
    sebagai shortcut "Terakhir dipakai" di atas grid.

- **Panel Update Inline**

  Tombol "Cek update" di footer kini membuka **slide-up sheet** di dalam window yang sama,
  tanpa membuka jendela atau dialog baru. Panel mendukung 6 state: `checking → latest /
  available → downloading → installing → done / error`.

### 🔧 Perbaikan

- **Fix: `NameError` saat mengaktifkan Select Tool dari Hub**

  `CoreTool.new` gagal karena Ruby tidak bisa resolve nama kelas tanpa namespace penuh
  saat file di-`load` secara dinamis. Diperbaiki ke `BoosokTools::SelectTool::CoreTool.new`.

---

## [1.4.0] — 2026-09-30

### ✨ Fitur Baru

- **Select Tool — Seleksi Hirarki Viewport**

  Tool seleksi inovatif yang memungkinkan inspeksi dan seleksi sub-komponen/group
  secara mendalam langsung dari viewport, tanpa perlu membuka container induk:

  - **Nested Level Persistence** — level kedalaman yang dipilih via `CTRL + Scroll`
    dipertahankan saat mouse berpindah antar objek, tidak lagi reset ke Level 0 setiap kali
    pointer bergerak.
  - **Boundary Clamping (`effective_depth`)** — level kedalaman otomatis disesuaikan jika
    objek yang disorot memiliki hirarki lebih dangkal, dan kembali ke target saat kursor
    menyorot objek bertingkat lagi.
  - **Shortcut ESC** — menekan `ESC` saat tool aktif langsung mereset level ke outermost (0).
  - **Integrasi Hub** — dapat diakses langsung dari tile launcher Hub Boosok Tools.

---

## [1.3.0] — 2026-09-29

### ✨ Fitur Baru

- **Deep Properties — Peningkatan UI & Performa**
  - Header toolbar dan listbox kini digabung dalam container terpadu (`.dp-box-wrap`),
    tampilan menjadi solid tanpa celah terputus.
  - Ukuran font header toolbar ditingkatkan dari 10.5px ke 12px.
  - **Counter tag dinamis** — indikator menampilkan jumlah tag terpilih per total secara
    real-time saat checklist diubah (contoh: `1/3 tag · 6/26`).
  - Tombol **Scan Objek** kini langsung aktif kembali setelah data selesai discan,
    tanpa delay timer buatan.
  - Seluruh logika JavaScript dipindahkan ke `ui.js` — file HTML menjadi bersih dan mudah dirawat.
  - `autoFitHeight` kini mengabaikan modal overlay fixed sehingga ukuran dialog tidak
    membesar saat notifikasi muncul.

- **Hub — Scrollbar Kustom Tema**

  Scrollbar pada grid menu Hub menggunakan scrollbar kustom dengan thumb membulat dan
  warna adaptif (light/dark mode).

---

## [1.2.7] — 2026-09-29

### ✨ Fitur Baru

- **Header & Ikon pada Modal Notifikasi**

  Menambahkan baris header di bagian atas kotak notifikasi modal dengan judul
  **Boosok Tools** dan ikon paket, identik dengan header Hub. Ikon menyesuaikan tema
  secara otomatis (terang/gelap).

---

## [1.2.6] — 2026-09-29

### ✨ Fitur Baru

- **Auto-Sync Tag pada Selector**

  Penambahan `LayersObserver`, `ModelObserver`, `AppObserver`, dan background polling (0.4s):
  penambahan, penghapusan, atau rename Tag di SketchUp langsung tersinkron ke dropdown
  tanpa perlu membuka ulang dialog. Jika tag yang dipilih terhapus, seleksi otomatis kembali
  ke `(Semua Tag / Abaikan)`.

- **Perbaikan End Isolate pada Hide on Scene**

  Penelusuran sub-group kini melewati Component dan Dynamic Component (DC) — hirarki
  internal komponen tidak diobrak-abrik sehingga geometri tersembunyi di dalamnya tetap aman.

- **Penyederhanaan Nama**

  `The Boosok Tools` diubah menjadi **Boosok Tools** di menu Extensions, header launcher,
  dan seluruh tombol kembali di setiap tool.

- **Kredit Pembuat di Panel Update**

  Menampilkan teks `Dibuat oleh: "Muh-Qosob"` di tampilan dialog saat plugin sudah versi terbaru.

---

## [1.2.5] — 2026-09-29

### ✨ Fitur Baru

- **Pembaruan Nama Tool**
  - `The Selector` → **Selector**
  - `The Replacer` → **Group Replacer**
  - `Clean Group` → **Group Cleaner**

- **Modal Notifikasi Baru**

  Menggantikan toast dengan dialog modal mengambang (*floating alert*) berlengkap tombol OK.
  Lebar notifikasi disesuaikan ke **280px** (~73% lebar jendela). Mendukung penutupan via
  keyboard `Enter` dan `Escape`.

### 🔧 Perbaikan

- **Group Replacer**
  - Posisi titik axes (origin) tidak lagi bergeser saat penggantian objek.
  - Dimensi objek baru (LenX, LenY, LenZ) mengikuti objek lama secara presisi.
  - Seleksi objek lama tersimpan saat beralih memilih objek pengganti (*sticky cache*).

- **Hide on Scene**
  - `LayersObserver` ditambahkan — penambahan, penghapusan, dan rename Tag langsung tersinkron.
  - Data scene dan tag tersinkron otomatis setiap kali tool dibuka kembali dari Hub.
  - Background polling (0.4s) mendeteksi perubahan dari Default Tray secara real-time.

---

## [1.2.4] — 2026-09-28

### ✨ Fitur Baru

- **Toast In-Flow di Bawah Tombol**

  Notifikasi muncul setelah konten/tombol (bukan overlay), dialog otomatis membesar saat
  notifikasi muncul dan mengecil saat notifikasi menghilang.

---

## [1.2.3] — 2026-09-28

### 🔧 Perbaikan

- Percobaan posisi toast di atas konten (in-flow sebelum header). Pendekatan ini digantikan
  oleh v1.2.4 yang lebih baik.

---

## [1.2.2] — 2026-09-28

### ✨ Fitur Baru

- **Tombol Changelog di Dialog Update** — tersedia di tampilan "Sudah versi terbaru" dan
  "Update berhasil!".
- **Toast In-Flow** — notifikasi mulai diubah menjadi bagian alur dokumen, tidak lagi overlay/fixed.
- **CHANGELOG.md** — file riwayat perubahan pertama kali dibuat di `the_bosok/CHANGELOG.md`.

---

## [1.2.1] — 2026-09-28

### ✨ Fitur Baru

- **Update Tanpa Restart SketchUp** — setelah update berhasil, plugin aktif seketika tanpa
  perlu menutup dan membuka ulang SketchUp.
- **Tombol Changelog di Dialog Update** — mengarah ke halaman CHANGELOG agar pengguna dapat
  melihat riwayat perubahan setiap versi.
- **Isolate → End Isolate** — tombol *End Isolate* di Hide on Scene menampilkan kembali semua
  objek tersembunyi termasuk group di dalam group.
- **Hub Ingat Posisi** — jendela Hub menyimpan posisi terakhir saat digeser; saat pertama kali
  dibuka, posisinya otomatis berada di tengah area kerja.
- **Notifikasi Dipindah ke Bawah** — tidak lagi menutupi judul/header dialog.
- **Dialog Update Tinggi Otomatis** — ukuran dialog menyesuaikan konten tanpa scroll.

### 🔧 Perbaikan

- Semua fungsi tool (Isolate, Replace, dll.) yang sebelumnya hanya berputar loading kini
  berjalan normal.
- Tombol "Selesai" di dialog update diubah menjadi "Tutup".
- Selector: tinggi dialog direset otomatis saat kembali ke langkah pertama.
- Group Replacer: item lama yang dipilih tetap tersimpan saat melanjutkan memilih pengganti.

---

## [1.2.0] — 2026-09-15

### ✨ Fitur Baru

- Semua tool kini tergabung dalam satu menu: **Extensions › The Bosok Tools**.
  *(Restart SketchUp sekali setelah update agar menu baru muncul.)*
- Animasi loading pada jendela pembuka yang menyesuaikan tema terang/gelap.
- Tool yang belum bisa dipakai (misalnya belum ada scene) diberi indikator dan penjelasan alasannya.
- Pesan error lebih jelas disertai tombol "Coba lagi".
- Cek update tersedia langsung di jendela pembuka.

### 🔧 Perbaikan

- Berbagai bug di Hide on Scene dan Group Replacer.

---

## [1.1.7] — 2026-08-20

### 🔧 Perbaikan

- Perbaikan crash saat membuka dialog di SketchUp versi lama.
- Perbaikan tampilan dark mode pada beberapa dialog.
- Ukuran dialog lebih responsif menggunakan auto-fit height.

---

## [1.1.6] — 2026-08-05

### ✨ Fitur Baru

- Dukungan dark mode otomatis mengikuti preferensi sistem.
- Ikon di setiap tool tile diperbarui.

### 🔧 Perbaikan

- Bug Group Replacer yang gagal mengganti komponen dalam group bersarang.

---

## [1.1.5] — 2026-07-18

### ✨ Fitur Baru

- **Selector** — pilih dan seleksi objek berdasarkan kriteria tertentu (tag, nama, atribut).
- **Group Replacer** — ganti satu group/komponen dengan group lain secara batch.

### 🔧 Perbaikan

- Stabilitas umum dan peningkatan performa loading dialog.

---

## [1.1.0] — 2026-06-10

### ✨ Fitur Baru

- **Hide on Scene** dengan mode Isolate — sembunyikan semua objek kecuali yang dipilih, per scene.
- Dialog manajemen scene dengan listbox scrollable.
- Tombol "Kembali ke Hub" dari setiap dialog tool.

---

## [1.0.0] — 2026-05-01

### 🚀 Rilis Pertama

- Plugin dasar Boosok Tools untuk SketchUp.
- Sistem cek update otomatis saat SketchUp dibuka.
- Dialog update dengan 6 state: memeriksa, tersedia, mengunduh, memasang, selesai, error.
- Dukungan redirect CDN GitHub saat mengunduh paket `.rbz`.
