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

    def self.attach(dialog, title)
      return unless dialog
      log("attach '#{title}' ready=#{ready?}")

      dialog.add_action_callback("syncTheme") do |_ctx, theme|
        is_dark = (theme.to_s == 'dark')
        Sketchup.write_default("BoosokTools", "theme", theme.to_s)
        set_theme(title, is_dark)
      end

      saved = Sketchup.read_default("BoosokTools", "theme", "light")
      is_dark = (saved.to_s == 'dark')

      [0.3, 0.6, 1.0, 1.5, 2.5].each do |delay|
        UI.start_timer(delay, false) { set_theme(title, is_dark) }
      end
    end
  end
end
