require 'sketchup'
require 'extensions'
require 'json'

module MyCustomPlugins
  PLUGIN_VERSION = "1.0.1"
  
  VERSION_URL = "https://raw.githubusercontent.com/muhqosob/boosok-tools/refs/heads/main/version.json"

  def self.check_for_updates(silent = true)
    headers = {
      'User-Agent' => 'BoosokTools-SketchupExtension',
      'Accept' => 'application/json'
    }
    
    # PERBAIKAN: Menggunakan Sketchup::Http::Request & Sketchup::Http::GET
    request = Sketchup::Http::Request.new(VERSION_URL, Sketchup::Http::GET)
    request.headers = headers

    request.start do |req, response|
      if response.nil?
        UI.messagebox("Tidak mendapat respon dari server.") unless silent
        next
      end

      status = response.status_code

      if status == 200
        begin
          data = JSON.parse(response.body)
          latest_version = data["version"]
          download_url = data["download_url"]
          changelog = data["changelog"]

          # Komparasi Versi
          if Gem::Version.new(latest_version) > Gem::Version.new(PLUGIN_VERSION)
            msg = "Pembaruan baru tersedia (#{latest_version})!\n\nCatatan Perubahan:\n#{changelog}\n\nApakah Anda ingin mengunduhnya sekarang?"
            
            result = UI.messagebox(msg, MB_YESNO)
            if result == IDYES
              UI.openURL(download_url)
            end
          else
            unless silent
              UI.messagebox("Boosok Tools sudah menggunakan versi terbaru (v#{PLUGIN_VERSION}).")
            end
          end
        rescue => e
          unless silent
            UI.messagebox("Gagal membaca data JSON: #{e.message}")
          end
        end
      else
        unless silent
          UI.messagebox("Gagal terhubung ke server (HTTP Status: #{status}).")
        end
      end
    end
  end

  unless file_loaded?(__FILE__)
    main_menu = UI.menu("Extensions")
    @my_submenu = main_menu.add_submenu("Boosok Tools")

    # 1. Memuat Plugin "The Selector"
    require_relative 'boosok_tools/main'
    @my_submenu.add_item("The Selector") {
      TheSelectorPlugin.run_selector
    }

    # 2. Memuat Plugin "Replace Group Tool"
    require_relative 'boosok_tools/the_replacer'
    @my_submenu.add_item("The Replacer") {
      TheReplacer.run
    }

    # 3. Memuat Plugin "G"
    require_relative 'boosok_tools/the_cleangroup'
    @my_submenu.add_item("Convert to Clean Group") {
      ConvertToCleanGroup.run
    }

    # 4. Memuat Plugin "The Reset Scale"
    require_relative 'boosok_tools/the_reset'
    @my_submenu.add_item("Reset The Group Scale") {
      TheResetScale.run
    }

    # 5. Memuat Plugin "The Hide on Scene Manager"
    require_relative 'boosok_tools/the_hideonscenemanager'
    @my_submenu.add_item("Hide on Scene Manager") {
      HideOnSceneManager.run
    }

    @my_submenu.add_separator

    # 6. Tombol Manual Cek Update
    @my_submenu.add_item("Check for Updates...") {
      self.check_for_updates(false)
    }

    # Cek otomatis saat SketchUp dibuka
    self.check_for_updates(true)

    file_loaded(__FILE__)
  end
end