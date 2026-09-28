require 'sketchup'
require 'json'
load File.join(__dir__, 'titlebar.rb')

module BoosokTools
  # Satu pintu masuk semua tool. Dialog cuma render state dari Ruby:
  # render({status: 'ready', stats: {...}}) atau render({status: 'error', error: '...'})
  module Hub
    TITLE = "The Boosok Tools"
    WIDTH = 380
    DEFAULT_HEIGHT = 550

    def self.has_booted?
      BoosokTools.hub_booted?
    end

    def self.set_booted(val = true)
      BoosokTools.set_hub_booted(val)
    end

    # id => [file, cara jalanin]. File di-load ulang tiap buka biar edit langsung kepakai.
    TOOLS = {
      'selector' => ['main.rb',                   -> { TheSelectorPlugin.run_selector }],
      'replacer' => ['the_replacer.rb',           -> { TheReplacer.run }],
      'clean'    => ['the_cleangroup.rb',         -> { ConvertToCleanGroup.run }],
      'reset'    => ['the_reset.rb',              -> { TheResetScale.run }],
      'scene'    => ['the_hideonscenemanager.rb', -> { HideOnSceneManager.run }],
      'untag'    => ['untagnpaint.rb',            -> { UntagUnpaintManager.run }]
    }.freeze

    def self.show(custom_x = nil, custom_y = nil)
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end

      pos = if custom_x && custom_y
        [custom_x.to_i, custom_y.to_i]
      else
        BoosokTools.get_position
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: TITLE,
        scrollable: false, resizable: false,
        width: WIDTH, height: DEFAULT_HEIGHT,
        style: UI::HtmlDialog::STYLE_DIALOG
      )

      if pos && pos[0] > 5 && pos[1] > 5
        @dialog.set_position(pos[0], pos[1])
      end

      @dialog.set_file(File.join(__dir__, 'html', 'hub.html'))
      TitleBar.attach(@dialog, TITLE, width: WIDTH)

      @dialog.add_action_callback("ready") { push(state) }
      @dialog.add_action_callback("boot_done") { BoosokTools.set_hub_booted(true) }

      @dialog.add_action_callback("open") do |_ctx, id, pos_json|
        pos_data = JSON.parse(pos_json) rescue nil
        if pos_data && pos_data["left"] && pos_data["top"]
          BoosokTools.save_position(pos_data["left"], pos_data["top"])
        else
          BoosokTools.capture_current_position(TITLE)
        end
        open_tool(id.to_s)
      end

      @dialog.add_action_callback("updates") { MyCustomPlugins::Updater.check(true) }
      @dialog.show
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

    def self.open_tool(id)
      file, run = TOOLS[id]
      return toast("Tool \"#{id}\" tidak dikenal.") unless run

      load File.join(__dir__, file)
      run.call
      @dialog.close if @dialog && @dialog.visible?
    rescue Exception => e # SyntaxError/LoadError bukan turunan StandardError
      puts "[Boosok Tools] Gagal membuka #{id}: #{e.class}: #{e.message}"
      toast("Gagal membuka tool: #{e.message}")
    end

    def self.toast(msg)
      @dialog.execute_script("onOpenFailed(#{msg.to_json})") if @dialog && @dialog.visible?
    end

    def self.push(st)
      @dialog.execute_script("render(#{st.to_json})") if @dialog && @dialog.visible?
    end
  end
end
