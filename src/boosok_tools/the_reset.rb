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
          "Skala #{result} objek di-reset (ukuran tetap #{result > 1 ? 'sama' : 'sama'})."
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

  # Salin atribut dictionary dari sumber ke target
  def self.copy_attributes(source, target)
    return unless source.respond_to?(:attribute_dictionaries) && source.attribute_dictionaries
    source.attribute_dictionaries.each do |dict|
      next unless dict
      new_dict = target.attribute_dictionary(dict.name, true)
      dict.each_pair do |k, v|
        new_dict[k] = v
      end
    end
  end

  # Reset skala ke 1:1:1 tanpa mengubah ukuran visual saat ini (bake scale ke geometri)
  def self.reset_scale_preserve(entity, parent_entities)
    return entity unless entity.respond_to?(:valid?) && entity.valid?
    return entity unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

    t = entity.transformation
    xaxis = t.xaxis
    yaxis = t.yaxis
    zaxis = t.zaxis

    sx = xaxis.length
    sy = yaxis.length
    sz = zaxis.length

    # Hindari degenerate vectors
    return entity if sx < 1e-6 || sy < 1e-6 || sz < 1e-6

    nx = xaxis.normalize
    ny = yaxis.normalize
    nz = zaxis.normalize
    t_unscaled = Geom::Transformation.axes(t.origin, nx, ny, nz)

    is_scaled = (sx - 1.0).abs > 1e-5 || (sy - 1.0).abs > 1e-5 || (sz - 1.0).abs > 1e-5

    # Jika skalanya memang sudah 1:1:1, cukup rapikan transformasi
    unless is_scaled
      entity.transformation = t_unscaled
      return entity
    end

    # Objek diskala: buat group pembungkus dengan t_unscaled, tambahkan instance ter-skala di dalamnya lalu explode
    is_component = entity.is_a?(Sketchup::ComponentInstance)
    orig_defn = entity.respond_to?(:definition) ? entity.definition : entity.entities.parent
    orig_name = entity.name
    orig_layer = entity.layer
    orig_material = entity.material
    orig_casts_shadows = entity.casts_shadows?
    orig_receives_shadows = entity.receives_shadows?
    orig_hidden = entity.hidden?
    orig_locked = entity.locked?

    t_scale = Geom::Transformation.scaling(sx, sy, sz)

    new_group = parent_entities.add_group
    new_group.transformation = t_unscaled
    new_group.layer = orig_layer if orig_layer
    new_group.material = orig_material if orig_material
    new_group.name = orig_name unless orig_name.to_s.empty?
    new_group.casts_shadows = orig_casts_shadows
    new_group.receives_shadows = orig_receives_shadows
    new_group.hidden = orig_hidden

    copy_attributes(entity, new_group)

    temp_inst = new_group.entities.add_instance(orig_defn, t_scale)
    temp_inst.explode if temp_inst

    entity.locked = false if entity.locked?
    entity.erase!

    result_entity = if is_component
      new_inst = new_group.to_component
      new_inst.definition.name = orig_defn.name
      copy_attributes(new_group, new_inst)
      new_inst
    else
      new_group
    end

    result_entity.locked = orig_locked if orig_locked
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
