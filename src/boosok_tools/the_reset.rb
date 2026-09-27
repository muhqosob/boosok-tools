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
      width: 360, height: 380,
      style: UI::HtmlDialog::STYLE_DIALOG
    )
    dialog.set_file(File.join(__dir__, 'html', 'reset.html'))

    dialog.add_action_callback("close") { dialog.close }

    dialog.add_action_callback("reset") do
      result = reset_selection
      if result.is_a?(Integer)
        dialog.execute_script("showSuccessStep(#{"Skala #{result} objek kembali ke 1.".to_json})")
      else
        dialog.execute_script("resetExecButton(); showToast(#{result.to_json})")
      end
    end

    dialog.show
  end

  # Balikin jumlah objek yang di-reset, atau pesan error (String)
  def self.reset_selection
    model = Sketchup.active_model
    targets = model.selection.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
    return "Pilih minimal 1 group / component dulu." if targets.empty?

    model.start_operation('The Reset Scale', true)
    begin
      targets.each do |entity|
        t = entity.transformation
        entity.transformation = Geom::Transformation.axes(
          t.origin, t.xaxis.normalize!, t.yaxis.normalize!, t.zaxis.normalize!
        )
      end
      model.commit_operation
    rescue => e
      model.abort_operation
      return "Reset skala gagal: #{e.message}"
    end
    targets.size
  end
end
