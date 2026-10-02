Sketchup.require 'boosok_tools/locale' unless defined?(::BoosokTools::Locale)

module BoosokTools::SelectTool
  class SelectHandler
    def initialize(tool)
      @tool = tool
    end

    def loc(key, fallback)
      defined?(::BoosokTools::Locale) ? ::BoosokTools::Locale.t(key, fallback) : fallback
    end

    def process_selection(flags)
      model = Sketchup.active_model
      return unless model && model.respond_to?(:selection)

      selection = model.selection
      ctrl_flag = defined?(COPY_MODIFIER_MASK) ? ((flags & COPY_MODIFIER_MASK) == COPY_MODIFIER_MASK) : false
      shift_flag = defined?(CONSTRAIN_MODIFIER_MASK) ? ((flags & CONSTRAIN_MODIFIER_MASK) == CONSTRAIN_MODIFIER_MASK) : false

      ctrl_down  = @tool.ctrl_pressed || ctrl_flag
      shift_down = shift_flag

      path = @tool.valid_hover_path

      # Pengecekan Empty State: Klik pada ruang kosong di viewport
      if path.empty?
        unless ctrl_down || shift_down
          selection.clear
          Sketchup.status_text = loc('cs_status_cleared', 'Select Tool: Seleksi dibersihkan.')
        end
        return
      end

      depth = @tool.effective_depth
      target_path_array = path[0..depth]
      return if target_path_array.empty?

      target_entity = target_path_array.last
      return unless target_entity && target_entity.respond_to?(:valid?) && target_entity.valid?

      # Notifikasi jika objek terkunci
      if target_entity.respond_to?(:locked?) && target_entity.locked?
        Sketchup.status_text = loc('cs_status_locked', 'Select Tool: Objek terkunci (Locked).')
      end

      # Kosongkan seleksi sebelumnya HANYA jika tidak menahan tombol Ctrl atau Shift
      selection.clear unless ctrl_down || shift_down

      # Coba seleksi berbasis InstancePath (SketchUp 2020+) tanpa membuka grup induk
      instance_path = nil
      if defined?(Sketchup::InstancePath)
        begin
          ip = Sketchup::InstancePath.new(target_path_array)
          instance_path = ip if ip.respond_to?(:valid?) && ip.valid?
        rescue => e
          instance_path = nil
        end
      end

      selected = false
      if instance_path
        begin
          if shift_down && selection.respond_to?(:toggle)
            selection.toggle(instance_path)
          else
            selection.add(instance_path)
          end
          selected = true
        rescue => e
          selected = false # Fallback ke target_entity
        end
      end

      # Fallback on Error: Jika InstancePath gagal, gunakan target_entity langsung
      unless selected
        begin
          if shift_down && selection.respond_to?(:toggle)
            selection.toggle(target_entity)
          else
            selection.add(target_entity)
          end
          selected = true
        rescue => e
          warn "[Select Tool] Fallback selection error: #{e.message}" if $DEBUG
        end
      end

      # Tampilkan feedback hasil seleksi ke status bar
      if selected
        obj_fallback = loc('cs_object', 'Objek')
        ent_name = if target_entity.respond_to?(:name) && !target_entity.name.empty?
                     target_entity.name
                   elsif target_entity.respond_to?(:definition) && !target_entity.definition.name.empty?
                     target_entity.definition.name
                   else
                     ::BoosokTools::SelectTool.type_name(target_entity)
                   end
        lock_badge = (target_entity.respond_to?(:locked?) && target_entity.locked?) ? loc('cs_locked_badge', ' [Terkunci]') : ""
        tpl = loc('cs_status_selected', 'Select Tool: Berhasil memilih %{name} (Level %{depth})%{lock} [Total: %{count}].')
        Sketchup.status_text = tpl.gsub('%{name}', ent_name.to_s).gsub('%{depth}', depth.to_s).gsub('%{lock}', lock_badge).gsub('%{count}', selection.count.to_s)
      end
    rescue => e
      warn "[Select Tool] Error during process_selection: #{e.message}" if $DEBUG
    end
  end
end
