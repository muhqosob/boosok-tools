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
        log("FindWindowA('#{title}') => hwnd=#{hwnd}")
        return hwnd if hwnd && hwnd != 0
      rescue => e
        log("FindWindowA error: #{e.message}")
      end

      0
    end

    def self.apply_dark_titlebar(hwnd, is_dark)
      return unless ready? && hwnd && hwnd != 0

      val = [is_dark ? 1 : 0].pack('l')

      # DWMWA_USE_IMMERSIVE_DARK_MODE = 20 (Win10 20H1+ / Win11)
      r20 = DwmSetWindowAttribute.call(hwnd, 20, val, 4) rescue -1
      # Fallback DWMWA = 19 (Win10 1809..1909)
      r19 = DwmSetWindowAttribute.call(hwnd, 19, val, 4) rescue -1

      # DWMWA_CAPTION_COLOR = 35 (Win11 22H2+)
      # Dark: #141416 -> COLORREF 0x00161414 | Light: DWMWA_COLOR_DEFAULT 0xFFFFFFFF
      bg = is_dark ? [0x00161414].pack('L') : [0xFFFFFFFF].pack('L')
      r35 = DwmSetWindowAttribute.call(hwnd, 35, bg, 4) rescue -1

      # DWMWA_TEXT_COLOR = 36
      fg = is_dark ? [0x00F4F4F6].pack('L') : [0xFFFFFFFF].pack('L')
      r36 = DwmSetWindowAttribute.call(hwnd, 36, fg, 4) rescue -1

      # SWP_FRAMECHANGED | SWP_NOSIZE | SWP_NOMOVE | SWP_NOZORDER = 0x0027
      SetWindowPos.call(hwnd, 0, 0, 0, 0, 0, 0x0027) rescue nil

      log("apply_dark_titlebar hwnd=#{hwnd} dark=#{is_dark} r20=#{r20} r19=#{r19} r35=#{r35} r36=#{r36}")
    end

    def self.set_theme(title, is_dark)
      log("set_theme '#{title}' dark=#{is_dark} ready=#{ready?} err=#{@init_error}")
      return unless ready?

      hwnd = find_hwnd(title)
      apply_dark_titlebar(hwnd, is_dark) if hwnd != 0
    end

    def self.attach(dialog, title)
      return unless dialog
      log("attach '#{title}' ready=#{ready?} err=#{@init_error}")

      dialog.add_action_callback("syncTheme") do |_ctx, theme|
        is_dark = (theme.to_s == 'dark')
        Sketchup.write_default("BoosokTools", "theme", theme.to_s)
        set_theme(title, is_dark)
      end

      saved = Sketchup.read_default("BoosokTools", "theme", "light")
      is_dark = (saved.to_s == 'dark')

      [0.1, 0.3, 0.6, 1.0, 1.5].each do |delay|
        UI.start_timer(delay, false) { set_theme(title, is_dark) }
      end
    end
  end
end
