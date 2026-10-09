require 'sketchup'
require 'json'
require 'tmpdir'
Sketchup.require 'boosok_tools/ruby/titlebar'

module BoosokTools
  # Update di dalam SketchUp: cek -> download .rbz -> install -> hot reload langsung aktif.
  # Satu state di Ruby, dialog cuma render state itu (render(state) di update.html).
  #
  # status: idle | checking | latest | available | downloading | installing | done | error
  module Updater
    CHECK_TIMEOUT = 15     # detik
    DOWNLOAD_TIMEOUT = 180 # detik
    MAX_REDIRECTS = 5      # link release GitHub redirect ke CDN

    # true: kalau server update tidak bisa dihubungi, cek versi / unduhan jatuh ke GitHub (masa transisi, saat rilis
    # masih juga dipublikasikan di GitHub). Ubah ke false setelah update sepenuhnya dari server (repo dijadikan privat).
    GITHUB_FALLBACK = true

    NOT_LICENSED_MSG = 'Update hanya untuk pengguna berlisensi aktif. Aktifkan lisensi (key dari server) di menu Tentang.'

    @state ||= { status: 'idle' }

    # Cek versi: server lisensi dulu (/update/latest, bentuk sama dengan version.json), lalu GitHub bila gagal.
    def self.fetch_version(loud, &on_version)
      github = lambda do
        fetch(VERSION_API_URL, CHECK_TIMEOUT, loud,
              headers: { 'Accept' => 'application/vnd.github.raw' },
              on_fail: ->(_e) { fetch(VERSION_URL, CHECK_TIMEOUT, loud, &on_version) },
              &on_version)
      end
      if BoosokTools::License.online_configured?
        fetch("#{BoosokTools::License::SERVER_URL}/update/latest", CHECK_TIMEOUT, loud,
              on_fail: ->(e) { GITHUB_FALLBACK ? github.call : (loud ? fail_with(e.message) : set(status: 'idle')) },
              &on_version)
      else
        github.call
      end
    end

    # Header unduhan: unduhan dari server butuh lisensi online aktif; sumber lain (GitHub) tanpa header.
    # Hasil: Hash header, atau :denied bila tidak berhak.
    def self.download_headers(url)
      return {} unless BoosokTools::License.online_configured? && url.to_s.start_with?(BoosokTools::License::SERVER_URL)

      BoosokTools::License.update_headers || :denied
    end

    def self.http_error(code, body)
      err = (JSON.parse(body.to_s)['error'] rescue nil)
      case err
      when 'not_bound', 'revoked', 'invalid_key' then NOT_LICENSED_MSG
      when 'no_release' then 'File update belum tersedia di server.'
      else "HTTP #{code}"
      end
    end

    # manual = dari menu. Cek otomatis saat startup diam saja kecuali ada update.
    def self.check(manual = false)
      show_dialog if manual
      return if busy? || (@state[:status] == 'done' && !manual)

      set(status: 'checking', error: nil, progress: nil)
      on_version = lambda do |body|
        data = JSON.parse(body)
        if Gem::Version.new(data["version"]) > Gem::Version.new(PLUGIN_VERSION)
          set(status: 'available', latest: data["version"],
              changelog: data["changelog"].to_s,
              download_url: data["download_url"],
              expected_sha256: data["sha256"].to_s)
          show_dialog
        else
          set(status: 'latest')
        end
      end
      fetch_version(manual, &on_version)
    end

    def self.download
      return unless @state[:status] == 'available'

      headers = download_headers(@state[:download_url])
      return fail_with(NOT_LICENSED_MSG) if headers == :denied

      set(status: 'downloading', progress: 0)
      expected_sha256 = @state[:expected_sha256].to_s
      fetch(@state[:download_url], DOWNLOAD_TIMEOUT, true, headers: headers) do |body|
        set(status: 'installing', progress: nil)
        # Guard: tolak file kosong atau partial download
        if body.nil? || body.empty?
          fail_with("Download gagal: file kosong.")
          next
        end
        # Verifikasi integritas SHA256 jika checksum tersedia di version.json
        unless expected_sha256.empty?
          require 'digest'
          actual_sha256 = Digest::SHA256.hexdigest(body)
          unless actual_sha256 == expected_sha256
            fail_with("Verifikasi gagal: checksum tidak cocok. File mungkin rusak atau dimanipulasi.")
            next
          end
        end
        path = File.join(Dir.tmpdir, "boosok_tools_v#{@state[:latest]}.rbz")
        File.binwrite(path, body)
        UI.start_timer(0.1, false) { install(path) }
      end
    end

    # ── Inline variants: push ke hub dialog, bukan buka window terpisah ──

    def self.check_inline(hub_dlg)
      @hub_dlg = hub_dlg
      return if busy?

      push_to_hub({ status: 'checking', current: PLUGIN_VERSION })
      on_version = lambda do |body|
        data = JSON.parse(body)
        if Gem::Version.new(data['version']) > Gem::Version.new(PLUGIN_VERSION)
          st = { status: 'available', current: PLUGIN_VERSION,
                 latest: data['version'], changelog: data['changelog'].to_s,
                 download_url: data['download_url'],
                 expected_sha256: data['sha256'].to_s }
          @state = @state.merge(st.transform_keys(&:to_sym))
          push_to_hub(st)
        else
          push_to_hub({ status: 'latest', current: PLUGIN_VERSION })
          @state = @state.merge(status: 'latest')
        end
      end
      fetch_version(false, &on_version)
    rescue => e
      push_to_hub({ status: 'error', current: PLUGIN_VERSION, error: e.message })
    end

    def self.download_inline(hub_dlg)
      @hub_dlg = hub_dlg
      return unless @state[:status] == 'available'

      headers = download_headers(@state[:download_url])
      if headers == :denied
        push_to_hub({ status: 'error', current: PLUGIN_VERSION, error: NOT_LICENSED_MSG })
        return
      end

      @state = @state.merge(status: 'downloading', progress: 0)
      push_to_hub({ status: 'downloading', current: PLUGIN_VERSION, progress: 0 })
      expected_sha256 = @state[:expected_sha256].to_s

      fetch(@state[:download_url], DOWNLOAD_TIMEOUT, false, headers: headers) do |body|
        @state = @state.merge(status: 'installing', progress: nil)
        # Guard: tolak file kosong atau partial download
        if body.nil? || body.empty?
          push_to_hub({ status: 'error', current: PLUGIN_VERSION, error: "Download gagal: file kosong." })
          next
        end
        # Verifikasi integritas SHA256 jika checksum tersedia di version.json
        unless expected_sha256.empty?
          require 'digest'
          actual_sha256 = Digest::SHA256.hexdigest(body)
          unless actual_sha256 == expected_sha256
            push_to_hub({ status: 'error', current: PLUGIN_VERSION,
                          error: "Verifikasi gagal: checksum tidak cocok. File mungkin rusak atau dimanipulasi." })
            next
          end
        end
        push_to_hub({ status: 'installing', current: PLUGIN_VERSION })
        path = File.join(Dir.tmpdir, "boosok_tools_v#{@state[:latest]}.rbz")
        File.binwrite(path, body)
        UI.start_timer(0.1, false) do
          install_inline(path)
        end
      end
    rescue StandardError => e
      push_to_hub({ status: 'error', current: PLUGIN_VERSION, error: e.message })
    end

    def self.install_inline(path)
      begin
        Sketchup.install_from_archive(path, false)
      rescue ArgumentError
        Sketchup.install_from_archive(path)
      end
      restart = !reload_plugin
      @state = @state.merge(status: 'done', restart: restart)
      push_to_hub({ status: 'done', current: PLUGIN_VERSION, restart: restart })
    rescue StandardError => e
      push_to_hub({ status: 'error', current: PLUGIN_VERSION, error: "Gagal memasang: #{e.message}" })
    ensure
      File.delete(path) rescue nil
    end

    def self.push_to_hub(st)
      dlg = @hub_dlg || (defined?(BoosokTools::Hub) ? BoosokTools.dialog : nil)
      return unless dlg && dlg.visible?
      # Inject progress callback untuk download
      if st[:status] == 'downloading' && @request&.respond_to?(:set_download_progress_callback)
        @request.set_download_progress_callback do |cur, total|
          next unless total.to_i > 0
          pct = (cur * 100 / total).to_i
          push_to_hub({ status: 'downloading', current: PLUGIN_VERSION, progress: pct })
        end
      end
      dlg.execute_script("if(typeof renderUpdate==='function')renderUpdate(#{st.to_json});")
    rescue => e
      puts "[Boosok Tools] push_to_hub error: #{e.message}"
    end

    def self.install(path)
      begin
        Sketchup.install_from_archive(path, false)
      rescue ArgumentError
        Sketchup.install_from_archive(path) # SketchUp lama: tanpa argumen show_messages
      end

      # Muat ulang semua modul plugin ke memori agar langsung aktif tanpa restart
      restart = !reload_plugin

      set(status: 'done', restart: restart)
    rescue StandardError => e # StandardError: cukup untuk handle kegagalan install biasa
      fail_with("Gagal memasang: #{e.message}")
    ensure
      File.delete(path) rescue nil
    end

    # Return true kalau modul sudah di-load ulang (aktif tanpa restart), false kalau perlu restart.
    def self.reload_plugin
      base_dir = ::BoosokTools::SUPPORT_DIR
      # Paket terenkripsi (.rbe) tidak punya file .rb: Sketchup.require cuma memuat sekali per
      # sesi, jadi kode baru baru dipakai setelah SketchUp di-restart.
      return false unless File.exist?(File.join(base_dir, 'ruby', 'bootstrap.rb'))

      old_verbose = $VERBOSE
      $VERBOSE = nil
      begin

        # Muat ulang loader utama (memperbarui PLUGIN_VERSION dan konstanta lainnya)
        loader_file = File.expand_path('../boosok_tools.rb', base_dir)
        load loader_file if File.exist?(loader_file)

        # Muat ulang semua file modul plugin
        ruby_files = [
          'ruby/titlebar.rb',
          'ruby/locale.rb',
          'ruby/bootstrap.rb',
          'ruby/paid/select_tool.rb',
          'ruby/free/selector.rb',
          'ruby/free/replacer.rb',
          'ruby/free/cleangroup.rb',
          'ruby/free/reset.rb',
          'ruby/paid/hideon_scene.rb',
          'ruby/free/untagnpaint.rb',
          'ruby/free/purge.rb',
          'ruby/paid/void.rb',
          'ruby/paid/slice.rb',
          'ruby/paid/trowel.rb',
          'ruby/paid/rab.rb',
          'updater.rb',
          'hub.rb'
        ]

        # Muat ulang semua handler Select Tool
        select_tool_dir = File.join(base_dir, 'ruby', 'paid', 'select_tool')
        if File.directory?(select_tool_dir)
          Dir[File.join(select_tool_dir, '*.rb')].sort.each do |f|
            load f
          end
        end

        ruby_files.each do |f|
          file_path = File.join(base_dir, f)
          load file_path if File.exist?(file_path)
        end

        if defined?(Sketchup.extensions) && Sketchup.extensions['Boosok Tools']
          Sketchup.extensions['Boosok Tools'].version = PLUGIN_VERSION
        end
        true
      rescue => e
        puts "[Boosok Tools] Gagal reload plugin: #{e.message}"
        false
      ensure
        $VERBOSE = old_verbose
      end
    end

    # --- internal ---

    def self.busy?
      %w[checking downloading installing].include?(@state[:status])
    end

    def self.set(patch)
      @state = @state.merge(patch)
      push
    end

    def self.fail_with(msg)
      set(status: 'error', error: msg, progress: nil)
    end

    def self.push
      return unless @dialog && @dialog.visible?
      @dialog.execute_script("render(#{@state.merge(current: PLUGIN_VERSION).to_json})")
    end

    # Pakai Sketchup::Http (bukan Net::HTTP di Thread): thread Ruby di SketchUp
    # berhenti jalan saat idle. Redirect diikuti manual. Error cuma ditampilkan kalau loud.
    # on_fail: ganti penanganan error default (mis. untuk fallback ke URL lain)
    def self.fetch(url, timeout, loud, headers: {}, on_fail: nil, hops: 0, &on_ok)
      done = false
      finish = lambda do |msg = nil, &blk|
        next if done
        done = true
        begin
          blk ? blk.call : raise(msg)
        rescue => e
          if on_fail then on_fail.call(e)
          elsif loud then fail_with(e.message)
          else set(status: 'idle')
          end
        end
      end

      # Simpan referensi, kalau tidak request bisa kena GC dan callback tidak pernah jalan
      @request = req = Sketchup::Http::Request.new(url, Sketchup::Http::GET)
      req.headers = { 'User-Agent' => 'BoosokTools-SketchupExtension' }.merge(headers)
      if req.respond_to?(:set_download_progress_callback)
        req.set_download_progress_callback do |cur, total|
          set(progress: cur * 100 / total) if @state[:status] == 'downloading' && total.to_i > 0
        end
      end

      req.start do |_r, res|
        finish.call do
          raise "Tidak ada respon dari server" if res.nil?
          code = res.status_code
          if [301, 302, 303, 307, 308].include?(code) && hops < MAX_REDIRECTS
            loc = res.headers.find { |k, _| k.to_s.downcase == 'location' }&.last
            raise "Redirect tanpa tujuan" unless loc
            next fetch(loc, timeout, loud, headers: headers, on_fail: on_fail, hops: hops + 1, &on_ok)
          end
          raise http_error(code, res.body) unless code == 200
          on_ok.call(res.body)
        end
      end

      UI.start_timer(timeout, false) do
        next if done
        req.cancel rescue nil
        finish.call("Tidak ada respon dari server (timeout #{timeout} detik).")
      end
    end

    def self.show_dialog
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: "Boosok Tools Update",
        preferences_key: "BoosokToolsUpdater",
        scrollable: false, resizable: false,
        width: 380, height: 420,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_file(File.join(::BoosokTools::SUPPORT_DIR, 'html', 'update.html'))
      BoosokTools::TitleBar.attach(@dialog, "Boosok Tools Update")

      @dialog.add_action_callback("ready")    { push }
      @dialog.add_action_callback("check")    { check(true) }
      @dialog.add_action_callback("download") { download }
      @dialog.add_action_callback("close")    { @dialog.close }
      @dialog.add_action_callback("quit")     { Sketchup.quit } # SketchUp tetap tanya simpan model
      @dialog.add_action_callback("browser")   { UI.openURL(RELEASES_URL) }
      @dialog.add_action_callback("changelog") { UI.openURL(defined?(CHANGELOG_URL) ? CHANGELOG_URL : RELEASES_URL) }
      @dialog.show
    end
  end
end
