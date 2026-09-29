module CustomTools::SelectTool5D
  class MouseHandler
    def initialize(tool)
      @tool = tool
    end

    def onMouseMove(flags, x, y, view)
      @tool.ctrl_pressed = ((flags & COPY_MODIFIER_MASK) == COPY_MODIFIER_MASK)
      @tool.cursor_x = x
      @tool.cursor_y = y

      # Inisialisasi PickHelper dari view aktif
      ph = view.pick_helper
      ph.do_pick(x, y)

      # Ambil hierarki instance path objek di bawah kursor
      model = Sketchup.active_model
      active_path = (model && model.active_path) ? model.active_path : []
      picked_path = (ph.count > 0 && ph.path_at(0)) ? ph.path_at(0) : []

      path = picked_path.empty? ? [] : (active_path + picked_path)

      if path != @tool.hover_path
        @tool.hover_path = path
        @tool.target_depth = 0
        @tool.refresh(view)
      else
        view.invalidate # Update posisi HUD mengambang di samping kursor secara smooth
      end
    end

    def onMouseWheel(flags, delta, x, y, view)
      @tool.cursor_x = x
      @tool.cursor_y = y

      if @tool.ctrl_pressed || ((flags & COPY_MODIFIER_MASK) == COPY_MODIFIER_MASK)
        # Scroll UP (delta > 0) -> menuju Level 0 (outermost) => step = -1
        # Scroll DOWN (delta < 0) -> menuju level lebih dalam => step = +1
        step = delta > 0 ? -1 : 1
        @tool.change_depth(step, view)
        return true
      end
      false
    end
  end
end