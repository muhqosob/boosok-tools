module BoosokTools::SelectTool5D
  class CoreTool
    attr_accessor :hover_path, :target_depth, :ctrl_pressed, :cursor_x, :cursor_y

    def initialize
      @hover_path = []
      @target_depth = 0
      @ctrl_pressed = false
      @cursor_x = nil
      @cursor_y = nil

      # Load Custom Cursor (panah biru khas Select Tool)
      begin
        res_dir = File.join(__dir__, 'resources')
        cursor_path     = File.join(res_dir, 'cursor_select.png')
        cursor_add_path = File.join(res_dir, 'cursor_select_add.png')
        @cursor_select_id = UI.create_cursor(cursor_path, 3, 3) if File.exist?(cursor_path)
        @cursor_add_id    = UI.create_cursor(cursor_add_path, 3, 3) if File.exist?(cursor_add_path)
      rescue => e
        @cursor_select_id = nil
        @cursor_add_id    = nil
        warn "[Select Tool] Cursor load error: #{e.message}" if $DEBUG
      end

      # Inisialisasi Handlers
      @draw_handler   = DrawHandler.new(self)
      @select_handler = SelectHandler.new(self)
      @mouse_handler  = MouseHandler.new(self)
    end

    def activate
      reset_state!
      model = Sketchup.active_model
      if model && model.valid?
        # Pengecekan Empty State Model
        if model.entities.empty?
          Sketchup.status_text = "Select Tool: Model kosong. Buat objek / grup terlebih dahulu."
        else
          update_status_bar
        end
        model.active_view.invalidate rescue nil
      end
    rescue => e
      warn "[Select Tool] Error during activate: #{e.message}" if $DEBUG
    end

    def deactivate(view)
      reset_state!
      Sketchup.status_text = "" rescue nil
      view.invalidate rescue nil
    rescue => e
      warn "[Select Tool] Error during deactivate: #{e.message}" if $DEBUG
    end

    def refresh(view)
      update_status_bar
      view.invalidate rescue nil
    rescue => e
      warn "[Select Tool] Error during refresh: #{e.message}" if $DEBUG
    end

    # Reset state tool ke kondisi bersih
    def reset_state!
      @hover_path = []
      @ctrl_pressed = false
      @cursor_x = nil
      @cursor_y = nil
    end

    # Bersihkan hover path dari entitas yang sudah terhapus / invalid
    def valid_hover_path
      return [] if @hover_path.nil? || @hover_path.empty?

      @hover_path.select { |e| e && e.respond_to?(:valid?) && e.valid? }
    rescue => e
      []
    end

    # Hitung level kedalaman efektif saat ini dengan aman (clamped ke batas hierarki hover)
    def effective_depth
      path = valid_hover_path
      return 0 if path.empty?

      max_depth = [path.length - 1, 0].max
      [[@target_depth, 0].max, max_depth].min
    rescue => e
      0
    end

    def change_depth(step, view)
      path = valid_hover_path
      # Pengecekan Empty State: kursor sedang berada di area kosong
      if path.empty?
        Sketchup.status_text = "Select Tool: Arahkan kursor ke group/komponen untuk mengubah level."
        return
      end

      max_depth = [path.length - 1, 0].max
      current = effective_depth
      new_depth = current + step

      # Mentok di 0 (outermost) saat scroll up dan mentok di max_depth (deepest) saat scroll down
      new_depth = 0 if new_depth < 0
      new_depth = max_depth if new_depth > max_depth

      if new_depth != @target_depth
        @target_depth = new_depth
        refresh(view)
      end
    rescue => e
      warn "[Select Tool] Error in change_depth: #{e.message}" if $DEBUG
    end

    # Update status bar teks untuk memandu pengguna
    def update_status_bar
      path = valid_hover_path
      if path.empty?
        if @target_depth > 0
          Sketchup.status_text = "Select Tool [Level #{@target_depth} Aktif]: Arahkan ke objek | [ESC] Reset ke Level 0"
        else
          Sketchup.status_text = "Select Tool: Arahkan ke objek | [CTRL + Scroll] Pilih level nested | [Klik] Seleksi"
        end
      else
        lvl = effective_depth
        entity = path[lvl]
        ent_name = if entity.respond_to?(:name) && !entity.name.empty?
                     entity.name
                   elsif entity.respond_to?(:definition) && !entity.definition.name.empty?
                     entity.definition.name
                   else
                     entity.typename rescue "Objek"
                   end
        Sketchup.status_text = "Select Tool [Level #{lvl}/#{path.length - 1}: #{ent_name}]: [Klik] Seleksi | [CTRL + Scroll] Ubah Level | [ESC] Reset"
      end
    rescue => e
      # Abaikan error status bar
    end

    # Delegate Callback Events ke Sub-Handlers dengan Fallback on Error
    def draw(view)
      @draw_handler.draw(view)
    rescue => e
      # Safe Fallback: Mencegah error viewport loop di SketchUp
      warn "[Select Tool] Fallback on draw error: #{e.message}" if $DEBUG
    end

    # Custom cursor: panah biru saat normal, panah biru+plus saat Ctrl ditekan
    def onSetCursor
      cursor_id = (@ctrl_pressed && @cursor_add_id) ? @cursor_add_id : @cursor_select_id
      UI.set_cursor(cursor_id) if cursor_id
    rescue
      # Abaikan error cursor
    end

    def onMouseMove(flags, x, y, view)
      @mouse_handler.onMouseMove(flags, x, y, view)
    rescue => e
      warn "[Select Tool] Fallback on onMouseMove error: #{e.message}" if $DEBUG
    end

    def onMouseWheel(flags, delta, x, y, view)
      @mouse_handler.onMouseWheel(flags, delta, x, y, view)
    rescue => e
      warn "[Select Tool] Fallback on onMouseWheel error: #{e.message}" if $DEBUG
      false
    end

    def onLButtonDown(flags, x, y, view)
      @select_handler.process_selection(flags)
    rescue => e
      warn "[Select Tool] Fallback on onLButtonDown error: #{e.message}" if $DEBUG
    end

    def onKeyDown(key, repeat, flags, view)
      if (defined?(COPY_MODIFIER_KEY) && key == COPY_MODIFIER_KEY) || key == 17 # Ctrl key
        @ctrl_pressed = true
        onSetCursor
        view.invalidate rescue nil
      elsif key == 27 # ESC key: keluar dari select tool
        Sketchup.active_model.select_tool(nil) rescue nil
      end
    rescue => e
      warn "[Select Tool] Fallback on onKeyDown error: #{e.message}" if $DEBUG
    end

    def onKeyUp(key, repeat, flags, view)
      if (defined?(COPY_MODIFIER_KEY) && key == COPY_MODIFIER_KEY) || key == 17
        @ctrl_pressed = false
        onSetCursor
        view.invalidate rescue nil
      end
    rescue => e
      warn "[Select Tool] Fallback on onKeyUp error: #{e.message}" if $DEBUG
    end
  end
end
