require 'sketchup'
require 'json'
Sketchup.require 'boosok_tools/ruby/titlebar'
Sketchup.require 'boosok_tools/ruby/shortcut_sync'
Sketchup.require 'boosok_tools/license'
Sketchup.require 'boosok_tools/ruby/locale'

module BoosokTools
  # Satu pintu masuk semua tool (Single Window Architecture).
  # Dialog tetap 1 jendela dan berpindah halaman HTML via window.location.replace
  # sehingga posisi jendela di layar tidak pernah bergeser atau berkedip.
  module Hub
    TITLE = "Boosok Tools" unless defined?(TITLE)
    WIDTH = 380 unless defined?(WIDTH)
    DEFAULT_HEIGHT = 480 unless defined?(DEFAULT_HEIGHT)

    # JANGAN pakai `unless defined?` di sini — TOOL_PAGES HARUS selalu di-assign ulang
    # setiap kali hub.rb di-load (hot-reload / update plugin). Kalau pakai `unless defined?`,
    # SketchUp akan terus pakai versi lama TOOL_PAGES dari memori → error "tidak dikenal".
    remove_const(:TOOL_PAGES) if defined?(TOOL_PAGES)
    TOOL_PAGES = {
      'selector'      => { file: 'ruby/free/selector',            page: 'selector.html',        title: 'Selector' },
      'custom_select' => { file: 'ruby/paid/select_tool',         page: nil,                    title: 'Select Tools' },
      'replacer'      => { file: 'ruby/free/replacer',            page: 'replacer.html',        title: 'Group Replacer' },
      'clean'         => { file: 'ruby/free/cleangroup',          page: 'cleangroup.html',      title: 'Group Cleaner' },
      'reset'         => { file: 'ruby/free/reset',               page: 'reset.html',           title: 'Reset Scale' },
      'scene'         => { file: 'ruby/paid/hideon_scene',        page: 'hidescene.html',       title: 'Hide on Scene' },
      'untag'         => { file: 'ruby/free/untagnpaint',           page: 'untagnpaint.html',     title: 'Untag & Unpaint' },
      'deep'          => { file: 'ruby/paid/deep_properties',     page: 'deep_properties.html', title: 'Deep Properties' },
      'purge'         => { file: 'ruby/free/purge',               page: 'purge.html',           title: 'Purge', width: 800 },
      'void'          => { file: 'ruby/paid/void',                page: 'void.html',            title: 'Void' },
      'slice'         => { file: 'ruby/paid/slice',               page: 'slice.html',           title: 'Slice' },
      'trowel'        => { file: 'ruby/paid/trowel',              page: 'trowel.html',          title: 'Trowel' }
    }.freeze

    # Tool yang tetap bisa dipakai walau trial habis dan belum berlisensi. Sisanya (Select Tools, Hide Scene,
    # Deep Props, Void, Slice) butuh lisensi aktif atau masa trial. Tanpa `unless defined?` supaya daftar ikut berubah saat reload.
    remove_const(:FREE_TOOLS) if defined?(FREE_TOOLS)
    FREE_TOOLS = %w[selector replacer reset clean untag purge].freeze

    # Boleh dibuka? Tool gratis selalu boleh; selain itu butuh lisensi aktif / masa trial.
    def self.tool_allowed?(id)
      return true if FREE_TOOLS.include?(id.to_s)

      !defined?(BoosokTools::License) || BoosokTools::License.can_use?
    end

    @current_tool ||= 'hub'

    # Catat callback dialog yang lambat ke Ruby Console, contoh:
    #   [Boosok perf] dp_scan: 812.4 ms
    # Supaya sumber jeda/not responding bisa langsung kelihatan tanpa menebak.
    SLOW_MS = 80 unless defined?(SLOW_MS)
    module SlowCallbackLog
      def add_action_callback(name, &blk)
        super(name) do |*args|
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          begin
            blk.call(*args)
          ensure
            ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000.0
            puts format('[Boosok perf] %s: %.1f ms', name, ms) if ms >= SLOW_MS
          end
        end
      end
    end

    def self.dialog
      BoosokTools.dialog
    end

    def self.dialog=(d)
      BoosokTools.dialog = d
    end

    def self.current_tool
      @current_tool || 'hub'
    end

    def self.has_booted?
      BoosokTools.hub_booted?
    end

    def self.set_booted(val = true)
      BoosokTools.set_hub_booted(val)
    end

    def self.show(custom_page = nil, tool_id = nil)
      dlg = BoosokTools.dialog
      if dlg && dlg.visible?
        if tool_id
          open_tool(tool_id)
        elsif custom_page
          navigate_to(custom_page)
        else
          back_to_hub
        end
        dlg.bring_to_front
        return
      end

      TitleBar.get_sketchup_hwnd rescue nil
      BoosokTools::Locale.export_js # murah: hanya menulis ulang kalau ada file bahasa yang berubah
      pos = BoosokTools.get_position(WIDTH, DEFAULT_HEIGHT)

      width = (tool_id && TOOL_PAGES[tool_id.to_s] && TOOL_PAGES[tool_id.to_s][:width]) || WIDTH
      dlg = UI::HtmlDialog.new(
        dialog_title: TITLE,
        scrollable: false,
        resizable: false,
        width: width,
        height: DEFAULT_HEIGHT,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      dlg.extend(SlowCallbackLog)
      BoosokTools.dialog = dlg

      if pos && pos[0] > 5 && pos[1] > 5
        dlg.set_position(pos[0], pos[1])
      end

      page_file = custom_page || 'hub.html'
      dlg.set_file(File.join(::BoosokTools::SUPPORT_DIR, 'html', page_file))
      TitleBar.attach(dlg, TITLE, width: width)

      @current_tool = tool_id ? tool_id.to_s : 'hub'
      # Dibuka langsung ke sebuah tool (menu/hotkey): loader pembuka tidak perlu muncul nanti
      # saat user menekan Kembali ke Hub.
      BoosokTools.set_hub_booted(true) if tool_id
      attach_hub_callbacks(dlg)
      # Semua callback tool HARUS terdaftar sebelum dlg.show. Callback yang baru ditambah
      # setelah dialog tampil tidak dikenali `sketchup.*` di halaman tool → "Fungsi belum siap".
      # File tool di-load sekali per sesi (biasanya sudah di-preload saat SketchUp start).
      preload_tools
      attach_all_tool_callbacks(dlg)
      # attach_callbacks beberapa tool ikut menyalakan timer/observer → matikan yang tidak sedang dibuka
      TOOL_PAGES.each_key { |tid| deactivate_tool(tid) unless tid == @current_tool }

      dlg.set_on_closed do
        BoosokTools.capture_current_position(TITLE)
        # Penutupan dialog LAMA (mis. saat reload/buka ulang cepat) bisa tiba setelah dialog baru terpasang. Jangan
        # sentuh pendaftaran callback & state milik dialog baru: kalau terhapus, callback terdaftar lagi di dialog
        # yang sama dan tiap aksi (mis. Replacer) jalan dua kali.
        if BoosokTools.dialog.nil? || BoosokTools.dialog.equal?(dlg)
          TOOL_PAGES.each_key { |tid| deactivate_tool(tid) }
          ConvertToCleanGroup.release_dialog if defined?(ConvertToCleanGroup)
          TheReplacer.release_dialog if defined?(TheReplacer)
          TheResetScale.release_dialog if defined?(TheResetScale)
          UntagUnpaintManager.release_dialog if defined?(UntagUnpaintManager)
          Purge.release_dialog if defined?(Purge)
          Void.release_dialog if defined?(Void)
          Slice.release_dialog if defined?(Slice)
          Trowel.release_dialog if defined?(Trowel)
          DeepProperties.instance_variable_set(:@callbacks_registered, false) rescue nil if defined?(DeepProperties)
          DeepProperties.instance_variable_set(:@dialog_registered_id, nil) rescue nil if defined?(DeepProperties)
          TheSelectorPlugin.instance_variable_set(:@callbacks_registered, false) rescue nil if defined?(TheSelectorPlugin)
          TheSelectorPlugin.instance_variable_set(:@dialog_registered_id, nil) rescue nil if defined?(TheSelectorPlugin)
          HideOnSceneManager.instance_variable_set(:@callbacks_registered, false) rescue nil if defined?(HideOnSceneManager)
          HideOnSceneManager.instance_variable_set(:@dialog_registered_id, nil) rescue nil if defined?(HideOnSceneManager)
          # Nonaktifkan Select Tool jika masih aktif
          begin
            model = Sketchup.active_model
            model.select_tool(nil) if model && model.respond_to?(:select_tool)
          rescue
          end
          BoosokTools.dialog = nil
          @current_tool = 'hub'
        end
      end

      # State dikirim saat halaman memanggil hub_ready/ready — tidak perlu timer di sini.
      dlg.show
    end

    # Matikan timer/observer milik tool yang sedang tidak dibuka.
    def self.deactivate_tool(id)
      case id.to_s
      when 'replacer' then TheReplacer.stop_cache_timer if defined?(TheReplacer)
      when 'selector' then TheSelectorPlugin.detach_all_observers if defined?(TheSelectorPlugin)
      when 'scene'    then HideOnSceneManager.detach_all_observers if defined?(HideOnSceneManager)
      when 'slice'    then Slice.leave if defined?(Slice)
      end
    rescue => e
      puts "[Boosok Tools] deactivate_tool '#{id}': #{e.message}"
    end

    def self.open_or_show(id)
      cfg = TOOL_PAGES[id.to_s]
      return unless cfg

      # Trial habis & belum berlisensi: tool berbayar cukup diberi notifikasi terkunci (tanpa popup aktivasi)
      unless tool_allowed?(id)
        notify_locked
        return
      end

      if id.to_s == 'custom_select'
        load_tool_file(id.to_s) unless defined?(BoosokTools::SelectTool)
        BoosokTools::SelectTool.activate_tool if defined?(BoosokTools::SelectTool)
        return
      end

      dlg = BoosokTools.dialog
      if dlg && dlg.visible?
        open_tool(id.to_s)
        dlg.bring_to_front
      else
        show(cfg[:page], id.to_s)
      end
    end

    def self.open_tool(id)
      dlg = BoosokTools.dialog
      return unless dlg && dlg.visible?

      # Tool berbayar terkunci jika trial habis dan belum berlisensi
      unless tool_allowed?(id)
        notify_locked
        return
      end

      cfg = TOOL_PAGES[id.to_s]
      return toast("Tool \"#{id}\" tidak dikenal.") unless cfg

      if id.to_s == 'custom_select'
        load_tool_file(id.to_s) unless defined?(BoosokTools::SelectTool)
        BoosokTools::SelectTool.activate_tool if defined?(BoosokTools::SelectTool)
        return
      end

      deactivate_tool(@current_tool) if @current_tool != id.to_s
      # Nonaktifkan Select Tool jika user berpindah ke tool lain
      begin
        model = Sketchup.active_model
        model.select_tool(nil) if model && model.respond_to?(:select_tool)
      rescue
      end
      @current_tool = id.to_s

      # File tool cukup di-load sekali per sesi (tidak di-parse ulang tiap buka)
      preload_tools
      attach_tool_callbacks(id.to_s)
      TitleBar.apply_width(dlg, cfg[:width] || WIDTH)
      navigate_to(cfg[:page])
    rescue Exception => e
      puts "[Boosok Tools] Gagal membuka #{id}: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n") rescue ''}"
      toast("Gagal membuka tool: #{e.message}")
    end

    def self.load_tool_file(id)
      cfg = TOOL_PAGES[id.to_s]
      return unless cfg && cfg[:file]
      # cfg[:file] = nama modul tanpa ekstensi (di paket terenkripsi file aslinya .rbe)
      BoosokTools.load_module(cfg[:file])
      true
    rescue Exception => e
      puts "[Boosok Tools] Gagal memuat file tool '#{id}': #{e.class}: #{e.message}"
      false
    end

    # Load semua file tool satu kali per sesi supaya modulnya sudah ada saat callback didaftarkan.
    def self.preload_tools
      @preloaded ||= {}
      TOOL_PAGES.each do |id, cfg|
        next if id == 'custom_select' || @preloaded[id]
        @preloaded[id] = true if load_tool_file(id)
      end
    end

    def self.back_to_hub
      dlg = BoosokTools.dialog
      return unless dlg && dlg.visible?

      deactivate_tool(@current_tool)
      # Nonaktifkan Select Tool saat kembali ke hub
      begin
        model = Sketchup.active_model
        model.select_tool(nil) if model && model.respond_to?(:select_tool)
      rescue
      end
      @current_tool = 'hub'
      TitleBar.apply_width(dlg, WIDTH)
      # Callback hub sudah terdaftar sejak show — tidak perlu didaftarkan ulang tiap kembali
      navigate_to('hub.html')
    end

    def self.navigate_to(page)
      dlg = BoosokTools.dialog
      return unless dlg && dlg.visible?
      dlg.execute_script("window.location.replace(#{page.to_json});")
    end

    def self.attach_hub_callbacks(dlg)
      return unless dlg

      # Satu kali render per load halaman hub (state sudah murah karena di-cache).
      # has_booted TIDAK dipaksa true di sini: false sampai halaman memanggil "boot_done"
      # (selesai menampilkan loader pembuka). Setelah itu loader tidak muncul lagi di sesi ini.
      dlg.add_action_callback("hub_ready") do |_ctx|
        dlg.execute_script("if (typeof render === 'function') render(#{state.to_json});")
        flush_notice if BoosokTools.hub_booted? # kalau loader pembuka belum selesai, tunggu boot_done
      end

      # Dipanggil saat jendela hub kembali difokus: hanya angka statistik & lisensi, tanpa redraw penuh.
      dlg.add_action_callback("hub_refresh") do |_ctx|
        next unless @current_tool == 'hub'
        model = Sketchup.active_model
        lite = {
          stats: model ? model_stats(model) : { objects: 0, scenes: 0, selected: 0 },
          license: (defined?(BoosokTools::License) ? BoosokTools::License.status : nil)
        }
        dlg.execute_script("if (typeof onHubRefresh === 'function') onHubRefresh(#{lite.to_json});")
        # Cek ulang lisensi online ke server (async, jarang: paling cepat tiap 12 jam). Bila key dicabut: perbarui tampilan.
        if defined?(BoosokTools::License)
          BoosokTools::License.maybe_refresh do |changed|
            next unless changed && dlg.visible?

            dlg.execute_script("if (typeof onHubRefresh === 'function') onHubRefresh(#{{ license: BoosokTools::License.status }.to_json});")
            dlg.execute_script("if (typeof onLicenseStatus === 'function') onLicenseStatus(#{BoosokTools::License.status.to_json});")
          end
        end
      end

      dlg.add_action_callback("ready") do |_ctx|
        if @current_tool == 'hub'
          dlg.execute_script("if (typeof render === 'function') render(#{state.to_json});")
        elsif @current_tool == 'scene' && defined?(HideOnSceneManager)
          HideOnSceneManager.send_init_data(dlg)
        elsif @current_tool == 'selector' && defined?(TheSelectorPlugin)
          TheSelectorPlugin.send_init_data(dlg)
        elsif @current_tool == 'deep' && defined?(DeepProperties)
          DeepProperties.send_init_data(dlg)
        elsif @current_tool == 'void' && defined?(Void)
          Void.send_init_data(dlg)
        elsif @current_tool == 'slice' && defined?(Slice)
          Slice.send_init_data(dlg)
        elsif @current_tool == 'trowel' && defined?(Trowel)
          Trowel.send_init_data(dlg)
        end
      end

      # Select Tool (dipakai Replacer & tab Objek di Hide Scene) — satu pendaftaran saja
      dlg.add_action_callback("activate_select_tool") do |_ctx|
        begin
          # Tanpa lisensi / trial habis: pakai tool Select bawaan SketchUp, bukan Select Tools Boosok
          boosok_select = tool_allowed?('custom_select')
          if boosok_select
            load_tool_file('custom_select') unless defined?(BoosokTools::SelectTool)
            BoosokTools::SelectTool.activate_tool if defined?(BoosokTools::SelectTool)
          else
            Sketchup.active_model.select_tool(nil)
          end
          dlg.execute_script("if (typeof onSelectMode === 'function') onSelectMode(#{boosok_select});")
        rescue => e
          puts "[Boosok Hub] Gagal aktifkan Select Tool: #{e.message}"
        end
      end

      dlg.add_action_callback("deactivate_select_tool") do |_ctx|
        begin
          Sketchup.active_model.select_tool(nil)
        rescue => e
          puts "[Boosok Hub] Gagal nonaktifkan Select Tool: #{e.message}"
        end
      end

      dlg.add_action_callback("boot_done") do |_ctx|
        BoosokTools.set_hub_booted(true)
        flush_notice(0.9) # tunggu fade-out loader (0,9 dtk) selesai
      end

      dlg.add_action_callback("open") do |_ctx, id, pos_json|
        pos_data = JSON.parse(pos_json) rescue nil
        if pos_data && pos_data["left"] && pos_data["top"]
          BoosokTools.save_position(pos_data["left"], pos_data["top"])
        else
          BoosokTools.capture_current_position(TITLE)
        end
        open_tool(id.to_s)
      end

      # "back_to_hub" & "save_position" sudah didaftarkan oleh TitleBar.attach — jangan dobel.

      dlg.add_action_callback("updates") do |_ctx|
        # Push state update inline ke hub (bukan buka dialog baru)
        BoosokTools::Updater.check_inline(dlg)
      end

      dlg.add_action_callback("update_download") do |_ctx|
        BoosokTools::Updater.download_inline(dlg)
      end

      dlg.add_action_callback("get_hotkeys") do |_ctx|
        begin
          shortcuts = BoosokTools::ShortcutSync.get_all_shortcuts
          dlg.execute_script("if (typeof onHotkeysLoaded === 'function') onHotkeysLoaded(#{shortcuts.to_json});")
        rescue => e
          puts "[Boosok Hub] get_hotkeys error: #{e.message}"
        end
      end

      dlg.add_action_callback("save_hotkeys") do |_ctx, hotkeys_json|
        begin
          data = JSON.parse(hotkeys_json) rescue {}
          clean_hash = {}
          if data.is_a?(Array)
            data.each { |item| clean_hash[item['id']] = item['key'] }
          elsif data.is_a?(Hash)
            clean_hash = data
          end

          success = BoosokTools::ShortcutSync.save_shortcuts_to_file(clean_hash)
          dat_path = BoosokTools::ShortcutSync.generate_dat_file(clean_hash)
          dlg.execute_script("if (typeof onHotkeysSaved === 'function') onHotkeysSaved(#{success.to_json}, #{dat_path.to_json});")
        rescue => e
          puts "[Boosok Hub] save_hotkeys error: #{e.message}"
          dlg.execute_script("if (typeof onHotkeysSaved === 'function') onHotkeysSaved(false, #{e.message.to_json});")
        end
      end

      dlg.add_action_callback("apply_hotkeys_to_sketchup") do |_ctx, hotkeys_json|
        begin
          data = JSON.parse(hotkeys_json) rescue {}
          clean_hash = {}
          if data.is_a?(Array)
            data.each { |item| clean_hash[item['id']] = item['key'] }
          elsif data.is_a?(Hash)
            clean_hash = data
          end

          dat_path = BoosokTools::ShortcutSync.apply_to_sketchup(clean_hash)
          dlg.execute_script("if (typeof onHotkeysApplied === 'function') onHotkeysApplied(true, #{dat_path.to_json});")
        rescue => e
          puts "[Boosok Hub] apply_hotkeys_to_sketchup error: #{e.message}"
          dlg.execute_script("if (typeof onHotkeysApplied === 'function') onHotkeysApplied(false, #{e.message.to_json});")
        end
      end

      dlg.add_action_callback("open_shortcut_prefs") do |_ctx|
        # Buka SketchUp Preferences > Shortcuts
        begin
          if UI.respond_to?(:show_preferences)
            UI.show_preferences('Shortcuts') rescue UI.show_preferences
          else
            Sketchup.send_action("showPreferences:") rescue Sketchup.send_action(21022) rescue nil
          end
        rescue => e
          puts "[Boosok Hub] open_shortcut_prefs error: #{e.message}"
        end
      end

      # ── Lisensi Callbacks ──────────────────────────────
      dlg.add_action_callback("get_license_status") do |_ctx|
        begin
          st = defined?(BoosokTools::License) ? BoosokTools::License.status : { status: 'unavailable' }
          dlg.execute_script("if (typeof onLicenseStatus === 'function') onLicenseStatus(#{st.to_json});")
        rescue => e
          dlg.execute_script("if (typeof onLicenseStatus === 'function') onLicenseStatus({status:'error',error:#{e.message.to_json}});")
        end
      end

      # Aktivasi: key dicek ke server lisensi (jawaban datang async); key lama tetap diterima offline
      dlg.add_action_callback("validate_license") do |_ctx, key_json|
        key = (JSON.parse(key_json) rescue key_json.to_s).to_s
        lic = defined?(BoosokTools::License) ? BoosokTools::License : nil
        js = lambda { |code| dlg.execute_script(code) if dlg.visible? }
        if lic.nil?
          js.call("if (typeof onLicenseValidated === 'function') onLicenseValidated(false, null, 'error');")
        else
          begin
            lic.activate(key) do |res|
              if res[:ok]
                js.call("if (typeof onLicenseValidated === 'function') onLicenseValidated(true, #{lic.status.to_json});")
              else
                js.call("if (typeof onLicenseValidated === 'function') onLicenseValidated(false, null, #{res[:error].to_s.to_json}, #{{ used: res[:used], max: res[:max] }.to_json});")
              end
            end
          rescue => e
            puts "[Boosok Hub] validate_license error: #{e.message}"
            js.call("if (typeof onLicenseValidated === 'function') onLicenseValidated(false, null, 'error');")
          end
        end
      end

      # Hapus aktivasi = lepas perangkat ini dari key di server (perangkat lain bisa memakai slot-nya)
      dlg.add_action_callback("remove_license") do |_ctx|
        lic = defined?(BoosokTools::License) ? BoosokTools::License : nil
        next unless lic

        begin
          lic.release do |res|
            next unless dlg.visible?

            if res[:ok]
              dlg.execute_script("if (typeof onLicenseStatus === 'function') onLicenseStatus(#{lic.status.to_json});")
              dlg.execute_script("if (typeof onLicenseRemoved === 'function') onLicenseRemoved(true);")
            else
              dlg.execute_script("if (typeof onLicenseRemoved === 'function') onLicenseRemoved(false, #{res[:error].to_s.to_json});")
            end
          end
        rescue => e
          puts "[Boosok Hub] remove_license error: #{e.message}"
        end
      end

      dlg.add_action_callback("open_external_url") do |_ctx, url_json|
        begin
          url = JSON.parse(url_json) rescue url_json.to_s
          UI.openURL(url.to_s)
        rescue => e
          puts "[Boosok Hub] open_external_url error: #{e.message}"
        end
      end

      # ── Pengaturan Bahasa / Locales ───────────────────
      dlg.add_action_callback("get_languages") do |_ctx|
        begin
          locales = BoosokTools::Locale.all_locales(true)
          # File bahasa baru yang ditambahkan saat SketchUp berjalan ikut diekspor ke js/strings.js
          # (dipakai halaman tool pada pemuatan berikutnya)
          BoosokTools::Locale.export_js
          cur_lang = BoosokTools::Locale.current_language
          dlg.execute_script("if (typeof onLanguagesLoaded === 'function') onLanguagesLoaded(#{locales.to_json}, #{cur_lang.to_json});")
        rescue => e
          puts "[Boosok Hub] get_languages error: #{e.message}"
        end
      end

      dlg.add_action_callback("set_language") do |_ctx, lang_code|
        begin
          saved = BoosokTools::Locale.set_language(lang_code)
          dlg.execute_script("if (typeof onLanguageSaved === 'function') onLanguageSaved(#{saved.to_json});")
        rescue => e
          puts "[Boosok Hub] set_language error: #{e.message}"
        end
      end

      dlg.add_action_callback("open_locales_folder") do |_ctx|
        begin
          BoosokTools::Locale.open_locales_folder
        rescue => e
          puts "[Boosok Hub] open_locales_folder error: #{e.message}"
        end
      end
    end

    def self.attach_all_tool_callbacks(dlg)
      return unless dlg
      # Register callbacks semua tool yang modulnya sudah ter-load (lihat preload_tools).
      TOOL_PAGES.each_key do |id|
        next if id.to_s == 'custom_select'
        attach_tool_callbacks(id.to_s, dlg)
      end
    end

    def self.attach_tool_callbacks(id, target_dlg = nil)
      dlg = target_dlg || BoosokTools.dialog
      return unless dlg
      case id.to_s
      when 'selector'
        TheSelectorPlugin.attach_callbacks(dlg) if defined?(TheSelectorPlugin)
      when 'replacer'
        TheReplacer.attach_callbacks(dlg) if defined?(TheReplacer)
      when 'clean'
        ConvertToCleanGroup.attach_callbacks(dlg) if defined?(ConvertToCleanGroup)
      when 'reset'
        TheResetScale.attach_callbacks(dlg) if defined?(TheResetScale)
      when 'scene'
        HideOnSceneManager.attach_callbacks(dlg) if defined?(HideOnSceneManager)
      when 'untag'
        UntagUnpaintManager.attach_callbacks(dlg) if defined?(UntagUnpaintManager)
      when 'deep'
        DeepProperties.attach_callbacks(dlg) if defined?(DeepProperties)
      when 'purge'
        Purge.attach_callbacks(dlg) if defined?(Purge)
      when 'void'
        Void.attach_callbacks(dlg) if defined?(Void)
      when 'slice'
        Slice.attach_callbacks(dlg) if defined?(Slice)
      when 'trowel'
        Trowel.attach_callbacks(dlg) if defined?(Trowel)
      end
    end

    STATS_TTL = 10 unless defined?(STATS_TTL)

    # Jumlah group/component di level atas. Scan entitas mahal di model besar, jadi hasilnya
    # di-cache dan hanya dihitung ulang kalau jumlah entitas berubah atau cache sudah > 10 detik.
    def self.model_stats(model)
      top = model.entities # rubocop:disable SketchupSuggestions/ModelEntities -- statistik seluruh model, bukan konteks edit
      key = [model.object_id, top.length]
      now = Time.now.to_f
      if @stats_key != key || !@stats_at || now - @stats_at > STATS_TTL
        @stats_objects = top.count { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        @stats_key = key
        @stats_at = now
      end
      { objects: @stats_objects, scenes: model.pages.size, selected: model.selection.size }
    end

    def self.state
      booted = BoosokTools.hub_booted?
      model = Sketchup.active_model
      return { status: 'error', error: "Tidak ada model yang aktif. Buka atau buat model dulu.", has_booted: booted } unless model

      lic_st = defined?(BoosokTools::License) ? BoosokTools::License.status : { status: 'expired', can_use: false, days_left: 0 }
      cur_lang = BoosokTools::Locale.current_language
      {
        status: 'ready',
        has_booted: booted,
        session_id: (BoosokTools.session_id rescue ''),
        version: BoosokTools::PLUGIN_VERSION,
        theme: Sketchup.read_default("BoosokTools", "theme", "").to_s,
        language: cur_lang,
        hotkeys: (BoosokTools::ShortcutSync.get_all_shortcuts rescue {}),
        license: lic_st,
        free_tools: FREE_TOOLS,
        stats: model_stats(model)
      }
    rescue => e
      { status: 'error', error: "Gagal membaca model: #{e.message}", has_booted: BoosokTools.hub_booted? }
    end

    # Pesan "terkunci" (ikut bahasa terpilih)
    def self.locked_message
      BoosokTools::Locale.t('lic_trial_expired_toast', 'Masa trial 7 hari telah habis.')
    end

    # Notifikasi biasa (bukan popup aktivasi). Kalau dialog Hub belum terbuka, buka dulu lalu
    # tampilkan notifnya setelah halaman siap (lihat flush_notice).
    def self.notify_locked
      msg = locked_message
      begin
        Sketchup.status_text = msg # juga tampil di status bar SketchUp
      rescue
      end
      dlg = BoosokTools.dialog
      if dlg && dlg.visible?
        notify(msg)
      else
        @pending_notice = msg
        show
      end
    end

    def self.notify(msg)
      dlg = BoosokTools.dialog
      return unless dlg && dlg.visible?
      dlg.execute_script("if (typeof showToast === 'function') showToast(#{msg.to_json}, 'error');")
    end

    # Kirim notif yang tertunda. Dipanggil setelah Hub siap (dan setelah loader pembuka selesai).
    def self.flush_notice(delay = 0.3)
      return unless @pending_notice
      msg = @pending_notice
      @pending_notice = nil
      UI.start_timer(delay, false) { notify(msg) }
    end

    def self.toast(msg)
      dlg = BoosokTools.dialog
      dlg.execute_script("if (typeof onOpenFailed === 'function') onOpenFailed(#{msg.to_json}); else if (typeof showToast === 'function') showToast(#{msg.to_json});") if dlg && dlg.visible?
    end

    def self.push(st)
      dlg = BoosokTools.dialog
      dlg.execute_script("if (typeof render === 'function') render(#{st.to_json});") if dlg && dlg.visible?
    end
  end
end
