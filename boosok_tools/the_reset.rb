module TheResetScale
  def self.run
    model = Sketchup.active_model
    selection = model.selection

    if selection.empty?
      UI.messagebox("Pilih semua Group/Component yang ingin di-reset skalanya terlebih dahulu!")
      return
    end

    model.start_operation('The Reset Scale', true)
    reset_count = 0
    
    selection.each do |entity|
      if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        t = entity.transformation
        
        x_axis = t.xaxis.normalize!
        y_axis = t.yaxis.normalize!
        z_axis = t.zaxis.normalize!
        
        new_transform = Geom::Transformation.axes(t.origin, x_axis, y_axis, z_axis)
        entity.transformation = new_transform
        
        reset_count += 1
      end
    end
    
    model.commit_operation
    UI.messagebox("Berhasil me-reset skala pada #{reset_count} objek secara bersamaan.")
  end
end