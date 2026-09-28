require 'sketchup'
require 'json'

module MyCustomPlugins
  unless file_loaded?(__FILE__)
    main_menu = UI.menu("Extensions")
    @my_submenu = main_menu.add_submenu("Boosok Tools")

    require_relative 'titlebar'

    require_relative 'main'
    @my_submenu.add_item("The Selector") {
      TheSelectorPlugin.run_selector
    }

    require_relative 'the_replacer'
    @my_submenu.add_item("The Replacer") {
      TheReplacer.run
    }

    require_relative 'the_cleangroup'
    @my_submenu.add_item("Convert to Clean Group") {
      ConvertToCleanGroup.run
    }

    require_relative 'the_reset'
    @my_submenu.add_item("Reset The Group Scale") {
      load File.join(__dir__, 'the_reset.rb')
      TheResetScale.run
    }

    require_relative 'the_hideonscenemanager'
    @my_submenu.add_item("Hide on Scene Manager") {
      HideOnSceneManager.run
    }

    require_relative 'untagnpaint'
    @my_submenu.add_item("Untag and Paint") {
      UntagUnpaintManager.run
    }

    @my_submenu.add_separator

    require_relative 'updater'
    @my_submenu.add_item("Check for Updates...") {
      Updater.check(true)
    }

    # Cek otomatis saat SketchUp dibuka, dialog cuma muncul kalau ada update
    Updater.check

    file_loaded(__FILE__)
  end
end
