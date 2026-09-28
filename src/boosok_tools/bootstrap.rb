require 'sketchup'
require 'json'

module MyCustomPlugins
  unless file_loaded?(__FILE__)
    load File.join(__dir__, 'titlebar.rb')
    require_relative 'updater'
    require_relative 'hub'

    # Satu item saja; semua tool + cek update ada di dalam launcher
    UI.menu("Extensions").add_item("The Bosok Tools") {
      load File.join(__dir__, 'titlebar.rb')
      load File.join(__dir__, 'hub.rb')
      BoosokTools::Hub.show
    }

    # Cek otomatis saat SketchUp dibuka, dialog cuma muncul kalau ada update
    Updater.check

    file_loaded(__FILE__)
  end
end
