require 'sketchup'

module BoosokTools
  module TitleBar
    @ready = false
    @init_error = nil

    begin
      require 'fiddle'

      User32 = Fiddle.dlopen('user32.dll')
      Dwmapi = Fiddle.dlopen('dwmapi.dll')

      FindWindowA = Fiddle::Function.new(
        User32['FindWindowA'],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INTPTR_T
      )

      SetWindowPos = Fiddle::Function.new(
        User32['SetWindowPos'],
        [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T,
         Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT,
         Fiddle::TYPE_INT],
        Fiddle::TYPE_INT
      )

      DwmSetWindowAttribute = Fiddle::Function.new(
        Dwmapi['DwmSetWindowAttribute'],
        [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
        Fiddle::TYPE_INT
      )

      # SendMessageA(hwnd, msg, wParam, lParam)
      SendMessageA = Fiddle::Function.new(
        User32['SendMessageA'],
        [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INT, Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T],
        Fiddle::TYPE_INTPTR_T
      )

      GetWindowRect = Fiddle::Function.new(
        User32['GetWindowRect'],
        [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT
      )

      @ready = true
    rescue => e
      @ready = false
      @init_error = e.message
    end

    def self.log(msg)
      log_file = File.join(File.dirname(__FILE__), 'titlebar.log')
      File.open(log_file, 'a') { |f| f.puts("[#{Time.now.strftime('%H:%M:%S')}] #{msg}") }
    rescue
    end

    def self.ready?
      @ready
    end

    def self.find_hwnd(title)
      return 0 unless ready?
      return 0 unless title && !title.strip.empty?

      begin
        hwnd = FindWindowA.call(nil, title.to_s)
        return hwnd if hwnd && hwnd != 0
      rescue => e
        log("FindWindowA error: #{e.message}")
      end

      0
    end

    def self.get_window_pos(title)
      return nil unless ready?
      hwnd = find_hwnd(title)
      return nil if hwnd == 0

      buf = [0, 0, 0, 0].pack('l4')
      if GetWindowRect.call(hwnd, buf) != 0
        left, top, right, bottom = buf.unpack('l4')
        return [left, top] if left > -2000 && top > -2000
      end
      nil
    rescue => e
      log("get_window_pos error: #{e.message}")
      nil
    end

    def self.set_window_pos(title, x, y)
      return unless ready?
      hwnd = find_hwnd(title)
      return if hwnd == 0
      # SWP_NOSIZE = 0x0001, SWP_NOZORDER = 0x0004, SWP_NOACTIVATE = 0x0010
      SetWindowPos.call(hwnd, 0, x.to_i, y.to_i, 0, 0, 0x0015) rescue nil
    end

    def self.apply_dark_titlebar(hwnd, is_dark)
      return unless ready? && hwnd && hwnd != 0

      val = [is_dark ? 1 : 0].pack('l')

      # DWMWA_USE_IMMERSIVE_DARK_MODE = 20 (Win10 20H1+/Win11)
      DwmSetWindowAttribute.call(hwnd, 20, val, 4) rescue nil
      # Fallback DWMWA = 19 (Win10 1809..1909)
      DwmSetWindowAttribute.call(hwnd, 19, val, 4) rescue nil

      # DWMWA_CAPTION_COLOR = 35 (Win11 22H2+)
      bg = is_dark ? [0x00161414].pack('L') : [0xFFFFFFFF].pack('L')
      DwmSetWindowAttribute.call(hwnd, 35, bg, 4) rescue nil

      # DWMWA_TEXT_COLOR = 36
      fg = is_dark ? [0x00F4F4F6].pack('L') : [0xFFFFFFFF].pack('L')
      DwmSetWindowAttribute.call(hwnd, 36, fg, 4) rescue nil

      # Force titlebar repaint: toggle WM_NCACTIVATE off then on
      # WM_NCACTIVATE = 0x0086
      SendMessageA.call(hwnd, 0x0086, 0, 0) rescue nil
      SendMessageA.call(hwnd, 0x0086, 1, 0) rescue nil

      # Also SWP_FRAMECHANGED for good measure
      SetWindowPos.call(hwnd, 0, 0, 0, 0, 0, 0x0027) rescue nil

      log("apply hwnd=#{hwnd} dark=#{is_dark}")
    end

    def self.set_theme(title, is_dark)
      return unless ready?
      hwnd = find_hwnd(title)
      if hwnd != 0
        apply_dark_titlebar(hwnd, is_dark)
      end
    end

    def self.attach(dialog, title, width: nil)
      return unless dialog
      log("attach '#{title}' ready=#{ready?}")

      dialog.add_action_callback("syncTheme") do |_ctx, theme|
        is_dark = (theme.to_s == 'dark')
        Sketchup.write_default("BoosokTools", "theme", theme.to_s)
        set_theme(title, is_dark)
      end

      dialog.add_action_callback("save_position") do |_ctx, pos_json|
        pos = JSON.parse(pos_json) rescue nil
        if pos && pos["left"] && pos["top"]
          BoosokTools.save_position(pos["left"], pos["top"])
        end
      end

      dialog.add_action_callback("back_to_hub") do |_ctx, pos_json|
        pos = JSON.parse(pos_json) rescue nil
        if pos && pos["left"] && pos["top"]
          BoosokTools.save_position(pos["left"], pos["top"])
        else
          BoosokTools.capture_current_position(title)
        end
        dialog.close rescue nil
        load File.join(__dir__, 'hub.rb')
        BoosokTools::Hub.show
      end

      dialog.add_action_callback("set_dialog_height") do |_ctx, height|
        h = height.to_i
        if h > 200 && h < 1200
          w = width ? width.to_i : 380
          dialog.set_size(w, h)
        end
      end

      saved = Sketchup.read_default("BoosokTools", "theme", "light")
      is_dark = (saved.to_s == 'dark')

      [0.3, 0.6, 1.0, 1.5, 2.5].each do |delay|
        UI.start_timer(delay, false) { set_theme(title, is_dark) }
      end
    end
  end

  @dialog_pos = nil

  def self.save_position(x, y)
    left = x.to_i
    top = y.to_i
    if left > 5 && top > 5
      @dialog_pos = [left, top]
      Sketchup.write_default("BoosokTools", "dialog_left", left)
      Sketchup.write_default("BoosokTools", "dialog_top", top)
    end
  end

  def self.get_position
    if @dialog_pos
      return @dialog_pos
    end
    x = Sketchup.read_default("BoosokTools", "dialog_left", nil)
    y = Sketchup.read_default("BoosokTools", "dialog_top", nil)
    if x && y && x.to_i > 5 && y.to_i > 5
      @dialog_pos = [x.to_i, y.to_i]
      return @dialog_pos
    end
    [320, 200]
  end

  def self.capture_current_position(title)
    pos = TitleBar.get_window_pos(title)
    if pos
      save_position(pos[0], pos[1])
      return pos
    end
    get_position
  end

  @hub_booted ||= false

  def self.hub_booted?
    @hub_booted == true
  end

  def self.set_hub_booted(val = true)
    @hub_booted = val
  end
end
