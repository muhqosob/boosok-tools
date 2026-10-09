require_relative 'test_helper'
require 'open3'
require 'tmpdir'
require 'rbconfig'

# Pengecekan statis seluruh src/: tidak butuh SketchUp.
class StaticTest < Minitest::Test
  RUBY_FILES = Dir[File.join(SRC, '**', '*.rb')].sort
  HTML_FILES = Dir[File.join(PLUGIN, 'html', '*.html')].sort
  JS_FILES = Dir[File.join(PLUGIN, 'js', '*.js')].sort
  LOCALE_FILES = Dir[File.join(PLUGIN, 'locales', '*.json')].sort

  def rel(path)
    path.sub("#{ROOT}/", '')
  end

  def read(path)
    File.read(path, encoding: 'UTF-8')
  end

  # ── Syntax ──────────────────────────────────────────────────────────────

  def test_all_ruby_files_have_valid_syntax
    refute_empty RUBY_FILES
    bad = RUBY_FILES.reject do |f|
      _out, _err, st = Open3.capture3(RbConfig.ruby, '-c', f)
      st.success?
    end
    assert_empty bad.map { |f| rel(f) }, 'syntax Ruby error'
  end

  def test_js_files_have_valid_syntax
    node = system('node --version', out: File::NULL, err: File::NULL)
    skip 'node tidak terpasang' unless node
    bad = JS_FILES.reject do |f|
      next true if File.zero?(f) || read(f).strip.empty?

      _out, _err, st = Open3.capture3('node', '--check', f)
      st.success?
    end
    assert_empty bad.map { |f| rel(f) }, 'syntax JS error'
  end

  def test_inline_html_scripts_have_valid_syntax
    node = system('node --version', out: File::NULL, err: File::NULL)
    skip 'node tidak terpasang' unless node
    bad = []
    HTML_FILES.each do |f|
      read(f).scan(%r{<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>}m).flatten.each_with_index do |code, i|
        next if code.strip.empty?

        tmp = File.join(Dir.tmpdir, "boosok_inline_#{File.basename(f)}_#{i}.js")
        File.write(tmp, code)
        _o, _e, st = Open3.capture3('node', '--check', tmp)
        File.delete(tmp)
        bad << "#{rel(f)} (script ##{i + 1})" unless st.success?
      end
    end
    assert_empty bad
  end

  # ── Aturan paket terenkripsi (sama dengan check_sketchup.ps1) ───────────

  ALLOWED_LOAD = %w[boosok_tools.rb updater.rb dev_reload.rb].freeze

  def test_no_require_relative_or_load_in_encrypted_package
    offenders = []
    RUBY_FILES.each do |f|
      next if ALLOWED_LOAD.include?(File.basename(f))

      read(f).each_line.with_index(1) do |line, n|
        offenders << "#{rel(f)}:#{n}: #{line.strip}" if line =~ /^\s*(require_relative|load)[\s(]/ ||
                                                          line =~ /\{\s*\|\w+\|\s*(require_relative|load)\b/ ||
                                                          (line =~ /Dir(\[|\.glob).*\.rb/ && line !~ /^\s*#/)
      end
    end
    assert_empty offenders, 'pakai BoosokTools.load_module / Sketchup.require tanpa ekstensi'
  end

  # ── Locale ──────────────────────────────────────────────────────────────

  def locale(code)
    JSON.parse(read(File.join(PLUGIN, 'locales', "#{code}.json")))
  end

  def test_locale_files_are_valid_json_with_required_fields
    refute_empty LOCALE_FILES
    LOCALE_FILES.each do |f|
      data = JSON.parse(read(f))
      assert_kind_of Hash, data['strings'], "#{rel(f)}: strings harus objek"
      assert_equal File.basename(f, '.json'), data['code'], "#{rel(f)}: code harus sama dengan nama file"
      refute_empty data['name'].to_s
    end
  end

  def test_locale_patterns_are_valid_regexes
    LOCALE_FILES.each do |f|
      (JSON.parse(read(f))['patterns'] || []).each do |p|
        Regexp.new(p['match'])
      rescue RegexpError => e
        flunk "#{rel(f)}: pattern #{p['match'].inspect} tidak valid (#{e.message})"
      end
    end
  end

  def test_en_and_id_have_same_keys
    en = locale('en')['strings'].keys
    id = locale('id')['strings'].keys
    assert_empty en - id, 'ada di en.json tapi tidak di id.json'
    assert_empty id - en, 'ada di id.json tapi tidak di en.json'
  end

  def test_no_empty_translations
    LOCALE_FILES.each do |f|
      empty = JSON.parse(read(f))['strings'].select { |_k, v| v.to_s.strip.empty? }.keys
      assert_empty empty, "#{rel(f)}: terjemahan kosong"
    end
  end

  def test_placeholders_match_between_languages
    en = locale('en')['strings']
    id = locale('id')['strings']
    mismatched = en.keys.select do |k|
      next false unless id[k]

      en[k].scan(/%\{\w+\}/).sort != id[k].scan(/%\{\w+\}/).sort
    end
    assert_empty mismatched, 'placeholder %{...} beda antara en dan id'
  end

  def test_every_data_i18n_key_in_html_exists_in_locales
    keys = locale('id')['strings'].keys | locale('en')['strings'].keys
    missing = []
    (HTML_FILES + JS_FILES).each do |f|
      read(f).scan(/data-i18n(?:-[a-z]+)?="([^"]+)"/).flatten.each do |k|
        missing << "#{rel(f)}: #{k}" unless keys.include?(k)
      end
    end
    assert_empty missing.uniq, 'kunci data-i18n tidak ada di locales/*.json'
  end

  def test_every_t_call_key_in_html_exists_in_locales
    keys = locale('id')['strings'].keys | locale('en')['strings'].keys
    missing = []
    (HTML_FILES + JS_FILES).each do |f|
      read(f).scan(/\bt\(\s*'([a-z0-9_]+)'/).flatten.each do |k|
        missing << "#{rel(f)}: #{k}" unless keys.include?(k)
      end
    end
    assert_empty missing.uniq, "kunci t('...') tidak ada di locales/*.json"
  end

  # ── HTML ⇄ Ruby ─────────────────────────────────────────────────────────

  def registered_callbacks
    RUBY_FILES.flat_map { |f| read(f).scan(/add_action_callback\(\s*["'](\w+)["']/).flatten }.uniq
  end

  # Didaftarkan lewat loop di titlebar.rb (`[...].each { |cb| add_action_callback(cb) }`), jadi tak terlihat regex.
  DYNAMIC_CALLBACKS = %w[closeDialog close_dialog close].freeze

  def test_every_literal_sketchup_call_from_html_has_a_ruby_callback
    registered = registered_callbacks + DYNAMIC_CALLBACKS
    missing = []
    (HTML_FILES + JS_FILES).each do |f|
      src = read(f)
      names = src.scan(/\bsketchup\.(\w+)\s*\(/).flatten + src.scan(/\bcall\(\s*'(\w+)'/).flatten
      optional = src.scan(/typeof\s+sketchup\.(\w+)/).flatten # fallback: dicek dulu sebelum dipanggil
      (names - optional).uniq.each do |n|
        next if %w[call apply].include?(n)

        missing << "#{rel(f)}: #{n}" unless registered.include?(n)
      end
    end
    assert_empty missing, 'dipanggil dari JS tapi tidak ada add_action_callback di Ruby'
  end

  def test_inline_event_handlers_refer_to_defined_functions
    js_all = JS_FILES.map { |f| read(f) }.join("\n")
    problems = []
    HTML_FILES.each do |f|
      html = read(f)
      defined = js_defined_names(html) + js_defined_names(js_all)
      html.scan(/\bon(?:click|change|input|keydown|submit|load)="\s*(?:return\s+)?([A-Za-z_]\w*)\s*\(/).flatten.uniq.each do |fn|
        problems << "#{rel(f)}: #{fn}()" unless defined.include?(fn)
      end
    end
    assert_empty problems, 'handler inline memanggil fungsi yang tidak didefinisikan'
  end

  # Ruby memanggil fungsi JS lewat execute_script: fungsinya harus ada di halaman (atau js/*.js).
  JS_BUILTINS = %w[if typeof function return JSON].freeze

  def js_defined_names(code)
    code.scan(/function\s+(\w+)/).flatten + code.scan(/(?:var|let|const)\s+(\w+)\s*=/).flatten +
      code.scan(/window\.(\w+)\s*=/).flatten
  end

  def test_ruby_execute_script_targets_exist_in_matching_html
    js_all = JS_FILES.map { |f| read(f) }.join("\n")
    problems = []
    RUBY_FILES.each do |rb|
      html_path = File.join(PLUGIN, 'html', "#{File.basename(rb, '.rb')}.html")
      next unless File.exist?(html_path)

      defined = js_defined_names(read(html_path)) + js_defined_names(js_all)
      read(rb).scan(/execute_script\(\s*"((?:[^"\\]|\\.)*)"/).flatten.each do |js|
        optional = js.scan(/typeof\s+(\w+)/).flatten # `if (typeof fn === 'function') fn(...)`
        js.gsub(/#\{.*?\}/, '').scan(/(?<![\w.])([A-Za-z_]\w*)\(/).flatten.uniq.each do |fn|
          next if JS_BUILTINS.include?(fn) || optional.include?(fn)

          problems << "#{rel(rb)}: #{fn}()" unless defined.include?(fn)
        end
      end
    end
    assert_empty problems.uniq, 'execute_script memanggil fungsi JS yang tidak ada di halaman'
  end

  # ── Rilis ───────────────────────────────────────────────────────────────

  def test_version_json_is_well_formed
    v = JSON.parse(read(File.join(ROOT, 'the_bosok', 'version.json')))
    assert_match(/\A\d+\.\d+\.\d+\z/, v['version'])
    assert_includes v['download_url'], "v#{v['version']}", 'download_url harus mengarah ke versi yang sama'
    assert_match(/\A\h{64}\z/, v['sha256'])
  end

  def test_extension_version_matches_version_json
    main = read(File.join(SRC, 'boosok_tools.rb'))
    ver = main[/VERSION\s*=\s*['"]([\d.]+)['"]/, 1] || main[/\.version\s*=\s*['"]([\d.]+)['"]/, 1]
    skip 'versi tidak ditemukan di boosok_tools.rb' unless ver
    json_ver = JSON.parse(read(File.join(ROOT, 'the_bosok', 'version.json')))['version']
    assert_equal json_ver, ver
  end
end
