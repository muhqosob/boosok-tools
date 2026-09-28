load File.join(__dir__, 'titlebar.rb')

module UntagUnpaintManager
  def self.run
    require_relative 'hub' unless defined?(BoosokTools::Hub)
    BoosokTools::Hub.open_or_show('untag')
  end

  def self.attach_callbacks(dialog)
    return unless dialog

    # --- CALLBACK PROCESS ---
    dialog.add_action_callback("prosesAction") do |_context, action_type, deep_process|
      execute_action(dialog, action_type, deep_process)
    end
  end

  def self.execute_action(dialog, action_type, deep_process)
    model = Sketchup.active_model
    return dialog.execute_script("onError('Tidak ada model aktif.');") unless model

    selection = model.selection.to_a

    if selection.empty?
      dialog.execute_script("onError('Gagal: Pilih minimal 1 Group / Component!');")
      return
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
            entity.entities.each { |child| clean_entity.call(child) }
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

      dialog.execute_script("onProcessComplete(#{msg.to_json});")

    rescue => e
      model.abort_operation
      err_msg = e.message.gsub("'", "\\'")
      dialog.execute_script("onError('Error: #{err_msg}');")
    end
  end
end