require 'sketchup'
require 'json'
load File.join(__dir__, 'titlebar.rb')

module BoosokTools
  # Satu pintu masuk semua tool (Single Window Architecture).
  # Dialog tetap 1 jendela dan berpindah halaman HTML via window.location.replace
  # sehingga posisi jendela di layar tidak pernah bergeser atau berkedip.
  module Hub
    TITLE = "The Boosok Tools"
    WIDTH = 380
    DEFAULT_HEIGHT = 480

    TOOL_PAGES = {
      'selector' => { file: 'main.rb',                   page: 'selector.html',   title: 'The Selector' },
      'replacer' => { file: 'the_replacer.rb',           page: 'replacer.html',   title: 'The Replacer' },
      'clean'    => { file: 'the_cleangroup.rb',         page: 'cleangroup.html', title: 'Clean Group' },
      'reset'    => { file: 'the_reset.rb',              page: 'reset.html',      title: 'Reset Scale' },
      'scene'    => { file: 'the_hideonscenemanager.rb', page: 'hidescene.html',  title: 'Hide on Scene' },
      'untag'    => { file: 'untagnpaint.rb',            page: 'untagnpaint.html',title: 'Untag & Unpaint' }
    }.freeze

    @dialog = nil
    @current_tool = 'hub'

    def self.dialog
      @dialog
    end

    def self.has_booted?
      BoosokTools.hub_booted?
    end

    def self.set_booted(val = true)
      BoosokTools.set_hub_booted(val)
    end

    def self.show(custom_page = nil, tool_id = nil)
      if @dialog && @dialog.visible?
        if tool_id
          open_tool(tool_id)
        elsif custom_page
          navigate_to(custom_page)
        else
          back_to_hub
        end
        @dialog.bring_to_front
        return
      end

      pos = BoosokTools.get_position

      @dialog = UI::HtmlDialog.new(
        dialog_title: TITLE,
        scrollable: false,
        resizable: false,
        width: WIDTH,
        height: DEFAULT_HEIGHT,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      BoosokTools.dialog = @dialog

      if pos && pos[0] > 5 && pos[1] > 5
        @dialog.set_position(pos[0], pos[1])
      end

      page_file = custom_page || 'hub.html'
      @dialog.set_file(File.join(__dir__, 'html', page_file))
      TitleBar.attach(@dialog, TITLE, width: WIDTH)

      attach_hub_callbacks(@dialog)

      if tool_id
        load File.join(__dir__, TOOL_PAGES[tool_id][:file]) if TOOL_PAGES[tool_id]
        attach_tool_callbacks(tool_id)
      end

      @dialog.set_on_closed do
        BoosokTools.capture_current_position(TITLE)
        HideOnSceneManager.detach_all_observers rescue nil if defined?(HideOnSceneManager)
        @dialog = nil
        BoosokTools.dialog = nil
        @current_tool = 'hub'
      end

      @dialog.show
    end

    def self.open_or_show(id)
      cfg = TOOL_PAGES[id.to_s]
      return unless cfg

      load File.join(__dir__, cfg[:file]) if cfg[:file]

      if @dialog && @dialog.visible?
        open_tool(id.to_s)
        @dialog.bring_to_front
      else
        show(cfg[:page], id.to_s)
      end
    end

    def self.open_tool(id)
      cfg = TOOL_PAGES[id.to_s]
      return toast("Tool \"#{id}\" tidak dikenal.") unless cfg

      if @current_tool == 'scene' && id.to_s != 'scene'
        HideOnSceneManager.detach_all_observers rescue nil if defined?(HideOnSceneManager)
      end
      @current_tool = id.to_s

      load File.join(__dir__, cfg[:file]) if cfg[:file]
      attach_tool_callbacks(id.to_s)
      navigate_to(cfg[:page])
    rescue Exception => e
      puts "[Boosok Tools] Gagal membuka #{id}: #{e.class}: #{e.message}"
      toast("Gagal membuka tool: #{e.message}")
    end

    def self.back_to_hub
      if @current_tool == 'scene'
        HideOnSceneManager.detach_all_observers rescue nil if defined?(HideOnSceneManager)
      end
      @current_tool = 'hub'
      attach_hub_callbacks(@dialog) if @dialog
      navigate_to('hub.html')
    end

    def self.navigate_to(page)
      return unless @dialog && @dialog.visible?
      @dialog.execute_script("window.location.replace(#{page.to_json});")
    end

    def self.attach_hub_callbacks(dlg)
      return unless dlg

      dlg.add_action_callback("ready") do |_ctx|
        push(state)
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

    def self.attach_tool_callbacks(id)
      return unless @dialog
      case id.to_s
      when 'selector'
        TheSelectorPlugin.attach_callbacks(@dialog) if defined?(TheSelectorPlugin)
      when 'replacer'
        TheReplacer.attach_callbacks(@dialog) if defined?(TheReplacer)
      when 'clean'
        ConvertToCleanGroup.attach_callbacks(@dialog) if defined?(ConvertToCleanGroup)
      when 'reset'
        TheResetScale.attach_callbacks(@dialog) if defined?(TheResetScale)
      when 'scene'
        HideOnSceneManager.attach_callbacks(@dialog) if defined?(HideOnSceneManager)
      when 'untag'
        UntagUnpaintManager.attach_callbacks(@dialog) if defined?(UntagUnpaintManager)
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
      @dialog.execute_script("if (typeof onOpenFailed === 'function') onOpenFailed(#{msg.to_json}); else if (typeof showToast === 'function') showToast(#{msg.to_json});") if @dialog && @dialog.visible?
    end

    def self.push(st)
      @dialog.execute_script("if (typeof render === 'function') render(#{st.to_json});") if @dialog && @dialog.visible?
    end
  end
end
