require 'sketchup'
require 'extensions'
require 'json'

module MyCustomPlugins
  # Naikkan angka ini setiap rilis, harus sama dengan the_selector/version.json
  PLUGIN_VERSION = "1.0.7"

  # Satu-satunya sumber versi. Instalasi lama juga membaca URL ini, jangan dipindah.
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
    @update_request.start do |_request, response|
      next if done
      done = true
      begin
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

    # 3. Memuat Plugin "Hide Group"
    require_relative 'the_selector/hide_group_tools'
    @my_submenu.add_item("Hide Group") {
      MyTools::HideGroupHelper.hide_selected
    }
    @my_submenu.add_item("Unhide All Groups") {
      MyTools::HideGroupHelper.unhide_all
    }

    @my_submenu.add_separator

    # 4. Tombol Manual Cek Update
    @my_submenu.add_item("Check for Updates...") {
      self.check_for_updates(true)
    }

    # Cek otomatis saat SketchUp dibuka
    self.check_for_updates

    file_loaded(__FILE__)
  end
end