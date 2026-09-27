module HideOnSceneManager
  def self.run
    require 'json'
    require 'set'

    # Satu dialog saja. Buka ulang supaya daftar scene/tag ikut ter-refresh.
    @dialog.close if @dialog && @dialog.visible?

    model = Sketchup.active_model

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

    dialog.add_action_callback("ready") do |action_context|
      data = { scenes: model.pages.map(&:name), tags: model.layers.map(&:name) }
      dialog.execute_script("init(#{data.to_json})")
    end

    # --- CALLBACK: TUTUP DIALOG ---
    dialog.add_action_callback("closeDialog") do |action_context|
      dialog.close
    end

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