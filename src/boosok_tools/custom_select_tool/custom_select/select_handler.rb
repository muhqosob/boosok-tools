module CustomTools::SelectTool5D
  class SelectHandler
    def initialize(tool)
      @tool = tool
    end

    def process_selection(flags)
      selection = Sketchup.active_model.selection
      ctrl_down = @tool.ctrl_pressed || ((flags & COPY_MODIFIER_MASK) == COPY_MODIFIER_MASK)
      shift_down = ((flags & CONSTRAIN_MODIFIER_MASK) == CONSTRAIN_MODIFIER_MASK)

      if @tool.hover_path.empty?
        selection.clear unless ctrl_down || shift_down
        return
      end

      target_path_array = @tool.hover_path[0..@tool.target_depth]
      return if target_path_array.empty?

      target_entity = target_path_array.last
      return unless target_entity && target_entity.valid?

      instance_path = begin
        Sketchup::InstancePath.new(target_path_array)
      rescue
        nil
      end

      # Kosongkan seleksi sebelumnya HANYA jika tidak menahan tombol Ctrl atau Shift
      selection.clear unless ctrl_down || shift_down

      # Seleksi target TANPA membuka grup induk (tidak mengubah model.active_path)
      selected = false
      if instance_path && instance_path.valid?
        begin
          if shift_down
            selection.toggle(instance_path)
          else
            selection.add(instance_path)
          end
          selected = true
        rescue
        end
      end

      unless selected
        begin
          if shift_down
            selection.toggle(target_entity)
          else
            selection.add(target_entity)
          end
        rescue
        end
      end
    end
  end
end