require 'sketchup'
require 'extensions'
require 'json'

module MyCustomPlugins
  # Naikkan angka ini lalu push ke main: GitHub Actions otomatis bikin release + update version.json
  PLUGIN_VERSION = "1.0.8"

  # Semua versi yang sudah dirilis (1.0.0 - 1.0.7) membaca URL ini. Jangan dipindah.
  VERSION_URL = "https://raw.githubusercontent.com/muhqosob/boosok-tools/main/the_selector/version.json"
  RELEASES_URL = "https://github.com/muhqosob/boosok-tools/releases/latest"
  UPDATE_TIMEOUT = 15 # detik

  # Pakai Sketchup::Http (bukan Net::HTTP di Thread): thread Ruby di SketchUp
  # berhenti jalan saat idle, jadi cek update dulu diam saja tanpa pesan.
  def self.check_for_updates(manual = false)
    done = false

    on_error = lambda do |msg|
      next unless manual
      result = UI.messagebox("Gagal memeriksa pembaruan: #{msg}\n\nBuka halaman download di browser?", MB_YESNO)
      UI.openURL(RELEASES_URL) if result == IDYES
    end

    # Simpan referensi, kalau tidak request bisa kena GC dan callback tidak pernah jalan
    @update_request = Sketchup::Http::Request.new(VERSION_URL, Sketchup::Http::GET)
    @update_request.headers = { 'User-Agent' => 'BoosokTools-SketchupExtension' }
    @update_request.start do |_request, response|
      next if done
      done = true
      begin
        raise "Tidak ada respon dari server" if response.nil?
        raise "HTTP #{response.status_code}" unless response.status_code == 200

        data = JSON.parse(response.body)
        latest_version = data["version"]
        download_url = data["download_url"]
        changelog = data["changelog"]

        if Gem::Version.new(latest_version) > Gem::Version.new(PLUGIN_VERSION)
          result = UI.messagebox("Pembaruan baru tersedia (#{latest_version})!\n\nCatatan Perubahan:\n#{changelog}\n\nApakah Anda ingin mengunduhnya sekarang?", MB_YESNO)
          UI.openURL(download_url) if result == IDYES
        elsif manual
          UI.messagebox("Boosok Tools sudah versi terbaru (#{PLUGIN_VERSION}).")
        end
      rescue => e
        on_error.call(e.message)
      end
    end

    # Fallback kalau server/jaringan tidak pernah membalas
    UI.start_timer(UPDATE_TIMEOUT, false) do
      next if done
      done = true
      @update_request.cancel rescue nil
      on_error.call("Tidak ada respon dari server (timeout #{UPDATE_TIMEOUT} detik).")
    end
  end

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

    @my_submenu.add_separator

    @my_submenu.add_item("Check for Updates...") {
      self.check_for_updates(true)
    }

    # Cek otomatis saat SketchUp dibuka
    self.check_for_updates

    file_loaded(__FILE__)
  end
end
