require 'sketchup'
require 'extensions'
require 'json'

module BoosokTools
  # Naikkan angka ini lalu push ke main: GitHub Actions otomatis bikin release + update version.json
  PLUGIN_VERSION = "1.7.3"

  # Folder kode plugin. Dihitung di sini (file root tidak dienkripsi) karena __dir__/__FILE__
  # di dalam file .rbe tidak bisa diandalkan. Semua modul memakai konstanta ini untuk path.
  # __FILE__ di Windows bisa ber-encoding salah kalau path memuat karakter non-ASCII (mis. nama user)
  root_file = __FILE__.dup.force_encoding('UTF-8')
  SUPPORT_DIR = File.join(File.dirname(root_file), 'boosok_tools').freeze unless defined?(SUPPORT_DIR)

  # Satu-satunya pintu untuk memuat file plugin. Sketchup.require (tanpa ekstensi) mengenali
  # .rb/.rbe/.rbs; require_relative, load, atau path ".rb" yang di-hardcode akan gagal setelah
  # paket dienkripsi. `name` relatif ke folder boosok_tools, mis. 'ruby/paid/select_tool/core_tool'.
  def self.load_module(name)
    src = File.join(SUPPORT_DIR, "#{name}.rb")
    if File.exist?(File.join(SUPPORT_DIR, '.dev_mode')) && File.exist?(src)
      load src # mode dev: dieksekusi ulang tiap dipanggil supaya hot reload jalan
    else
      Sketchup.require("boosok_tools/#{name}")
    end
  end

  # Semua versi yang sudah dirilis (1.0.10+) membaca URL ini. Jangan dipindah.
  VERSION_URL = "https://raw.githubusercontent.com/muhqosob/boosok-tools/main/the_bosok/version.json"
  # File yang sama lewat API: tidak kena cache CDN raw (~5 menit), tapi limit 60 request/jam per IP.
  VERSION_API_URL = "https://api.github.com/repos/muhqosob/boosok-tools/contents/the_bosok/version.json"
  RELEASES_URL = "https://github.com/muhqosob/boosok-tools/releases/latest"
  CHANGELOG_URL = "https://github.com/muhqosob/boosok-tools/blob/main/the_bosok/CHANGELOG.md"

  # Lingkungan yang didukung: SketchUp 2021 ke atas (Ruby 2.7+) di Windows. Versi lama tidak punya fitur Ruby yang
  # dipakai plugin dan tampilannya (CSS modern) tidak terjamin; Mac belum didukung (title bar, registry, path APPDATA).
  # Dicek di file root ini (tidak dienkripsi, dan hanya memakai sintaks Ruby lama) supaya pesannya tetap muncul
  # di SketchUp lama, bukan error sintaks di modul yang dimuat sesudahnya.
  MIN_SKETCHUP_VERSION = 21 unless defined?(MIN_SKETCHUP_VERSION)

  def self.supported_environment?
    Sketchup.version.to_i >= MIN_SKETCHUP_VERSION && Sketchup.platform == :platform_win
  end

  unless file_loaded?(__FILE__) || !supported_environment?
    plugin_dir = File.dirname(root_file)

    # Migrasi dari versi <= 1.6.0 yang file root-nya bernama boosok_tools_loader.rb. Kalau masih
    # ada, ia mendaftarkan extension yang sama dan menimpa PLUGIN_VERSION dengan angka lama
    # (update terus-menerus muncul), jadi hapus. Nama root harus sama dengan nama folder
    # (boosok_tools.rb + boosok_tools/) agar bisa di-sign di portal SketchUp.
    old_root = File.join(plugin_dir, 'boosok_tools_loader.rb')
    (File.delete(old_root) if File.exist?(old_root)) rescue nil

    # Tanpa ekstensi: SketchUp mencari bootstrap.rb maupun bootstrap.rbe
    loader_path = File.join('boosok_tools', 'ruby', 'bootstrap')
    ext = SketchupExtension.new("Boosok Tools", loader_path)
    ext.version     = PLUGIN_VERSION
    ext.creator     = "Muh Qosob"
    ext.author      = "Muh Qosob" if ext.respond_to?(:author=)
    ext.copyright   = "2026"
    ext.description = "Plugin Bosok ini hanya untuk yang membutuhkannya saja. Membutuhkan SketchUp 2021 atau lebih baru (Windows)."

    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end

  unless supported_environment? || file_loaded?(__FILE__)
    file_loaded(__FILE__) # satu pesan per sesi
    UI.start_timer(1.0, false) do
      UI.messagebox("Boosok Tools membutuhkan SketchUp 2021 atau lebih baru di Windows.\n" \
                    "Boosok Tools requires SketchUp 2021 or newer on Windows.\n\n" \
                    "Terdeteksi / Detected: SketchUp #{Sketchup.version} (#{Sketchup.platform})")
    end
  end
end
