module UntagUnpaintManager
  def self.run
    require 'json'

    # --- MEMBUAT UI DIALOG ---
    dialog = UI::HtmlDialog.new(
      {
        :dialog_title => "Untag & Unpaint",
        :preferences_key => "com.sketchup.untagunpaint.manager",
        :scrollable => false,
        :resizable => false,
        :width => 360,
        :height => 420,
        :style => UI::HtmlDialog::STYLE_DIALOG
      }
    )
    dialog.set_file(File.join(__dir__, 'untagnpaint.html'))

    # --- CALLBACK PROCESS ---
    dialog.add_action_callback("prosesAction") do |context, action_type, deep_process|
      model = Sketchup.active_model
      selection = model.selection.to_a

      if selection.empty?
        dialog.execute_script("onError('Gagal: Pilih minimal 1 Group / Component!');")
        next
      end

      model.start_operation("Untag / Unpaint Deep", true)

      begin
        count_untag = 0
        count_unpaint = 0

        # Algoritma Rekursif Pembersih
        clean_entity = nil
        clean_entity = lambda do |entity|
          next unless entity.respond_to?(:valid?) && entity.valid?

          # 1. UNTAG PROCESS (Pindahkan ke Layer0 / Untagged)
          if ['untag', 'both'].include?(action_type)
            if entity.layer != model.layers[0]
              entity.layer = model.layers[0]
              count_untag += 1
            end
          end

          # 2. UNPAINT PROCESS (Hapus Material)
          if ['unpaint', 'both'].include?(action_type)
            if entity.respond_to?(:material) && entity.material
              entity.material = nil
              count_unpaint += 1
            end
            if entity.respond_to?(:back_material) && entity.back_material
              entity.back_material = nil
              count_unpaint += 1
            end
          end

          # 3. REKURSIONAL (Masuk ke dalam Group / Component)
          if deep_process
            if entity.is_a?(Sketchup::Group)
              entity.definition.entities.each { |child| clean_entity.call(child) }
            elsif entity.is_a?(Sketchup::ComponentInstance)
              entity.definition.entities.each { |child| clean_entity.call(child) }
            end
          end
        end

        # Jalankan pembersihan pada item terseleksi
        selection.each { |ent| clean_entity.call(ent) }

        model.commit_operation

        # Pesan Balikan
        msg = case action_type
              when 'untag' then "Berhasil untag #{count_untag} elemen!"
              when 'unpaint' then "Berhasil unpaint #{count_unpaint} material!"
              else "Berhasil untag (#{count_untag}) & unpaint (#{count_unpaint})!"
              end

        dialog.execute_script("onProcessComplete('#{msg}');")

      rescue => e
        model.abort_operation
        err_msg = e.message.gsub("'", "\\'")
        dialog.execute_script("onError('Error: #{err_msg}');")
      end
    end

    dialog.show
  end
end

# Untuk menjalankan script langsung dari Ruby Console:
# UntagUnpaintManager.run