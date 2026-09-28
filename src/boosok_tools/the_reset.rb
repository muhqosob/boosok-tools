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

      process_entity = lambda do |entity, container|
        return nil unless entity.respond_to?(:valid?) && entity.valid?
        return nil unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        res_ent = if mode == "preserve"
          reset_scale_preserve(entity, container)
        else
          reset_scale_original(entity)
          entity
        end

        processed_count += 1

        if recursive && res_ent && res_ent.valid?
          defn = res_ent.respond_to?(:definition) ? res_ent.definition : res_ent.entities.parent
          children = defn.entities.select { |child| child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance) }
          children.each { |child| process_entity.call(child, defn.entities) }
        end

        res_ent
      end

      targets.each do |entity|
        res = process_entity.call(entity, parent_entities)
        final_entities << res if res && res.valid?
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

  # Reset skala ke 1:1:1 dengan metode Explode & Regroup (ukuran hasil skala tetap sama persis)
  def self.reset_scale_preserve(entity, parent_entities)
    return entity unless entity.respond_to?(:valid?) && entity.valid?
    return entity unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

    t = entity.transformation
    sx = t.xaxis.length
    sy = t.yaxis.length
    sz = t.zaxis.length

    is_scaled = (sx - 1.0).abs > 1e-5 || (sy - 1.0).abs > 1e-5 || (sz - 1.0).abs > 1e-5

    # Jika objek memang tidak diskala (1:1:1), cukup normalisasi sumbu
    unless is_scaled
      nx = t.xaxis.normalize
      ny = t.yaxis.normalize
      nz = t.zaxis.normalize
      entity.transformation = Geom::Transformation.axes(t.origin, nx, ny, nz)
      return entity
    end

    is_component = entity.is_a?(Sketchup::ComponentInstance)
    orig_defn_name = is_component ? entity.definition.name : nil

    # Simpan metadata group / component
    layer = entity.layer
    material = entity.material
    name = entity.name
    hidden = entity.hidden?
    locked = entity.locked?
    casts_shadows = entity.casts_shadows?
    receives_shadows = entity.receives_shadows?

    # Simpan atribut dictionary (termasuk dynamic attributes jika ada)
    attrs = {}
    if entity.respond_to?(:attribute_dictionaries) && entity.attribute_dictionaries
      entity.attribute_dictionaries.each do |dict|
        next unless dict
        attrs[dict.name] = {}
        dict.each_pair { |k, v| attrs[dict.name][k] = v }
      end
    end

    entity.locked = false if locked

    # 1. Explode group/component yang sudah diskala
    # Ukuran fisik geometri sekarang berada pada koordinat hasil skala (misal 500x200x200)
    exploded = entity.explode
    return entity unless exploded && exploded.is_a?(Array)

    valid_ents = exploded.select { |e| e.respond_to?(:valid?) && e.valid? }
    return entity if valid_ents.empty?

    # 2. Jadikan group kembali dari geometri yang sudah mekar/ter-skala
    new_group = parent_entities.add_group(valid_ents)

    # 3. Kembalikan semua properti & metadata
    new_group.name = name unless name.to_s.empty?
    new_group.layer = layer if layer
    new_group.material = material if material
    new_group.hidden = hidden
    new_group.casts_shadows = casts_shadows
    new_group.receives_shadows = receives_shadows

    # Kembalikan atribut
    attrs.each do |dict_name, pairs|
      dict = new_group.attribute_dictionary(dict_name, true)
      pairs.each { |k, v| dict[k] = v }

      # Jika ada Dynamic Component attributes, sesuaikan lenx/leny/lenz ke ukuran baru
      if dict_name.downcase == 'dynamic_attributes'
        bb = new_group.bounds
        dict['lenx'] = bb.width.to_f if dict.keys.include?('lenx')
        dict['leny'] = bb.height.to_f if dict.keys.include?('leny')
        dict['lenz'] = bb.depth.to_f if dict.keys.include?('lenz')
        dict['_lenx_nominal'] = bb.width.to_f if dict.keys.include?('_lenx_nominal')
        dict['_leny_nominal'] = bb.height.to_f if dict.keys.include?('_leny_nominal')
        dict['_lenz_nominal'] = bb.depth.to_f if dict.keys.include?('_lenz_nominal')
      end
    end

    result_entity = if is_component
      new_inst = new_group.to_component
      new_inst.definition.name = orig_defn_name if orig_defn_name
      new_inst
    else
      new_group
    end

    result_entity.locked = locked if locked
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
