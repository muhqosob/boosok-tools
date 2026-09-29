# Changelog — Boosok Tools

Semua perubahan versi dicatat di sini.
Format mengikuti [Keep a Changelog](https://keepachangelog.com/id/1.0.0/).

---

## [1.4.0] — 2026-09-30

### ✨ Baru & Perbaikan
- **5D Select Tool**:
  - **Fitur Baru (Modular In-Viewport Selection)**: Tool seleksi hirarki viewport inovatif yang memungkinkan inspeksi dan seleksi sub-komponen/group secara mendalam tanpa membuka container induk.
  - **Presistensi Level Kedalaman (Nested Level 1 Persistence)**: Level kedalaman yang dipilih user (misalnya Nested Level 1 via CTRL + Scroll Wheel) kini dipertahankan secara konsisten saat mouse digerakkan atau berpindah antar objek geometri (tidak lagi reset ke Level 0 setiap kali pointer berpindah).
  - **Handling Boundary Hirarki Aman (`effective_depth`)**: Akses level kedalaman secara otomatis disesuaikan (*clamped*) jika objek yang disorot memiliki tingkat kedalaman lebih sedikit, dan langsung kembali ke level target user begitu kursor menyorot objek bertingkat lagi.
  - **Shortcut Reset Cepat (ESC)**: Menekan tombol `ESC` saat tool aktif akan mereset level kedalaman kembali ke Level 0 (outermost container).
  - **Integrasi Penuh Boosok Tools**: Terintegrasi langsung dengan menu launcher Hub Boosok Tools dan siap diakses dari viewport maupun toolbar.

---

## [1.3.0] — 2026-09-29

### ✨ Baru & Perbaikan
- **Deep Properties**:
  - **Penyatuan Header & Listbox**: Toolbar atas dan daftar listbox kini dirangkum dalam container terpadu (`.dp-box-wrap`), menghilangkan celah terputus sehingga tampilan menyatu elegan dan solid.
  - **Penyelarasan Tipografi Header Toolbar**: Ukuran font header toolbar ditingkatkan dari 10.5px ke 12px dengan padding yang lebih proporsional sehingga lebih jelas dan nyaman dibaca.
  - **Counter Tag Dinamis**: Indikator counter tag pada header kini menampilkan jumlah tag yang dipilih per total tag secara real-time saat checklist diubah (contoh: `1/3 tag · 6/26`).
  - **Respons Tombol Scan Objek Instan**: Menghapus jeda timer buatan pada tombol **Scan Objek**; tombol langsung kembali aktif begitu data selesai discan oleh Ruby tanpa delay.
  - **Modularisasi Kode JavaScript**: Seluruh logika dan script JavaScript Deep Properties telah dipindahkan dan ditautkan ke `ui.js`, menghasilkan kode HTML yang sangat bersih, terstruktur, dan mudah dirawat.
  - **Stabilisasi Dialog Height**: Fungsi `autoFitHeight` kini mengabaikan modal overlay fixed sehingga ukuran dialog tidak lagi membesar saat notifikasi muncul dan tetap auto fit secara proporsional.
- **Hub Boosok Tools**:
  - **Custom Scrollbar Menu Sesuai Tema**: Scrollbar pada grid menu Hub kini menggunakan scrollbar kustom tema Boosok Tools dengan thumb membulat dan warna adaptif (light/dark mode), menggantikan scrollbar bawaan browser.

---

## [1.2.7] — 2026-09-29

### ✨ Baru
- **Header & Icon pada Modal Notifikasi**:
  - Menambahkan baris header di bagian atas kotak notifikasi modal (*floating alert*) dengan judul **Boosok Tools** serta icon box paket (`#i-package`) yang identik dengan header menu utama Hub.
  - Tampilan icon otomatis menyesuaikan tema (latar hitam icon putih pada tema terang, latar putih icon hitam pada tema gelap).

---

## [1.2.6] — 2026-09-29

### ✨ Baru
- **Auto-Sync Tag pada Selector**:
  - Penambahan `LayersObserver`, `ModelObserver`, `AppObserver`, dan background monitoring (0.4s) pada tool **Selector**: penambahan, penghapusan, atau rename Tag di SketchUp langsung sinkron otomatis secara real-time ke dropdown tag tanpa perlu membuka ulang dialog.
  - Pembersihan otomatis: jika tag yang sedang dipilih terhapus di SketchUp, nilai seleksi otomatis kembali ke `(Semua Tag / Abaikan)`.
  - Dropdown yang sedang terbuka otomatis memperbarui daftar tag secara langsung.
- **Perbaikan End Isolate pada Hide on Scene**:
  - Melewati (*skip*) penelusuran kedalaman sub-group di dalam objek jika objek tersebut merupakan Component atau Dynamic Component (DC).
  - Objek tetap dibuka/ditampilkan pada tingkat instance-nya di scene aktif, tetapi hirarki internal di dalam komponen/DC tidak diobrak-abrik atau dibuka paksa sehingga geometri/sub-group internal yang sengaja disembunyikan tetap aman.
- **Penyederhanaan Nama "Boosok Tools"**:
  - Mengubah `The Boosok Tools` menjadi **Boosok Tools** di menu Extensions SketchUp, header launcher utama, dan seluruh tombol kembali di setiap tool.
- **Kredit Pembuat di Updater**:
  - Menambahkan teks `Dibuat oleh: "Muh-Qosob"` di tengah tampilan dialog pembaruan saat plugin sudah versi terbaru.

---

## [1.2.5] — 2026-09-29

### ✨ Baru
- **Penyederhanaan & Perubahan Nama Tool**:
  - `The Selector` kini menjadi **Selector**
  - `The Replacer` kini menjadi **Group Replacer**
  - `Clean Group` kini menjadi **Group Cleaner**
- **Modal Notifikasi Baru & Optimal**:
  - Menggantikan toast dengan dialog modal mengambang (*floating alert*) yang dilengkapi tombol OK.
  - Lebar notifikasi disesuaikan ke ukuran optimal **280px** (hanya ~73% dari lebar jendela), tidak lagi menutupi seluruh lebar dialog.
  - Dukungan tombol keyboard **Enter** dan **Escape** untuk menutup notifikasi dengan cepat.

### 🔧 Perbaikan
- **Group Replacer**:
  - Posisi titik axes (origin) tidak lagi bergeser saat penggantian objek.
  - Penskalaan dimensi objek baru (LenX, LenY, LenZ) mengikuti objek lama secara presisi dengan transformasi skala lokal.
  - Seleksi objek lama tetap tersimpan aman saat beralih memilih objek baru berkat sistem *sticky cache*.
- **Hide on Scene**:
  - Penambahan `LayersObserver` agar penambahan, pengurangan, dan perubahan nama Tag langsung sinkron otomatis.
  - Sinkronisasi data scene dan tag otomatis berjalan setiap kali tool dibuka kembali dari Hub.
  - Background polling (0.4s) mendeteksi perubahan dari Default Tray SketchUp secara real-time.

---

## [1.2.4] — 2026-09-28

### ✨ Baru / Perbaikan
- **Notifikasi (toast) in-flow di bawah tombol** — toast muncul setelah konten/tombol (bukan overlay), dialog otomatis membesar saat notif muncul dan mengecil saat notif menghilang.

---

## [1.2.3] — 2026-09-28

### 🔧 Perbaikan
- Percobaan posisi toast di atas konten (in-flow sebelum header) — digantikan oleh v1.2.4 yang lebih baik.

---

## [1.2.2] — 2026-09-28

### ✨ Baru / Perbaikan
- **Tombol Change Log di dialog update** — tersedia di tampilan "Sudah versi terbaru" dan "Update berhasil!".
- **Toast in-flow** — notifikasi tidak lagi overlay/fixed, mulai diubah jadi bagian alur dokumen.
- **CHANGELOG.md** — file riwayat perubahan pertama kali dibuat di `the_bosok/CHANGELOG.md`.

---

## [1.2.1] — 2026-09-28


### ✨ Baru
- **Update langsung tanpa restart SketchUp** — setelah update berhasil, plugin aktif seketika tanpa perlu menutup dan membuka ulang SketchUp.
- **Tombol Change Log di dialog update** — mengarah ke halaman ini agar pengguna bisa melihat riwayat perubahan setiap versi.
- **Isolate → End Isolate** — di fitur Hide on Scene, tersedia tombol *End Isolate* yang menampilkan kembali semua objek tersembunyi termasuk group di dalam group.
- **Hub dialog ingat posisi** — jendela utama (Hub) menyimpan posisi terakhir saat digeser; saat SketchUp pertama dibuka, posisinya otomatis berada di tengah area kerja.
- **Notifikasi (toast) dipindah ke bawah** — tidak lagi menutupi judul/header dialog.
- **Dialog update tinggi otomatis** — ukuran dialog menyesuaikan konten tanpa perlu scroll.
- **The Selector fix** — tinggi dialog direset otomatis saat kembali ke langkah pertama.
- **The Replacer fix** — item lama yang dipilih tetap tersimpan saat melanjutkan memilih group pengganti.

### 🔧 Perbaikan
- Semua fungsi tool (Isolate, Replace, dll.) yang sebelumnya hanya berputar loading kini berjalan normal.
- Tombol "Selesai" di dialog update diganti menjadi "Tutup".

---

## [1.2.0] — 2026-09-15

### ✨ Baru
- Semua tool kini tergabung dalam satu menu: **Extensions › The Bosok Tools** (restart SketchUp sekali setelah update agar menu baru muncul).
- Jendela pembuka baru dengan animasi loading yang mengikuti tema terang/gelap.
- Tool yang belum bisa dipakai (misalnya belum ada scene) diberi tanda dan penjelasan alasannya.
- Pesan error lebih jelas disertai tombol "Coba lagi".
- Cek update sekarang tersedia langsung di jendela pembuka.

### 🔧 Perbaikan
- Perbaikan berbagai bug di fitur Hide on Scene dan The Replacer.

---

## [1.1.7] — 2026-08-20

### 🔧 Perbaikan
- Perbaikan crash saat membuka dialog di SketchUp versi lama.
- Perbaikan tampilan dark mode pada beberapa dialog.
- Ukuran dialog lebih responsif menggunakan auto-fit height.

---

## [1.1.6] — 2026-08-05

### ✨ Baru
- Tambah dukungan dark mode otomatis mengikuti preferensi sistem.
- Ikon di setiap tool tile diperbarui.

### 🔧 Perbaikan
- Perbaikan bug The Replacer yang gagal mengganti komponen dalam group bersarang.

---

## [1.1.5] — 2026-07-18

### ✨ Baru
- Fitur **The Selector** — pilih dan seleksi objek berdasarkan kriteria tertentu.
- Fitur **The Replacer** — ganti satu group/komponen dengan group lain secara batch.

### 🔧 Perbaikan
- Stabilitas umum dan perbaikan performa loading dialog.

---

## [1.1.0] — 2026-06-10

### ✨ Baru
- Fitur **Hide on Scene** dengan mode Isolate: sembunyikan semua objek kecuali yang dipilih, per scene.
- Dialog manajemen scene dengan listbox scrollable.
- Tombol Kembali ke Hub dari setiap dialog fitur.

---

## [1.0.0] — 2026-05-01

### 🚀 Rilis Pertama
- Plugin dasar Boosok Tools untuk SketchUp.
- Sistem cek update otomatis saat SketchUp dibuka.
- Dialog update dengan status: memeriksa, tersedia, mengunduh, memasang, selesai, error.
- Dukungan redirect CDN GitHub saat mengunduh paket `.rbz`.
