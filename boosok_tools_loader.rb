require 'sketchup'
require 'extensions'
require 'net/http'
require 'json'
require 'uri'

module MyCustomPlugins
  PLUGIN_VERSION = "1.0.0"
  
  # PERHATIKAN PATH DENGAN TAMBAHAN FOLDER 'the_selector/' DI BAWAH INI:
  VERSION_URL = URI.parse("https://raw.githubusercontent.com/muhqosob/boosok-tools/main/the_selector/version.json")

  def self.check_for_updates
    Thread.new do
      begin
        response = Net::HTTP.get_response(VERSION_URL)
        if response.is_a?(Net::HTTPSuccess)
          data = JSON.parse(response.body)
          latest_version = data["version"]
          download_url = data["download_url"]
          changelog = data["changelog"]

          if latest_version > PLUGIN_VERSION
            UI.start_timer(0.1, false) {
              result = UI.messagebox("Pembaruan baru tersedia (#{latest_version})!\n\nCatatan Perubahan:\n#{changelog}\n\nApakah Anda ingin mengunduhnya sekarang?", MB_YESNO)
              if result == IDYES
                UI.openURL(download_url)
              end
            }
          end
        end
      rescue => e
        # Abaikan jika koneksi internet terputus/gagal
      end
    end
  end

  unless file_loaded?(__FILE__)
    main_menu = UI.menu("Extensions")
    @my_submenu = main_menu.add_submenu("Boosok Tools")

    # 1. Memuat Plugin "The Selector"
    require_relative 'the_selector/main'
    @my_submenu.add_item("The Selector") {
      TheSelectorPlugin.run_selector
    }

    # 2. Memuat Plugin "Replace Group Tool"
    require_relative 'the_selector/replace_group_tools'
    @my_submenu.add_item("Replace Group Tool") {
      MyTools::ReplaceGroupHelper.run
    }

    @my_submenu.add_separator

    # 3. Tombol Manual Cek Update
    @my_submenu.add_item("Check for Updates...") {
      self.check_for_updates
      UI.messagebox("Memeriksa pembaruan dari server...")
    }

    # Cek otomatis saat SketchUp dibuka
    self.check_for_updates

    file_loaded(__FILE__)
  end
end