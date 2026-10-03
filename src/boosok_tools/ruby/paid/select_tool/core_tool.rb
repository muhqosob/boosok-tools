Sketchup.require 'boosok_tools/ruby/locale' unless defined?(::BoosokTools::Locale)

module BoosokTools::SelectTool
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
        res_dir = File.join(::BoosokTools::SUPPORT_DIR, 'ruby', 'paid', 'select_tool', 'resources')
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
      @area_handler   = AreaHandler.new(self)
    end

    # Sedang menyeret kotak seleksi area? (dipakai HUD)
    def area_dragging?
      @area_handler.dragging?
    end

    def area_window?
      @area_handler.dragging? && @area_handler.window?
    end

    def loc(key, fallback)
      defined?(::BoosokTools::Locale) ? ::BoosokTools::Locale.t(key, fallback) : fallback
    end

    def activate
      reset_state!
      model = Sketchup.active_model
      if model && model.valid?
        # Pengecekan Empty State Model
        # Sengaja entities root (bukan active_entities): cek model kosong tidak boleh tergantung konteks edit
        if model.entities.empty? # rubocop:disable SketchupSuggestions/ModelEntities
          Sketchup.status_text = loc('cs_model_empty', 'Select Tool: Model kosong. Buat objek / grup terlebih dahulu.')
        else
          update_status_bar
        end
        model.active_view.invalidate rescue nil
      end
    rescue => e
      warn "[Select Tool] Error during activate: #{e.message}" if $DEBUG
    end

    # Tool dijeda (mis. orbit/pan): hapus overlay hover supaya tidak tertinggal di viewport
    def suspend(view)
      view.invalidate
    end

    # Area yang ditempati gambar tool, supaya highlight tidak terpotong (clipped) di viewport
    def getExtents
      bb = Geom::BoundingBox.new
      model = Sketchup.active_model
      bb.add(model.bounds) if model
      bb
    rescue
      Geom::BoundingBox.new
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
      @area_handler.reset if @area_handler
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
        Sketchup.status_text = loc('cs_hover_empty', 'Select Tool: Arahkan kursor ke group/komponen untuk mengubah level.')
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
          tpl = loc('cs_status_lvl_active', 'Select Tool [Level %{lvl} Aktif]: Arahkan ke objek | [ESC] Reset ke Level 0')
          Sketchup.status_text = tpl.gsub('%{lvl}', @target_depth.to_s)
        else
          Sketchup.status_text = loc('cs_status_idle', 'Select Tool: Arahkan ke objek | [CTRL + Scroll] Pilih level nested | [Klik] Seleksi')
        end
      else
        lvl = effective_depth
        entity = path[lvl]
        obj_fallback = loc('cs_object', 'Objek')
        ent_name = if entity.respond_to?(:name) && !entity.name.empty?
                     entity.name
                   elsif entity.respond_to?(:definition) && !entity.definition.name.empty?
                     entity.definition.name
                   else
                     ::BoosokTools::SelectTool.type_name(entity)
                   end
        tpl = loc('cs_status_hover', 'Select Tool [Level %{lvl}/%{max}: %{name}]: [Klik] Seleksi | [CTRL + Scroll] Ubah Level | [ESC] Reset')
        Sketchup.status_text = tpl.gsub('%{lvl}', lvl.to_s).gsub('%{max}', (path.length - 1).to_s).gsub('%{name}', ent_name.to_s)
      end
    rescue => e
      # Abaikan error status bar
    end

    # Delegate Callback Events ke Sub-Handlers dengan Fallback on Error
    def draw(view)
      @draw_handler.draw(view)
      @area_handler.draw(view)
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
      # Tombol kiri ditahan & bergeser: sedang menyeret kotak seleksi → sembunyikan highlight hover
      if @area_handler.pressed? && @area_handler.move(x, y)
        @cursor_x = x
        @cursor_y = y
        @hover_path = []
        update_status_bar
        view.invalidate
        return
      end

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

    # Klik tanpa seret = seleksi level seperti biasa (diproses saat tombol dilepas); tahan & seret = seleksi area
    def onLButtonDown(flags, x, y, view)
      @area_handler.press(x, y, flags)
    rescue => e
      warn "[Select Tool] Fallback on onLButtonDown error: #{e.message}" if $DEBUG
    end

    def onLButtonUp(flags, x, y, view)
      return unless @area_handler.pressed?

      if @area_handler.dragging?
        n = @area_handler.select_area(view, flags)
        mode = @area_handler.window? ? 'Window' : 'Crossing'
        Sketchup.status_text = loc('cs_status_area', 'Select Tool: %{n} objek terseleksi (%{mode}).').gsub('%{n}', n.to_s).gsub('%{mode}', mode)
      else
        @select_handler.process_selection(@area_handler.down_flags)
      end
      @area_handler.reset
      view.invalidate
    rescue => e
      @area_handler.reset
      warn "[Select Tool] Fallback on onLButtonUp error: #{e.message}" if $DEBUG
    end

    def onKeyDown(key, repeat, flags, view)
      if (defined?(COPY_MODIFIER_KEY) && key == COPY_MODIFIER_KEY) || key == 17 # Ctrl key
        @ctrl_pressed = true
        onSetCursor
        view.invalidate rescue nil
      elsif key == 27 # ESC: batalkan seret kotak kalau sedang menyeret, selain itu keluar dari select tool
        if @area_handler.pressed?
          @area_handler.reset
          view.invalidate rescue nil
        else
          Sketchup.active_model.select_tool(nil) rescue nil
        end
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
