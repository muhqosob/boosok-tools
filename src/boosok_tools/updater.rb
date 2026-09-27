require 'sketchup'
require 'json'
require 'tmpdir'

module MyCustomPlugins
  # Update di dalam SketchUp: cek -> download .rbz -> install -> minta restart.
  # Satu state di Ruby, dialog cuma render state itu (render(state) di update.html).
  #
  # status: idle | checking | latest | available | downloading | installing | done | error
  module Updater
    CHECK_TIMEOUT = 15     # detik
    DOWNLOAD_TIMEOUT = 180 # detik
    MAX_REDIRECTS = 5      # link release GitHub redirect ke CDN

    @state = { status: 'idle' }

    # manual = dari menu. Cek otomatis saat startup diam saja kecuali ada update.
    def self.check(manual = false)
      show_dialog if manual
      # done: versi baru baru aktif setelah restart, jangan cek ulang (bakal "available" lagi)
      return if busy? || @state[:status] == 'done'

      set(status: 'checking', error: nil, progress: nil)
      fetch(VERSION_URL, CHECK_TIMEOUT, manual) do |body|
        data = JSON.parse(body)
        if Gem::Version.new(data["version"]) > Gem::Version.new(PLUGIN_VERSION)
          set(status: 'available', latest: data["version"],
              changelog: data["changelog"].to_s, download_url: data["download_url"])
          show_dialog
        else
          set(status: 'latest')
        end
      end
    end

    def self.download
      return unless @state[:status] == 'available'

      set(status: 'downloading', progress: 0)
      fetch(@state[:download_url], DOWNLOAD_TIMEOUT, true) do |body|
        set(status: 'installing', progress: nil)
        path = File.join(Dir.tmpdir, "boosok_tools_v#{@state[:latest]}.rbz")
        File.binwrite(path, body)
        # Kasih UI satu frame buat render "Memasang..." sebelum install nge-block
        UI.start_timer(0.1, false) { install(path) }
      end
    end

    def self.install(path)
      begin
        Sketchup.install_from_archive(path, false)
      rescue ArgumentError
        Sketchup.install_from_archive(path) # SketchUp lama: tanpa argumen show_messages
      end
      set(status: 'done')
    rescue Exception => e # install_from_archive bisa raise Interrupt kalau user batal
      fail_with("Gagal memasang: #{e.message}")
    ensure
      File.delete(path) rescue nil
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
    def self.fetch(url, timeout, loud, hops = 0, &on_ok)
      done = false
      finish = lambda do |msg = nil, &blk|
        next if done
        done = true
        begin
          blk ? blk.call : raise(msg)
        rescue => e
          loud ? fail_with(e.message) : set(status: 'idle')
        end
      end

      # Simpan referensi, kalau tidak request bisa kena GC dan callback tidak pernah jalan
      @request = req = Sketchup::Http::Request.new(url, Sketchup::Http::GET)
      req.headers = { 'User-Agent' => 'BoosokTools-SketchupExtension' }
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
            next fetch(loc, timeout, loud, hops + 1, &on_ok)
          end
          raise "HTTP #{code}" unless code == 200
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
      @dialog.set_file(File.join(__dir__, 'update.html'))

      @dialog.add_action_callback("ready")    { push }
      @dialog.add_action_callback("check")    { check(true) }
      @dialog.add_action_callback("download") { download }
      @dialog.add_action_callback("close")    { @dialog.close }
      @dialog.add_action_callback("quit")     { Sketchup.quit } # SketchUp tetap tanya simpan model
      @dialog.add_action_callback("browser")  { UI.openURL(RELEASES_URL) }
      @dialog.show
    end
  end
end
