require 'sketchup'
require 'json'

module TheResetScale
  def self.run
    if @dialog && @dialog.visible?
      @dialog.bring_to_front
      return
    end

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
          "Skala #{result} objek di-reset (ukuran saat ini tetap)."
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

      process_entity = lambda do |entity|
        return unless entity.respond_to?(:valid?) && entity.valid?
        return unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        if mode == "preserve"
          reset_scale_preserve(entity)
        else
          reset_scale_original(entity)
        end
        processed_count += 1

        if recursive
          defn = entity.respond_to?(:definition) ? entity.definition : entity.entities.parent
          children = defn.entities.select { |child| child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance) }
          children.each { |child| process_entity.call(child) }
        end
      end

      targets.each { |entity| process_entity.call(entity) }

      model.commit_operation
      processed_count
    rescue => e
      model.abort_operation
      return "Reset skala gagal: #{e.message}"
    end
  end

  # Reset skala ke 1:1:1 tanpa mengubah ukuran visual saat ini (bake scale ke geometri definition)
  def self.reset_scale_preserve(entity)
    t = entity.transformation
    xaxis = t.xaxis
    yaxis = t.yaxis
    zaxis = t.zaxis

    sx = xaxis.length
    sy = yaxis.length
    sz = zaxis.length

    # Hindari degenerate vectors (objek gepeng total)
    return if sx < 1e-6 || sy < 1e-6 || sz < 1e-6

    nx = xaxis.normalize
    ny = yaxis.normalize
    nz = zaxis.normalize
    t_unscaled = Geom::Transformation.axes(t.origin, nx, ny, nz)

    is_scaled = (sx - 1.0).abs > 1e-5 || (sy - 1.0).abs > 1e-5 || (sz - 1.0).abs > 1e-5

    if is_scaled
      entity.make_unique if entity.respond_to?(:make_unique)
      defn = entity.respond_to?(:definition) ? entity.definition : entity.entities.parent
      inner_ents = defn.entities.to_a

      # t_unscaled * t_inner = t  =>  t_inner = t_unscaled.inverse * t
      t_inner = t_unscaled.inverse * t

      unless inner_ents.empty?
        begin
          defn.entities.transform_entities(t_inner, inner_ents)
        rescue
          inner_ents.each do |e|
            if e.respond_to?(:transform!)
              e.transform!(t_inner)
            elsif e.is_a?(Sketchup::Drawingelement)
              defn.entities.transform_entities(t_inner, [e]) rescue nil
            end
          end
        end
      end
    end

    entity.transformation = t_unscaled
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
