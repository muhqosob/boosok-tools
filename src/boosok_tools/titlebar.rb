require 'sketchup'

module BoosokTools
  module TitleBar
    IS_WINDOWS = (RUBY_PLATFORM =~ /mswin|mingw|cygwin/) != nil

    module WinAPI
      @ready = false
      @error = nil

      def self.ready?
        @ready
      end

      def self.error
        @error
      end

      if (RUBY_PLATFORM =~ /mswin|mingw|cygwin/) != nil
        begin
          require 'fiddle'
          require 'fiddle/import'

          extend Fiddle::Importer
          dlload 'user32.dll'
          dlload 'dwmapi.dll'

          extern 'uintptr_t FindWindowA(void*, char*)'
          extern 'uintptr_t FindWindowW(void*, void*)'
          extern 'uintptr_t GetTopWindow(uintptr_t)'
          extern 'uintptr_t GetWindow(uintptr_t, uint32_t)'
          extern 'int GetWindowTextA(uintptr_t, char*, int)'
          extern 'int SetWindowPos(uintptr_t, uintptr_t, int, int, int, int, uint32_t)'
          extern 'int DwmSetWindowAttribute(uintptr_t, uint32_t, void*, uint32_t)'

          @ready = true
        rescue => e
          @ready = false
          @error = e.message
        end
      end
    end

    def self.log(msg)
      log_file = File.join(File.dirname(__FILE__), 'titlebar.log')
      File.open(log_file, 'a') { |f| f.puts("[#{Time.now.strftime('%H:%M:%S')}] #{msg}") }
    rescue
    end

    def self.find_hwnd(title)
      return 0 unless WinAPI.ready? && title

      target = title.to_s.strip

      # 1. Coba FindWindowA (ASCII)
      begin
        hwnd = WinAPI.FindWindowA(nil, target)
        if hwnd && hwnd != 0
          log("FindWindowA found hwnd=#{hwnd} for '#{target}'")
          return hwnd
        end
      rescue => e
        log("FindWindowA error: #{e.message}")
      end

      # 2. Coba FindWindowW (UTF-16LE)
      begin
        wide = (target + "\0").encode('UTF-16LE')
        hwnd = WinAPI.FindWindowW(nil, Fiddle::Pointer[wide])
        if hwnd && hwnd != 0
          log("FindWindowW found hwnd=#{hwnd} for '#{target}'")
          return hwnd
        end
      rescue => e
        log("FindWindowW error: #{e.message}")
      end

      # 3. Iterasi seluruh window yang ada di Z-order
      begin
        hwnd = WinAPI.GetTopWindow(0)
        target_down = target.downcase
        buf = "\0" * 256

        while hwnd && hwnd != 0
          len = WinAPI.GetWindowTextA(hwnd, buf, 255) rescue 0
          if len > 0
            str = buf[0...len].strip
            if str.downcase.include?(target_down) || target_down.include?(str.downcase)
              log("GetWindow loop found hwnd=#{hwnd} with title='#{str}' for target='#{target}'")
              return hwnd
            end
          end
          hwnd = WinAPI.GetWindow(hwnd, 2) rescue 0 # 2 = GW_HWNDNEXT
        end
      rescue => e
        log("GetWindow loop error: #{e.message}")
      end

      log("Window not found for '#{target}'")
      0
    end

    def self.apply_dark_mode(hwnd, is_dark)
      return unless WinAPI.ready? && hwnd && hwnd != 0

      val = [is_dark ? 1 : 0].pack('l') # 4-byte BOOL

      # Immersive dark mode (Windows 11 / Windows 10 20H1+)
      r20 = WinAPI.DwmSetWindowAttribute(hwnd, 20, val, 4) rescue -1
      # Fallback Windows 10 build 17763..18363
      r19 = WinAPI.DwmSetWindowAttribute(hwnd, 19, val, 4) rescue -1

      # Windows 11 custom caption color & text color
      bg = is_dark ? [0x00161414].pack('L') : [0xFFFFFFFF].pack('L')
      fg = is_dark ? [0x00FFFFFF].pack('L') : [0xFFFFFFFF].pack('L')
      r35 = WinAPI.DwmSetWindowAttribute(hwnd, 35, bg, 4) rescue -1
      r36 = WinAPI.DwmSetWindowAttribute(hwnd, 36, fg, 4) rescue -1

      # Paksa frame redraw
      WinAPI.SetWindowPos(hwnd, 0, 0, 0, 0, 0, 0x0027) rescue nil

      log("apply_dark_mode hwnd=#{hwnd} is_dark=#{is_dark} (DWM 20=#{r20}, 19=#{r19}, 35=#{r35}, 36=#{r36})")
    end

    def self.set_theme(title, is_dark)
      log("set_theme requested for '#{title}', is_dark=#{is_dark}")
      hwnd = find_hwnd(title)
      if hwnd && hwnd != 0
        apply_dark_mode(hwnd, is_dark)
      end
    end

    def self.attach(dialog, title)
      return unless dialog

      log("attach called for '#{title}', WinAPI.ready?=#{WinAPI.ready?} err=#{WinAPI.error}")

      dialog.add_action_callback("syncTheme") do |_action_context, theme|
        is_dark = (theme.to_s == 'dark')
        Sketchup.write_default("BoosokTools", "theme", theme.to_s)
        set_theme(title, is_dark)
      end

      saved_theme = Sketchup.read_default("BoosokTools", "theme", "dark")
      is_dark = (saved_theme == 'dark')

      # Timer berkala setelah dialog dibuka agar window sudah selesai dibuat OS
      [0.05, 0.15, 0.35, 0.7, 1.2].each do |delay|
        UI.start_timer(delay, false) do
          set_theme(title, is_dark)
        end
      end
    end
  end
end
