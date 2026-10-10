require 'sketchup'

module BoosokTools
  module TitleBar
    @ready = false unless defined?(@ready)
    @init_error = nil unless defined?(@init_error)

    unless defined?(User32)
      begin
        require 'fiddle'

        User32 = Fiddle.dlopen('user32.dll')
        Dwmapi = Fiddle.dlopen('dwmapi.dll')

        FindWindowA = Fiddle::Function.new(
          User32['FindWindowA'],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INTPTR_T
        )

        GetForegroundWindow = Fiddle::Function.new(
          User32['GetForegroundWindow'],
          [],
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
    end

    # GetWindow dipisah dari blok di atas: blok itu tidak dijalankan ulang saat hot-reload (User32 sudah ada).
    unless defined?(GetWindowFn)
      begin
        GetWindowFn = Fiddle::Function.new(
          User32['GetWindow'],
          [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INT],
          Fiddle::TYPE_INTPTR_T
        )
      rescue StandardError, LoadError
        nil
      end
    end

    # SystemParametersInfo / MonitorFromWindow: batas area kerja layar (di luar taskbar) untuk animasi ukuran jendela
    unless defined?(SystemParametersInfoFn)
      begin
        SystemParametersInfoFn = Fiddle::Function.new(
          User32['SystemParametersInfoA'],
          [Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
          Fiddle::TYPE_INT
        )
        MonitorFromWindowFn = Fiddle::Function.new(User32['MonitorFromWindow'], [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INT], Fiddle::TYPE_INTPTR_T)
        GetMonitorInfoFn = Fiddle::Function.new(User32['GetMonitorInfoA'], [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      rescue StandardError, LoadError
        nil
      end
    end

    def self.log(msg)
      log_file = File.join(::BoosokTools::SUPPORT_DIR, 'ruby', 'titlebar.log')
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

    @sketchup_hwnd = nil

    def self.get_sketchup_hwnd
      if @sketchup_hwnd && @sketchup_hwnd != 0
        return @sketchup_hwnd
      end
      if ready? && defined?(GetForegroundWindow)
        fg = GetForegroundWindow.call rescue 0
        if fg && fg != 0
          @sketchup_hwnd = fg
          return @sketchup_hwnd
        end
      end
      0
    end

    def self.get_sketchup_rect
      hwnd = get_sketchup_hwnd
      if (hwnd.nil? || hwnd == 0) && ready? && defined?(GetForegroundWindow)
        hwnd = GetForegroundWindow.call rescue 0
      end
      if hwnd && hwnd != 0 && ready?
        buf = [0, 0, 0, 0].pack('l4')
        if GetWindowRect.call(hwnd, buf) != 0
          left, top, right, bottom = buf.unpack('l4')
          if (right - left) > 300 && (bottom - top) > 200
            return [left, top, right, bottom]
          end
        end
      end
      nil
    rescue => e
      log("get_sketchup_rect error: #{e.message}")
      nil
    end

    # Area gambar (viewport) SketchUp dalam koordinat layar, dicari sebagai child window yang
    # ukurannya sama dengan view.vpwidth x view.vpheight. Return [left, top, right, bottom] atau nil.
    def self.get_viewport_rect
      return nil unless ready? && defined?(GetWindowFn)

      root = get_sketchup_hwnd
      view = Sketchup.active_model && Sketchup.active_model.active_view
      return nil unless root && root != 0 && view

      vw = view.vpwidth
      vh = view.vpheight
      queue = [root]
      seen = 0
      until queue.empty? || seen > 800
        hwnd = queue.shift
        child = GetWindowFn.call(hwnd, 5) # GW_CHILD
        while child && child != 0 && seen <= 800
          seen += 1
          buf = [0, 0, 0, 0].pack('l4')
          if GetWindowRect.call(child, buf) != 0
            left, top, right, bottom = buf.unpack('l4')
            return [left, top, right, bottom] if (right - left - vw).abs <= 2 && (bottom - top - vh).abs <= 2
          end
          queue << child
          child = GetWindowFn.call(child, 2) # GW_HWNDNEXT
        end
      end
      nil
    rescue => e
      log("get_viewport_rect error: #{e.message}")
      nil
    end

    # Pojok kiri atas area gambar (+ sedikit jarak). Kalau viewport tidak ketemu: pojok kiri atas
    # jendela SketchUp digeser melewati menu/toolbar; kalau itu pun gagal: tengah jendela.
    def self.get_viewport_corner_pos(dialog_width = 380, dialog_height = 480)
      margin = 16
      vp = get_viewport_rect
      return [vp[0] + margin, vp[1] + margin] if vp

      rect = get_sketchup_rect
      return [rect[0] + margin, rect[1] + 140] if rect

      get_sketchup_center_pos(dialog_width, dialog_height)
    end

    def self.get_sketchup_center_pos(dialog_width = 380, dialog_height = 480)
      rect = get_sketchup_rect
      if rect
        s_left, s_top, s_right, s_bottom = rect
        s_w = s_right - s_left
        s_h = s_bottom - s_top
        cx = s_left + [(s_w - dialog_width) / 2, 20].max
        cy = s_top + [(s_h - dialog_height) / 2, 40].max
        return [cx.to_i, cy.to_i]
      end
      [360, 180]
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

      # Repaint frame (SWP_NOSIZE|SWP_NOMOVE|SWP_NOZORDER|SWP_FRAMECHANGED).
      # Tidak pakai SendMessage(WM_NCACTIVATE): sinkron & memaksa repaint ganda.
      SetWindowPos.call(hwnd, 0, 0, 0, 0, 0, 0x0027) rescue nil
    end

    # Tema hanya diterapkan kalau jendela/temanya berubah. Sebelumnya dijalankan di
    # setiap load halaman (syncTheme) + 5 timer → repaint frame berulang tiap pindah menu.
    def self.set_theme(title, is_dark)
      return unless ready?
      hwnd = find_hwnd(title)
      return if hwnd == 0
      return if @applied_theme == [hwnd, is_dark]
      apply_dark_titlebar(hwnd, is_dark)
      @applied_theme = [hwnd, is_dark]
    end

    SLIDE_SECONDS = 0.22 unless defined?(SLIDE_SECONDS)

    # [left, top, right, bottom] jendela dialog (koordinat layar yang sama dengan SetWindowPos).
    def self.get_window_rect(title)
      return nil unless ready?
      hwnd = find_hwnd(title)
      return nil if hwnd == 0

      buf = [0, 0, 0, 0].pack('l4')
      GetWindowRect.call(hwnd, buf) != 0 ? buf.unpack('l4') : nil
    rescue => e
      log("get_window_rect error: #{e.message}")
      nil
    end

    HEIGHT_SECONDS = 0.16 unless defined?(HEIGHT_SECONDS)

    # Tinggi dialog berubah halus (ease-out) dari tinggi saat ini ke target; sisi atas jendela tetap.
    # Lebar diambil dari @dialog_width, jadi aman berjalan bersamaan dengan animasi lebar (apply_width).
    def self.animate_height(dialog, target)
      UI.stop_timer(@height_timer) if @height_timer
      @height_timer = nil
      from = @cur_h
      if from.nil? || (from - target).abs < 6
        @cur_h = target
        dialog.set_size(@dialog_width || 380, target)
        return
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      step = lambda do
        k = [(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) / HEIGHT_SECONDS, 1.0].min
        e = 1 - ((1 - k)**3) # easeOutCubic
        @cur_h = (from + ((target - from) * e)).round
        dialog.set_size(@dialog_width || 380, @cur_h)
        if k >= 1.0 || !dialog.visible?
          UI.stop_timer(@height_timer) if @height_timer
          @height_timer = nil
        end
      end
      step.call
      @height_timer = UI.start_timer(0.016, true) { step.call } if @height_timer.nil? && @cur_h != target
    end

    # Area kerja (di luar taskbar) monitor tempat jendela berada: [left, top, right, bottom] atau nil
    def self.work_area_for(title)
      hwnd = find_hwnd(title)
      if hwnd != 0 && defined?(MonitorFromWindowFn)
        mon = MonitorFromWindowFn.call(hwnd, 2) # MONITOR_DEFAULTTONEAREST
        if mon != 0
          buf = [40].pack('l') + ([0] * 9).pack('l9') # MONITORINFO: cbSize, rcMonitor, rcWork, dwFlags
          return buf.unpack('l10')[5, 4] if GetMonitorInfoFn.call(mon, buf) != 0
        end
      end
      return nil unless defined?(SystemParametersInfoFn)

      buf = [0, 0, 0, 0].pack('l4')
      SystemParametersInfoFn.call(0x0030, 0, buf, 0) != 0 ? buf.unpack('l4') : nil # SPI_GETWORKAREA
    rescue StandardError => e
      log("work_area_for error: #{e.message}")
      nil
    end

    BOX_SECONDS = 0.3 unless defined?(BOX_SECONDS)
    BOX_DEFAULT_H = 440 unless defined?(BOX_DEFAULT_H)

    # Lebar + (opsional) tinggi tetap untuk halaman tujuan. height nil = tinggi mengikuti isi halaman (autoFitHeight).
    # Ke tool bertinggi tetap (RAB) dan kembali: jendela tumbuh/menyusut ke semua arah dari titik tengahnya, jadi Hub
    # berada di tengah jendela RAB, dan tidak pernah melewati area kerja layar (taskbar tidak tertutup).
    def self.apply_size(dialog, width, height = nil)
      return unless dialog

      if height
        @fixed_h = height
        box_resize(dialog, width, height, true)
      elsif @in_fixed
        @fixed_h = nil
        box_resize(dialog, width, nil, false)
      else
        @fixed_h = nil
        apply_width(dialog, width)
      end
    end

    # Animasi lebar + tinggi + posisi sekaligus (ease in-out) ke jendela selebar width x height di sekitar titik tengah.
    # entering: true = masuk ke tool bertinggi tetap (titik tengah Hub diingat), false = kembali (ke titik tengah yang diingat
    # kalau jendela belum dipindah user).
    def self.box_resize(dialog, width, height, entering)
      [@slide_timer, @height_timer, @box_timer].each { |t| UI.stop_timer(t) if t }
      @slide_timer = @height_timer = @box_timer = nil
      @pending_fit = nil

      rect = @dialog_title && get_window_rect(@dialog_title)
      from_w = @dialog_width || width
      from_h = @cur_h || @fit_h || BOX_DEFAULT_H
      unless rect
        @in_fixed = entering
        @target_width = width
        @dialog_width = width
        @cur_h = height || from_h
        dialog.set_size(width, @cur_h)
        return
      end

      extra_w = (rect[2] - rect[0]) - from_w # bingkai/bayangan jendela di luar ukuran isi
      extra_h = (rect[3] - rect[1]) - from_h
      cx = rect[0] + ((rect[2] - rect[0]) / 2.0)
      cy = rect[1] + ((rect[3] - rect[1]) / 2.0)
      pb = @prev_box
      if entering
        @prev_box = { left: rect[0], top: rect[1], h: from_h } unless @in_fixed
      else
        @prev_box = nil
      end
      to_w = width
      to_h = height || (pb && pb[:h]) || BOX_DEFAULT_H

      wa = work_area_for(@dialog_title)
      if wa
        to_w = [to_w, (wa[2] - wa[0]) - extra_w].min
        to_h = [to_h, (wa[3] - wa[1]) - extra_h].min
      end
      ow = to_w + extra_w
      oh = to_h + extra_h
      left = (cx - (ow / 2.0)).round
      top = (cy - (oh / 2.0)).round
      if wa
        left = [[left, wa[2] - ow].min, wa[0]].max
        top = [[top, wa[3] - oh].min, wa[1]].max
      end
      # Kembali: Hub persis di posisi terakhirnya sebelum tool lebar dibuka (juga kalau jendela tool sempat digeser)
      left, top = pb[:left], pb[:top] if !entering && pb

      @target_width = to_w
      @last_h = to_h
      @fit_h = to_h
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      done = false

      step = lambda do
        k = [(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) / BOX_SECONDS, 1.0].min
        e = k < 0.5 ? 4 * k * k * k : 1 - ((-2 * k + 2)**3) / 2 # easeInOutCubic
        @dialog_width = (from_w + ((to_w - from_w) * e)).round
        @cur_h = (from_h + ((to_h - from_h) * e)).round
        dialog.set_size(@dialog_width, @cur_h)
        x = (rect[0] + ((left - rect[0]) * e)).round
        y = (rect[1] + ((top - rect[1]) * e)).round
        # Ukuran luar sebenarnya diukur ulang (satuan set_size bisa beda dengan piksel layar), jadi jendela tidak
        # pernah melewati area kerja walau perhitungan di atas meleset
        if wa && entering && (cur = get_window_rect(@dialog_title))
          x = [[x, wa[2] - (cur[2] - cur[0])].min, wa[0]].max
          y = [[y, wa[3] - (cur[3] - cur[1])].min, wa[1]].max
        end
        set_window_pos(@dialog_title, x, y)
        if k >= 1.0 || !dialog.visible?
          UI.stop_timer(@box_timer) if @box_timer
          @box_timer = nil
          fit_into_work_area(dialog, wa) if wa && entering && dialog.visible?
          @in_fixed = entering
          @slide_left = nil # apply_width menghitung ulang titik tengahnya dari posisi sekarang
          if @pending_fit && !entering && dialog.visible?
            h = @pending_fit
            @pending_fit = nil
            @last_h = h
            @fit_h = h
            animate_height(dialog, h)
          end
          done = true
        end
      end

      step.call
      @box_timer = UI.start_timer(0.016, true) { step.call } unless done
    end

    # Pastikan ukuran luar jendela yang sebenarnya muat di area kerja: kalau melebihi, isi dikecilkan (dua kali
    # percobaan), lalu posisinya digeser masuk. Dipanggil di akhir animasi.
    def self.fit_into_work_area(dialog, wa)
      2.times do
        r = get_window_rect(@dialog_title)
        break unless r

        ow = r[2] - r[0]
        oh = r[3] - r[1]
        over_w = ow - (wa[2] - wa[0])
        over_h = oh - (wa[3] - wa[1])
        break if over_w <= 0 && over_h <= 0

        scale = @dialog_width.to_i > 0 ? [[ow.to_f / @dialog_width, 1.0].max, 3.0].min : 1.0
        @dialog_width = [@dialog_width - (over_w > 0 ? (over_w / scale).ceil : 0), 200].max
        @cur_h = [@cur_h - (over_h > 0 ? (over_h / scale).ceil : 0), 200].max
        dialog.set_size(@dialog_width, @cur_h)
      end
      r = get_window_rect(@dialog_title)
      return unless r

      x = [[r[0], wa[2] - (r[2] - r[0])].min, wa[0]].max
      y = [[r[1], wa[3] - (r[3] - r[1])].min, wa[1]].max
      set_window_pos(@dialog_title, x, y) if x != r[0] || y != r[1]
      @target_width = @dialog_width
      @last_h = @cur_h
      @fit_h = @cur_h
    end

    # Lebar jendela aktif. Default 380; tool lebar (mis. Purge) mengubahnya lewat apply_width.
    # Lebar dianimasikan (ease in-out) dan sisi kirinya digeser setengah selisih lebar, jadi jendela
    # melebar/menyempit ke kiri-kanan sama rata. Titik tengah (anchor) disimpan supaya bolak-balik
    # Hub <-> tool lebar tidak membuat posisi bergeser; anchor dihitung ulang kalau user memindahkan jendela.
    def self.apply_width(dialog, width)
      width = width.to_i
      return unless dialog && width > 0
      return if @box_timer # jendela sedang berganti ukuran (apply_size)
      return if @target_width == width

      @target_width = width
      UI.stop_timer(@slide_timer) if @slide_timer
      @slide_timer = nil
      @last_h = nil # paksa set_dialog_height berikutnya menerapkan ukuran baru
      from = @dialog_width || width
      rect = @dialog_title && get_window_rect(@dialog_title)
      unless rect
        @dialog_width = width
        dialog.set_size(width, @cur_h || @fit_h || 480)
        return
      end

      if @slide_left.nil? || (rect[0] - @slide_left).abs > 3
        @frame_extra = (rect[2] - rect[0]) - from # bingkai/bayangan jendela di luar lebar konten
        @anchor_cx = rect[0] + ((rect[2] - rect[0]) / 2.0)
      end
      top = rect[1]
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      step = lambda do
        k = [(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) / SLIDE_SECONDS, 1.0].min
        e = k < 0.5 ? 4 * k * k * k : 1 - ((-2 * k + 2)**3) / 2 # easeInOutCubic
        w = (from + ((width - from) * e)).round
        @dialog_width = w
        dialog.set_size(w, @cur_h || @fit_h || 480)
        left = (@anchor_cx - ((w + @frame_extra) / 2.0)).round
        sk = get_sketchup_rect
        left = [left, sk[0]].max if sk # jangan keluar dari sisi kiri jendela SketchUp
        set_window_pos(@dialog_title, left, top)
        @slide_left = left
        if k >= 1.0 || !dialog.visible?
          UI.stop_timer(@slide_timer) if @slide_timer
          @slide_timer = nil
        end
      end

      step.call
      @slide_timer = UI.start_timer(0.016, true) { step.call } if @slide_timer.nil? && @dialog_width != width
    end

    def self.attach(dialog, title, width: nil, height: nil)
      return unless dialog
      @fixed_h = height
      @in_fixed = !height.nil?
      @prev_box = nil
      @pending_fit = nil
      UI.stop_timer(@box_timer) if @box_timer
      @box_timer = nil
      @applied_theme = nil
      @dialog_width = width ? width.to_i : 380
      @target_width = @dialog_width
      UI.stop_timer(@slide_timer) if @slide_timer
      @slide_timer = nil
      @slide_left = nil
      @dialog_title = title
      @last_h = nil
      @fit_h = nil
      @cur_h = height
      UI.stop_timer(@height_timer) if @height_timer
      @height_timer = nil

      dialog.add_action_callback("syncTheme") do |_ctx, theme|
        is_dark = (theme.to_s == 'dark')
        if @saved_theme != theme.to_s
          Sketchup.write_default("BoosokTools", "theme", theme.to_s)
          @saved_theme = theme.to_s
        end
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
        HideOnSceneManager.detach_all_observers rescue nil if defined?(HideOnSceneManager)
        Sketchup.require 'boosok_tools/hub' unless defined?(BoosokTools::Hub)
        BoosokTools::Hub.back_to_hub
      end

      ['closeDialog', 'close_dialog', 'close'].each do |cb|
        dialog.add_action_callback(cb) { dialog.close }
      end

      dialog.add_action_callback("set_dialog_height") do |_ctx, height|
        next if @fixed_h # tool dengan tinggi tetap (mis. RAB): tinggi tidak mengikuti isi

        h = height.to_i
        # Jendela sedang berganti ukuran (kembali dari RAB): tinggi pas-isi diterapkan setelah gerakannya selesai
        if @box_timer
          @pending_fit = h if h > 200 && h < 1200
          next
        end
        # set_size = resize jendela native + relayout; lewati kalau tingginya tidak berubah
        if h > 200 && h < 1200 && (@last_h.nil? || (h - @last_h).abs >= 4)
          @last_h = h
          @fit_h = h
          animate_height(dialog, h)
        end
      end

      saved = Sketchup.read_default("BoosokTools", "theme", "light")
      is_dark = (saved.to_s == 'dark')

      [0.3, 0.6, 1.0, 1.5, 2.5].each do |delay|
        UI.start_timer(delay, false) { set_theme(title, is_dark) }
      end
    end
  end

  @dialog ||= nil

  def self.dialog
    @dialog
  end

  def self.dialog=(d)
    @dialog = d
  end

  @dialog_pos ||= nil
  @session_position_saved ||= false

  def self.save_position(x, y)
    left = x.to_i
    top = y.to_i
    if left > 5 && top > 5
      @dialog_pos = [left, top]
      @session_position_saved = true
      Sketchup.write_default("BoosokTools", "dialog_left", left)
      Sketchup.write_default("BoosokTools", "dialog_top", top)
    end
  end

  def self.get_position(width = 380, height = 480)
    # Jika user sudah pernah menggeser posisi dialog dalam sesi kerja ini, pakai posisi tersebut
    if @dialog_pos && @session_position_saved
      return @dialog_pos
    end

    # Pembukaan pertama di sesi SketchUp ini: pojok kiri atas area gambar (viewport) model kerja
    start_pos = TitleBar.get_viewport_corner_pos(width, height)
    @dialog_pos = start_pos
    start_pos
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
  @session_id ||= "#{Time.now.to_i}_#{rand(1000..9999)}"

  def self.hub_booted?
    @hub_booted == true
  end

  def self.set_hub_booted(val = true)
    @hub_booted = val
  end

  def self.session_id
    @session_id ||= "#{Time.now.to_i}_#{rand(1000..9999)}"
  end

  def self.init_session_file
    @session_id = "#{Time.now.to_i}_#{rand(1000..9999)}"
    @hub_booted = false
    js_dir = File.join(::BoosokTools::SUPPORT_DIR, 'js')
    Dir.mkdir(js_dir) unless File.directory?(js_dir)
    session_file = File.join(js_dir, 'session.js')
    File.write(session_file, "window.BOOSOK_SESSION_ID = #{@session_id.to_json};\n")
  rescue => e
    puts "[Boosok Tools] init_session_file error: #{e.message}"
  end
end
