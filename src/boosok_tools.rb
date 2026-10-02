require 'sketchup'
require 'extensions'
require 'json'

module BoosokTools
  # Naikkan angka ini lalu push ke main: GitHub Actions otomatis bikin release + update version.json
  PLUGIN_VERSION = "1.6.0"

  # Folder kode plugin. Dihitung di sini (file root tidak dienkripsi) karena __dir__/__FILE__
  # di dalam file .rbe tidak bisa diandalkan. Semua modul memakai konstanta ini untuk path.
  SUPPORT_DIR = File.join(File.dirname(__FILE__), 'boosok_tools').freeze unless defined?(SUPPORT_DIR)

  # Satu-satunya pintu untuk memuat file plugin. Sketchup.require (tanpa ekstensi) mengenali
  # .rb/.rbe/.rbs; require_relative, load, atau path ".rb" yang di-hardcode akan gagal setelah
  # paket dienkripsi. `name` relatif ke folder boosok_tools, mis. 'custom_select/core_tool'.
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

  unless file_loaded?(__FILE__)
    plugin_dir = File.dirname(__FILE__)
    $LOAD_PATH << plugin_dir unless $LOAD_PATH.include?(plugin_dir)

    # Migrasi dari versi <= 1.6.0 yang file root-nya bernama boosok_tools_loader.rb. Kalau masih
    # ada, ia mendaftarkan extension yang sama dan menimpa PLUGIN_VERSION dengan angka lama
    # (update terus-menerus muncul), jadi hapus. Nama root harus sama dengan nama folder
    # (boosok_tools.rb + boosok_tools/) agar bisa di-sign di portal SketchUp.
    old_root = File.join(plugin_dir, 'boosok_tools_loader.rb')
    (File.delete(old_root) if File.exist?(old_root)) rescue nil

    # Tanpa ekstensi: SketchUp mencari bootstrap.rb maupun bootstrap.rbe
    loader_path = File.join('boosok_tools', 'bootstrap')
    ext = SketchupExtension.new("Boosok Tools", loader_path)
    ext.version     = PLUGIN_VERSION
    ext.creator     = "Muh Qosob"
    ext.author      = "Muh Qosob" if ext.respond_to?(:author=)
    ext.copyright   = "2026"
    ext.description = "Plugin Bosok ini hanya untuk yang membutuhkannya saja."

    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end

# Backward-compatibility: versi lama yang di-install user masih pakai MyCustomPlugins
MyCustomPlugins = BoosokTools unless defined?(MyCustomPlugins)
