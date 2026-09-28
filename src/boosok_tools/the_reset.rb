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

  def self.reset_selection(mode = "preserve", recursive = false)
    model = Sketchup.active_model
    targets = model.selection.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
    return "Pilih minimal 1 group / component dulu." if targets.empty?

    model.start_operation('The Reset Scale', true)
    begin
      processed_count = 0
      final_entities = []

      # Helper lambda untuk memproses satu entitas dan anak-anaknya jika recursive
      process_entity = lambda do |entity|
        return unless entity.respond_to?(:valid?) && entity.valid?
        return unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        if mode == "preserve"
          res = reset_scale_preserve(entity)
        else
          reset_scale_original(entity)
          res = entity
        end

        processed_count += 1
        final_entities << res if res && res.respond_to?(:valid?) && res.valid?

        # Jika recursive, proses juga child group & component di dalam definition
        if recursive && res && res.respond_to?(:valid?) && res.valid?
          defn = res.respond_to?(:definition) ? res.definition : res.entities.parent
          children = defn.entities.select { |c| c.is_a?(Sketchup::Group) || c.is_a?(Sketchup::ComponentInstance) }
          children.each { |child| process_entity.call(child) }
        end
      end

      targets.each do |target|
        process_entity.call(target)
      end

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

  # Reset skala: pertahankan ukuran saat ini (bake scale ke geometri definition),
  # dan reset transformasi instance menjadi 1:1:1 tanpa mengubah posisi atau sumbu (axes).
  def self.reset_scale_preserve(entity)
    return entity unless entity.respond_to?(:valid?) && entity.valid?
    return entity unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

    was_locked = entity.locked? if entity.respond_to?(:locked?)
    entity.locked = false if was_locked

    t = entity.transformation
    m = t.to_a
    s = m[15].to_f.abs > 1e-9 ? m[15].to_f : 1.0

    vx = Geom::Vector3d.new(m[0], m[1], m[2])
    vy = Geom::Vector3d.new(m[4], m[5], m[6])
    vz = Geom::Vector3d.new(m[8], m[9], m[10])

    if vx.length < 1e-6 || vy.length < 1e-6 || vz.length < 1e-6
      entity.locked = was_locked if was_locked
      return entity
    end

    sx = vx.length / s
    sy = vy.length / s
    sz = vz.length / s

    is_scaled = (sx - 1.0).abs > 1e-4 || (sy - 1.0).abs > 1e-4 || (sz - 1.0).abs > 1e-4 || (s - 1.0).abs > 1e-4

    # Jika sudah 1:1:1, tidak perlu modifikasi geometri
    unless is_scaled
      entity.locked = was_locked if was_locked
      return entity
    end

    # Pastikan definition unik agar perubahan geometri tidak merusak duplikat lain
    if entity.respond_to?(:make_unique)
      begin
        entity.make_unique
      rescue
      end
    end

    defn = entity.respond_to?(:definition) ? entity.definition : entity.entities.parent

    # 1. Terapkan skala ke geometri internal definition
    t_scale = Geom::Transformation.scaling(sx, sy, sz)
    ents = defn.entities.to_a
    defn.entities.transform_entities(t_scale, ents) unless ents.empty?

    # 2. Reset skala transformasi instance ke 1:1:1 dengan posisi dan orientasi axes yang tetap persis
    origin = Geom::Point3d.new(m[12] / s, m[13] / s, m[14] / s)
    ux = vx.normalize
    uy = vy.normalize
    uz = vz.normalize
    t_unscaled = Geom::Transformation.axes(origin, ux, uy, uz)

    entity.transformation = t_unscaled

    # Sesuaikan ukuran jika ada Dynamic Attributes
    [entity, defn].each do |target_obj|
      next unless target_obj.respond_to?(:attribute_dictionaries) && target_obj.attribute_dictionaries
      dict = target_obj.attribute_dictionary('dynamic_attributes')
      next unless dict
      ['lenx', 'leny', 'lenz', '_lenx_nominal', '_leny_nominal', '_lenz_nominal'].each do |k|
        next unless dict.keys.include?(k)
        scale_factor = k.include?('x') ? sx : (k.include?('y') ? sy : sz)
        dict[k] = (dict[k].to_f * scale_factor)
      end
    end

    entity.locked = was_locked if was_locked
    entity
  end

  # Reset skala kembali ke ukuran asli sebelum diskala
  def self.reset_scale_original(entity)
    return entity unless entity.respond_to?(:valid?) && entity.valid?
    return entity unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

    was_locked = entity.locked? if entity.respond_to?(:locked?)
    entity.locked = false if was_locked

    t = entity.transformation
    m = t.to_a
    s = m[15].to_f.abs > 1e-9 ? m[15].to_f : 1.0

    vx = Geom::Vector3d.new(m[0], m[1], m[2])
    vy = Geom::Vector3d.new(m[4], m[5], m[6])
    vz = Geom::Vector3d.new(m[8], m[9], m[10])

    if vx.length < 1e-6 || vy.length < 1e-6 || vz.length < 1e-6
      entity.locked = was_locked if was_locked
      return entity
    end

    origin = Geom::Point3d.new(m[12] / s, m[13] / s, m[14] / s)
    entity.transformation = Geom::Transformation.axes(
      origin, vx.normalize, vy.normalize, vz.normalize
    )

    entity.locked = was_locked if was_locked
    entity
  end
end
