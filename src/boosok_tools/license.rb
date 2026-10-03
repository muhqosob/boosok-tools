require 'sketchup'
require 'digest'
require 'json'
require 'base64'
require 'fileutils'

module BoosokTools
  module License
    # Salt rahasia untuk pembuatan dan validasi lisensi (XOR obfuscated)
    unless defined?(SECRET)
      _S = [0x19,0x3F,0x28,0x32,0x0E,0x08,0x3A,0x2F,0x1C,0x3A,0x2D,0x0E,0x37,0x20,0x3B,0x39,
            0x2F,0x10,0x3C,0x2A,0x1D,0x3A,0x18,0x3A,0x28,0x2F,0x1D,0x3A,0x0E,0x3A,0x2C,0x29].map { |b| (b ^ 0x5A).chr }.join
      SECRET = _S.freeze
    end

    PREF_KEY        = "license_key"  unless defined?(PREF_KEY)
    # Token bertanda tangan dari server lisensi, disimpan sebagai base64 URL-safe: Sketchup.read_default meng-eval nilai
    # string, jadi JSON mentah (berisi tanda kutip) menyebabkan SyntaxError. Nama lama "license_token" (JSON mentah,
    # dari versi bermasalah) dikosongkan saat lisensi diaktifkan / dihapus.
    PREF_TOKEN      = "license_tok"     unless defined?(PREF_TOKEN)
    PREF_TOKEN_OLD  = "license_token"   unless defined?(PREF_TOKEN_OLD)
    PREF_MODE       = "license_mode"    unless defined?(PREF_MODE)    # 'online' | 'legacy' (key lama berbasis Hardware ID)
    PREF_CHECKED    = "license_checked" unless defined?(PREF_CHECKED) # waktu terakhir berhasil dicek ke server

    # ── Server lisensi online (Cloudflare Workers) ──
    # Isi SERVER_URL dengan alamat hasil "wrangler deploy". Selama masih berisi ISI_ALAMAT_SERVER, aktivasi online
    # nonaktif dan plugin hanya menerima key lama (berbasis Hardware ID) seperti sebelumnya.
    SERVER_URL = "https://boosok-license.boosok.workers.dev" unless defined?(SERVER_URL)
    PUBLIC_KEY_PEM = <<~PEM unless defined?(PUBLIC_KEY_PEM)
      -----BEGIN PUBLIC KEY-----
      MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAgijOnKh3GmcSMDR+BKFv
      NpV9pOs+sGlA5GqKfaH/koU6kgt0ZpoM8T/S0PXSbkUiySuqWdbS70pirpfNzlGK
      HYgP3FZpvkGQH/8l2PEabZG2otA8DQJS/R78gCA+ZQ+0bLV5pUwF4k0bYizZf2Qy
      1gf9KmKHb10QiZFhuO+kS84AB7IFBhC5RbEjGBoskGB80yXyLf35ESn67C3taENV
      IiN3P5yfI3aA8KLg89LjQC7IcrWlAAUEEKgiTsDa5spdQO3jSTAALvqA2UEl64E5
      o1OfqJNXhII0/pK5qDqRB5HixdNPhmKRJT1lZyLJ1GZQMQ18O0dizgCPpmASZ9wV
      CQIDAQAB
      -----END PUBLIC KEY-----
    PEM
    REFRESH_INTERVAL = 12 * 3600 unless defined?(REFRESH_INTERVAL) # cek otomatis saat startup paling sering tiap 12 jam
    HTTP_TIMEOUT     = 20 unless defined?(HTTP_TIMEOUT)
    PREF_SECT       = "BoosokTools"  unless defined?(PREF_SECT)
    remove_const(:TRIAL_DURATION) if defined?(TRIAL_DURATION)
    TRIAL_DAYS      = 7
    TRIAL_DURATION  = TRIAL_DAYS * 86400 # 604,800 detik (7 hari)

    @cached_hardware_id = nil

    # 1. Ambil komponen hardware unik mesin Windows tanpa spawn shell/powershell yang lambat
    def self.get_hardware_components
      parts = []

      # a. Registry Windows via Win32::Registry (Pure Ruby, instan 0.001ms)
      begin
        require 'win32/registry'
        Win32::Registry::HKEY_LOCAL_MACHINE.open('SOFTWARE\Microsoft\Cryptography') do |reg|
          val = reg['MachineGuid'].to_s.strip
          parts << "GUID:#{val}" unless val.empty?
        end rescue nil

        Win32::Registry::HKEY_LOCAL_MACHINE.open('HARDWARE\DESCRIPTION\System\BIOS') do |reg|
          val = reg['BaseBoardProduct'].to_s.strip
          parts << "MB:#{val}" unless val.empty? || val =~ /default|to be|none|n\/a/i
        end rescue nil

        Win32::Registry::HKEY_LOCAL_MACHINE.open('HARDWARE\DESCRIPTION\System\CentralProcessor\0') do |reg|
          val = reg['ProcessorNameString'].to_s.strip
          parts << "CPU:#{val}" unless val.empty?
        end rescue nil
      rescue
      end

      # b. Environment variables mesin
      parts << "HOST:#{ENV['COMPUTERNAME'] || ENV['HOSTNAME'] || 'DEFAULT'}"
      parts << "PROC:#{ENV['PROCESSOR_IDENTIFIER'] || ''}"
      parts << "USERDOM:#{ENV['USERDOMAIN'] || ''}"

      parts.reject(&:empty?)
    rescue => e
      ["HOST:#{ENV['COMPUTERNAME'] || 'DEFAULT'}"]
    end

    # Sidik jari tiap komponen: {"GUID"=>"ab12cd34", "MB"=>..., "HOST"=>...}. Hanya hash pendek, bukan nilai aslinya.
    # Label hanya huruf, jadi aman digabung dengan "-" dan "_" (read_default meng-eval string, hindari tanda kutip).
    def self.component_digests(parts)
      parts.each_with_object({}) do |p, h|
        label, = p.split(":", 2)
        h[label] = Digest::SHA256.hexdigest(p)[0, 8]
      end
    end

    def self.encode_digests(digests)
      digests.map { |k, d| "#{k}-#{d}" }.join("_")
    end

    def self.decode_digests(str)
      str.to_s.split("_").map { |e| e.split("-", 2) }.select { |a| a.size == 2 && !a[0].empty? }.to_h
    end

    # Apakah komponen tersimpan (saved) berasal dari mesin yang sama dengan komponen sekarang (fresh)?
    # MachineGuid wajib sama bila ada di keduanya (beda PC / Windows diinstal ulang = beda GUID). Sisanya cukup
    # 2/3 yang cocok, supaya ganti nama komputer atau domain tidak dianggap pindah mesin.
    def self.same_machine?(saved, fresh)
      return true if saved.empty? # tidak ada pembanding (pengguna lama): percaya, komponen disimpan sekarang
      return false if saved["GUID"] && fresh["GUID"] && saved["GUID"] != fresh["GUID"]

      common = saved.keys & fresh.keys
      return true if common.empty?

      common.count { |k| saved[k] == fresh[k] } * 3 >= common.size * 2
    end

    # 2. Hardware ID = SHA256(sorted_parts)[0,16] diformat XXXX-XXXX-XXXX-XXXX
    # ID disimpan di SketchUp defaults (stabil walau komponen berubah sedikit, mis. ganti nama PC), tetapi hanya
    # dipakai bila komponen mesin sekarang cocok dengan yang tersimpan. Registry yang disalin ke PC lain ditolak
    # dan ID dihitung ulang dari mesin ini, sehingga token lisensi PC asal tidak berlaku di PC baru.
    def self.hardware_id
      return @cached_hardware_id if @cached_hardware_id

      parts  = get_hardware_components
      fresh  = component_digests(parts)
      saved  = Sketchup.read_default(PREF_SECT, "cached_hwid", "").to_s.strip
      saved_parts = decode_digests(Sketchup.read_default(PREF_SECT, "hw_parts", ""))

      if saved =~ /^[0-9A-Z]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$/i && same_machine?(saved_parts, fresh)
        @cached_hardware_id = saved.upcase
        Sketchup.write_default(PREF_SECT, "hw_parts", encode_digests(fresh)) if saved_parts != fresh
        return @cached_hardware_id
      end

      hex = Digest::SHA256.hexdigest(parts.sort.join("|"))[0, 16].upcase
      hw  = "#{hex[0,4]}-#{hex[4,4]}-#{hex[8,4]}-#{hex[12,4]}"
      @cached_hardware_id = hw
      Sketchup.write_default(PREF_SECT, "cached_hwid", hw) rescue nil
      Sketchup.write_default(PREF_SECT, "hw_parts", encode_digests(fresh)) rescue nil
      hw
    rescue => e
      "UNKNOWN-HWID"
    end

    # Key yang seharusnya untuk sebuah Hardware ID (dipakai validasi dan pembuat key di tools/keygen)
    def self.expected_key(hw)
      clean_hw = hw.to_s.strip.upcase.gsub(/[^0-9A-Z]/, '')
      return nil if clean_hw.empty?

      Digest::SHA256.hexdigest("#{clean_hw}::#{SECRET}").upcase.gsub(/[^0-9A-Z]/, '')[0, 20]
    end

    # Validasi license key yang diinput user
    def self.validate(input_key, hw = nil)
      return false if input_key.nil? || input_key.to_s.strip.empty?
      clean_input = input_key.to_s.strip.upcase.gsub(/[^0-9A-Z]/, '')
      return false if clean_input.length != 20

      expected = expected_key(hw || hardware_id)
      !expected.nil? && clean_input == expected
    rescue => e
      false
    end

    # 5. Simpan & baca dari SketchUp Defaults
    def self.save_key(key)
      Sketchup.write_default(PREF_SECT, PREF_KEY, key.to_s.strip)
      clear_cache!
      true
    rescue => e
      false
    end

    # Hasil validasi key & trial disimpan di memori supaya can_use?/status tidak membaca
    # registry + menghitung SHA256 berulang kali di setiap perpindahan menu.
    # Wajib dipanggil setiap kali key / data trial diubah.
    def self.clear_cache!
      @licensed_cache = nil
      @saved_key_cache = nil
      @saved_mode_cache = nil
      @token_cache = nil
      @trial_start_cache = nil
    end

    def self.saved_key
      @saved_key_cache ||= Sketchup.read_default(PREF_SECT, PREF_KEY, "").to_s.strip
    rescue => e
      ""
    end

    # Mode lisensi tersimpan: 'online' (token dari server) atau 'legacy' (key lama berbasis Hardware ID; juga bila
    # belum ada mode tersimpan, yaitu pengguna lama)
    def self.saved_mode
      @saved_mode_cache ||= (Sketchup.read_default(PREF_SECT, PREF_MODE, "").to_s.strip == "online" ? "online" : "legacy")
    rescue => e
      "legacy"
    end

    def self.licensed?
      return @licensed_cache unless @licensed_cache.nil?
      key = saved_key
      @licensed_cache =
        if key.empty?
          false
        elsif saved_mode == "online"
          online_valid?(key)
        else
          validate(key)
        end
    rescue => e
      false
    end

    # ── Lisensi online ──────────────────────────────────────────────────────────

    def self.online_configured?
      !SERVER_URL.include?("ISI_ALAMAT_SERVER")
    end

    def self.compact_id(str)
      str.to_s.upcase.gsub(/[^0-9A-Z]/, '')
    end

    # Token tersimpan {"payload"=>String, "sig"=>base64}. Diverifikasi dengan kunci publik, jadi tidak bisa dipalsukan
    # tanpa kunci privat di server. Hasil: Hash payload atau nil.
    def self.verified_payload(token)
      return nil unless token.is_a?(Hash) && token["payload"].is_a?(String) && token["sig"].is_a?(String)

      # OpenSSL dimuat malas (baru saat token pertama diverifikasi, jarang) agar startup SketchUp tidak melambat
      require 'openssl' # rubocop:disable SketchupPerformance/OpenSSL -- hanya verifikasi tanda tangan RSA token lisensi
      pkey = OpenSSL::PKey::RSA.new(PUBLIC_KEY_PEM)
      sig = Base64.strict_decode64(token["sig"])
      return nil unless pkey.verify(OpenSSL::Digest.new("SHA256"), sig, token["payload"])

      JSON.parse(token["payload"])
    rescue => e
      nil
    end

    def self.saved_token
      @token_cache ||= begin
        raw = Sketchup.read_default(PREF_SECT, PREF_TOKEN, "").to_s
        raw.empty? ? {} : JSON.parse(Base64.urlsafe_decode64(raw))
      end
    rescue StandardError, ScriptError # ScriptError: nilai lama bermasalah di-eval oleh read_default
      {}
    end

    def self.saved_payload
      verified_payload(saved_token)
    end

    # Token sah bila tanda tangannya benar dan untuk key + Hardware ID ini. Tidak ada masa kedaluwarsa dan tidak ada
    # cek jam: setelah aktivasi, plugin dipakai offline selamanya. "exp" di token (diisi server jauh ke depan) hanya
    # ada demi plugin v1.7.0 - v1.7.2 yang masih mengeceknya; sengaja diabaikan di sini. Pencabutan key baru
    # berlaku saat perangkat online lagi (cek saat startup / tombol Cek update, lihat maybe_refresh).
    def self.online_valid?(key)
      p = saved_payload
      return false unless p

      compact_id(p["k"]) == compact_id(key) && compact_id(p["hw"]) == compact_id(hardware_id)
    rescue => e
      false
    end

    # POST JSON ke server lisensi (async, Sketchup::Http). Blok dipanggil SEKALI dengan (status_http, data_hash_atau_nil);
    # status 0 = gagal terhubung / waktu habis.
    def self.http_post(path, body, &callback)
      done = false
      finish = lambda do |status, data|
        next if done

        done = true
        callback.call(status, data)
      end
      request = Sketchup::Http::Request.new("#{SERVER_URL}#{path}", Sketchup::Http::POST)
      request.headers = { "Content-Type" => "application/json" }
      request.body = JSON.generate(body)
      request.start do |_req, res|
        status = (res.status_code rescue 0).to_i
        data = (JSON.parse(res.body.to_s) rescue nil)
        finish.call(status, data)
      end
      UI.start_timer(HTTP_TIMEOUT, false) { finish.call(0, nil) } # jaga-jaga bila callback tidak pernah datang
    rescue => e
      finish.call(0, nil) if finish
    end

    # Header untuk mengunduh update dari server. Hanya lisensi online yang aktif (key + perangkat terikat) yang berhak;
    # selain itu nil (trial, key lama, atau belum aktif).
    def self.update_headers
      return nil unless online_configured? && saved_mode == "online" && licensed?

      { "X-License-Key" => saved_key, "X-Hardware-Id" => hardware_id }
    end

    def self.clear_license!
      Sketchup.write_default(PREF_SECT, PREF_KEY, "")
      Sketchup.write_default(PREF_SECT, PREF_TOKEN, "")
      Sketchup.write_default(PREF_SECT, PREF_TOKEN_OLD, "")
      Sketchup.write_default(PREF_SECT, PREF_MODE, "")
      Sketchup.write_default(PREF_SECT, PREF_CHECKED, "")
      clear_cache!
    end

    def self.store_token(key, token)
      Sketchup.write_default(PREF_SECT, PREF_KEY, key.to_s.strip)
      Sketchup.write_default(PREF_SECT, PREF_TOKEN_OLD, "")
      Sketchup.write_default(PREF_SECT, PREF_TOKEN, Base64.urlsafe_encode64(JSON.generate(token), padding: false))
      Sketchup.write_default(PREF_SECT, PREF_MODE, "online")
      Sketchup.write_default(PREF_SECT, PREF_CHECKED, Time.now.to_i.to_s)
      clear_cache!
    end

    # Aktivasi: key dicek ke server (mengikat key ke Hardware ID ini). Key lama berbasis Hardware ID tetap diterima
    # secara offline. Blok dipanggil dengan Hash {ok:, error:, used:, max:}; error: invalid_key, revoked,
    # device_limit, network, bad_response.
    def self.activate(key, &callback)
      key = key.to_s.strip
      legacy_ok = validate(key)
      accept_legacy = lambda do
        save_key(key)
        Sketchup.write_default(PREF_SECT, PREF_MODE, "legacy")
        Sketchup.write_default(PREF_SECT, PREF_TOKEN, "")
        clear_cache!
        callback.call({ ok: true, mode: "legacy" })
      end
      unless online_configured?
        legacy_ok ? accept_legacy.call : callback.call({ ok: false, error: "invalid_key" })
        return
      end

      http_post("/activate", { key: key, hwid: hardware_id }) do |status, data|
        if status == 200 && data && data["ok"] && verified_payload(data["token"])
          store_token(key, data["token"])
          callback.call({ ok: true, mode: "online" })
        elsif status == 200 && data && data["ok"]
          callback.call({ ok: false, error: "bad_response" })
        elsif data && data["error"] == "invalid_key"
          legacy_ok ? accept_legacy.call : callback.call({ ok: false, error: "invalid_key" })
        elsif data && data["error"]
          callback.call({ ok: false, error: data["error"], used: data["used"], max: data["max"] })
        else
          legacy_ok ? accept_legacy.call : callback.call({ ok: false, error: "network" })
        end
      end
    end

    # Cek ulang ke server, dipanggil bersamaan dengan cek update (saat SketchUp dibuka dan tombol Cek update).
    # Hanya untuk lisensi online; tanpa force paling sering tiap REFRESH_INTERVAL. Tanpa internet tidak terjadi apa-apa
    # dan lisensi tetap berlaku. Key dicabut / perangkat dilepas di server: lisensi lokal dihapus. Blok dipanggil
    # dengan true bila status lisensi berubah.
    def self.maybe_refresh(force = false, &callback)
      return unless online_configured? && saved_mode == "online" && !saved_key.empty? && !@refreshing

      last = Sketchup.read_default(PREF_SECT, PREF_CHECKED, "").to_i
      # Token dari versi server lama belum memuat nama / nomor HP terdaftar: perbarui segera
      stale = (p = saved_payload) && !p.key?("nm")
      return if !force && !stale && last > 0 && (Time.now.to_i - last) < REFRESH_INTERVAL

      @refreshing = true
      key = saved_key
      http_post("/check", { key: key, hwid: hardware_id }) do |status, data|
        @refreshing = false
        changed = false
        if status == 200 && data && data["ok"] && verified_payload(data["token"])
          store_token(key, data["token"])
        elsif data && %w[revoked not_bound invalid_key].include?(data["error"])
          clear_license!
          changed = true
        end
        callback.call(changed) if callback
      end
    rescue => e
      @refreshing = false
    end

    # Lepas perangkat ini dari key (pindah komputer): server menghapus ikatan, lalu lisensi lokal dihapus. Lisensi
    # lama (legacy) cukup dihapus lokal. Blok dipanggil dengan {ok:, error:}; error 'network' = tidak ada koneksi
    # (lisensi tidak dihapus supaya perangkat tidak tertahan di server).
    def self.release(&callback)
      unless online_configured? && saved_mode == "online"
        clear_license!
        callback.call({ ok: true })
        return
      end

      key = saved_key
      http_post("/release", { key: key, hwid: hardware_id }) do |status, data|
        if status == 200 || (data && %w[revoked invalid_key].include?(data["error"]))
          clear_license!
          callback.call({ ok: true })
        else
          callback.call({ ok: false, error: "network" })
        end
      end
    end

    # ── 6. Sistem Trial 7 Hari ──
    def self.trial_start_time
      if @trial_start_cache
        now = Time.now.to_i
        # Anti-clock rollback tetap dicek tiap panggilan (murah, dari memori)
        return 0 if @last_seen_mem && now < (@last_seen_mem - 3600)
        if now > @last_seen_mem
          @last_seen_mem = now
          # Tulis registry + salinan file paling sering 1x per menit, bukan tiap panggilan
          if now - @last_seen_written >= 60
            Sketchup.write_default(PREF_SECT, "last_seen", now.to_s) rescue nil
            write_trial_files(@trial_start_cache, trial_signature(@trial_start_cache, hardware_id), now)
            @last_seen_written = now
          end
        end
        return @trial_start_cache
      end

      start = trial_start_time_uncached
      if start > 0
        @trial_start_cache = start
        @last_seen_mem = @last_seen_written = Time.now.to_i
      end
      start
    end

    def self.trial_signature(start, hw)
      Digest::SHA256.hexdigest("#{start}:#{hw}:#{SECRET}")[0, 16]
    end

    # Salinan kedua data trial di file, di luar registry SketchUp. Registry itu per versi SketchUp dan gampang dihapus
    # lewat regedit; file di sini dipakai bersama semua versi SketchUp, jadi menghapus registry saja tidak mengulang
    # trial. Dua lokasi (APPDATA dan LOCALAPPDATA) supaya menghapus satu file juga tidak cukup.
    def self.trial_file_paths
      %w[APPDATA LOCALAPPDATA].map { |v| ENV[v].to_s.dup.force_encoding('UTF-8') }.reject(&:empty?)
                              .map { |d| File.join(d, "BoosokTools", "cache.dat") }.uniq
    rescue
      []
    end

    # Hash {start:, seen:} bila file ada dan tanda tangannya cocok untuk perangkat ini; selain itu nil (dianggap tidak ada)
    def self.read_trial_file(path, hw)
      data = JSON.parse(File.read(path))
      start = data["s"].to_i
      return nil unless start > 0 && data["g"].to_s == trial_signature(start, hw)

      { start: start, seen: data["l"].to_i }
    rescue StandardError
      nil
    end

    def self.write_trial_files(start, sig, seen)
      body = JSON.generate({ "s" => start, "g" => sig, "l" => seen })
      trial_file_paths.each do |path|
        begin
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, body)
        rescue StandardError
          nil # satu lokasi gagal (izin / disk): lokasi lain dan registry tetap jalan
        end
      end
    end

    # Tulis data trial ke registry dan semua salinan file
    def self.write_trial_stores(start, seen)
      sig = trial_signature(start, hardware_id)
      Sketchup.write_default(PREF_SECT, "trial_start", start.to_s)
      Sketchup.write_default(PREF_SECT, "trial_sig", sig)
      Sketchup.write_default(PREF_SECT, "last_seen", seen.to_s)
      write_trial_files(start, sig, seen)
    end

    def self.trial_start_time_uncached
      raw = Sketchup.read_default(PREF_SECT, "trial_start", "").to_s.strip
      sig = Sketchup.read_default(PREF_SECT, "trial_sig", "").to_s.strip
      hw  = hardware_id
      now = Time.now.to_i

      files = trial_file_paths.map { |p| read_trial_file(p, hw) }.compact
      last_seen = ([Sketchup.read_default(PREF_SECT, "last_seen", 0).to_i] + files.map { |f| f[:seen] }).max

      reg_start = nil
      unless raw.empty?
        # Validasi integritas signature anti-tamper
        return 0 if sig != trial_signature(raw, hw) # Manipulasi terdeteksi, kunci trial

        reg_start = raw.to_i
      end

      # Mulai trial = yang paling awal dari semua salinan. Registry dihapus tapi file masih ada (atau sebaliknya):
      # trial tetap berlanjut dari tanggal asli, dan salinan yang hilang dipulihkan di bawah.
      start = ([reg_start] + files.map { |f| f[:start] }).compact.min || now # nil = pertama kali plugin dijalankan

      # Anti-clock rollback: jika jam sistem dimundurkan > 1 jam
      return 0 if last_seen > 0 && now < (last_seen - 3600) # Jam dimundurkan, kunci trial

      write_trial_stores(start, [now, last_seen].max)
      start
    rescue => e
      0
    end

    def self.trial_remaining_seconds
      start = trial_start_time
      return 0 if start <= 0
      elapsed = Time.now.to_i - start
      rem = TRIAL_DURATION - elapsed
      rem > 0 ? rem : 0
    end

    def self.trial_days_remaining
      rem = trial_remaining_seconds
      return 0 if rem <= 0
      (rem / 86400.0).ceil
    end

    def self.trial_minutes_remaining
      rem = trial_remaining_seconds
      return 0 if rem <= 0
      (rem / 60.0).ceil
    end

    # Menentukan apakah tool diizinkan berjalan:
    # - True jika sudah berlisensi aktif ATAU masih dalam masa trial 7 hari
    # - False jika lisensi belum aktif dan masa trial 7 hari telah habis (Semua tool terkunci)
    def self.can_use?
      return true if licensed?
      trial_remaining_seconds > 0
    end

    # Helper untuk reset masa uji coba ke 7 hari lagi (untuk developer / testing)
    def self.reset_trial!
      now = Time.now.to_i
      write_trial_stores(now, now)
      clear_cache!
      puts "[Boosok Tools] Trial di-reset! 7 hari tersisa."
      status
    end

    # Helper untuk simulasi trial habis (untuk testing keadaan terkunci)
    def self.expire_trial!
      past = Time.now.to_i - (8 * 86400) # 8 hari yang lalu
      write_trial_stores(past, past)
      clear_cache!
      puts "[Boosok Tools] Trial di-set KADALUARSA (expired)! Semua tool terkunci."
      status
    end

    # 7. Status lengkap untuk dikirim ke UI HTML
    def self.status
      hw_id     = hardware_id
      saved     = saved_key
      is_valid  = licensed?
      rem_sec   = trial_remaining_seconds
      mins_left = (rem_sec / 60.0).ceil

      st_code = if is_valid
                  "active"
                elsif rem_sec > 0
                  "trial"
                else
                  "expired"
                end

      time_str = if rem_sec >= 86400
                   "#{rem_sec / 86400} hari #{(rem_sec % 86400) / 3600} jam"
                 elsif rem_sec > 3600
                   "#{mins_left / 60} jam #{mins_left % 60} m"
                 elsif rem_sec > 60
                   "#{mins_left} menit"
                 elsif rem_sec > 0
                   "#{rem_sec} detik"
                 else
                   "0 menit"
                 end

      {
        hw_id:       hw_id,
        hw_short:    hw_id[0, 9],
        is_valid:    is_valid,
        saved_key:   saved.empty? ? "" : saved,
        mode:        saved_mode,
        devices:     (saved_mode == "online" && saved_payload ? { used: saved_payload["used"], max: saved_payload["max"] } : nil),
        name:        (saved_mode == "online" && is_valid && saved_payload ? saved_payload["nm"].to_s : ""),
        phone:       (saved_mode == "online" && is_valid && saved_payload ? saved_payload["ph"].to_s : ""),
        status:      st_code,
        days_left:   (rem_sec > 0 ? (rem_sec / 86400.0).ceil : 0),
        mins_left:   mins_left,
        time_str:    time_str,
        rem_seconds: rem_sec,
        can_use:     is_valid || (rem_sec > 0)
      }
    rescue => e
      { hw_id: "ERROR", hw_short: "ERROR", is_valid: false, saved_key: "", status: "expired", days_left: 0, mins_left: 0, rem_seconds: 0, can_use: false }
    end
  end
end