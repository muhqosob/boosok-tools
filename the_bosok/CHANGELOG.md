# Changelog — Boosok Tools

Semua perubahan versi dicatat di sini.
Format mengikuti [Keep a Changelog](https://keepachangelog.com/id/1.0.0/).

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
