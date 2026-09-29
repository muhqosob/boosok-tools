require 'sketchup'
require 'extensions'
require 'json'

module MyCustomPlugins
  # Naikkan angka ini lalu push ke main: GitHub Actions otomatis bikin release + update version.json
  PLUGIN_VERSION = "1.5.0"

  # Semua versi yang sudah dirilis (1.0.10+) membaca URL ini. Jangan dipindah.
  VERSION_URL = "https://raw.githubusercontent.com/muhqosob/boosok-tools/main/the_bosok/version.json"
  # File yang sama lewat API: tidak kena cache CDN raw (~5 menit), tapi limit 60 request/jam per IP.
  VERSION_API_URL = "https://api.github.com/repos/muhqosob/boosok-tools/contents/the_bosok/version.json"
  RELEASES_URL = "https://github.com/muhqosob/boosok-tools/releases/latest"
  CHANGELOG_URL = "https://github.com/muhqosob/boosok-tools/blob/main/the_bosok/CHANGELOG.md"

  unless file_loaded?(__FILE__)
    plugin_dir = File.dirname(__FILE__)
    $LOAD_PATH << plugin_dir unless $LOAD_PATH.include?(plugin_dir)

    loader_path = File.join('boosok_tools', 'bootstrap.rb')
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
