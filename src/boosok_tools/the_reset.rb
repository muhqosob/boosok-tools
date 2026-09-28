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
      puts "[TheReset] mode=#{mode_str}, recursive=#{is_recursive}"

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
      puts "[TheReset] ERROR: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      return "Reset skala gagal: #{e.message}"
    end
  end

  # Reset skala ke 1:1:1 tanpa mengubah ukuran (explode lalu group kembali)
  def self.reset_scale_preserve(entity, parent_entities)
    return entity unless entity.respond_to?(:valid?) && entity.valid?
    return entity unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

    t = entity.transformation
    sx = t.xaxis.length.to_f
    sy = t.yaxis.length.to_f
    sz = t.zaxis.length.to_f

    puts "[TheReset] === PRESERVE START ==="
    puts "[TheReset] Entity: #{entity.class}, name=#{entity.name.inspect}"
    puts "[TheReset] Scale: X=#{sx}, Y=#{sy}, Z=#{sz}"
    puts "[TheReset] BBox SEBELUM: #{entity.bounds.width.to_mm.round(1)}mm x #{entity.bounds.height.to_mm.round(1)}mm x #{entity.bounds.depth.to_mm.round(1)}mm"

    is_scaled = (sx - 1.0).abs > 1e-5 || (sy - 1.0).abs > 1e-5 || (sz - 1.0).abs > 1e-5
    puts "[TheReset] is_scaled=#{is_scaled}"

    # Jika objek sudah 1:1:1, tidak perlu apa-apa
    unless is_scaled
      puts "[TheReset] Sudah 1:1:1, skip."
      return entity
    end

    # Simpan metadata
    is_component = entity.is_a?(Sketchup::ComponentInstance)
    orig_defn_name = is_component ? entity.definition.name : nil
    layer = entity.layer
    material = entity.material
    name = entity.name
    hidden = entity.hidden?
    locked = entity.locked?
    casts_shadows = entity.casts_shadows?
    receives_shadows = entity.receives_shadows?

    # Simpan atribut
    attrs = {}
    if entity.respond_to?(:attribute_dictionaries) && entity.attribute_dictionaries
      entity.attribute_dictionaries.each do |dict|
        next unless dict
        attrs[dict.name] = {}
        dict.each_pair { |k, v| attrs[dict.name][k] = v }
      end
    end

    entity.locked = false if locked

    # === LANGKAH 1: Explode ===
    puts "[TheReset] Exploding..."
    exploded = entity.explode
    puts "[TheReset] Explode result class: #{exploded.class}"

    unless exploded.is_a?(Array)
      puts "[TheReset] GAGAL: explode tidak mengembalikan Array!"
      return nil
    end

    valid_ents = exploded.select { |e| e.respond_to?(:valid?) && e.valid? }
    puts "[TheReset] Exploded entities: #{exploded.length} total, #{valid_ents.length} valid"

    if valid_ents.empty?
      puts "[TheReset] GAGAL: tidak ada entity valid setelah explode!"
      return nil
    end

    # Cek tipe entity yang ada
    type_counts = {}
    valid_ents.each do |e|
      cn = e.class.name.split('::').last
      type_counts[cn] = (type_counts[cn] || 0) + 1
    end
    puts "[TheReset] Tipe entities: #{type_counts.inspect}"

    # Cek bounding box dari entity-entity yang di-explode
    all_pts = []
    valid_ents.each do |e|
      if e.respond_to?(:bounds)
        bb = e.bounds
        all_pts << bb.min
        all_pts << bb.max
      end
    end
    unless all_pts.empty?
      xs = all_pts.map(&:x)
      ys = all_pts.map(&:y)
      zs = all_pts.map(&:z)
      w = (xs.max - xs.min).to_mm.round(1)
      h = (ys.max - ys.min).to_mm.round(1)
      d = (zs.max - zs.min).to_mm.round(1)
      puts "[TheReset] BBox entities SETELAH explode: #{w}mm x #{h}mm x #{d}mm"
    end

    # === LANGKAH 2: Jadikan group kembali ===
    puts "[TheReset] Membuat group baru..."
    new_group = parent_entities.add_group(valid_ents)
    puts "[TheReset] New group class: #{new_group.class}"

    new_t = new_group.transformation
    puts "[TheReset] New group scale: X=#{new_t.xaxis.length.to_f}, Y=#{new_t.yaxis.length.to_f}, Z=#{new_t.zaxis.length.to_f}"
    puts "[TheReset] BBox SESUDAH regroup: #{new_group.bounds.width.to_mm.round(1)}mm x #{new_group.bounds.height.to_mm.round(1)}mm x #{new_group.bounds.depth.to_mm.round(1)}mm"

    # Kembalikan metadata
    new_group.name = name unless name.to_s.empty?
    new_group.layer = layer if layer
    new_group.material = material if material
    new_group.hidden = hidden
    new_group.casts_shadows = casts_shadows
    new_group.receives_shadows = receives_shadows

    attrs.each do |dict_name, pairs|
      dict = new_group.attribute_dictionary(dict_name, true)
      pairs.each { |k, v| dict[k] = v }
    end

    result_entity = if is_component
      new_inst = new_group.to_component
      new_inst.definition.name = orig_defn_name if orig_defn_name
      new_inst
    else
      new_group
    end

    result_entity.locked = locked if locked
    puts "[TheReset] === PRESERVE DONE ==="
    result_entity
  end

  # Reset skala kembali ke ukuran asli sebelum diskala
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
