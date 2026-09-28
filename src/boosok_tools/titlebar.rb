require 'sketchup'

module BoosokTools
  module TitleBar
    IS_WINDOWS = (RUBY_PLATFORM =~ /mswin|mingw|cygwin/) != nil

    @available = false

    if IS_WINDOWS
      begin
        require 'fiddle'
        require 'fiddle/import'

        module Win32
          extend Fiddle::Importer
          dlload 'user32.dll'
          dlload 'dwmapi.dll'

          extern 'uintptr_t FindWindowW(void*, void*)' rescue nil
          extern 'uint32_t GetWindowThreadProcessId(uintptr_t, void*)' rescue nil
          extern 'uintptr_t GetTopWindow(uintptr_t)' rescue nil
          extern 'uintptr_t GetWindow(uintptr_t, uint32_t)' rescue nil
          extern 'int GetWindowTextW(uintptr_t, void*, int)' rescue nil
          extern 'int SetWindowPos(uintptr_t, uintptr_t, int, int, int, int, uint32_t)' rescue nil
          extern 'int DwmSetWindowAttribute(uintptr_t, uint32_t, void*, uint32_t)' rescue nil
        end

        if Win32.respond_to?(:DwmSetWindowAttribute) && Win32.respond_to?(:FindWindowW)
          @available = true
        end
      rescue => e
        @available = false
      end
    end

    DWMWA_USE_IMMERSIVE_DARK_MODE = 20
    DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1 = 19
    DWMWA_CAPTION_COLOR = 35
    DWMWA_TEXT_COLOR = 36

    SWP_NOSIZE = 0x0001
    SWP_NOMOVE = 0x0002
    SWP_NOZORDER = 0x0004
    SWP_FRAMECHANGED = 0x0020
    SWP_FLAGS = SWP_NOSIZE | SWP_NOMOVE | SWP_NOZORDER | SWP_FRAMECHANGED

    def self.available?
      @available == true
    end

    def self.find_dialog_hwnd(title)
      return nil unless available? && title

      current_pid = Process.pid
      pid_buf = [0].pack('L')

      # 1. Coba FindWindowW dengan judul persis
      begin
        wide_title = (title.to_s + "\0").encode('UTF-16LE')
        hwnd = Win32.FindWindowW(nil, wide_title) rescue 0
        if hwnd && hwnd != 0
          Win32.GetWindowThreadProcessId(hwnd, pid_buf)
          return hwnd if pid_buf.unpack1('L') == current_pid
        end
      rescue
      end

      # 2. Iterasi window milik proses SketchUp
      begin
        hwnd = Win32.GetTopWindow(0) rescue 0
        buf = ("\0" * 512).encode('UTF-16LE')
        target = title.to_s.strip.downcase

        while hwnd && hwnd != 0
          Win32.GetWindowThreadProcessId(hwnd, pid_buf) rescue nil
          if pid_buf.unpack1('L') == current_pid
            len = Win32.GetWindowTextW(hwnd, buf, 255) rescue 0
            if len > 0
              str = buf[0...(len * 2)].force_encoding('UTF-16LE').encode('UTF-8') rescue ""
              str_down = str.strip.downcase
              if str_down.include?(target) || target.include?(str_down)
                return hwnd
              end
            end
          end
          hwnd = Win32.GetWindow(hwnd, 2) rescue 0 # 2 = GW_HWNDNEXT
        end
      rescue
      end

      nil
    end

    def self.apply_dark_mode_to_hwnd(hwnd, is_dark)
      return unless available? && hwnd && hwnd != 0

      val = [is_dark ? 1 : 0].pack('l') # 4-byte BOOL

      # Immersive dark mode (Windows 11 / Windows 10 20H1+)
      Win32.DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, val, 4) rescue nil
      # Fallback untuk Windows 10 versi lama (1809 - 1909)
      Win32.DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1, val, 4) rescue nil

      # Windows 11 custom caption color & text color
      # Warna dark: #141416 -> RGB: 0x14, 0x14, 0x16 -> COLORREF: 0x00161414
      # Warna light: 0xFFFFFFFF (DWMWA_COLOR_DEFAULT) kembalikan ke warna sistem
      bg_color = is_dark ? [0x00161414].pack('L') : [0xFFFFFFFF].pack('L')
      text_color = is_dark ? [0x00FFFFFF].pack('L') : [0xFFFFFFFF].pack('L')

      Win32.DwmSetWindowAttribute(hwnd, DWMWA_CAPTION_COLOR, bg_color, 4) rescue nil
      Win32.DwmSetWindowAttribute(hwnd, DWMWA_TEXT_COLOR, text_color, 4) rescue nil

      # Paksa redraw frame window seketika
      Win32.SetWindowPos(hwnd, 0, 0, 0, 0, 0, SWP_FLAGS) rescue nil
    end

    def self.set_theme(title, is_dark)
      return unless available?

      hwnd = find_dialog_hwnd(title)
      apply_dark_mode_to_hwnd(hwnd, is_dark) if hwnd
    end

    # Hubungkan dialog HtmlDialog dengan pengubah tema title bar
    def self.attach(dialog, title)
      return unless dialog

      # Callback saat tema berubah di Javascript UI
      dialog.add_action_callback("syncTheme") do |_action_context, theme|
        is_dark = (theme.to_s == 'dark')
        Sketchup.write_default("BoosokTools", "theme", theme.to_s)
        set_theme(title, is_dark)
      end

      # Tema yang sedang aktif
      saved_theme = Sketchup.read_default("BoosokTools", "theme", "dark")
      is_dark = (saved_theme == 'dark')

      # Jalankan dengan timer bertahap agar window sudah selesai dibuat oleh OS
      [0.05, 0.15, 0.35].each do |delay|
        UI.start_timer(delay, false) do
          set_theme(title, is_dark)
        end
      end
    end
  end
end
