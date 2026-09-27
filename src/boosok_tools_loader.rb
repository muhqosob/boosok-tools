require 'sketchup'
require 'extensions'
require 'json'

module MyCustomPlugins
  # Naikkan angka ini lalu push ke main: GitHub Actions otomatis bikin release + update version.json
  PLUGIN_VERSION = "1.0.12"

  # Semua versi yang sudah dirilis (1.0.10+) membaca URL ini. Jangan dipindah.
  VERSION_URL = "https://raw.githubusercontent.com/muhqosob/boosok-tools/main/the_bosok/version.json"
  RELEASES_URL = "https://github.com/muhqosob/boosok-tools/releases/latest"

  unless file_loaded?(__FILE__)
    main_menu = UI.menu("Extensions")
    @my_submenu = main_menu.add_submenu("Boosok Tools")

    require_relative 'boosok_tools/main'
    @my_submenu.add_item("The Selector") {
      TheSelectorPlugin.run_selector
    }

    require_relative 'boosok_tools/the_replacer'
    @my_submenu.add_item("The Replacer") {
      TheReplacer.run
    }

    require_relative 'boosok_tools/the_cleangroup'
    @my_submenu.add_item("Convert to Clean Group") {
      ConvertToCleanGroup.run
    }

    require_relative 'boosok_tools/the_reset'
    @my_submenu.add_item("Reset The Group Scale") {
      TheResetScale.run
    }

    require_relative 'boosok_tools/the_hideonscenemanager'
    @my_submenu.add_item("Hide on Scene Manager") {
      HideOnSceneManager.run
    }

    require_relative 'boosok_tools/untagnpaint'
    @my_submenu.add_item("Untag and Paint") {
      UntagUnpaintManager.run
    }

    @my_submenu.add_separator

    require_relative 'boosok_tools/updater'
    @my_submenu.add_item("Check for Updates...") {
      Updater.check(true)
    }

    # Cek otomatis saat SketchUp dibuka, dialog cuma muncul kalau ada update
    Updater.check

    file_loaded(__FILE__)
  end
end
