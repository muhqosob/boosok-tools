module CustomTools::SelectTool5D
  class CoreTool
    attr_accessor :hover_path, :target_depth, :ctrl_pressed, :cursor_x, :cursor_y

    def initialize
      @hover_path = []
      @target_depth = 0
      @ctrl_pressed = false
      @cursor_x = nil
      @cursor_y = nil

      # Inisialisasi Handlers
      @draw_handler   = DrawHandler.new(self)
      @select_handler = SelectHandler.new(self)
      @mouse_handler  = MouseHandler.new(self)
    end

    def activate
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      view.invalidate
    end

    def refresh(view)
      view.invalidate
    end

    def change_depth(step, view)
      return if @hover_path.nil? || @hover_path.empty?

      max_depth = [@hover_path.length - 1, 0].max
      new_depth = @target_depth + step

      # Mentok di 0 (outermost) saat scroll up dan mentok di max_depth (deepest) saat scroll down
      new_depth = 0 if new_depth < 0
      new_depth = max_depth if new_depth > max_depth

      if new_depth != @target_depth
        @target_depth = new_depth
        refresh(view)
      end
    end

    # Delegate Callback Events ke Sub-Handlers
    def draw(view)
      @draw_handler.draw(view)
    end

    def onMouseMove(flags, x, y, view)
      @mouse_handler.onMouseMove(flags, x, y, view)
    end

    def onMouseWheel(flags, delta, x, y, view)
      @mouse_handler.onMouseWheel(flags, delta, x, y, view)
    end

    def onLButtonDown(flags, x, y, view)
      @select_handler.process_selection(flags)
    end

    def onKeyDown(key, repeat, flags, view)
      if key == COPY_MODIFIER_KEY
        @ctrl_pressed = true
        view.invalidate
      end
    end

    def onKeyUp(key, repeat, flags, view)
      if key == COPY_MODIFIER_KEY
        @ctrl_pressed = false
        view.invalidate
      end
    end
  end
end