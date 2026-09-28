module HideOnSceneManager
  require 'json'
  require 'set'
  load File.join(__dir__, 'titlebar.rb')

  class PagesObserver < Sketchup::PagesObserver
    def onElementAdded(*args)
      HideOnSceneManager.schedule_sync rescue nil
    end

    def onElementRemoved(*args)
      HideOnSceneManager.schedule_sync rescue nil
    end

    def onContentsModified(*args)
      HideOnSceneManager.schedule_sync rescue nil
    end
  end

  class ModelObserver < Sketchup::ModelObserver
    def onTransactionCommit(*args)
      HideOnSceneManager.schedule_sync rescue nil
    end

    def onTransactionUndo(*args)
      HideOnSceneManager.schedule_sync rescue nil
    end

    def onTransactionRedo(*args)
      HideOnSceneManager.schedule_sync rescue nil
    end
  end

  class AppObserver < Sketchup::AppObserver
    def onActivateModel(model)
      HideOnSceneManager.attach_to_model(model) rescue nil
    end

    def onNewModel(model)
      HideOnSceneManager.attach_to_model(model) rescue nil
    end

    def onOpenModel(model)
      HideOnSceneManager.attach_to_model(model) rescue nil
    end
  end

  def self.schedule_sync
    return unless @dialog && @dialog.visible?

    UI.stop_timer(@update_timer) if @update_timer
    @update_timer = UI.start_timer(0.08, false) do
      @update_timer = nil
      sync_scenes_and_tags
    end
  end

  def self.sync_scenes_and_tags
    return unless @dialog && @dialog.visible?
    model = Sketchup.active_model
    return unless model && model.valid?

    current_scenes = model.pages.map(&:name)
    current_tags = model.layers.map(&:name)

    if current_scenes != @cached_scenes
      @cached_scenes = current_scenes
      begin
        @dialog.execute_script("updateScenes(#{@cached_scenes.to_json});")
      rescue => e
      end
    end

    if current_tags != @cached_tags
      @cached_tags = current_tags
      begin
        @dialog.execute_script("updateTags(#{@cached_tags.to_json});")
      rescue => e
      end
    end
  end

  def self.attach_to_model(model)
    detach_model_observers
    return unless model && model.valid?
    @observed_model = model

    @pages_observer ||= PagesObserver.new
    @model_observer ||= ModelObserver.new

    begin
      model.pages.add_observer(@pages_observer)
    rescue => e
    end

    begin
      model.add_observer(@model_observer)
    rescue => e
    end

    schedule_sync
  end

  def self.detach_model_observers
    if @observed_model && @observed_model.valid?
      begin
        @observed_model.pages.remove_observer(@pages_observer) if @pages_observer
      rescue => e
      end
      begin
        @observed_model.remove_observer(@model_observer) if @model_observer
      rescue => e
      end
    end
    @observed_model = nil
  end

  def self.detach_all_observers
    UI.stop_timer(@update_timer) if @update_timer
    @update_timer = nil

    detach_model_observers

    if @app_observer
      begin
        Sketchup.remove_observer(@app_observer)
      rescue => e
      end
      @app_observer = nil
    end
  end

  def self.run
    if @dialog && @dialog.visible?
      @dialog.bring_to_front
      sync_scenes_and_tags
      return
    end

    detach_all_observers

    model = Sketchup.active_model
    @cached_scenes = model.pages.map(&:name)
    @cached_tags = model.layers.map(&:name)

    # --- BUAT DIALOG UI ---
    dialog = @dialog = UI::HtmlDialog.new(
      {
        :dialog_title => "Hide on Scene",
        :preferences_key => "com.sketchup.hidemanager.pro",
        :scrollable => false,
        :resizable => true,
        :width => 390,
        :min_width => 390,
        :max_width => 390,
        :height => 580,
        :min_height => 450,
        :style => UI::HtmlDialog::STYLE_DIALOG
      }
    )
    dialog.set_file(File.join(__dir__, 'html', 'hidescene.html'))
    BoosokTools::TitleBar.attach(dialog, "Hide on Scene")

    dialog.add_action_callback("ready") do |action_context|
      current_model = Sketchup.active_model
      @cached_scenes = current_model.pages.map(&:name)
      @cached_tags = current_model.layers.map(&:name)
      data = { scenes: @cached_scenes, tags: @cached_tags }
      dialog.execute_script("init(#{data.to_json})")
    end

    # --- CALLBACK: TUTUP DIALOG ---
    dialog.add_action_callback("closeDialog") do |action_context|
      dialog.close
    end

    dialog.set_on_closed do
      HideOnSceneManager.detach_all_observers
      HideOnSceneManager.instance_variable_set(:@dialog, nil)
    end

    @app_observer ||= AppObserver.new
    begin
      Sketchup.add_observer(@app_observer)
    rescue => e
    end

    attach_to_model(model)

    # --- CALLBACK 1: PROSES ISOLATE SCENE AKTIF (LANGSUNG REFRESH VIEWPORT) ---
    dialog.add_action_callback("prosesIsolateActive") do |action_context|
      model = Sketchup.active_model
      selection = model.selection.to_a
      
      if selection.empty?
        dialog.execute_script("resetIsolateBtn();")
        dialog.execute_script("showToast('Gagal: Tidak ada objek yang diseleksi!', 'error');")
        next
      end

      # Cek apakah ada page/scene yang aktif
      page = model.pages.selected_page

      model.start_operation("Isolate Objects (Smart)", true)

      begin
        if page
          page.use_hidden_objects = true if page.respond_to?(:use_hidden_objects=)
          page.use_hidden_geometry = true if page.respond_to?(:use_hidden_geometry=)
          page.use_hidden = true if page.respond_to?(:use_hidden=)
        end

        # ALGORITMA PENCARIAN SILSILAH GRUP:
        selected = selection.to_set
        queue = selection.dup
        visited = {}
        
        while !queue.empty?
          ent = queue.shift
          next if visited[ent]
          visited[ent] = true

          if ent.respond_to?(:parent)
            p = ent.parent
            if p.is_a?(Sketchup::ComponentDefinition)
              p.instances.each do |inst|
                queue << inst
              end
            end
          end
        end

        # ALGORITMA PEMINDAI HIRARKI (Recursive Scanner):
        isolate_recursive = nil
        isolate_recursive = lambda do |entities|
          entities.each do |ent|
            next unless ent.is_a?(Sketchup::Drawingelement)

            if selected.include?(ent)
              # Jika persis objek yang dipilih, Unhide (tampilkan)
              if page
                page.set_drawingelement_visibility(ent, true)
                ent.hidden = false # UPDATE VIEWPORT SECARA INSTAN!
              else
                ent.hidden = false
              end
            elsif visited[ent] # grup induk dari objek terpilih
              # Jika ini adalah grup induk/bungkusan luarnya, tetap tampilkan
              if page
                page.set_drawingelement_visibility(ent, true)
                ent.hidden = false # UPDATE VIEWPORT SECARA INSTAN!
              else
                ent.hidden = false
              end
              
              # Lanjut scan kedalam isi grup tersebut
              if ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
                isolate_recursive.call(ent.definition.entities)
              end
            else
              # Jika bukan objek yang dipilih & bukan grup induknya, Sembunyikan (Hide)
              if page
                page.set_drawingelement_visibility(ent, false)
                ent.hidden = true # UPDATE VIEWPORT SECARA INSTAN!
              else
                ent.hidden = true
              end
            end
          end
        end

        # Eksekusi scan dimulai dari entitas paling atas
        isolate_recursive.call(model.entities)

        model.commit_operation
        dialog.execute_script("resetIsolateBtn();")
        
        nama_scene = page ? page.name : "Model Global"
        dialog.execute_script("showToast(#{("Sukses mengisolasi objek di scene: " + nama_scene).to_json}, 'success');")
        
      rescue => e
        model.abort_operation
        dialog.execute_script("resetIsolateBtn();")
        dialog.execute_script("showToast(#{("Kesalahan Sistem: " + e.message).to_json}, 'error');")
      end
    end

    # --- CALLBACK 2: PROSES HIDE/UNHIDE TAG ---
    dialog.add_action_callback("prosesHideTags") do |action_context, scene_terpilih, tag_terpilih, action_type|
      model = Sketchup.active_model
      model.start_operation("#{action_type.capitalize} Multiple Tags", true)
      begin

        visibility_status = (action_type == 'unhide')

        scene_terpilih.each do |nama_scene|
          page = model.pages[nama_scene]
          next unless page

          page.use_hidden_layers = true
          tag_terpilih.each do |nama_tag|
            layer = model.layers[nama_tag]
            next unless layer

            page.set_visibility(layer, visibility_status)
            layer.visible = visibility_status if model.pages.selected_page == page # REFRESH VIEWPORT
          end
        end
        model.commit_operation
      rescue => e
        model.abort_operation
        dialog.execute_script("resetTagButton();")
        dialog.execute_script("showToast(#{("Kesalahan Sistem: " + e.message).to_json}, 'error');")
        next
      end

      dialog.execute_script("resetTagButton();")
      
      aksi_teks = visibility_status ? "menampilkan" : "menyembunyikan"
      pesan = "Sukses #{aksi_teks} #{tag_terpilih.length} Tag di #{scene_terpilih.length} Scene."
      dialog.execute_script("showSuccessStep('#{pesan}');")
    end

    # --- CALLBACK 3: PROSES HIDE/UNHIDE OBJEK ---
    dialog.add_action_callback("prosesHideObjects") do |action_context, scene_terpilih, action_type|
      model = Sketchup.active_model
      selection = model.selection.to_a
      
      if selection.empty?
        dialog.execute_script("resetObjButton();")
        dialog.execute_script("showToast('Gagal: Tidak ada objek yang diseleksi!', 'error');")
        next
      end
      
      model.start_operation("#{action_type.capitalize} Objects on Scenes", true)
      
      visibility_status = (action_type == 'unhide')
      
      begin
        scene_terpilih.each do |nama_scene|
          page = model.pages[nama_scene]
          next unless page
          
          page.use_hidden_objects = true if page.respond_to?(:use_hidden_objects=)
          page.use_hidden_geometry = true if page.respond_to?(:use_hidden_geometry=)
          page.use_hidden = true if page.respond_to?(:use_hidden=)
          
          selection.each do |ent|
            if ent.respond_to?(:valid?) && ent.valid? && ent.is_a?(Sketchup::Drawingelement)
              page.set_drawingelement_visibility(ent, visibility_status)
              
              # UPDATE VIEWPORT INSTAN JIKA SCENE INI SEDANG DIBUKA DI LAYAR
              if model.pages.selected_page == page
                ent.hidden = !visibility_status 
              end
            end
          end
        end
        
        model.commit_operation
        dialog.execute_script("resetObjButton();")
        
        aksi_teks = visibility_status ? "menampilkan" : "menyembunyikan"
        pesan = "Sukses #{aksi_teks} #{selection.length} objek di #{scene_terpilih.length} Scene."
        dialog.execute_script("showSuccessStep('#{pesan}');")
        
      rescue => e
        model.abort_operation
        dialog.execute_script("resetObjButton();")
        dialog.execute_script("showToast(#{("Kesalahan Sistem: " + e.message).to_json}, 'error');")
      end
    end

    dialog.show
  end
end