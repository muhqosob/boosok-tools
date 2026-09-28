require 'sketchup'
require 'json'

module TheResetScale
  def self.run
    # Tutup dialog lama jika masih ada agar selalu memuat versi terbaru
    @dialog.close if @dialog && @dialog.visible?

    dialog = @dialog = UI::HtmlDialog.new(
      dialog_title: "Reset Scale",
      preferences_key: "BoosokToolsResetScale",
      scrollable: false, resizable: false,
      width: 360, height: 430,
      style: UI::HtmlDialog::STYLE_DIALOG
    )
    dialog.set_file(File.join(__dir__, 'html', 'reset.html'))

    dialog.add_action_callback("close") { dialog.close }

    dialog.add_action_callback("reset") do |_action_context, mode, recursive|
      mode_str = mode.to_s.empty? ? "preserve" : mode.to_s
      is_recursive = (recursive == true)

      result = reset_selection(mode_str, is_recursive)
      if result.is_a?(Integer)
        msg = if mode_str == "preserve"
          "Skala #{result} objek di-reset (ukuran tetap dipertahankan)."
        else
          "Skala #{result} objek kembali ke ukuran asli."
        end
        dialog.execute_script("showSuccessStep(#{msg.to_json})")
      else
        dialog.execute_script("resetExecButton(); showToast(#{result.to_json})")
      end
    end

    dialog.show
  end

  # Balikin jumlah objek yang di-reset, atau pesan error (String)
  def self.reset_selection(mode = "preserve", recursive = false)
    model = Sketchup.active_model
    targets = model.selection.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
    return "Pilih minimal 1 group / component dulu." if targets.empty?

    model.start_operation('The Reset Scale', true)
    begin
      processed_count = 0
      final_entities = []

      parent_entities = model.active_entities

      targets.each do |entity|
        next unless entity.respond_to?(:valid?) && entity.valid?
        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        if mode == "preserve"
          res_ent = reset_scale_preserve(entity, parent_entities)
        else
          reset_scale_original(entity)
          res_ent = entity
        end

        processed_count += 1
        final_entities << res_ent if res_ent && res_ent.respond_to?(:valid?) && res_ent.valid?
      end

      # Perbarui seleksi ke entitas yang baru
      model.selection.clear
      valid_to_select = final_entities.select { |e| e.respond_to?(:valid?) && e.valid? }
      model.selection.add(valid_to_select) unless valid_to_select.empty?

      model.commit_operation
      processed_count
    rescue => e
      model.abort_operation
      return "Reset skala gagal: #{e.message}"
    end
  end

  # Reset skala: pertahankan ukuran saat ini, hapus riwayat "scaled" dari SketchUp.
  # Caranya: bungkus semua isi definition ke sub-group, lalu explode group luar.
  # Sub-group yang keluar adalah group bersih tanpa riwayat scale.
  def self.reset_scale_preserve(entity, parent_entities)
    return entity unless entity.respond_to?(:valid?) && entity.valid?
    return entity unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

    is_component = entity.is_a?(Sketchup::ComponentInstance)

    # Simpan metadata
    orig_name = entity.name
    orig_layer = entity.layer
    orig_material = entity.material
    orig_hidden = entity.hidden?
    orig_locked = entity.locked?
    orig_casts_shadows = entity.casts_shadows?
    orig_receives_shadows = entity.receives_shadows?
    orig_transformation = entity.transformation

    # Simpan atribut dictionary
    attrs = {}
    if entity.respond_to?(:attribute_dictionaries) && entity.attribute_dictionaries
      entity.attribute_dictionaries.each do |dict|
        next unless dict
        attrs[dict.name] = {}
        dict.each_pair { |k, v| attrs[dict.name][k] = v }
      end
    end

    entity.locked = false if orig_locked

    # Pastikan definition unik agar tidak mempengaruhi copy group lain
    entity.make_unique if entity.respond_to?(:make_unique)

    defn = entity.respond_to?(:definition) ? entity.definition : entity.entities.parent
    inner_ents = defn.entities.to_a

    if inner_ents.empty?
      entity.locked = orig_locked if orig_locked
      return entity
    end

    # === LANGKAH INTI ===
    # 1. Bungkus semua isi definition ke dalam sub-group baru.
    #    Sub-group ini adalah group BARU tanpa riwayat scale.
    #    Geometrinya tetap pada ukuran saat ini (sudah di-scale oleh SketchUp).
    inner_group = defn.entities.add_group(inner_ents)

    # 2. Explode group luar (yang punya riwayat scale).
    #    Hasilnya: inner_group keluar ke parent_entities dengan transformasi group luar diterapkan.
    #    Karena transformasi group luar adalah identity (scale 1:1:1), ukuran inner_group tidak berubah.
    exploded = entity.explode

    # 3. Cari inner_group di hasil explode
    result = nil
    if exploded.is_a?(Array)
      result = exploded.find { |e| e.is_a?(Sketchup::Group) && e.respond_to?(:valid?) && e.valid? }
    end

    unless result
      # Fallback: cari group terakhir di parent_entities
      groups = parent_entities.grep(Sketchup::Group).select(&:valid?)
      result = groups.last
    end

    return nil unless result && result.valid?

    # 4. Kembalikan semua metadata
    result.name = orig_name unless orig_name.to_s.empty?
    result.layer = orig_layer if orig_layer
    result.material = orig_material if orig_material
    result.hidden = orig_hidden
    result.casts_shadows = orig_casts_shadows
    result.receives_shadows = orig_receives_shadows

    # Kembalikan atribut (kecuali yang berhubungan dengan scale internal SketchUp)
    attrs.each do |dict_name, pairs|
      next if dict_name == 'GSU_ContributorsInfo' # skip internal SketchUp
      dict = result.attribute_dictionary(dict_name, true)
      pairs.each { |k, v| dict[k] = v }
    end

    result.locked = orig_locked if orig_locked
    result
  end

  # Reset skala kembali ke ukuran asli sebelum diskala (mode lama)
  def self.reset_scale_original(entity)
    t = entity.transformation
    xaxis = t.xaxis
    yaxis = t.yaxis
    zaxis = t.zaxis

    return if xaxis.length < 1e-6 || yaxis.length < 1e-6 || zaxis.length < 1e-6

    entity.transformation = Geom::Transformation.axes(
      t.origin, xaxis.normalize, yaxis.normalize, zaxis.normalize
    )
  end
end
