require 'sketchup'
require 'json'
require 'digest'

module BoosokTools
  # Sumber terjemahan TUNGGAL: locales/<kode>.json (satu file per bahasa).
  #
  # Format file (lihat locales/README.md):
  #   { "code": "en", "name": "English", "native_name": "English",
  #     "strings":  { "kunci": "teks", ... },                 # semua teks UI
  #     "messages": { "pesan Indonesia dari Ruby": "terjemahan" },   # opsional
  #     "patterns": [ { "match": "^regex$", "replace": "teks $1" } ] }  # opsional
  #
  # Ruby membaca file ini langsung (Locale.t). Halaman HTML membacanya lewat js/strings.js yang
  # DIBUAT OTOMATIS dari file-file yang sama (export_js) — jadi menambah bahasa cukup satu file.
  module Locale
    LOCALES_DIR  = File.join(::BoosokTools::SUPPORT_DIR, 'locales')
    DEFAULT_LANG = 'id'
    JS_FILE      = File.join(::BoosokTools::SUPPORT_DIR, 'js', 'strings.js')

    @cached_locales = nil
    @cache_sig = nil
    @lang_cache = nil
    @exported_sig = nil

    # Buang tanda kutip / karakter aneh (JS mengirim JSON.stringify("id") => "\"id\"").
    def self.sanitize_code(code)
      code.to_s.downcase.gsub(/[^a-z0-9_-]/, '')
    end

    # Sketchup.read_default meng-eval nilai tersimpan: nilai rusak melempar SyntaxError
    # (ScriptError, bukan StandardError) — tangkap lalu perbaiki otomatis.
    def self.current_language
      return @lang_cache if @lang_cache
      raw = begin
        Sketchup.read_default("BoosokTools", "language", DEFAULT_LANG)
      rescue ScriptError, StandardError
        nil
      end
      code = sanitize_code(raw)
      if code.empty?
        code = DEFAULT_LANG
        begin
          Sketchup.write_default("BoosokTools", "language", code)
        rescue ScriptError, StandardError
        end
      end
      @lang_cache = code
    end

    def self.set_language(code)
      clean_code = sanitize_code(code)
      clean_code = DEFAULT_LANG if clean_code.empty?
      Sketchup.write_default("BoosokTools", "language", clean_code)
      @lang_cache = clean_code
    end

    CHECK_INTERVAL = 5 unless defined?(CHECK_INTERVAL)

    def self.locale_files
      Dir.exist?(LOCALES_DIR) ? Dir.glob(File.join(LOCALES_DIR, '*.json')).sort : []
    end

    # Tanda tangan murah (mtime + ukuran) untuk mendeteksi file bahasa yang berubah / ditambah.
    def self.signature(files = locale_files)
      files.map { |f| [f, (File.mtime(f).to_i rescue 0), (File.size(f) rescue 0)] }
    end

    # Pastikan satu file bahasa bentuknya benar; bagian yang salah bentuk diganti kosong + peringatan.
    def self.normalize(data, file)
      code = (data['code'] || File.basename(file, '.json')).to_s.downcase
      data['code'] = code
      data['name'] = data['name'].to_s.empty? ? code : data['name'].to_s
      data['native_name'] = data['native_name'].to_s.empty? ? data['name'] : data['native_name'].to_s
      data['file'] = File.basename(file)
      unless data['strings'].is_a?(Hash)
        puts "[Boosok Tools] #{File.basename(file)}: \"strings\" harus berupa objek {kunci: teks}"
        data['strings'] = {}
      end
      data['messages'] = {} unless data['messages'].is_a?(Hash)
      pats = data['patterns'].is_a?(Array) ? data['patterns'] : []
      data['patterns'] = pats.select { |p| p.is_a?(Hash) && p['match'].is_a?(String) && p['replace'].is_a?(String) }
      data
    end

    def self.all_locales(force_reload = false)
      # Locale.t dipanggil per frame oleh Select Tool → jangan sentuh disk di setiap panggilan.
      # Cek perubahan file paling sering tiap 5 detik; parse ulang hanya kalau mtime/size berubah.
      now = Time.now.to_f
      if !force_reload && @cached_locales && @checked_at && (now - @checked_at) < CHECK_INTERVAL
        return @cached_locales
      end
      @checked_at = now

      files = locale_files
      sig = signature(files)
      if !force_reload && @cached_locales && @cache_sig == sig
        return @cached_locales
      end

      locales = {}
      files.each do |f|
        begin
          data = JSON.parse(File.read(f, encoding: 'UTF-8'))
          raise 'isi file harus berupa objek JSON' unless data.is_a?(Hash)
          data = normalize(data, f)
          locales[data['code']] = data
        rescue => e
          puts "[Boosok Tools] Gagal membaca locale '#{File.basename(f)}': #{e.message}"
        end
      end

      @cached_locales = locales
      @cache_sig = sig
      locales
    end

    # Tulis js/strings.js (window.BOOSOK_LOCALES = {...}) dari semua locales/*.json supaya halaman
    # HTML memakai sumber yang sama dengan Ruby. Hanya menulis kalau file bahasa berubah.
    # Mengembalikan true kalau file ditulis ulang.
    def self.export_js(force = false)
      files = locale_files
      sig = Digest::SHA1.hexdigest(signature(files).map { |f, m, s| "#{File.basename(f)}:#{m}:#{s}" }.join('|'))
      return false if !force && @exported_sig == sig && File.exist?(JS_FILE)

      if !force && File.exist?(JS_FILE)
        on_disk = File.open(JS_FILE, 'r:UTF-8') { |io| io.gets.to_s[/sig:(\h+)/, 1] }
        if on_disk == sig
          @exported_sig = sig
          return false
        end
      end

      locs = all_locales(true)
      body = "// DIBUAT OTOMATIS oleh BoosokTools::Locale.export_js dari locales/*.json — jangan diedit. sig:#{sig}\n" \
             "window.BOOSOK_LOCALES = #{JSON.generate(locs)};\n"
      tmp = "#{JS_FILE}.tmp"
      File.open(tmp, 'w:UTF-8') { |io| io.write(body) }
      File.rename(tmp, JS_FILE)
      @exported_sig = sig
      true
    rescue => e
      puts "[Boosok Tools] Gagal menulis js/strings.js: #{e.class}: #{e.message}"
      false
    end

    def self.open_locales_folder
      if Dir.exist?(LOCALES_DIR)
        UI.openURL(LOCALES_DIR) rescue nil
      end
    end

    def self.t(key, fallback = nil, lang = nil)
      lang_code = lang || current_language
      locs = all_locales
      str = locs.dig(lang_code, 'strings', key.to_s)
      return str if str

      # Fallback ke default (id)
      str_id = locs.dig(DEFAULT_LANG, 'strings', key.to_s)
      return str_id if str_id

      fallback || key.to_s
    end
  end
end
