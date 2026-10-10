require 'sketchup'

module BoosokTools
  # Mode developer: perubahan file di folder plugin langsung ter-reload tanpa restart SketchUp.
  #
  # Aktif HANYA kalau ada file penanda `.dev_mode` di folder plugin (dibuat oleh
  # sync_to_sketchup.ps1). User biasa tidak punya file itu, jadi modul ini tidak jalan.
  #
  #  - File .rb berubah         → semua modul di-reload, dialog dibuka ulang di tool yang sama
  #  - .html/.js/.css/.json     → halaman dialog yang terbuka di-refresh saja
  #  - Menu: Extensions > Boosok Tools > Reload Plugin (Dev)  untuk reload manual
  module Dev
    ROOT       = ::BoosokTools::SUPPORT_DIR unless defined?(ROOT)
    MARKER     = File.join(::BoosokTools::SUPPORT_DIR, '.dev_mode') unless defined?(MARKER)
    WATCH_EXT  = %w[.rb .html .js .css .json].freeze unless defined?(WATCH_EXT)
    # File yang ditulis plugin saat berjalan: jangan dianggap perubahan (hindari reload berulang)
    IGNORE     = %w[session.js strings.js].freeze unless defined?(IGNORE)
    SKIP_RELOAD = %w[bootstrap.rb dev_reload.rb].freeze unless defined?(SKIP_RELOAD)
    # Urutan penting: pondasi dulu, baru yang bergantung padanya
    CORE_ORDER = %w[ruby/titlebar.rb ruby/locale.rb updater.rb license.rb flags.rb hub.rb].freeze unless defined?(CORE_ORDER)
    INTERVAL   = 1.0 unless defined?(INTERVAL)

    @timer    = nil
    @baseline = nil
    @prev     = nil

    def self.enabled?
      File.exist?(MARKER)
    end

    def self.start
      return unless enabled?
      stop
      @baseline = @prev = snapshot
      @timer = UI.start_timer(INTERVAL, true) { tick }
      puts "[Boosok Dev] Auto-reload aktif (#{@baseline.size} file dipantau)"
    end

    def self.stop
      UI.stop_timer(@timer) if @timer
      @timer = nil
    end

    # { path => [mtime, size] } untuk semua file yang relevan
    def self.snapshot
      snap = {}
      Dir.glob(File.join(ROOT, '**', '*')).each do |f|
        next unless File.file?(f)
        next unless WATCH_EXT.include?(File.extname(f).downcase)
        next if IGNORE.include?(File.basename(f))
        st = File.stat(f)
        snap[f] = [st.mtime.to_f, st.size]
      end
      snap
    rescue
      {}
    end

    def self.changed_files(old, new)
      ((old.keys | new.keys).select { |f| old[f] != new[f] })
    end

    # Dipanggil tiap detik. Reload baru dijalankan kalau perubahan sudah "tenang" selama
    # satu tick (sync menyalin banyak file berurutan, jangan reload di tengah-tengah).
    def self.tick
      snap = snapshot
      if snap != @baseline && snap == @prev
        files = changed_files(@baseline, snap)
        @baseline = snap
        apply(files)
      end
      @prev = snap
    rescue Exception => e
      puts "[Boosok Dev] tick error: #{e.class}: #{e.message}"
    end

    def self.apply(files)
      names = files.map { |f| f.sub(ROOT + '/', '') }
      puts "[Boosok Dev] Berubah: #{names.first(6).join(', ')}#{names.size > 6 ? " (+#{names.size - 6})" : ''}"
      # File bahasa (locales/*.json) berubah → bangun ulang js/strings.js sebelum halaman dimuat ulang
      if files.any? { |f| File.extname(f) == '.json' } && defined?(BoosokTools::Locale)
        BoosokTools::Locale.all_locales(true)
        BoosokTools::Locale.export_js
      end
      if files.any? { |f| File.extname(f) == '.rb' }
        reload_all
      else
        refresh_dialog
      end
    end

    # Perubahan UI saja: muat ulang halaman yang sedang terbuka
    def self.refresh_dialog
      dlg = BoosokTools.dialog
      return unless dlg && dlg.visible?
      dlg.execute_script('location.reload();')
      puts '[Boosok Dev] Halaman dialog di-refresh'
    end

    def self.reload_all
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      hub = (BoosokTools::Hub if defined?(BoosokTools::Hub))
      prev_tool = hub ? hub.current_tool : 'hub'
      was_open  = BoosokTools.dialog && BoosokTools.dialog.visible?

      teardown

      old_verbose = $VERBOSE
      $VERBOSE = nil # konstanta di-assign ulang saat reload; peringatan itu tidak berguna di sini
      errors = []
      count = 0
      ordered_files.each do |path|
        begin
          load path
          count += 1
        rescue Exception => e
          errors << "#{File.basename(path)}: #{e.class}: #{e.message.lines.first.to_s.strip}"
        end
      end
      $VERBOSE = old_verbose

      reset_caches
      BoosokTools::Hub.preload_tools if defined?(BoosokTools::Hub)

      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
      if errors.empty?
        puts "[Boosok Dev] Reload selesai: #{count} file, #{ms} ms"
      else
        puts "[Boosok Dev] Reload selesai dengan #{errors.size} ERROR:"
        errors.each { |e| puts "  - #{e}" }
      end

      reopen(prev_tool) if was_open
    rescue Exception => e
      $VERBOSE = old_verbose if defined?(old_verbose)
      puts "[Boosok Dev] Reload GAGAL: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    end

    # Matikan semua timer/observer/tool lama sebelum definisi diganti
    def self.teardown
      begin
        model = Sketchup.active_model
        model.select_tool(nil) if model
      rescue
      end
      if defined?(BoosokTools::Hub)
        BoosokTools::Hub::TOOL_PAGES.each_key { |id| BoosokTools::Hub.deactivate_tool(id) }
        BoosokTools::Hub.instance_variable_set(:@preloaded, {})
      end
      dlg = BoosokTools.dialog
      if dlg
        dlg.close rescue nil
        BoosokTools.dialog = nil
      end
    end

    def self.ordered_files
      all = Dir.glob(File.join(ROOT, '**', '*.rb')).sort
      all.reject! { |f| SKIP_RELOAD.include?(File.basename(f)) }
      core = CORE_ORDER.map { |n| File.join(ROOT, n) }.select { |f| all.include?(f) }
      # select_tool.rb memuat folder select_tool/ sendiri → jangan dimuat dobel.
      # File tool lain (selector.rb, replacer.rb, ...) dimuat oleh Hub.preload_tools setelah ini.
      sel = all.select { |f| File.basename(f) == 'select_tool.rb' }
      core + sel
    end

    def self.reset_caches
      BoosokTools::License.clear_cache! if defined?(BoosokTools::License)
      if defined?(BoosokTools::Locale)
        %i[@cached_locales @cache_sig @lang_cache @checked_at @exported_sig].each { |iv| BoosokTools::Locale.instance_variable_set(iv, nil) }
        BoosokTools::Locale.export_js
      end
    end

    # Buka dialog lagi di tool yang sama setelah reload
    def self.reopen(tool)
      UI.start_timer(0.4, false) do
        begin
          if tool.to_s == 'hub' || tool.nil?
            BoosokTools::Hub.show
          else
            BoosokTools::Hub.open_or_show(tool)
          end
        rescue Exception => e
          puts "[Boosok Dev] Gagal membuka ulang dialog: #{e.message}"
        end
      end
    end
  end
end
