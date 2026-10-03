Sketchup.require 'boosok_tools/ruby/titlebar'

module BoosokTools::UntagUnpaintManager
  # Guard agar callbacks tidak di-stack oleh Hub reload (@dialog = dialog yang sudah terdaftar).
  # Dipanggil Hub saat dialog ditutup supaya callback didaftarkan lagi di dialog berikutnya.
  def self.release_dialog
    @dialog = nil
  end

  def self.run
    Sketchup.require 'boosok_tools/hub' unless defined?(BoosokTools::Hub)
    BoosokTools::Hub.open_or_show('untag')
  end

  def self.attach_callbacks(dialog)
    return unless dialog
    return if @dialog.equal?(dialog) # sudah terdaftar di dialog ini (hindari handler bertumpuk)
    @dialog = dialog

    # --- CALLBACK PROCESS ---
    action_cb = lambda do |_context, action_type, deep_process|
      deep = (deep_process.to_s == 'true')
      execute_action(dialog, action_type, deep)
    end

    dialog.add_action_callback("prosesAction", &action_cb)
    dialog.add_action_callback("proses_untagnpaint", &action_cb)
    dialog.add_action_callback("untag_unpaint", &action_cb)
  end

  def self.execute_action(dialog, action_type, deep_process)
    model = Sketchup.active_model
    return dialog.execute_script("onError('Tidak ada model aktif.');") unless model

    # Baca selection; jika kosong (HtmlDialog mungkin ambil focus → cleared),
    # coba tangkap dari semua entities sebagai fallback tidak tersedia —
    # kembalikan error yang informatif
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