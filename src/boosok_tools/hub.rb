require 'sketchup'
require 'json'
require_relative 'titlebar'
require_relative 'shortcut_sync'
require_relative 'license'

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
      'selector'      => { file: 'main.rb',                   page: 'selector.html',        title: 'Selector' },
      'custom_select' => { file: 'the_custom_select.rb',      page: nil,                    title: 'Select Tools' },
      'replacer'      => { file: 'the_replacer.rb',           page: 'replacer.html',        title: 'Group Replacer' },
      'clean'         => { file: 'the_cleangroup.rb',         page: 'cleangroup.html',      title: 'Group Cleaner' },
      'reset'         => { file: 'the_reset.rb',              page: 'reset.html',           title: 'Reset Scale' },
      'scene'         => { file: 'the_hideonscenemanager.rb', page: 'hidescene.html',       title: 'Hide on Scene' },
      'untag'         => { file: 'untagnpaint.rb',            page: 'untagnpaint.html',     title: 'Untag & Unpaint' },
      'deep'          => { file: 'deep_properties.rb',        page: 'deep_properties.html', title: 'Deep Properties' }
    }.freeze

    @current_tool ||= 'hub'

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
        attach_all_callbacks(dlg)
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
      pos = BoosokTools.get_position(WIDTH, DEFAULT_HEIGHT)

      dlg = UI::HtmlDialog.new(
        dialog_title: TITLE,
        scrollable: false,
        resizable: false,
        width: WIDTH,
        height: DEFAULT_HEIGHT,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      BoosokTools.dialog = dlg

      if pos && pos[0] > 5 && pos[1] > 5
        dlg.set_position(pos[0], pos[1])
      end

      page_file = custom_page || 'hub.html'
      dlg.set_file(File.join(__dir__, 'html', page_file))
      TitleBar.attach(dlg, TITLE, width: WIDTH)

      @current_tool = tool_id ? tool_id.to_s : 'hub'
      attach_all_callbacks(dlg)

      dlg.set_on_closed do
        BoosokTools.capture_current_position(TITLE)
        HideOnSceneManager.detach_all_observers rescue nil if defined?(HideOnSceneManager)
        TheSelectorPlugin.detach_all_observers rescue nil if defined?(TheSelectorPlugin)
        # Nonaktifkan Select Tool jika masih aktif
        begin
          model = Sketchup.active_model
          model.select_tool(nil) if model && model.respond_to?(:select_tool)
        rescue
        end
        BoosokTools.dialog = nil
        @current_tool = 'hub'
      end

      dlg.show
    end

    def self.open_or_show(id)
      cfg = TOOL_PAGES[id.to_s]
      return unless cfg

      # Cek apakah lisensi / trial mengizinkan penggunaan tool
      if defined?(BoosokTools::License) && !BoosokTools::License.can_use?
        show
        dlg = BoosokTools.dialog
        if dlg && dlg.visible?
          dlg.execute_script("if (typeof onLicenseExpiredPrompt === 'function') onLicenseExpiredPrompt(); else if (typeof openAbout === 'function') openAbout();") rescue nil
        end
        UI.messagebox("Masa uji coba (trial 7 hari) Boosok Tools telah habis.\nSemua tool terkunci.\n\nSilakan masukkan lisensi key di jendela Hub untuk membuka.") rescue nil
        return
      end

      if id.to_s == 'custom_select'
        load_tool_file(id.to_s)
        BoosokTools::SelectTool5D.activate_tool if defined?(BoosokTools::SelectTool5D)
        dlg = BoosokTools.dialog
        dlg.close rescue nil if dlg && dlg.visible?
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

      # Kunci semua tool jika trial habis dan belum berlisensi
      if defined?(BoosokTools::License) && !BoosokTools::License.can_use?
        toast("Masa trial 7 hari telah habis. Semua tool terkunci.")
        dlg.execute_script("if (typeof onLicenseExpiredPrompt === 'function') onLicenseExpiredPrompt(); else if (typeof openAbout === 'function') openAbout();") rescue nil
        return
      end

      cfg = TOOL_PAGES[id.to_s]
      return toast("Tool \"#{id}\" tidak dikenal.") unless cfg

      if id.to_s == 'custom_select'
        load_tool_file(id.to_s)
        BoosokTools::SelectTool5D.activate_tool if defined?(BoosokTools::SelectTool5D)
        dlg.close rescue nil
        return
      end

      if @current_tool == 'scene' && id.to_s != 'scene'
        HideOnSceneManager.detach_all_observers rescue nil if defined?(HideOnSceneManager)
      end
      if @current_tool == 'selector' && id.to_s != 'selector'
        TheSelectorPlugin.detach_all_observers rescue nil if defined?(TheSelectorPlugin)
      end
      if @current_tool == 'deep' && id.to_s != 'deep'
        DeepProperties.instance_variable_set(:@callbacks_registered, false) rescue nil if defined?(DeepProperties)
      end
      # Nonaktifkan Select Tool jika user berpindah ke tool lain
      begin
        model = Sketchup.active_model
        model.select_tool(nil) if model && model.respond_to?(:select_tool)
      rescue
      end
      @current_tool = id.to_s

      load_tool_file(id.to_s)
      attach_tool_callbacks(id.to_s)
      navigate_to(cfg[:page])
    rescue Exception => e
      puts "[Boosok Tools] Gagal membuka #{id}: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n") rescue ''}"
      toast("Gagal membuka tool: #{e.message}")
    end

    def self.load_tool_file(id)
      cfg = TOOL_PAGES[id.to_s]
      return unless cfg && cfg[:file]
      file_path = File.join(__dir__, cfg[:file])
      load file_path if File.exist?(file_path)
    rescue => e
      puts "[Boosok Tools] Gagal memuat file tool '#{id}': #{e.class}: #{e.message}"
    end

    def self.back_to_hub
      dlg = BoosokTools.dialog
      return unless dlg && dlg.visible?

      if @current_tool == 'scene'
        HideOnSceneManager.detach_all_observers rescue nil if defined?(HideOnSceneManager)
      end
      if @current_tool == 'selector'
        TheSelectorPlugin.detach_all_observers rescue nil if defined?(TheSelectorPlugin)
      end
      if @current_tool == 'deep'
        DeepProperties.instance_variable_set(:@callbacks_registered, false) rescue nil if defined?(DeepProperties)
      end
      # Nonaktifkan Select Tool saat kembali ke hub
      begin
        model = Sketchup.active_model
        model.select_tool(nil) if model && model.respond_to?(:select_tool)
      rescue
      end
      @current_tool = 'hub'
      attach_hub_callbacks(dlg)
      navigate_to('hub.html')
    end

    def self.navigate_to(page)
      dlg = BoosokTools.dialog
      return unless dlg && dlg.visible?
      dlg.execute_script("window.location.replace(#{page.to_json});")
    end

    def self.attach_hub_callbacks(dlg)
      return unless dlg

      dlg.add_action_callback("hub_ready") do |_ctx|
        push(state)
      end

      dlg.add_action_callback("ready") do |_ctx|
        if @current_tool == 'hub'
          push(state)
        elsif @current_tool == 'scene' && defined?(HideOnSceneManager)
          HideOnSceneManager.send_init_data(dlg)
        elsif @current_tool == 'selector' && defined?(TheSelectorPlugin)
          TheSelectorPlugin.send_init_data(dlg)
        elsif @current_tool == 'deep' && defined?(DeepProperties)
          DeepProperties.send_init_data(dlg)
        end
      end

      dlg.add_action_callback("boot_done") do |_ctx|
        BoosokTools.set_hub_booted(true)
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

      dlg.add_action_callback("updates") do |_ctx|
        # Push state update inline ke hub (bukan buka dialog baru)
        MyCustomPlugins::Updater.check_inline(dlg)
      end

      dlg.add_action_callback("update_download") do |_ctx|
        MyCustomPlugins::Updater.download_inline(dlg)
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

      dlg.add_action_callback("validate_license") do |_ctx, key_json|
        begin
          key = JSON.parse(key_json) rescue key_json.to_s
          if defined?(BoosokTools::License)
            is_valid = BoosokTools::License.validate(key)
            if is_valid
              BoosokTools::License.save_key(key)
              st = BoosokTools::License.status
              dlg.execute_script("if (typeof onLicenseValidated === 'function') onLicenseValidated(true, #{st.to_json});")
            else
              dlg.execute_script("if (typeof onLicenseValidated === 'function') onLicenseValidated(false, null);")
            end
          else
            dlg.execute_script("if (typeof onLicenseValidated === 'function') onLicenseValidated(false, null);")
          end
        rescue => e
          puts "[Boosok Hub] validate_license error: #{e.message}"
          dlg.execute_script("if (typeof onLicenseValidated === 'function') onLicenseValidated(false, null);")
        end
      end

      dlg.add_action_callback("remove_license") do |_ctx|
        begin
          Sketchup.write_default("BoosokTools", "license_key", "") rescue nil
          st = defined?(BoosokTools::License) ? BoosokTools::License.status : { status: 'unlicensed' }
          dlg.execute_script("if (typeof onLicenseStatus === 'function') onLicenseStatus(#{st.to_json});")
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
    end

    def self.attach_all_callbacks(dlg)
      return unless dlg

      attach_hub_callbacks(dlg)

      TOOL_PAGES.each do |tid, _cfg|
        begin
          load_tool_file(tid)
          attach_tool_callbacks(tid, dlg)
        rescue => e
          puts "[Boosok Tools] Gagal attach callback '#{tid}': #{e.class}: #{e.message}"
        end
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
      end
    end

    def self.state
      booted = BoosokTools.hub_booted?
      model = Sketchup.active_model
      return { status: 'error', error: "Tidak ada model yang aktif. Buka atau buat model dulu.", has_booted: booted } unless model

      top = model.entities
      lic_st = defined?(BoosokTools::License) ? BoosokTools::License.status : { status: 'expired', can_use: false, days_left: 0 }
      {
        status: 'ready',
        has_booted: booted,
        session_id: (BoosokTools.session_id rescue ''),
        version: MyCustomPlugins::PLUGIN_VERSION,
        theme: Sketchup.read_default("BoosokTools", "theme", "").to_s,
        hotkeys: (BoosokTools::ShortcutSync.get_all_shortcuts rescue {}),
        license: lic_st,
        stats: {
          objects: top.count { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) },
          scenes: model.pages.size,
          selected: model.selection.size
        }
      }
    rescue => e
      { status: 'error', error: "Gagal membaca model: #{e.message}", has_booted: BoosokTools.hub_booted? }
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
