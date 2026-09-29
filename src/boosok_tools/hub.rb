require 'sketchup'
require 'json'
load File.join(__dir__, 'titlebar.rb')

module BoosokTools
  # Satu pintu masuk semua tool (Single Window Architecture).
  # Dialog tetap 1 jendela dan berpindah halaman HTML via window.location.replace
  # sehingga posisi jendela di layar tidak pernah bergeser atau berkedip.
  module Hub
    TITLE = "Boosok Tools"
    WIDTH = 380
    DEFAULT_HEIGHT = 480

    TOOL_PAGES = {
      'selector' => { file: 'main.rb',                   page: 'selector.html',   title: 'Selector' },
      'replacer' => { file: 'the_replacer.rb',           page: 'replacer.html',   title: 'Group Replacer' },
      'clean'    => { file: 'the_cleangroup.rb',         page: 'cleangroup.html', title: 'Group Cleaner' },
      'reset'    => { file: 'the_reset.rb',              page: 'reset.html',      title: 'Reset Scale' },
      'scene'    => { file: 'the_hideonscenemanager.rb', page: 'hidescene.html',  title: 'Hide on Scene' },
      'untag'    => { file: 'untagnpaint.rb',            page: 'untagnpaint.html',title: 'Untag & Unpaint' }
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
        BoosokTools.dialog = nil
        @current_tool = 'hub'
      end

      dlg.show
    end

    def self.open_or_show(id)
      cfg = TOOL_PAGES[id.to_s]
      return unless cfg

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

      cfg = TOOL_PAGES[id.to_s]
      return toast("Tool \"#{id}\" tidak dikenal.") unless cfg

      if @current_tool == 'scene' && id.to_s != 'scene'
        HideOnSceneManager.detach_all_observers rescue nil if defined?(HideOnSceneManager)
      end
      if @current_tool == 'selector' && id.to_s != 'selector'
        TheSelectorPlugin.detach_all_observers rescue nil if defined?(TheSelectorPlugin)
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
        MyCustomPlugins::Updater.check(true)
      end
    end

    def self.attach_all_callbacks(dlg)
      return unless dlg

      attach_hub_callbacks(dlg)

      TOOL_PAGES.each do |tid, _cfg|
        load_tool_file(tid)
        attach_tool_callbacks(tid, dlg)
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
      end
    end

    def self.state
      booted = BoosokTools.hub_booted?
      model = Sketchup.active_model
      return { status: 'error', error: "Tidak ada model yang aktif. Buka atau buat model dulu.", has_booted: booted } unless model

      top = model.entities
      {
        status: 'ready',
        has_booted: booted,
        version: MyCustomPlugins::PLUGIN_VERSION,
        theme: Sketchup.read_default("BoosokTools", "theme", "").to_s,
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
