require 'sketchup'
require 'json'
load File.join(__dir__, 'titlebar.rb')

module BoosokTools
  # Satu pintu masuk semua tool. Dialog cuma render state dari Ruby:
  # render({status: 'ready', stats: {...}}) atau render({status: 'error', error: '...'})
  module Hub
    TITLE = "The Bosok Tools"

    # id => [file, cara jalanin]. File di-load ulang tiap buka biar edit langsung kepakai.
    TOOLS = {
      'selector' => ['main.rb',                   -> { TheSelectorPlugin.run_selector }],
      'replacer' => ['the_replacer.rb',           -> { TheReplacer.run }],
      'clean'    => ['the_cleangroup.rb',         -> { ConvertToCleanGroup.run }],
      'reset'    => ['the_reset.rb',              -> { TheResetScale.run }],
      'scene'    => ['the_hideonscenemanager.rb', -> { HideOnSceneManager.run }],
      'untag'    => ['untagnpaint.rb',            -> { UntagUnpaintManager.run }]
    }.freeze

    def self.show
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: TITLE,
        preferences_key: "BoosokToolsHub",
        scrollable: false, resizable: false,
        width: 380, height: 500,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_file(File.join(__dir__, 'html', 'hub.html'))
      TitleBar.attach(@dialog, TITLE)

      @dialog.add_action_callback("ready") { push(state) }
      @dialog.add_action_callback("open") { |_ctx, id| open_tool(id.to_s) }
      @dialog.add_action_callback("updates") { MyCustomPlugins::Updater.check(true) }
      @dialog.show
    end

    def self.state
      model = Sketchup.active_model
      return { status: 'error', error: "Tidak ada model yang aktif. Buka atau buat model dulu." } unless model

      top = model.entities
      {
        status: 'ready',
        version: MyCustomPlugins::PLUGIN_VERSION,
        theme: Sketchup.read_default("BoosokTools", "theme", "").to_s,
        stats: {
          objects: top.count { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) },
          scenes: model.pages.size,
          selected: model.selection.size
        }
      }
    rescue => e
      { status: 'error', error: "Gagal membaca model: #{e.message}" }
    end

    def self.open_tool(id)
      file, run = TOOLS[id]
      return toast("Tool \"#{id}\" tidak dikenal.") unless run

      load File.join(__dir__, file)
      run.call
      @dialog.close
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
