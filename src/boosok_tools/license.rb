require 'sketchup'
require 'digest'

module BoosokTools
  module License
    # Salt rahasia untuk pembuatan dan validasi lisensi (XOR obfuscated)
    unless defined?(SECRET)
      _S = [0x19,0x3F,0x28,0x32,0x0E,0x08,0x3A,0x2F,0x1C,0x3A,0x2D,0x0E,0x37,0x20,0x3B,0x39,
            0x2F,0x10,0x3C,0x2A,0x1D,0x3A,0x18,0x3A,0x28,0x2F,0x1D,0x3A,0x0E,0x3A,0x2C,0x29].map { |b| (b ^ 0x5A).chr }.join
      SECRET = _S.freeze
    end

    PREF_KEY        = "license_key"  unless defined?(PREF_KEY)
    PREF_SECT       = "BoosokTools"  unless defined?(PREF_SECT)
    TRIAL_DAYS      = 7              unless defined?(TRIAL_DAYS)
    TRIAL_DURATION  = TRIAL_DAYS * 86400 unless defined?(TRIAL_DURATION) # 604,800 detik (7 hari)

    @cached_hardware_id = nil

    # 1. Ambil komponen hardware unik mesin Windows
    def self.get_hardware_components
      parts = []

      # a. MachineGuid dari Registry Windows
      begin
        require 'win32/registry'
        Win32::Registry::HKEY_LOCAL_MACHINE.open('SOFTWARE\Microsoft\Cryptography') do |reg|
          val = reg['MachineGuid'].to_s.strip
          parts << "GUID:#{val}" unless val.empty?
        end
      rescue
        begin
          out = `cmd /c "reg query HKLM\\SOFTWARE\\Microsoft\\Cryptography /v MachineGuid 2>nul"`.strip
          val = out.scan(/MachineGuid\s+REG_SZ\s+(\S+)/i).flatten.first.to_s.strip
          parts << "GUID:#{val}" unless val.empty?
        rescue; end
      end

      # b. BaseBoard Product dari BIOS Registry
      begin
        out = `cmd /c "reg query HKLM\\HARDWARE\\DESCRIPTION\\System\\BIOS /v BaseBoardProduct 2>nul"`.strip
        val = out.scan(/BaseBoardProduct\s+REG_SZ\s+(.+)/i).flatten.first.to_s.strip
        parts << "MB:#{val}" unless val.empty? || val =~ /default|to be|none|n\/a/i
      rescue; end

      # c. Processor Name dari Registry
      begin
        out = `cmd /c "reg query HKLM\\HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0 /v ProcessorNameString 2>nul"`.strip
        val = out.scan(/ProcessorNameString\s+REG_SZ\s+(.+)/i).flatten.first.to_s.strip
        parts << "CPU:#{val}" unless val.empty?
      rescue; end

      # d. System UUID dari CIM / PowerShell (jika ada)
      begin
        out = `powershell -NoProfile -Command "(Get-CimInstance Win32_ComputerSystemProduct).UUID" 2>nul`.strip
        parts << "UUID:#{out}" unless out.empty? || out =~ /error|fail/i
      rescue; end

      # e. Volume Serial C:
      begin
        out = `cmd /c vol C: 2>nul`.strip
        vol = out.match(/[0-9A-F]{4}-[0-9A-F]{4}/i)&.to_s.strip
        parts << "VOL:#{vol}" unless vol.nil? || vol.empty?
      rescue; end

      if parts.empty?
        parts << "HOST:#{ENV['COMPUTERNAME'] || ENV['HOSTNAME'] || 'DEFAULT'}"
      end

      parts
    rescue => e
      ["HOST:#{ENV['COMPUTERNAME'] || 'DEFAULT'}"]
    end

    # 2. Hardware ID = SHA256(sorted_parts)[0,16] diformat XXXX-XXXX-XXXX-XXXX
    def self.hardware_id
      @cached_hardware_id ||= begin
        parts = get_hardware_components
        raw   = parts.sort.join("|")
        hex   = Digest::SHA256.hexdigest(raw)[0, 16].upcase
        "#{hex[0,4]}-#{hex[4,4]}-#{hex[8,4]}-#{hex[12,4]}"
      end
    rescue => e
      "UNKNOWN-HWID"
    end

    # Validasi license key yang diinput user
    def self.validate(input_key, hw = nil)
      return false if input_key.nil? || input_key.to_s.strip.empty?
      clean_input = input_key.to_s.strip.upcase.gsub(/[^0-9A-Z]/, '')
      return false if clean_input.length != 20

      hw ||= hardware_id
      clean_hw = hw.to_s.strip.upcase.gsub(/[^0-9A-Z]/, '')
      return false if clean_hw.empty?

      raw_hash = Digest::SHA256.hexdigest("#{clean_hw}::#{SECRET}").upcase
      expected_chars = raw_hash.gsub(/[^0-9A-Z]/, '')[0, 20]
      clean_input == expected_chars
    rescue => e
      false
    end

    # 5. Simpan & baca dari SketchUp Defaults
    def self.save_key(key)
      Sketchup.write_default(PREF_SECT, PREF_KEY, key.to_s.strip)
      true
    rescue => e
      false
    end

    def self.saved_key
      Sketchup.read_default(PREF_SECT, PREF_KEY, "").to_s.strip
    rescue => e
      ""
    end

    def self.licensed?
      key = saved_key
      return false if key.empty?
      validate(key)
    rescue => e
      false
    end

    # ── 6. Sistem Trial 7 Hari ──
    def self.trial_start_time
      raw = Sketchup.read_default(PREF_SECT, "trial_start", "").to_s.strip
      sig = Sketchup.read_default(PREF_SECT, "trial_sig", "").to_s.strip
      hw  = hardware_id

      if raw.empty?
        # Pertama kali plugin dipasang / dijalankan
        now = Time.now.to_i
        signature = Digest::SHA256.hexdigest("#{now}:#{hw}:#{SECRET}")[0, 16]
        Sketchup.write_default(PREF_SECT, "trial_start", now.to_s)
        Sketchup.write_default(PREF_SECT, "trial_sig", signature)
        Sketchup.write_default(PREF_SECT, "last_seen", now.to_s)
        return now
      end

      # Validasi integritas signature anti-tamper
      expected_sig = Digest::SHA256.hexdigest("#{raw}:#{hw}:#{SECRET}")[0, 16]
      if sig != expected_sig
        return 0 # Manipulasi terdeteksi, kunci trial
      end

      # Anti-clock rollback: jika jam sistem dimundurkan > 1 jam
      last_seen = Sketchup.read_default(PREF_SECT, "last_seen", 0).to_i
      now = Time.now.to_i
      if last_seen > 0 && now < (last_seen - 3600)
        return 0 # Jam dimundurkan, kunci trial
      end

      Sketchup.write_default(PREF_SECT, "last_seen", now.to_s) if now > last_seen
      raw.to_i
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
      hw  = hardware_id
      sig = Digest::SHA256.hexdigest("#{now}:#{hw}:#{SECRET}")[0, 16]
      Sketchup.write_default(PREF_SECT, "trial_start", now.to_s)
      Sketchup.write_default(PREF_SECT, "trial_sig", sig)
      Sketchup.write_default(PREF_SECT, "last_seen", now.to_s)
      puts "[Boosok Tools] Trial di-reset! 7 hari tersisa."
      status
    end

    # Helper untuk simulasi trial habis (untuk testing keadaan terkunci)
    def self.expire_trial!
      past = Time.now.to_i - (8 * 86400) # 8 hari yang lalu
      hw   = hardware_id
      sig  = Digest::SHA256.hexdigest("#{past}:#{hw}:#{SECRET}")[0, 16]
      Sketchup.write_default(PREF_SECT, "trial_start", past.to_s)
      Sketchup.write_default(PREF_SECT, "trial_sig", sig)
      Sketchup.write_default(PREF_SECT, "last_seen", past.to_s)
      puts "[Boosok Tools] Trial di-set KADALUARSA (expired)! Semua tool terkunci."
      status
    end

    # 7. Status lengkap untuk dikirim ke UI HTML
    def self.status
      hw_id     = hardware_id
      saved     = saved_key
      is_valid  = saved.empty? ? false : validate(saved, hw_id)
      days_left = trial_days_remaining
      rem_sec   = trial_remaining_seconds

      st_code = if is_valid
                  "active"
                elsif days_left > 0
                  "trial"
                else
                  "expired"
                end

      {
        hw_id:       hw_id,
        hw_short:    hw_id[0, 9],
        is_valid:    is_valid,
        saved_key:   saved.empty? ? "" : saved,
        status:      st_code,
        days_left:   days_left,
        rem_seconds: rem_sec,
        can_use:     is_valid || (days_left > 0)
      }
    rescue => e
      { hw_id: "ERROR", hw_short: "ERROR", is_valid: false, saved_key: "", status: "expired", days_left: 0, can_use: false }
    end
  end
end