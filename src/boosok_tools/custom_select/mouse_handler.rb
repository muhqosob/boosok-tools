module BoosokTools::SelectTool5D
  class MouseHandler
    def initialize(tool)
      @tool = tool
    end

    def onMouseMove(flags, x, y, view)
      ctrl_flag = defined?(COPY_MODIFIER_MASK) ? ((flags & COPY_MODIFIER_MASK) == COPY_MODIFIER_MASK) : false
      @tool.ctrl_pressed = ctrl_flag || @tool.ctrl_pressed
      @tool.cursor_x = x
      @tool.cursor_y = y

      return unless view && view.respond_to?(:pick_helper)

      # Inisialisasi PickHelper dari view aktif
      ph = view.pick_helper
      ph.do_pick(x, y)

      # Ambil hierarki instance path objek di bawah kursor
      model = Sketchup.active_model
      active_path = (model && model.respond_to?(:active_path) && model.active_path) ? model.active_path : []
      picked_path = (ph.respond_to?(:count) && ph.count > 0 && ph.path_at(0)) ? ph.path_at(0) : []

      raw_path = picked_path.empty? ? [] : (active_path + picked_path)
      # Validasi State Management: pastikan semua entitas di path masih valid
      path = raw_path.select { |e| e && e.respond_to?(:valid?) && e.valid? }

      if path != @tool.hover_path
        @tool.hover_path = path
        # Pertahankan target_depth (presisten pada Level 1 / level yang dipilih user)
        @tool.refresh(view)
      else
        @tool.update_status_bar if path.empty?
        view.invalidate rescue nil # Update posisi HUD mengambang di samping kursor secara smooth
      end
    rescue => e
      # Fallback on Error: Reset hover path agar tidak corrupt state
      @tool.hover_path = []
      view.invalidate rescue nil if view
      warn "[5D Select Tool] Error onMouseMove: #{e.message}" if $DEBUG
    end

    def onMouseWheel(flags, delta, x, y, view)
      @tool.cursor_x = x
      @tool.cursor_y = y

      ctrl_flag = defined?(COPY_MODIFIER_MASK) ? ((flags & COPY_MODIFIER_MASK) == COPY_MODIFIER_MASK) : false
      if @tool.ctrl_pressed || ctrl_flag
        # Scroll UP (delta > 0) -> menuju Level 0 (outermost) => step = -1
        # Scroll DOWN (delta < 0) -> menuju level lebih dalam => step = +1
        step = delta > 0 ? -1 : 1
        @tool.change_depth(step, view)
        return true
      end
      false
    rescue => e
      warn "[5D Select Tool] Error onMouseWheel: #{e.message}" if $DEBUG
      false
    end
  end
end
