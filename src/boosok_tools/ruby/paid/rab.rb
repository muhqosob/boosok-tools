require 'sketchup'
require 'json'
require 'set'
require 'zlib'
require 'cgi'
require 'tmpdir'
require 'fileutils'
Sketchup.require 'boosok_tools/ruby/titlebar'
Sketchup.require 'boosok_tools/ruby/locale' unless defined?(BoosokTools::Locale)
# Mode dev memuat ulang lewat load_module (hot reload); paket rilis memakai Sketchup.require. Tes tanpa SketchUp memuatnya sendiri.
RAB_PARTS = %w[rab_io rab_theme rab_schedule rab_pdf].freeze
if BoosokTools.respond_to?(:load_module)
  RAB_PARTS.each { |f| BoosokTools.load_module("ruby/paid/#{f}") }
else
  RAB_PARTS.each { |f| Sketchup.require "boosok_tools/ruby/paid/#{f}" }
end

# RAB (Rencana Anggaran Biaya): ukur volume dari model lalu kalikan dengan harga satuan pekerjaan (AHSP).
#   1. Scan   : hitung jumlah / panjang / luas / volume per tag (group, component, face, edge yang terlihat)
#   2. Mapping: tiap tag dipasangkan ke satu item AHSP (disimpan di model, bukan di plugin)
#   3. Hitung : volume x harga satuan, subtotal per divisi, PPN, total
#   4. Export : Excel (.xlsx, formula hidup) atau cetak ke PDF lewat browser
# Data AHSP/harga dasar: satu atau beberapa file JSON yang dipilih user per model (tab Sumber Data). Bawaan: data/ahsp_se47_2026.json
# (SE DJBK 47/2026, dibuat oleh tools/extract-ahsp) dan data/ahsp_starter.json; file milik user disimpan di folder data user.
# Harga yang diubah, komponen AHSP resmi yang diubah, dan analisa buatan sendiri disimpan per model (database aslinya tidak berubah).
module BoosokTools::Rab
  DICT = 'BoosokRAB'.freeze unless defined?(DICT)
  KEY = 'state'.freeze unless defined?(KEY)
  UNTAGGED_NAMES = %w[Untagged Layer0].freeze unless defined?(UNTAGGED_NAMES)
  UNTAGGED_KEY = 'Untagged'.freeze unless defined?(UNTAGGED_KEY)
  BASES = %w[auto count length area plane volume].freeze unless defined?(BASES)
  KINDS = %w[tag mat].freeze unless defined?(KINDS)

  # SketchUp menyimpan semua ukuran dalam inci
  IN = 0.0254 unless defined?(IN)
  IN2 = (0.0254**2) unless defined?(IN2)
  IN3 = (0.0254**3) unless defined?(IN3)

  # Satuan AHSP -> besaran yang diukur dari model. Satuan lain (mis. "10 kg", "ls") diisi manual.
  UNIT_BASIS = {
    'm3' => 'volume', 'm³' => 'volume',
    'm2' => 'area', 'm²' => 'area',
    'm' => 'length', 'm1' => 'length', 'mtr' => 'length',
    'bh' => 'count', 'buah' => 'count', 'unit' => 'count', 'titik' => 'count', 'ttk' => 'count',
    'set' => 'count', 'pcs' => 'count', 'lbr' => 'count', 'btg' => 'count', 'batang' => 'count', 'tunggul' => 'count'
  }.freeze unless defined?(UNIT_BASIS)

  def self.release_dialog
    @dialog = nil
  end

  def self.run
    Sketchup.require 'boosok_tools/hub' unless defined?(BoosokTools::Hub)
    BoosokTools::Hub.open_or_show('rab')
  end

  # ── Database AHSP: satu atau beberapa file JSON ───────────────────────────
  # Sumber bawaan ada di data/ (ikut plugin); sumber milik user disalin ke folder data user (tidak hilang saat plugin diperbarui).
  # Id sumber: "app/<nama>.json" (bawaan) atau "user/<nama>.json". Model hanya menyimpan daftar id yang dipakai.
  # Kalau beberapa sumber memuat kode yang sama, sumber yang lebih atas dalam urutan prioritas dipakai (milik user dulu, lalu bawaan).

  APP_SOURCES = %w[ahsp_se47_2026.json ahsp_starter.json].freeze unless defined?(APP_SOURCES)
  SOURCE_ID_RE = %r{\A(app|user)/[^/\\:*?"<>|]{1,120}\.json\z} unless defined?(SOURCE_ID_RE)
  MAX_SOURCES = 12 unless defined?(MAX_SOURCES)
  MAX_SOURCE_ITEMS = 30_000 unless defined?(MAX_SOURCE_ITEMS)
  # Kode analisa (U.001) dan harga dasar (C.001) buatan sendiri: tidak boleh dipakai file sumber
  RESERVED_AHSP_RE = /\AU\.\d{1,5}\z/ unless defined?(RESERVED_AHSP_RE)
  RESERVED_BASE_RE = /\AC\.\d{1,5}\z/ unless defined?(RESERVED_BASE_RE)
  BASE_JENIS = %w[upah bahan alat].freeze unless defined?(BASE_JENIS)

  def self.app_data_dir
    File.join(BoosokTools::SUPPORT_DIR, 'data')
  end

  def self.user_data_dir
    root = ENV['APPDATA'].to_s.dup.force_encoding('UTF-8').tr('\\', '/')
    root = File.join(Dir.home, 'Library', 'Application Support') if root.empty?
    File.join(root, 'BoosokTools', 'ahsp')
  end

  # Nama file .json di satu folder. Sengaja bukan Dir.glob: APPDATA di Windows berisi backslash (C:\Users\...) yang
  # dianggap karakter escape oleh pola glob, sehingga file yang sudah tersimpan tidak pernah ditemukan.
  def self.json_files(dir)
    Dir.children(dir).select { |f| f.downcase.end_with?('.json') && File.file?(File.join(dir, f)) }
  rescue SystemCallError
    []
  end

  def self.source_path(id)
    return nil unless id.to_s.match?(SOURCE_ID_RE)

    kind, file = id.split('/', 2)
    File.join(kind == 'app' ? app_data_dir : user_data_dir, file)
  end

  def self.app_source_ids
    APP_SOURCES.select { |f| File.exist?(File.join(app_data_dir, f)) }.map { |f| "app/#{f}" }
  end

  # Id sumber yang filenya ada, urut prioritas: milik user (abjad), lalu bawaan
  def self.available_source_ids
    user = json_files(user_data_dir).map { |f| "user/#{f}" }.select { |id| id.match?(SOURCE_ID_RE) }.sort
    user + app_source_ids
  end

  # Model lama (tanpa daftar sumber) tetap memakai satu file bawaan seperti sebelumnya
  def self.default_sources
    app_source_ids.first(1)
  end

  def self.normalize_sources(raw)
    return default_sources unless raw.is_a?(Array)

    ids = raw.select { |id| id.is_a?(String) && id.match?(SOURCE_ID_RE) }.uniq.first(MAX_SOURCES)
    ids.empty? ? default_sources : ids
  end

  # Id yang benar-benar dipakai menghitung: filenya ada dan terbaca, urut prioritas; kosong -> bawaan
  def self.effective_source_ids(selected)
    ids = available_source_ids.select { |id| selected.include?(id) && load_source(id)['data'] }
    ids.empty? ? default_sources : ids
  end

  def self.clean_kode(value)
    s = value.to_s.strip
    s.empty? || s.length > 40 || s.match?(/[[:cntrl:]]/) ? nil : s
  end

  def self.sanitize_base(list, info)
    seen = {}
    Array(list).first(MAX_SOURCE_ITEMS).filter_map do |b|
      kode = b.is_a?(Hash) ? clean_kode(b['kode']) : nil
      nama = b.is_a?(Hash) ? clean_text(b['nama'], 160) : ''
      if kode.nil? || nama.empty? || !BASE_JENIS.include?(b['jenis']) || seen[kode]
        info['skipped'] += 1
        next
      end
      if kode.match?(RESERVED_BASE_RE)
        info['reserved'] += 1
        next
      end
      seen[kode] = true
      item = { 'kode' => kode, 'jenis' => b['jenis'], 'nama' => nama, 'satuan' => clean_text(b['satuan'], 16),
               'harga' => [num(b['harga'], 0.0), 0.0].max }
      sumber = clean_text(b['sumber_harga'], 160)
      item['sumber_harga'] = sumber unless sumber.empty?
      item
    end
  end

  def self.sanitize_ahsp(list, info)
    seen = {}
    list.first(MAX_SOURCE_ITEMS).filter_map do |a|
      kode = a.is_a?(Hash) ? clean_kode(a['kode']) : nil
      uraian = a.is_a?(Hash) ? clean_text(a['uraian'], 240) : ''
      if kode.nil? || uraian.empty? || seen[kode]
        info['skipped'] += 1
        next
      end
      if kode.match?(RESERVED_AHSP_RE)
        info['reserved'] += 1
        next
      end
      seen[kode] = true
      divisi = clean_text(a['divisi'], 120)
      comps = Array(a['komponen']).first(MAX_CUSTOM_COMPS * 2).filter_map do |c|
        k = c.is_a?(Hash) ? clean_kode(c['kode']) : nil
        koef = c.is_a?(Hash) ? num(c['koef'], 0.0) : 0.0
        { 'kode' => k, 'koef' => koef } if k && koef.positive?
      end
      item = { 'kode' => kode, 'divisi' => divisi.empty? ? 'Lainnya' : divisi, 'kategori' => clean_text(a['kategori'], 120),
               'uraian' => uraian, 'satuan' => clean_text(a['satuan'], 16), 'komponen' => comps }
      %w[keyakinan acuan catatan].each do |f|
        v = clean_text(a[f], 400)
        item[f] = v unless v.empty?
      end
      item
    end
  end

  def self.sanitize_meta(raw)
    meta = {}
    return meta unless raw.is_a?(Hash)

    %w[nama versi sumber mata_uang catatan_harga].each { |f| meta[f] = clean_text(raw[f], 400) if raw[f].is_a?(String) }
    %w[overhead_profit_persen ppn_persen].each { |f| meta[f] = num(raw[f], nil) if raw[f] }
    meta['harga'] = raw['harga'] if raw['harga'].is_a?(Hash)
    meta
  end

  # Bersihkan isi satu file sumber. Return [data_bersih, info]; data nil kalau bukan format AHSP.
  def self.sanitize_source(raw)
    info = { 'skipped' => 0, 'reserved' => 0 }
    return [nil, info] unless raw.is_a?(Hash) && raw['ahsp'].is_a?(Array)

    data = { 'meta' => sanitize_meta(raw['meta']), 'harga_dasar' => sanitize_base(raw['harga_dasar'], info),
             'ahsp' => sanitize_ahsp(raw['ahsp'], info) }
    [data, info]
  end

  # Isi satu sumber (sudah dibersihkan), dibaca ulang kalau filenya berubah (hot reload / user mengedit file).
  # Hasil: { 'data'=>, 'info'=>, 'mtime'=> } atau { 'error'=> 'path'|'json'|'format' }
  def self.load_source(id)
    path = source_path(id)
    return { 'error' => 'path' } unless path && File.exist?(path)

    mtime = File.mtime(path)
    @sources ||= {}
    cached = @sources[path]
    return cached if cached && cached['mtime'] == mtime

    entry = begin
      data, info = sanitize_source(JSON.parse(File.read(path, encoding: 'UTF-8').sub(/\A\uFEFF/, '')))
      data ? { 'data' => data, 'info' => info } : { 'error' => 'format' }
    rescue StandardError => e
      puts "[Boosok RAB] baca #{id}: #{e.class}: #{e.message}" unless e.is_a?(JSON::ParserError)
      { 'error' => 'json' }
    end
    @sources[path] = entry.merge('mtime' => mtime, 'path' => path)
  end

  # Gabungan sumber (urut prioritas). Kode yang sudah ada dilewati; komponen yang tak punya harga dasar dibuang.
  def self.combined_db(ids)
    loaded = ids.map { |id| [id, load_source(id)] }.select { |_id, s| s['data'] }
    key = loaded.map { |_id, s| [s['path'], s['mtime']] }
    return @combined if @combined && @combined_key == key

    base = {}
    ahsp = {}
    loaded.each do |_id, s|
      s['data']['harga_dasar'].each { |b| base[b['kode']] ||= b }
      s['data']['ahsp'].each { |a| ahsp[a['kode']] ||= a }
    end
    ahsp = ahsp.values.map do |a|
      comps = a['komponen'].select { |c| base.key?(c['kode']) }
      comps.size == a['komponen'].size ? a : a.merge('komponen' => comps)
    end
    metas = loaded.map { |_id, s| s['data']['meta'] }
    meta = (metas.first || {}).dup
    if metas.size > 1
      meta['nama'] = metas.map { |m| m['nama'].to_s }.reject(&:empty?).join(' + ')
      meta['sumber'] = metas.map { |m| m['sumber'].to_s }.reject(&:empty?).uniq.join('; ')
    end
    @combined_key = key
    @combined = { 'meta' => meta, 'harga_dasar' => base.values, 'ahsp' => ahsp }
  end

  # ── Daftar harga: file terpisah dari analisa ──────────────────────────────
  # Satu file = daftar { kode?, jenis?, nama, satuan, harga }. Disalin ke folder harga user (id "harga/<nama>.json") dan
  # dicocokkan ke harga dasar database AHSP: lewat kode (+ nama), lalu nama + satuan. Yang cocok mengganti harga bawaan
  # file AHSP; harga yang diketik user per model tetap paling atas. Urutan: file yang lebih atas menang.

  PRICE_ID_RE = %r{\Aharga/[^/\\:*?"<>|]{1,120}\.json\z} unless defined?(PRICE_ID_RE)
  UNIT_ALIAS = { 'hari' => 'oh', 'jam' => 'oj' }.freeze unless defined?(UNIT_ALIAS)

  def self.price_data_dir
    File.join(File.dirname(user_data_dir), 'harga')
  end

  def self.price_path(id)
    id.to_s.match?(PRICE_ID_RE) ? File.join(price_data_dir, id.split('/', 2).last) : nil
  end

  def self.available_price_ids
    json_files(price_data_dir).map { |f| "harga/#{f}" }.select { |id| id.match?(PRICE_ID_RE) }.sort
  end

  def self.normalize_price_sources(raw)
    return [] unless raw.is_a?(Array)

    raw.select { |id| id.is_a?(String) && id.match?(PRICE_ID_RE) }.uniq.first(MAX_SOURCES)
  end

  # Hasil: { 'data' => { 'meta', 'items' }, 'mtime', 'path' } atau { 'error' => 'path'|'json'|'format' }
  def self.load_price_source(id)
    path = price_path(id)
    return { 'error' => 'path' } unless path && File.exist?(path)

    mtime = File.mtime(path)
    @price_files ||= {}
    cached = @price_files[path]
    return cached if cached && cached['mtime'] == mtime

    entry = begin
      data = BoosokTools::RabIo.sanitize_prices(JSON.parse(File.read(path, encoding: 'UTF-8').sub(/\A﻿/, '')))
      data ? { 'data' => data } : { 'error' => 'format' }
    rescue StandardError => e
      puts "[Boosok RAB] baca #{id}: #{e.class}: #{e.message}" unless e.is_a?(JSON::ParserError)
      { 'error' => 'json' }
    end
    @price_files[path] = entry.merge('mtime' => mtime, 'path' => path)
  end

  def self.effective_price_ids(selected)
    available_price_ids.select { |id| selected.include?(id) && load_price_source(id)['data'] }
  end

  def self.norm_name(text)
    text.to_s.downcase.gsub(/\s+/, ' ').strip
  end

  def self.norm_unit(text)
    u = text.to_s.downcase.tr('³²', '32').delete(' .')
    UNIT_ALIAS.fetch(u, u)
  end

  # [per_kode, per_nama_satuan] untuk harga dasar database (dihitung sekali per database)
  def self.price_index(database)
    return @price_idx if @price_idx_db.equal?(database)

    by_kode = {}
    by_name = {}
    database['harga_dasar'].each do |h|
      by_kode[h['kode']] = h
      by_name[[norm_name(h['nama']), norm_unit(h['satuan'])]] ||= h
    end
    @price_idx_db = database
    @price_idx = [by_kode, by_name]
  end

  # Harga dasar yang dimaksud satu baris file harga, atau nil
  def self.match_price_item(item, index)
    by_kode, by_name = index
    b = item['kode'] && by_kode[item['kode']]
    return b if b && (item['nama'].to_s.empty? || norm_name(b['nama']) == norm_name(item['nama']))

    m = by_name[[norm_name(item['nama']), norm_unit(item['satuan'])]]
    return m if m

    b && !item['satuan'].to_s.empty? && norm_unit(b['satuan']) == norm_unit(item['satuan']) ? b : nil # nama diubah di Excel, kode & satuan tetap
  end

  def self.price_label(id, source)
    source['data']['meta']['nama'] || File.basename(id, '.json')
  end

  # Terapkan file harga yang aktif ke database (hasilnya objek baru; database aslinya tidak diubah)
  def self.apply_price_sources(database, ids)
    files = ids.filter_map { |id| (s = load_price_source(id))['data'] ? [id, s] : nil }
    return database if files.empty?

    key = files.map { |_id, s| [s['path'], s['mtime']] }
    return @priced if @priced && @priced_from.equal?(database) && @priced_key == key

    index = price_index(database)
    assigned = {}
    files.each do |id, s|
      label = price_label(id, s)
      s['data']['items'].each do |it|
        b = match_price_item(it, index)
        assigned[b['kode']] ||= [it['harga'], label] if b
      end
    end
    base = database['harga_dasar'].map do |h|
      a = assigned[h['kode']]
      a ? h.merge('harga' => a[0], 'sumber_harga' => a[1]) : h
    end
    metas = files.map { |_id, s| s['data']['meta'] }
    harga = { 'wilayah' => (metas.map { |m| m['wilayah'] }.compact.uniq.join(', ').then { |w| w.empty? ? files.map { |id, s| price_label(id, s) }.join(', ') : w }),
              'tahun_data' => metas.map { |m| m['tahun'] }.compact.first || '-',
              'terisi' => base.count { |h| h['harga'].to_f.positive? }, 'dari' => base.size }
    @priced_key = key
    @priced_from = database
    @priced = database.merge('harga_dasar' => base, 'meta' => (database['meta'] || {}).merge('harga' => harga))
  end

  # Database untuk state ini: sumber AHSP yang dipilih model + daftar harga yang aktif
  def self.state_db(state)
    base = combined_db(effective_source_ids(state['sources'] || default_sources))
    apply_price_sources(base, effective_price_ids(state['price_sources'] || []))
  end

  def self.db
    combined_db(effective_source_ids(default_sources))
  end

  # Ringkasan sumber untuk tab "Sumber Data"
  def self.sources_payload(state)
    avail = available_source_ids
    active = effective_source_ids(state['sources'])
    items = avail.map do |id|
      s = load_source(id)
      row = { 'id' => id, 'kind' => id.start_with?('app/') ? 'app' : 'user', 'file' => id.split('/', 2).last,
              'active' => active.include?(id), 'error' => s['error'] }
      if s['data']
        m = s['data']['meta']
        row.merge!('nama' => m['nama'].to_s, 'versi' => m['versi'].to_s, 'sumber' => m['sumber'].to_s,
                   'ahsp' => s['data']['ahsp'].size, 'base' => s['data']['harga_dasar'].size,
                   'skipped' => s['info']['skipped'], 'reserved' => s['info']['reserved'])
      end
      row
    end
    { 'items' => items, 'missing' => state['sources'] - avail, 'prices' => price_sources_payload(state, combined_db(active)) }
  end

  def self.price_sources_payload(state, database)
    avail = available_price_ids
    active = effective_price_ids(state['price_sources'])
    index = price_index(database)
    items = avail.map do |id|
      s = load_price_source(id)
      row = { 'id' => id, 'file' => id.split('/', 2).last, 'active' => active.include?(id), 'error' => s['error'] }
      if s['data']
        m = s['data']['meta']
        row.merge!('nama' => price_label(id, s), 'wilayah' => m['wilayah'].to_s, 'tahun' => m['tahun'].to_s, 'sumber' => m['sumber'].to_s,
                   'items' => s['data']['items'].size, 'matched' => s['data']['items'].count { |it| match_price_item(it, index) })
      end
      row
    end
    { 'items' => items, 'missing' => state['price_sources'] - avail }
  end

  def self.unit_basis(satuan)
    UNIT_BASIS[satuan.to_s.strip.downcase] || 'manual'
  end

  # Daftar item AHSP untuk dropdown di dialog
  def self.catalog(database = db)
    database['ahsp'].map do |a|
      { 'kode' => a['kode'], 'divisi' => a['divisi'], 'kategori' => a['kategori'].to_s, 'uraian' => a['uraian'],
        'satuan' => a['satuan'], 'basis' => unit_basis(a['satuan']), 'keyakinan' => a['keyakinan'] }
    end
  end

  # Komponen asli tiap AHSP, ringkas: { kode => [[kode_komponen, koef], ...] } (untuk pratinjau & ubah di dialog)
  def self.ahsp_comps(database = db)
    database['ahsp'].to_h { |a| [a['kode'], a['komponen'].map { |c| [c['kode'], c['koef']] }] }
  end

  # ── State (disimpan di model) ─────────────────────────────────────────────

  def self.num(value, default)
    f = Float(value)
    f.finite? ? f : default
  rescue StandardError
    default
  end

  # Kunci baris RAB = sumber + nama: "tag:Brick" atau "mat:Cat Putih". Kunci lama tanpa awalan dianggap tag.
  def self.make_key(kind, name)
    "#{kind}:#{name}"
  end

  def self.normalize_key(key)
    key = key.to_s
    KINDS.any? { |k| key.start_with?("#{k}:") } ? key : make_key('tag', key)
  end

  def self.split_key(key)
    kind, name = key.split(':', 2)
    [kind, name.to_s]
  end

  # ── Analisa & harga dasar buatan sendiri ──────────────────────────────────
  # Disimpan di state model (ikut file .skp). AHSP sendiri berkode U.001 dst, harga dasar sendiri C.001 dst,
  # supaya tidak pernah bentrok dengan kode database resmi. Komponennya boleh memakai harga dasar resmi maupun sendiri.

  CUSTOM_DIVISI = '00. Analisa Saya'.freeze unless defined?(CUSTOM_DIVISI)
  CUSTOM_JENIS = %w[upah bahan alat].freeze unless defined?(CUSTOM_JENIS)
  MAX_CUSTOM_AHSP = 500 unless defined?(MAX_CUSTOM_AHSP)
  MAX_CUSTOM_BASE = 1000 unless defined?(MAX_CUSTOM_BASE)
  MAX_CUSTOM_COMPS = 100 unless defined?(MAX_CUSTOM_COMPS)
  CUSTOM_FORMAT = 'boosok-rab-analisa'.freeze unless defined?(CUSTOM_FORMAT)

  def self.blank_custom
    { 'ahsp' => [], 'base' => [] }
  end

  def self.clean_text(value, max)
    value.to_s.gsub(/[[:cntrl:]]+/, ' ').strip[0, max].to_s
  end

  # Pisahkan komponen [{kode, koef}] jadi yang kodenya dikenal (known: Set) dan yang belum (mis. sumber datanya sedang tidak dipakai).
  # Yang belum dikenal TIDAK dibuang, disimpan terpisah supaya pulih saat sumbernya aktif lagi.
  def self.split_comps(list, known)
    resolved = []
    held = []
    list.each do |c|
      kode = c.is_a?(Hash) ? clean_kode(c['kode']) : nil
      koef = c.is_a?(Hash) ? num(c['koef'], 0.0) : 0.0
      next unless kode && koef.positive?

      (known.include?(kode) ? resolved : held) << { 'kode' => kode, 'koef' => koef }
    end
    [resolved.first(MAX_CUSTOM_COMPS), held.first(MAX_CUSTOM_COMPS)]
  end

  def self.custom_empty?(custom)
    !custom.is_a?(Hash) || (custom['ahsp'].to_a.empty? && custom['base'].to_a.empty?)
  end

  # Bersihkan data buatan user: kode tak valid / dobel / bentrok dibuang, nama kosong dibuang, komponen tak dikenal dibuang.
  def self.normalize_custom(raw, database = db)
    raw = {} unless raw.is_a?(Hash)
    taken = database['harga_dasar'].map { |h| h['kode'] }
    base = []
    Array(raw['base']).first(MAX_CUSTOM_BASE).each do |b|
      next unless b.is_a?(Hash) && b['kode'].to_s.match?(/\AC\.\d{1,5}\z/) && !taken.include?(b['kode'])

      nama = clean_text(b['nama'], 120)
      next if nama.empty?

      satuan = clean_text(b['satuan'], 12)
      taken << b['kode']
      base << { 'kode' => b['kode'], 'jenis' => CUSTOM_JENIS.include?(b['jenis']) ? b['jenis'] : 'bahan', 'nama' => nama,
                'satuan' => satuan.empty? ? 'ls' : satuan, 'harga' => [num(b['harga'], 0.0), 0.0].max }
    end

    known = taken.to_set
    ahsp_taken = database['ahsp'].map { |a| a['kode'] }
    ahsp = []
    Array(raw['ahsp']).first(MAX_CUSTOM_AHSP).each do |a|
      next unless a.is_a?(Hash) && a['kode'].to_s.match?(/\AU\.\d{1,5}\z/) && !ahsp_taken.include?(a['kode'])

      uraian = clean_text(a['uraian'], 200)
      next if uraian.empty?

      comps, held = split_comps(Array(a['komponen']) + Array(a['hold_komponen']), known)
      satuan = clean_text(a['satuan'], 12)
      item = { 'kode' => a['kode'], 'uraian' => uraian, 'satuan' => satuan.empty? ? 'ls' : satuan, 'komponen' => comps }
      item['hold_komponen'] = held unless held.empty?
      kategori = clean_text(a['kategori'], 80)
      catatan = clean_text(a['catatan'], 400)
      item['kategori'] = kategori unless kategori.empty?
      item['catatan'] = catatan unless catatan.empty?
      ahsp_taken << a['kode']
      ahsp << item
    end
    { 'ahsp' => ahsp, 'base' => base }
  end

  # Database efektif = database resmi + data buatan user (analisa sendiri tampil paling atas di divisi "00. Analisa Saya")
  def self.merge_custom(database, custom)
    return database if custom_empty?(custom)

    base = custom['base'].map { |b| b.merge('sumber_harga' => 'Analisa saya') }
    ahsp = custom['ahsp'].map { |a| { 'divisi' => CUSTOM_DIVISI, 'kategori' => '', 'keyakinan' => 'sendiri' }.merge(a) }
    database.merge('harga_dasar' => database['harga_dasar'] + base, 'ahsp' => ahsp + database['ahsp'])
  end

  # Komponen AHSP resmi yang diubah user, per kode AHSP: { "1.3.1.2" => { "komponen" => [{kode, koef}], "hold_komponen" => [...] } }.
  # Disimpan di model; database resminya sendiri tidak pernah diubah. Override yang AHSP-nya belum ada (sumber tidak dipakai)
  # disimpan di hold, dan dipulihkan saat sumbernya dipakai lagi.
  MAX_OVERRIDES = 2000 unless defined?(MAX_OVERRIDES)

  def self.normalize_overrides(raw, held_raw, database, merged)
    ahsp_kodes = database['ahsp'].to_set { |a| a['kode'] }
    known = merged['harga_dasar'].to_set { |h| h['kode'] }
    pool = {}
    [held_raw, raw].each { |src| src.each { |kode, o| pool[kode.to_s] = o if o.is_a?(Hash) } if src.is_a?(Hash) }
    out = {}
    hold = {}
    pool.first(MAX_OVERRIDES).each do |kode, o|
      next unless clean_kode(kode)

      comps, held = split_comps(Array(o['komponen']) + Array(o['hold_komponen']), known)
      if ahsp_kodes.include?(kode)
        out[kode] = { 'komponen' => comps }
        out[kode]['hold_komponen'] = held unless held.empty?
      else
        hold[kode] = { 'komponen' => comps + held }
      end
    end
    [out, hold]
  end

  def self.apply_overrides(database, overrides)
    return database if overrides.nil? || overrides.empty?

    ahsp = database['ahsp'].map do |a|
      o = overrides[a['kode']]
      o ? a.merge('komponen' => o['komponen'], 'diubah' => true) : a
    end
    database.merge('ahsp' => ahsp)
  end

  # Database efektif satu model = resmi + analisa/harga buatan sendiri + komponen resmi yang diubah
  def self.effective_db(database, state)
    apply_overrides(merge_custom(database, state['custom']), state['overrides'])
  end

  # Isi file ekspor analisa sendiri. Komponen resmi ikut membawa nama/satuan supaya bisa dicocokkan ulang
  # kalau kode database di komputer lain berbeda.
  def self.export_custom(custom, database = db)
    merged = merge_custom(database, custom)
    base_by_kode = merged['harga_dasar'].to_h { |h| [h['kode'], h] }
    ahsp = custom['ahsp'].map do |a|
      a.merge('komponen' => a['komponen'].map do |c|
        b = base_by_kode[c['kode']]
        { 'kode' => c['kode'], 'koef' => c['koef'], 'nama' => b['nama'], 'satuan' => b['satuan'], 'jenis' => b['jenis'] }
      end)
    end
    { 'format' => CUSTOM_FORMAT, 'versi' => 1, 'dibuat' => Time.now.strftime('%Y-%m-%d'), 'ahsp' => ahsp, 'base' => custom['base'] }
  end

  def self.next_custom_number(list)
    list.map { |x| x['kode'].to_s[/\d+\z/].to_i }.max.to_i + 1
  end

  # Gabungkan hasil ekspor ke data saat ini. Kode U./C. diberi nomor baru; komponen resmi dicocokkan lewat kode+nama,
  # lalu nama+satuan; yang tidak ketemu dibuat jadi harga dasar sendiri (harga 0). Return [custom_baru, info].
  def self.import_custom(current, data, database = db)
    info = { 'ahsp' => 0, 'base' => 0, 'diganti' => 0 }
    return [current, info] unless data.is_a?(Hash) && data['format'] == CUSTOM_FORMAT

    base = current['base'].map(&:dup)
    ahsp = current['ahsp'].map(&:dup)
    official = database['harga_dasar']
    by_kode = official.to_h { |h| [h['kode'], h] }
    by_name = official.to_h { |h| [[h['nama'].to_s.downcase, h['satuan'].to_s.downcase], h] }
    imported_base = Array(data['base']).select { |b| b.is_a?(Hash) }.to_h { |b| [b['kode'], b] }
    base_map = {}

    add_base = lambda do |nama, satuan, jenis, harga|
      found = base.find { |b| b['nama'].downcase == nama.to_s.downcase && b['satuan'].downcase == satuan.to_s.downcase && b['jenis'] == jenis }
      return found['kode'] if found

      kode = format('C.%03d', next_custom_number(base))
      base << { 'kode' => kode, 'jenis' => jenis, 'nama' => nama.to_s, 'satuan' => satuan.to_s, 'harga' => harga }
      info['base'] += 1
      kode
    end

    resolve = lambda do |c|
      kode = c['kode'].to_s
      if kode.start_with?('C.')
        b = imported_base[kode]
        return nil unless b

        return base_map[kode] ||= add_base.call(b['nama'], b['satuan'], CUSTOM_JENIS.include?(b['jenis']) ? b['jenis'] : 'bahan', num(b['harga'], 0.0))
      end

      off = by_kode[kode]
      return kode if off && off['nama'].to_s.downcase == c['nama'].to_s.downcase
      return kode if off && c['nama'].to_s.empty?

      match = by_name[[c['nama'].to_s.downcase, c['satuan'].to_s.downcase]]
      if match
        info['diganti'] += 1
        return match['kode']
      end
      return nil if c['nama'].to_s.strip.empty?

      add_base.call(c['nama'], c['satuan'].to_s.empty? ? 'ls' : c['satuan'], CUSTOM_JENIS.include?(c['jenis']) ? c['jenis'] : 'bahan', 0.0)
    end

    Array(data['ahsp']).first(MAX_CUSTOM_AHSP).each do |a|
      next unless a.is_a?(Hash)

      comps = Array(a['komponen']).filter_map do |c|
        next unless c.is_a?(Hash)

        kode = resolve.call(c)
        { 'kode' => kode, 'koef' => c['koef'] } if kode
      end
      ahsp << a.merge('kode' => format('U.%03d', next_custom_number(ahsp)), 'komponen' => comps)
      info['ahsp'] += 1
    end
    [normalize_custom({ 'ahsp' => ahsp, 'base' => base }, database), info]
  end

  # Bersihkan state dari dialog / model: tipe dipaksa benar, kode tak dikenal dibuang.
  MAX_HOLD = 5000 unless defined?(MAX_HOLD)

  # database: kalau tidak diberikan, dibentuk dari sumber yang dipilih state. Pilihan user yang kodenya tidak ada di
  # database saat ini (sumber dimatikan / file tidak ada di komputer ini) tidak dibuang: disimpan di 'hold' dan pulih sendiri.
  def self.normalize_state(raw, database = nil)
    raw = {} unless raw.is_a?(Hash)
    sources = normalize_sources(raw['sources'])
    price_sources = normalize_price_sources(raw['price_sources'])
    theme = raw['theme'].is_a?(String) && raw['theme'].match?(BoosokTools::RabTheme::THEME_ID_RE) ? raw['theme'] : BoosokTools::RabTheme::DEFAULT_ID
    database ||= combined_db(effective_source_ids(sources))
    held = raw['hold'].is_a?(Hash) ? raw['hold'] : {}
    custom = normalize_custom(raw['custom'], database)
    merged = merge_custom(database, custom)
    overrides, hold_over = normalize_overrides(raw['overrides'], held['overrides'], database, merged)
    database = apply_overrides(merged, overrides)
    kodes = database['ahsp'].to_set { |a| a['kode'] }
    base_kodes = database['harga_dasar'].to_set { |h| h['kode'] }

    map = {}
    hold_map = {}
    [held['map'], raw['map']].each do |src|
      next unless src.is_a?(Hash)

      src.first(MAX_HOLD).each do |key, e|
        kode = e.is_a?(Hash) ? clean_kode(e['kode']) : nil
        next unless kode

        factor = num(e['factor'], 1.0)
        entry = {
          'kode' => kode,
          'basis' => BASES.include?(e['basis']) ? e['basis'] : 'auto',
          'factor' => factor.positive? ? factor : 1.0,
          'manual' => num(e['manual'], nil)
        }
        key = normalize_key(key)
        if kodes.include?(kode)
          hold_map.delete(key)
          map[key] = entry
        else
          map.delete(key)
          hold_map[key] = entry
        end
      end
    end

    prices = {}
    hold_prices = {}
    [held['prices'], raw['prices']].each do |src|
      next unless src.is_a?(Hash)

      src.first(MAX_HOLD).each do |kode, price|
        p = num(price, nil)
        next unless p && p >= 0 && clean_kode(kode)

        if base_kodes.include?(kode)
          hold_prices.delete(kode)
          prices[kode] = p
        else
          prices.delete(kode)
          hold_prices[kode] = p
        end
      end
    end

    meta = database['meta'] || {}
    {
      'map' => map,
      'prices' => prices,
      'op' => num(raw['op'], meta['overhead_profit_persen'] || 10).clamp(0, 100),
      'ppn' => num(raw['ppn'], meta['ppn_persen'] || 11).clamp(0, 100),
      'ppn_on' => raw.key?('ppn_on') ? raw['ppn_on'] == true : true,
      'custom' => custom,
      'sources' => sources,
      'price_sources' => price_sources,
      'theme' => theme,
      'weeks' => BoosokTools::RabSchedule.weeks(raw['weeks']),
      'info' => normalize_info(raw['info']),
      'info_date' => raw.key?('info_date') ? raw['info_date'] == true : true,
      'overrides' => overrides,
      'hold' => { 'map' => hold_map, 'prices' => hold_prices, 'overrides' => hold_over }
    }
  end

  MAX_INFO = 20 unless defined?(MAX_INFO)

  # Data pekerjaan di kepala dokumen: daftar { label, value } bebas (urutan dipertahankan). nil = belum pernah diatur
  # (dokumen memakai baris "Proyek : <judul model>"); [] = sengaja dikosongkan.
  def self.normalize_info(raw)
    return nil unless raw.is_a?(Array)

    raw.first(MAX_INFO).filter_map do |e|
      next unless e.is_a?(Hash)

      label = e['label'].to_s.gsub(/\s+/, ' ').strip[0, 60]
      value = e['value'].to_s.gsub(/\s+/, ' ').strip[0, 300]
      { 'label' => label, 'value' => value } unless label.empty? && value.empty?
    end
  end

  def self.load_state(model)
    raw = begin
      JSON.parse(model.get_attribute(DICT, KEY, '{}').to_s)
    rescue StandardError
      {}
    end
    normalize_state(raw)
  end

  def self.save_state(model, state)
    model.set_attribute(DICT, KEY, JSON.generate(state))
  end

  # ── Scan model ────────────────────────────────────────────────────────────

  # count   : jumlah group/component | face (untuk sumber material)
  # area    : jumlah luas SEMUA face     plane : luas satu sisi utama solid (lihat plane_area)
  def self.blank_measure
    { 'count' => 0, 'length' => 0.0, 'area' => 0.0, 'plane' => 0.0, 'volume' => 0.0, 'nonsolid' => 0 }
  end

  def self.untagged?(name)
    UNTAGGED_NAMES.include?(name.to_s)
  end

  # Objek tersembunyi dan objek di tag yang dimatikan tidak dihitung (mis. sumber Void yang disembunyikan).
  def self.counted?(ent)
    return false if ent.respond_to?(:hidden?) && ent.hidden?

    layer = ent.respond_to?(:layer) ? ent.layer : nil
    layer.nil? || layer.visible?
  end

  def self.entities_of(ent)
    ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
  end

  # Volume (inci kubik) kalau solid, selain itu nil
  def self.solid_volume(ent)
    v = ent.volume
    v && v > 0 ? v : nil
  rescue StandardError
    nil
  end

  # Faktor pembesaran volume dari transformasi induk (group di dalam group yang di-scale)
  # = |determinan| bagian 3x3 matriks (x . (y x z)); Transformation#to_a berisi 16 angka kolom-demi-kolom.
  def self.volume_scale(tr)
    m = tr.to_a
    x = m[0, 3]
    y = m[4, 3]
    z = m[8, 3]
    ((x[0] * ((y[1] * z[2]) - (y[2] * z[1]))) -
      (x[1] * ((y[0] * z[2]) - (y[2] * z[0]))) +
      (x[2] * ((y[0] * z[1]) - (y[1] * z[0])))).abs
  rescue StandardError
    1.0
  end

# Luas satu sisi utama sebuah solid dari daftar face [[nx, ny, nz, luas_m2], ...] (normal dunia).
# Face dikelompokkan per arah normal (arah berlawanan digabung); kelompok terbesar dibagi 2 = luas satu sisi.
# Cocok untuk dinding/pelat/lapisan tipis. Lubang (pintu/jendela) sudah mengurangi luas face-nya.
def self.plane_area(faces)
  groups = Hash.new(0.0)
  faces.each do |nx, ny, nz, area|
    len = Math.sqrt((nx * nx) + (ny * ny) + (nz * nz))
    next if len < 1e-9

    v = [nx / len, ny / len, nz / len]
    lead = v.find { |c| c.abs > 1e-6 }
    v = v.map { |c| -c } if lead && lead < 0
    groups[v.map { |c| c.round(2) + 0.0 }] += area
  end
  groups.empty? ? 0.0 : groups.values.max / 2.0
end

# Ukur seluruh model. Hasil: { "tag:Brick" => {...}, "mat:Cat Putih" => {...} } dalam satuan SI (m, m2, m3).
#   Sumber TAG
#     count    : group/component yang tag-nya SENDIRI = tag itu (yang paling luar saja kalau bersarang)
#     volume   : tiap group/component yang punya face sendiri dan solid, ke tag terdekat ke atas. Group pembungkus
#                (isinya cuma group lain) tidak dihitung, jadi tag induk dan tag anak tidak tumpang tindih.
#     plane    : luas satu sisi utama dari solid-solid itu (plane_area)
#     area/length : semua face / edge lepas dengan tag terdekat ke atas (face tanpa tag ikut tag group-nya)
#   Sumber MATERIAL (material sisi depan face, atau material group kalau face belum dicat)
#     area, count(face) : luas face yang bermaterial itu, tanpa double hitung sisi lain solid
def self.scan(model)
  acc = Hash.new { |h, k| h[k] = blank_measure }
  walk(model.entities, Geom::Transformation.new, UNTAGGED_KEY, [], nil, acc, nil) # rubocop:disable SketchupSuggestions/ModelEntities -- seluruh model
  acc
end

def self.tag_of(ent, inherited)
  name = ent.layer.name
  untagged?(name) ? inherited : name
end

def self.normal_world(face, tr)
  n = face.normal.transform(tr)
  [n.x, n.y, n.z]
end

# Volume + luas bidang satu group/component yang punya face sendiri; non-solid dicatat sebagai peringatan.
def self.measure_solid(ent, tr, key, faces, acc)
  m = acc[key]
  vol = solid_volume(ent)
  if vol
    m['volume'] += vol * volume_scale(tr) * IN3
    m['plane'] += plane_area(faces)
  else
    m['nonsolid'] += 1
  end
end

# ents: isi yang diukur | tr: transformasi isi itu ke dunia | inherited: tag terdekat ke atas
# owners: tag eksplisit di rantai induk | inherited_mat: material group terdekat ke atas
# faces_out: wadah face LANGSUNG milik container ini (nil di level model)
def self.walk(ents, tr, inherited, owners, inherited_mat, acc, faces_out)
  ents.each do |e|
    next unless e.valid?

    case e
    when Sketchup::Face
      next unless counted?(e)

      area = e.area(tr) * IN2
      acc[make_key('tag', tag_of(e, inherited))]['area'] += area
      faces_out << (normal_world(e, tr) + [area]) if faces_out
      mat = e.material ? e.material.name : inherited_mat
      if mat
        m = acc[make_key('mat', mat)]
        m['area'] += area
        m['count'] += 1
      end
    when Sketchup::Edge
      next unless counted?(e) && e.faces.empty?

      len = (tr * e.start.position).distance(tr * e.end.position)
      acc[make_key('tag', tag_of(e, inherited))]['length'] += len * IN
    when Sketchup::Group, Sketchup::ComponentInstance
      next unless counted?(e)

      explicit = !untagged?(e.layer.name)
      tag = explicit ? e.layer.name : inherited
      key = make_key('tag', tag)
      acc[key]['count'] += 1 if explicit && !owners.include?(tag)
      own_faces = []
      walk(entities_of(e), tr * e.transformation, tag, explicit ? owners + [tag] : owners,
           e.material ? e.material.name : inherited_mat, acc, own_faces)
      measure_solid(e, tr, key, own_faces, acc) unless own_faces.empty?
    end
  end
end

def self.hex(color)
  color ? format('#%02x%02x%02x', color.red, color.green, color.blue) : '#a1a1aa'
rescue StandardError
  '#a1a1aa'
end

def self.measured?(m)
  m['count'] > 0 || m['length'] > 0 || m['area'] > 0 || m['volume'] > 0 || m['nonsolid'] > 0
end

# Baris untuk dialog: semua sumber (tag & material) yang punya ukuran + yang sudah dipetakan
def self.tag_rows(model, measures, mapped_keys)
  keys = measures.select { |_k, m| measured?(m) }.keys | mapped_keys
  rows = keys.map do |key|
    kind, name = split_key(key)
    holder = kind == 'mat' ? model.materials[name] : model.layers[name]
    { 'key' => key, 'kind' => kind, 'name' => name, 'color' => hex(holder && holder.color) }
      .merge(measures.fetch(key) { blank_measure })
  end
  rows.sort_by { |r| [r['kind'], r['name'].downcase] }
end

  # ── Hitung RAB (murni, tanpa SketchUp) ────────────────────────────────────

  def self.effective_prices(database, overrides)
    database['harga_dasar'].each_with_object({}) do |h, out|
      out[h['kode']] = (overrides[h['kode']] || h['harga']).to_f
    end
  end

  # Rincian satu AHSP: tiap komponen (koefisien x harga), jumlah upah+bahan+alat, overhead & profit, harga satuan akhir.
  def self.ahsp_breakdown(item, base_by_kode, prices, op_pct)
    comps = item['komponen'].map do |c|
      base = base_by_kode[c['kode']]
      price = prices[c['kode']]
      { 'kode' => c['kode'], 'nama' => base['nama'], 'satuan' => base['satuan'], 'jenis' => base['jenis'],
        'koef' => c['koef'].to_f, 'harga' => price, 'jumlah' => c['koef'].to_f * price }
    end
    jumlah = comps.sum { |c| c['jumlah'] }
    op = jumlah * op_pct / 100.0
    {
      'comps' => comps,
      'bahan' => comps.select { |c| c['jenis'] == 'bahan' }.sum { |c| c['jumlah'] },
      'upah' => comps.select { |c| c['jenis'] == 'upah' }.sum { |c| c['jumlah'] },
      'alat' => comps.select { |c| c['jenis'] == 'alat' }.sum { |c| c['jumlah'] },
      'jumlah' => jumlah, 'op' => op, 'hsp' => jumlah + op
    }
  end

  # Urutan kode AHSP secara angka per segmen: "1.2" sebelum "1.10", "2.2.1.1.3" sebelum "2.2.1.1.3a"
  def self.kode_sort_key(kode)
    kode.to_s.split('.').map { |seg| seg =~ /\A(\d+)(.*)\z/ ? [Regexp.last_match(1).to_i, Regexp.last_match(2)] : [-1, seg] }
  end

  # Volume satu baris. Isian manual menang atas hasil ukur; basis 'auto' mengikuti satuan AHSP.
  # Hasil: [qty, basis_terpakai, sumber('auto'|'manual')]
  def self.quantity(measure, entry, satuan)
    return [entry['manual'], 'manual', 'manual'] if entry['manual']

    basis = entry['basis'] == 'auto' ? unit_basis(satuan) : entry['basis']
    # Auto + m2 pada sumber yang berisi solid: luas satu sisi, bukan jumlah semua face (dua sisi + tepi)
    basis = 'plane' if entry['basis'] == 'auto' && basis == 'area' && measure['plane'] > 0
    base = case basis
           when 'count' then measure['count']
           when 'length' then measure['length']
           when 'area' then measure['area']
           when 'plane' then measure['plane']
           when 'volume' then measure['volume']
           else 0.0
           end
    [base * entry['factor'], basis, 'auto']
  end

  def self.build_report(database, state, measures)
    database = effective_db(database, state)
    base_by_kode = database['harga_dasar'].to_h { |h| [h['kode'], h] }
    ahsp_by_kode = database['ahsp'].to_h { |a| [a['kode'], a] }
    prices = effective_prices(database, state['prices'])

    rows = state['map'].map do |key, entry|
      kind, name = split_key(key)
      item = ahsp_by_kode[entry['kode']]
      measure = measures.fetch(key) { blank_measure }
      hsp = ahsp_breakdown(item, base_by_kode, prices, state['op'])['hsp']
      qty, basis, src = quantity(measure, entry, item['satuan'])
      warn = nil
      warn = 'nonsolid' if %w[volume plane].include?(basis) && src == 'auto' && measure['nonsolid'] > 0
      warn ||= 'zero' if qty.zero?
      { 'key' => key, 'kind' => kind, 'tag' => name, 'label' => "#{kind == 'mat' ? 'Material' : 'Tag'}: #{name}",
        'kode' => item['kode'], 'divisi' => item['divisi'], 'uraian' => item['uraian'],
        'satuan' => item['satuan'], 'basis' => basis, 'src' => src, 'qty' => qty, 'hsp' => hsp,
        'jumlah' => qty * hsp, 'warn' => warn, 'nonsolid' => measure['nonsolid'] }
    end
    rows.sort_by! { |r| [r['divisi'], kode_sort_key(r['kode']), r['kind'], r['tag'].downcase] }

    # Komponen (kode dasar) di AHSP yang terpakai tapi harganya masih 0: pengingat supaya harga diisi
    used_base = rows.flat_map { |r| ahsp_by_kode[r['kode']]['komponen'].map { |c| c['kode'] } }.uniq
    unpriced = used_base.count { |k| prices[k].to_f <= 0 }

    divisi = rows.group_by { |r| r['divisi'] }.map { |name, rs| { 'name' => name, 'subtotal' => rs.sum { |r| r['jumlah'] } } }
    subtotal = rows.sum { |r| r['jumlah'] }
    ppn = state['ppn_on'] ? subtotal * state['ppn'] / 100.0 : 0.0
    { 'rows' => rows, 'divisi' => divisi, 'subtotal' => subtotal, 'ppn_on' => state['ppn_on'],
      'ppn_pct' => state['ppn'], 'ppn' => ppn, 'total' => subtotal + ppn, 'op_pct' => state['op'], 'unpriced' => unpriced, 'used_base' => used_base }
  end

  # ── Format angka gaya Indonesia (1.234.567,89) ────────────────────────────

  def self.fmt_num(value, decimals = 0)
    s = format("%.#{decimals}f", value.to_f)
    int, frac = s.split('.')
    neg = int.start_with?('-')
    int = int.delete('-').reverse.scan(/\d{1,3}/).join('.').reverse
    "#{neg ? '-' : ''}#{int}#{frac ? ",#{frac}" : ''}"
  end

  # ── Penulis XLSX tanpa library: ZIP + XML ─────────────────────────────────
  # Sel boleh berisi nilai, formula, atau keduanya (nilai = hasil cache supaya terbaca di aplikasi tanpa kalkulator).
  # Warna & huruf mengikuti tema (RabTheme). Sheet boleh membawa satu grafik garis (kurva S).
  class Xlsx
    # numFmt: 3 = #,##0   4 = #,##0.00   10 = 0.00%   164 = #,##0.0000   165 = 0.0%   1 = 0
    NUMFMTS = { 164 => '#,##0.0000', 165 => '0.0%' }.freeze
    FONT_KEYS = %i[default bold head band total input title muted].freeze
    FILL_KEYS = %i[none gray125 head band total].freeze

    STYLES = {
      default: {},
      title: { font: :title },
      muted: { font: :muted },
      head: { font: :head, fill: :head, border: true, h: 'center', v: 'center', wrap: true },
      divisi: { font: :band, fill: :band, border: true },
      text: { border: true },
      wrap: { border: true, wrap: true, v: 'top' },
      bold: { font: :bold, border: true },
      bold_plain: { font: :bold },
      center: { border: true, h: 'center' },
      int: { border: true, numfmt: 3 },
      pct: { border: true, numfmt: 165 },
      pct2: { border: true, numfmt: 10 },
      sub_label: { font: :band, fill: :band, border: true, h: 'right' },
      sub_rp: { font: :band, fill: :band, border: true, numfmt: 3 },
      sub_pct2: { font: :band, fill: :band, border: true, numfmt: 10 },
      total_label: { font: :total, fill: :total, border: true, h: 'right' },
      total_rp: { font: :total, fill: :total, border: true, numfmt: 3 },
      total_pct2: { font: :total, fill: :total, border: true, numfmt: 10 },
      total_text: { font: :total, fill: :total, border: true },
      in_rp: { font: :input, border: true, numfmt: 3 },
      in_qty: { font: :input, border: true, numfmt: 4 },
      in_koef: { font: :input, border: true, numfmt: 164 },
      in_pct: { font: :input, border: true, numfmt: 165 },
      in_int: { font: :input, border: true, numfmt: 1, h: 'center' },
      in_text: { font: :input, border: true }
    }.freeze

    Cell = Struct.new(:v, :f, :s)
    Chart = Struct.new(:anchor, :title, :x_title, :y_title, :name, :name_ref, :cats, :cats_ref, :vals, :vals_ref, :color, keyword_init: true)

    class Sheet
      attr_reader :name, :cells, :merges, :widths, :lists
      attr_accessor :freeze_row, :selected, :chart

      def initialize(name)
        @name = name
        @cells = {}
        @merges = []
        @widths = {}
        @lists = []
        @freeze_row = nil
        @selected = false
        @chart = nil
      end

      def set(row, col, v = nil, style: :default, f: nil)
        @cells[[row, col]] = Cell.new(v, f, style)
      end

      def merge(r1, c1, r2, c2)
        @merges << "#{Xlsx.col_letter(c1)}#{r1}:#{Xlsx.col_letter(c2)}#{r2}"
      end

      def width(col, w)
        @widths[col] = w
      end

      # Pilihan dropdown untuk kolom col, baris r1..r2
      def list(col, r1, r2, items)
        letter = Xlsx.col_letter(col)
        @lists << ["#{letter}#{r1}:#{letter}#{r2}", items.join(',')]
      end
    end

    def self.col_letter(n)
      s = +''
      while n > 0
        n, r = (n - 1).divmod(26)
        s.prepend((65 + r).chr)
      end
      s
    end

    def self.esc(text)
      CGI.escapeHTML(text.to_s).gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F]/, '')
    end

    attr_reader :sheets, :theme

    def initialize(theme = nil)
      @sheets = []
      @theme = theme || BoosokTools::RabTheme.default
    end

    def add_sheet(name)
      sh = Sheet.new(name)
      @sheets << sh
      sh
    end

    def style_keys
      STYLES.keys
    end

    # ── Tema -> XML gaya ──
    def font_xml(key)
      r = @theme['roles']
      spec = case key
             when :default then { color: r['text']['color'] }
             when :bold then { b: true, color: r['text']['color'] }
             when :head then { b: r['head']['bold'], color: r['head']['color'] }
             when :band then { b: r['band']['bold'], color: r['band']['color'] }
             when :total then { b: r['total']['bold'], color: r['total']['color'] }
             when :input then { color: r['input']['color'] }
             when :title then { b: r['title']['bold'], sz: r['title']['size'], color: r['title']['color'] }
             when :muted then { i: true, sz: 10, color: r['muted']['color'] }
             end
      size = format('%g', spec[:sz] || @theme['size'])
      "<font>#{'<b/>' if spec[:b]}#{'<i/>' if spec[:i]}<sz val=\"#{size}\"/><color rgb=\"FF#{spec[:color].upcase}\"/><name val=\"#{self.class.esc(@theme['font'])}\"/></font>"
    end

    def fill_xml(key)
      case key
      when :none then '<fill><patternFill patternType="none"/></fill>'
      when :gray125 then '<fill><patternFill patternType="gray125"/></fill>'
      else %(<fill><patternFill patternType="solid"><fgColor rgb="FF#{@theme['roles'][key.to_s]['fill'].upcase}"/><bgColor indexed="64"/></patternFill></fill>)
      end
    end

    def border_thin_xml
      c = "<color rgb=\"FF#{@theme['roles']['grid']['border'].upcase}\"/>"
      "<border><left style=\"thin\">#{c}</left><right style=\"thin\">#{c}</right><top style=\"thin\">#{c}</top><bottom style=\"thin\">#{c}</bottom><diagonal/></border>"
    end

    BORDER_NONE = '<border><left/><right/><top/><bottom/><diagonal/></border>'.freeze

    def styles_xml
      xfs = STYLES.values.map do |st|
        numfmt = st[:numfmt] || 0
        align = %w[h v].any? { |k| st[k.to_sym] } || st[:wrap]
        attrs = %(numFmtId="#{numfmt}" fontId="#{FONT_KEYS.index(st[:font] || :default)}" fillId="#{FILL_KEYS.index(st[:fill] || :none)}" ) +
                %(borderId="#{st[:border] ? 1 : 0}" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1")
        if align
          al = +'<alignment'
          al << %( horizontal="#{st[:h]}") if st[:h]
          al << %( vertical="#{st[:v]}") if st[:v]
          al << ' wrapText="1"' if st[:wrap]
          "<xf #{attrs} applyAlignment=\"1\">#{al}/></xf>"
        else
          "<xf #{attrs}/>"
        end
      end
      numfmts = NUMFMTS.map { |id, code| %(<numFmt numFmtId="#{id}" formatCode="#{self.class.esc(code)}"/>) }.join
      <<~XML.delete("\n")
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <numFmts count="#{NUMFMTS.size}">#{numfmts}</numFmts>
        <fonts count="#{FONT_KEYS.size}">#{FONT_KEYS.map { |k| font_xml(k) }.join}</fonts>
        <fills count="#{FILL_KEYS.size}">#{FILL_KEYS.map { |k| fill_xml(k) }.join}</fills>
        <borders count="2">#{BORDER_NONE}#{border_thin_xml}</borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="#{xfs.size}">#{xfs.join}</cellXfs>
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
        </styleSheet>
      XML
    end

    def num_text(n)
      n.is_a?(Integer) ? n.to_s : format('%.12g', n)
    end

    def cell_xml(row, col, cell)
      ref = "#{self.class.col_letter(col)}#{row}"
      s = style_keys.index(cell.s || :default)
      v = cell.v
      if cell.f
        if v.is_a?(String)
          %(<c r="#{ref}" s="#{s}" t="str"><f>#{self.class.esc(cell.f)}</f><v>#{self.class.esc(v)}</v></c>)
        else
          %(<c r="#{ref}" s="#{s}"><f>#{self.class.esc(cell.f)}</f>#{v.nil? ? '' : "<v>#{num_text(v)}</v>"}</c>)
        end
      elsif v.nil?
        %(<c r="#{ref}" s="#{s}"/>)
      elsif v.is_a?(String)
        %(<c r="#{ref}" s="#{s}" t="inlineStr"><is><t xml:space="preserve">#{self.class.esc(v)}</t></is></c>)
      else
        %(<c r="#{ref}" s="#{s}"><v>#{num_text(v)}</v></c>)
      end
    end

    def sheet_xml(sh)
      by_row = sh.cells.group_by { |(r, _c), _cell| r } # sekali jalan; mencari per baris membuat sheet besar (ribuan baris) sangat lambat
      rows = by_row.keys.sort
      max_col = sh.cells.keys.map(&:last).max || 1
      data = rows.map do |r|
        cols = by_row[r].sort_by { |(_, c), _| c }
        "<row r=\"#{r}\">#{cols.map { |(rr, c), cell| cell_xml(rr, c, cell) }.join}</row>"
      end.join
      cols = sh.widths.sort.map { |c, w| %(<col min="#{c}" max="#{c}" width="#{w}" customWidth="1"/>) }.join
      pane = ''
      if sh.freeze_row
        pane = %(<pane ySplit="#{sh.freeze_row}" topLeftCell="A#{sh.freeze_row + 1}" activePane="bottomLeft" state="frozen"/>)
      end
      merges = sh.merges.empty? ? '' : %(<mergeCells count="#{sh.merges.size}">#{sh.merges.map { |m| %(<mergeCell ref="#{m}"/>) }.join}</mergeCells>)
      lists = sh.lists.map do |ref, items|
        %(<dataValidation type="list" allowBlank="1" showErrorMessage="1" sqref="#{ref}"><formula1>"#{self.class.esc(items)}"</formula1></dataValidation>)
      end
      validations = lists.empty? ? '' : %(<dataValidations count="#{lists.size}">#{lists.join}</dataValidations>)
      drawing = sh.chart ? '<drawing r:id="rId1"/>' : ''
      <<~XML.delete("\n")
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>
        <dimension ref="A1:#{self.class.col_letter(max_col)}#{rows.last || 1}"/>
        <sheetViews><sheetView workbookViewId="0"#{sh.selected ? ' tabSelected="1"' : ''}>#{pane}</sheetView></sheetViews>
        <sheetFormatPr defaultRowHeight="15"/>
        #{cols.empty? ? '' : "<cols>#{cols}</cols>"}
        <sheetData>#{data}</sheetData>
        #{merges}
        #{validations}
        <pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>
        <pageSetup paperSize="9" orientation="landscape" fitToHeight="0"/>
        #{drawing}
        </worksheet>
      XML
    end

    # ── Grafik garis (kurva S) ──
    def chart_xml(ch)
      pts = ->(arr) { arr.each_with_index.map { |v, i| %(<c:pt idx="#{i}"><c:v>#{num_text(v)}</c:v></c:pt>) }.join }
      axis_title = lambda do |text|
        %(<c:title><c:tx><c:rich><a:bodyPr/><a:p><a:pPr><a:defRPr sz="900" b="0"/></a:pPr><a:r><a:rPr lang="id-ID" sz="900" b="0"/><a:t>#{self.class.esc(text)}</a:t></a:r></a:p></c:rich></c:tx><c:overlay val="0"/></c:title>)
      end
      color = (ch.color || '1f3a5f').upcase
      <<~XML.delete("\n")
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <c:roundedCorners val="0"/>
        <c:chart>
        <c:title><c:tx><c:rich><a:bodyPr/><a:p><a:pPr><a:defRPr sz="1200" b="1"/></a:pPr><a:r><a:rPr lang="id-ID" sz="1200" b="1"/><a:t>#{self.class.esc(ch.title)}</a:t></a:r></a:p></c:rich></c:tx><c:overlay val="0"/></c:title>
        <c:autoTitleDeleted val="0"/>
        <c:plotArea><c:layout/>
        <c:lineChart><c:grouping val="standard"/><c:varyColors val="0"/>
        <c:ser><c:idx val="0"/><c:order val="0"/>
        <c:tx><c:strRef><c:f>#{self.class.esc(ch.name_ref)}</c:f><c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>#{self.class.esc(ch.name)}</c:v></c:pt></c:strCache></c:strRef></c:tx>
        <c:spPr><a:ln w="28575" cap="rnd"><a:solidFill><a:srgbClr val="#{color}"/></a:solidFill><a:round/></a:ln></c:spPr>
        <c:marker><c:symbol val="circle"/><c:size val="5"/><c:spPr><a:solidFill><a:srgbClr val="#{color}"/></a:solidFill></c:spPr></c:marker>
        <c:cat><c:numRef><c:f>#{self.class.esc(ch.cats_ref)}</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val="#{ch.cats.size}"/>#{pts.call(ch.cats)}</c:numCache></c:numRef></c:cat>
        <c:val><c:numRef><c:f>#{self.class.esc(ch.vals_ref)}</c:f><c:numCache><c:formatCode>0.00%</c:formatCode><c:ptCount val="#{ch.vals.size}"/>#{pts.call(ch.vals)}</c:numCache></c:numRef></c:val>
        <c:smooth val="0"/></c:ser>
        <c:marker val="1"/><c:axId val="500000001"/><c:axId val="500000002"/></c:lineChart>
        <c:catAx><c:axId val="500000001"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="b"/>#{axis_title.call(ch.x_title)}<c:numFmt formatCode="General" sourceLinked="0"/><c:majorTickMark val="out"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:crossAx val="500000002"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx>
        <c:valAx><c:axId val="500000002"/><c:scaling><c:orientation val="minMax"/><c:max val="1"/><c:min val="0"/></c:scaling><c:delete val="0"/><c:axPos val="l"/><c:majorGridlines/>#{axis_title.call(ch.y_title)}<c:numFmt formatCode="0%" sourceLinked="0"/><c:majorTickMark val="out"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:crossAx val="500000001"/><c:crosses val="autoZero"/><c:crossBetween val="between"/></c:valAx>
        </c:plotArea>
        <c:legend><c:legendPos val="b"/><c:overlay val="0"/></c:legend>
        <c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/>
        </c:chart>
        </c:chartSpace>
      XML
    end

    def drawing_xml(ch)
      c1, r1, c2, r2 = ch.anchor
      <<~XML.delete("\n")
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
        <xdr:twoCellAnchor>
        <xdr:from><xdr:col>#{c1}</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>#{r1}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>
        <xdr:to><xdr:col>#{c2}</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>#{r2}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>
        <xdr:graphicFrame macro="">
        <xdr:nvGraphicFramePr><xdr:cNvPr id="2" name="#{self.class.esc(ch.title)}"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>
        <xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm>
        <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="rId1"/></a:graphicData></a:graphic>
        </xdr:graphicFrame>
        <xdr:clientData/>
        </xdr:twoCellAnchor>
        </xdr:wsDr>
      XML
    end

    REL_NS = 'http://schemas.openxmlformats.org/package/2006/relationships'.freeze
    OD_REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'.freeze

    def package_files
      n = @sheets.size
      charts = @sheets.each_index.select { |i| @sheets[i].chart }
      content_types = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">) +
                      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' \
                      '<Default Extension="xml" ContentType="application/xml"/>' \
                      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' \
                      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
                      (1..n).map { |i| %(<Override PartName="/xl/worksheets/sheet#{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>) }.join +
                      (1..charts.size).map do |k|
                        %(<Override PartName="/xl/drawings/drawing#{k}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>) +
                          %(<Override PartName="/xl/charts/chart#{k}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>)
                      end.join +
                      '</Types>'
      root_rels = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="#{REL_NS}">) +
                  %(<Relationship Id="rId1" Type="#{OD_REL}/officeDocument" Target="xl/workbook.xml"/></Relationships>)
      workbook = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="#{OD_REL}"><sheets>) +
                 @sheets.each_with_index.map { |sh, i| %(<sheet name="#{self.class.esc(sh.name)}" sheetId="#{i + 1}" r:id="rId#{i + 1}"/>) }.join +
                 '</sheets><calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>'
      wb_rels = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="#{REL_NS}">) +
                (1..n).map { |i| %(<Relationship Id="rId#{i}" Type="#{OD_REL}/worksheet" Target="worksheets/sheet#{i}.xml"/>) }.join +
                %(<Relationship Id="rId#{n + 1}" Type="#{OD_REL}/styles" Target="styles.xml"/></Relationships>)
      files = [
        ['[Content_Types].xml', content_types], ['_rels/.rels', root_rels], ['xl/workbook.xml', workbook],
        ['xl/_rels/workbook.xml.rels', wb_rels], ['xl/styles.xml', styles_xml]
      ]
      @sheets.each_with_index { |sh, i| files << ["xl/worksheets/sheet#{i + 1}.xml", sheet_xml(sh)] }
      charts.each_with_index do |sheet_idx, k|
        no = k + 1
        ch = @sheets[sheet_idx].chart
        files << ["xl/worksheets/_rels/sheet#{sheet_idx + 1}.xml.rels",
                  %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="#{REL_NS}"><Relationship Id="rId1" Type="#{OD_REL}/drawing" Target="../drawings/drawing#{no}.xml"/></Relationships>)]
        files << ["xl/drawings/drawing#{no}.xml", drawing_xml(ch)]
        files << ["xl/drawings/_rels/drawing#{no}.xml.rels",
                  %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="#{REL_NS}"><Relationship Id="rId1" Type="#{OD_REL}/chart" Target="../charts/chart#{no}.xml"/></Relationships>)]
        files << ["xl/charts/chart#{no}.xml", chart_xml(ch)]
      end
      files
    end

    # ZIP minimal (deflate), cukup untuk dibuka Excel/LibreOffice.
    DOS_DATE = (((2026 - 1980) << 9) | (1 << 5) | 1) unless defined?(DOS_DATE)

    def to_binary
      out = String.new(encoding: Encoding::BINARY)
      central = String.new(encoding: Encoding::BINARY)
      count = 0
      package_files.each do |name, text|
        data = text.encode('UTF-8').b
        crc = Zlib.crc32(data)
        z = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
        packed = z.deflate(data, Zlib::FINISH)
        z.close
        offset = out.bytesize
        out << [0x04034b50, 20, 0, 8, 0, DOS_DATE, crc, packed.bytesize, data.bytesize, name.bytesize, 0].pack('VvvvvvVVVvv') << name.b << packed
        central << [0x02014b50, 20, 20, 0, 8, 0, DOS_DATE, crc, packed.bytesize, data.bytesize, name.bytesize, 0, 0, 0, 0, 0, offset]
                   .pack('VvvvvvvVVVvvvvvVV') << name.b
        count += 1
      end
      cd_offset = out.bytesize
      out << central << [0x06054b50, 0, 0, count, count, central.bytesize, cd_offset, 0].pack('VvvvvVVv')
      out
    end

    def save(path)
      File.binwrite(path, to_binary)
    end
  end

  # ── Susun workbook RAB ────────────────────────────────────────────────────

  SHEET_REKAP = 'Rekapitulasi'.freeze unless defined?(SHEET_REKAP)
  SHEET_RAB = 'RAB'.freeze unless defined?(SHEET_RAB)
  SHEET_DHSP = 'DHSP'.freeze unless defined?(SHEET_DHSP)
  SHEET_AHSP = 'AHSP'.freeze unless defined?(SHEET_AHSP)
  SHEET_KURVA = 'Kurva S'.freeze unless defined?(SHEET_KURVA)
  AHSP_EXTRA_COLS = [%w[Divisi divisi], %w[Kategori kategori], %w[Keyakinan keyakinan], %w[Acuan acuan], %w[Catatan catatan]].freeze unless defined?(AHSP_EXTRA_COLS)

  # Warna garis kurva S: warna judul kolom, kecuali terlalu terang (tema hitam-putih) -> warna teks
  def self.chart_color(theme)
    BoosokTools::RabTheme.line_color(theme['roles']['head']['fill'], theme['roles']['text']['color'])
  end

  # Isi sheet "Harga Dasar" (hanya komponen dari kodes) dan "AHSP" (rincian tiap AHSP, formula hidup ke Harga Dasar).
  # Return { kode AHSP => alamat sel harga satuan akhir }
  # extras: tambah kolom Divisi, Kategori, Keyakinan, Acuan, Catatan di kanan baris analisa (supaya file bisa diimpor lagi tanpa kehilangan data).
  # all_base: semua harga dasar database masuk sheet harga, bukan hanya yang dipakai kodes.
  def self.fill_ahsp_sheets(sh_ahsp, sh_base, kodes, database, prices, op_pct, extras: false, all_base: false)
    base_by_kode = database['harga_dasar'].to_h { |h| [h['kode'], h] }
    ahsp_by_kode = database['ahsp'].to_h { |a| [a['kode'], a] }

    # --- Harga Dasar ---
    sh_base.set(1, 1, 'DAFTAR HARGA BAHAN (DHSP)', style: :title)
    sh_base.set(2, 1, "Upah, bahan dan alat. Font biru = boleh diubah; perubahan otomatis masuk ke sheet #{SHEET_AHSP}, #{SHEET_RAB}, dan #{SHEET_REKAP}.", style: :muted)
    %w[Kode Jenis Nama Satuan Harga\ Satuan\ (Rp)].each_with_index { |h, i| sh_base.set(4, i + 1, h, style: :head) }
    # Hanya komponen dari AHSP yang terpakai di RAB (database lengkap ribuan baris, tidak perlu masuk Excel)
    used_kodes = kodes.flat_map { |kode| ahsp_by_kode[kode]['komponen'].map { |c| c['kode'] } }.uniq
    base_rows = all_base ? database['harga_dasar'] : database['harga_dasar'].select { |h| used_kodes.include?(h['kode']) }
    base_rows.each_with_index do |h, i|
      r = 5 + i
      sh_base.set(r, 1, h['kode'], style: :text)
      sh_base.set(r, 2, h['jenis'], style: :text)
      sh_base.set(r, 3, h['nama'], style: :text)
      sh_base.set(r, 4, h['satuan'], style: :center)
      sh_base.set(r, 5, prices[h['kode']], style: :in_rp)
    end
    base_last = 4 + [base_rows.size, 1].max
    [9, 8, 36, 9, 18].each_with_index { |w, i| sh_base.width(i + 1, w) }
    sh_base.freeze_row = 4
    lookup = lambda do |col, row|
      "INDEX(#{SHEET_DHSP}!$#{col}$5:$#{col}$#{base_last},MATCH($A#{row},#{SHEET_DHSP}!$A$5:$A$#{base_last},0))"
    end

    # --- AHSP (hanya item yang dipakai di RAB) ---
    sh_ahsp.set(1, 1, 'ANALISA HARGA SATUAN PEKERJAAN (AHSP)', style: :title)
    sh_ahsp.set(2, 1, "#{database.dig('meta', 'sumber') || 'Koefisien AHSP'}. Verifikasi ke dokumen resmi sebelum dipakai. Font biru = boleh diubah.", style: :muted)
    sh_ahsp.set(3, 1, 'Overhead & Profit', style: :bold)
    sh_ahsp.set(3, 2, nil, style: :bold)
    sh_ahsp.set(3, 3, nil, style: :bold)
    sh_ahsp.set(3, 4, op_pct / 100.0, style: :in_pct)
    %w[Kode Uraian/Komponen Sat. Koefisien Harga\ Satuan Jumlah].each_with_index { |h, i| sh_ahsp.set(5, i + 1, h, style: :head) }
    AHSP_EXTRA_COLS.each_with_index { |(h, _f), i| sh_ahsp.set(5, 7 + i, h, style: :head) } if extras
    hsp_cell = {} # kode AHSP -> alamat sel harga satuan akhir
    r = 6
    kodes.each do |kode|
      item = ahsp_by_kode[kode]
      bd = ahsp_breakdown(item, base_by_kode, prices, op_pct)
      sh_ahsp.set(r, 1, item['kode'], style: :divisi)
      sh_ahsp.set(r, 2, item['uraian'], style: :divisi)
      sh_ahsp.set(r, 3, item['satuan'], style: :divisi)
      4.upto(6) { |c| sh_ahsp.set(r, c, nil, style: :divisi) }
      AHSP_EXTRA_COLS.each_with_index { |(_h, f), i| sh_ahsp.set(r, 7 + i, item[f].to_s.empty? ? nil : item[f].to_s, style: :divisi) } if extras
      r += 1
      first = r
      bd['comps'].each do |c|
        sh_ahsp.set(r, 1, c['kode'], style: :in_text)
        sh_ahsp.set(r, 2, c['nama'], style: :text, f: lookup.call('C', r))
        sh_ahsp.set(r, 3, c['satuan'], style: :center, f: lookup.call('D', r))
        sh_ahsp.set(r, 4, c['koef'], style: :in_koef)
        sh_ahsp.set(r, 5, c['harga'], style: :int, f: lookup.call('E', r))
        sh_ahsp.set(r, 6, c['jumlah'], style: :int, f: "D#{r}*E#{r}")
        r += 1
      end
      sh_ahsp.set(r, 2, 'Jumlah harga upah + bahan + alat', style: :bold)
      [1, 3, 4, 5].each { |c| sh_ahsp.set(r, c, nil, style: :bold) }
      sh_ahsp.set(r, 6, bd['jumlah'], style: :sub_rp, f: "SUM(F#{first}:F#{r - 1})")
      sum_row = r
      r += 1
      sh_ahsp.set(r, 2, 'Overhead & profit', style: :bold)
      [1, 3, 5].each { |c| sh_ahsp.set(r, c, nil, style: :bold) }
      sh_ahsp.set(r, 4, op_pct / 100.0, style: :pct, f: '$D$3')
      sh_ahsp.set(r, 6, bd['op'], style: :int, f: "F#{sum_row}*D#{r}")
      op_row = r
      r += 1
      sh_ahsp.set(r, 2, "Harga satuan pekerjaan per #{item['satuan']}", style: :total_label)
      [1, 3, 4, 5].each { |c| sh_ahsp.set(r, c, nil, style: :total_label) }
      sh_ahsp.set(r, 6, bd['hsp'], style: :total_rp, f: "F#{sum_row}+F#{op_row}")
      hsp_cell[kode] = "AHSP!$F$#{r}"
      r += 2
    end
    [9, 52, 9, 12, 16, 18].each_with_index { |w, i| sh_ahsp.width(i + 1, w) }
    [24, 24, 14, 24, 30].each_with_index { |w, i| sh_ahsp.width(7 + i, w) } if extras
    hsp_cell
  end

  # Workbook RAB, urutan sheet: REKAPITULASI, RAB, DAFTAR HARGA BAHAN (DHSP), ANALISA HARGA SATUAN PEKERJAAN (AHSP), TIME SCHEDULE KURVA S.
  # Semua jumlah saling terhubung lewat rumus (volume, harga, koefisien, mulai/durasi jadwal boleh diubah di Excel).
  def self.build_workbook(report, database, state, project, theme = nil)
    database = effective_db(database, state)
    prices = effective_prices(database, state['prices'])
    wb = Xlsx.new(theme || theme_for(state))

    sh_rekap = wb.add_sheet(SHEET_REKAP)
    sh_rab = wb.add_sheet(SHEET_RAB)
    sh_dhsp = wb.add_sheet(SHEET_DHSP)
    sh_ahsp = wb.add_sheet(SHEET_AHSP)
    sh_kurva = wb.add_sheet(SHEET_KURVA)
    sh_rekap.selected = true

    hsp_cell = fill_ahsp_sheets(sh_ahsp, sh_dhsp, report['rows'].map { |row| row['kode'] }.uniq, database, prices, state['op'])
    now = Time.now
    lines = BoosokTools::RabPdf.info_lines(state, project, now)
    layout = fill_rab_sheet(sh_rab, report, hsp_cell, lines)
    fill_rekap_sheet(sh_rekap, report, layout, lines)
    fill_kurva_sheet(sh_kurva, report, layout, BoosokTools::RabPdf.info_lines(state, project, now, date: false), state['weeks'], chart_color(wb.theme))
    wb
  end

  # Tulis baris data pekerjaan mulai baris 2. Return nomor baris judul kolom (satu baris kosong di bawah data).
  def self.put_info_lines(sh, lines)
    lines.each_with_index { |text, i| sh.set(2 + i, 1, text) }
    lines.size + 3
  end

  def self.sheet_ref(name)
    "'#{name}'"
  end

  # Sheet RAB. Return { rows: { key baris => nomor baris }, divisi: [[nama, baris sub total]], jumlah:, ppn:, total: }
  def self.fill_rab_sheet(sh, report, hsp_cell, lines)
    sh.set(1, 1, 'RENCANA ANGGARAN BIAYA (RAB)', style: :title)
    sh.merge(1, 1, 1, 8)
    head_row = put_info_lines(sh, lines)
    %w[No Uraian\ Pekerjaan Sat. Volume Harga\ Satuan\ (Rp) Jumlah\ (Rp) Kode\ AHSP Sumber].each_with_index { |h, i| sh.set(head_row, i + 1, h, style: :head) }
    r = head_row + 1
    out = { rows: {}, divisi: [] }
    report['rows'].group_by { |row| row['divisi'] }.each do |divisi, rows|
      sh.set(r, 1, divisi.upcase, style: :divisi)
      2.upto(8) { |c| sh.set(r, c, nil, style: :divisi) }
      sh.merge(r, 1, r, 8)
      r += 1
      first = r
      rows.each_with_index do |row, i|
        out[:rows][row['key']] = r
        sh.set(r, 1, i + 1, style: :center)
        sh.set(r, 2, row['uraian'], style: :wrap)
        sh.set(r, 3, row['satuan'], style: :center)
        sh.set(r, 4, row['qty'], style: :in_qty)
        sh.set(r, 5, row['hsp'], style: :int, f: hsp_cell[row['kode']])
        sh.set(r, 6, row['jumlah'], style: :int, f: "D#{r}*E#{r}")
        sh.set(r, 7, row['kode'], style: :center)
        sh.set(r, 8, row['label'], style: :text)
        r += 1
      end
      sh.set(r, 2, "Sub total #{divisi}", style: :sub_label)
      [1, 3, 4, 5, 7, 8].each { |c| sh.set(r, c, nil, style: :sub_label) }
      sh.set(r, 6, rows.sum { |row| row['jumlah'] }, style: :sub_rp, f: "SUM(F#{first}:F#{r - 1})")
      out[:divisi] << [divisi, r]
      r += 1
    end
    r += 1
    sh.set(r, 2, 'JUMLAH', style: :sub_label)
    [1, 3, 4, 5, 7, 8].each { |c| sh.set(r, c, nil, style: :sub_label) }
    sh.set(r, 6, report['subtotal'], style: :sub_rp, f: out[:divisi].empty? ? '0' : out[:divisi].map { |_d, row| "F#{row}" }.join('+'))
    out[:jumlah] = r
    r += 1
    ppn_pct = report['ppn_on'] ? report['ppn_pct'] : 0.0
    sh.set(r, 2, 'PPN', style: :sub_label)
    [1, 3, 4, 7, 8].each { |c| sh.set(r, c, nil, style: :sub_label) }
    sh.set(r, 5, ppn_pct / 100.0, style: :in_pct)
    sh.set(r, 6, report['ppn'], style: :sub_rp, f: "F#{out[:jumlah]}*E#{r}")
    out[:ppn] = r
    r += 1
    sh.set(r, 2, 'TOTAL', style: :total_label)
    [1, 3, 4, 5, 7, 8].each { |c| sh.set(r, c, nil, style: :total_label) }
    sh.set(r, 6, report['total'], style: :total_rp, f: "F#{out[:jumlah]}+F#{out[:ppn]}")
    out[:total] = r
    r += 2
    sh.set(r, 1, "Volume (font biru) dan harga di sheet \"#{SHEET_DHSP}\" boleh diubah; semua jumlah dihitung ulang otomatis.", style: :muted)
    [6, 52, 8, 12, 18, 18, 10, 24].each_with_index { |w, i| sh.width(i + 1, w) }
    sh.freeze_row = head_row
    out
  end

  # Sheet REKAPITULASI: jumlah per divisi (ditarik dari sheet RAB), bobot, PPN, total, terbilang
  def self.fill_rekap_sheet(sh, report, layout, lines)
    sh.set(1, 1, 'REKAPITULASI RENCANA ANGGARAN BIAYA', style: :title)
    sh.merge(1, 1, 1, 4)
    head_row = put_info_lines(sh, lines)
    ['No', 'Uraian Pekerjaan', 'Jumlah Harga (Rp)', 'Bobot (%)'].each_with_index { |h, i| sh.set(head_row, i + 1, h, style: :head) }
    rab = sheet_ref(SHEET_RAB)
    first = head_row + 1
    sums = report['rows'].group_by { |row| row['divisi'] }.transform_values { |rows| rows.sum { |row| row['jumlah'] } }
    r = first
    layout[:divisi].each_with_index do |(divisi, sub_row), i|
      sh.set(r, 1, i + 1, style: :center)
      sh.set(r, 2, BoosokTools::RabPdf.plain_division(divisi), style: :wrap)
      sh.set(r, 3, sums[divisi], style: :int, f: "#{rab}!F#{sub_row}")
      r += 1
    end
    last = r - 1
    jumlah_row = r
    # bobot: setiap baris dibagi JUMLAH (sel di bawah tabel)
    (first..last).each do |row|
      divisi = layout[:divisi][row - first][0]
      sh.set(row, 4, report['subtotal'].to_f.positive? ? sums[divisi] / report['subtotal'] : 0.0, style: :pct2, f: "IF($C$#{jumlah_row}=0,0,C#{row}/$C$#{jumlah_row})")
    end
    sh.set(r, 2, 'JUMLAH', style: :sub_label)
    sh.set(r, 1, nil, style: :sub_label)
    sh.set(r, 3, report['subtotal'], style: :sub_rp, f: layout[:divisi].empty? ? '0' : "SUM(C#{first}:C#{last})")
    sh.set(r, 4, layout[:divisi].empty? ? 0.0 : 1.0, style: :sub_pct2, f: layout[:divisi].empty? ? '0' : "SUM(D#{first}:D#{last})")
    r += 1
    ppn_pct = report['ppn_on'] ? report['ppn_pct'] : 0.0
    sh.set(r, 1, nil, style: :sub_label)
    sh.set(r, 2, 'PPN', style: :sub_label)
    sh.set(r, 3, report['ppn'], style: :sub_rp, f: "#{rab}!F#{layout[:ppn]}")
    sh.set(r, 4, ppn_pct / 100.0, style: :pct, f: "#{rab}!E#{layout[:ppn]}")
    ppn_row = r
    r += 1
    sh.set(r, 1, nil, style: :total_label)
    sh.set(r, 2, 'TOTAL', style: :total_label)
    sh.set(r, 3, report['total'], style: :total_rp, f: "C#{jumlah_row}+C#{ppn_row}")
    sh.set(r, 4, nil, style: :total_label)
    r += 2
    words = BoosokTools::RabPdf.terbilang(report['total'].round)
    sh.set(r, 2, "Terbilang : #{words.capitalize} rupiah", style: :bold_plain)
    sh.set(r + 1, 2, '(terbilang dibuat saat ekspor; tidak ikut berubah kalau angka di Excel diubah)', style: :muted)
    [6, 56, 22, 12].each_with_index { |w, i| sh.width(i + 1, w) }
    sh.freeze_row = head_row
  end

  # Sheet TIME SCHEDULE KURVA S: bobot tiap pekerjaan dibagi rata ke minggu-minggu durasinya, dikumulatifkan jadi kurva S (+ grafik)
  def self.fill_kurva_sheet(sh, report, layout, lines, weeks, color)
    sched = BoosokTools::RabSchedule.compute(report, weeks)
    w = sched[:weeks]
    last_col = 6 + w
    sh.set(1, 1, 'TIME SCHEDULE (KURVA S)', style: :title)
    sh.merge(1, 1, 1, 8)
    # data pekerjaan, lalu catatan, baris "MINGGU KE-", lalu judul kolom (tanpa baris kosong)
    note_row = put_info_lines(sh, lines) - 1
    head_row = note_row + 2
    sh.set(note_row, 1, 'Isi Mulai (minggu ke-) dan Durasi (minggu) pada sel biru; bobot dan kurva S dihitung otomatis dari jumlah di sheet RAB.', style: :muted)
    sh.set(head_row - 1, 7, 'MINGGU KE-', style: :head)
    (8..last_col).each { |c| sh.set(head_row - 1, c, nil, style: :head) }
    sh.merge(head_row - 1, 7, head_row - 1, last_col)
    ['No', 'Uraian Pekerjaan', 'Jumlah (Rp)', 'Bobot', 'Mulai', 'Durasi'].each_with_index { |h, i| sh.set(head_row, i + 1, h, style: :head) }
    (1..w).each { |k| sh.set(head_row, 6 + k, k, style: :head) }
    items = sched[:items]
    if items.empty?
      sh.set(head_row + 1, 2, 'Belum ada pekerjaan yang dipilih.', style: :muted)
      [5, 46, 16, 9, 8, 8].each_with_index { |wd, i| sh.width(i + 1, wd) }
      return
    end

    rab = sheet_ref(SHEET_RAB)
    r = head_row + 1
    first = r
    plan = [] # [divisi / nil, item]
    items.group_by { |it| it[:row]['divisi'] }.each { |d, list| plan << [d, nil]; list.each { |it| plan << [nil, it] } }
    jumlah_row = first + plan.size
    no = 0
    plan.each do |divisi, it|
      if divisi
        sh.set(r, 1, divisi.upcase, style: :divisi)
        2.upto(last_col) { |c| sh.set(r, c, nil, style: :divisi) }
        sh.merge(r, 1, r, last_col)
      else
        no += 1
        row = it[:row]
        sh.set(r, 1, no, style: :center)
        sh.set(r, 2, row['uraian'], style: :wrap)
        sh.set(r, 3, row['jumlah'], style: :int, f: "#{rab}!F#{layout[:rows][row['key']]}")
        sh.set(r, 4, it[:bobot], style: :pct2, f: "IF($C$#{jumlah_row}=0,0,C#{r}/$C$#{jumlah_row})")
        sh.set(r, 5, it[:start], style: :in_int)
        sh.set(r, 6, it[:dur], style: :in_int)
        (1..w).each do |k|
          col = Xlsx.col_letter(6 + k)
          sh.set(r, 6 + k, it[:weekly][k - 1], style: :pct2,
                           f: "IF(AND(#{col}$#{head_row}>=$E#{r},#{col}$#{head_row}<=$E#{r}+$F#{r}-1),$D#{r}/$F#{r},0)")
        end
      end
      r += 1
    end
    last = r - 1
    sh.set(r, 1, nil, style: :sub_label)
    sh.set(r, 2, 'JUMLAH / RENCANA PER MINGGU', style: :sub_label)
    sh.set(r, 3, report['subtotal'], style: :sub_rp, f: "SUM(C#{first}:C#{last})")
    sh.set(r, 4, 1.0, style: :sub_pct2, f: "SUM(D#{first}:D#{last})")
    sh.set(r, 5, nil, style: :sub_label)
    sh.set(r, 6, nil, style: :sub_label)
    (1..w).each do |k|
      col = Xlsx.col_letter(6 + k)
      sh.set(r, 6 + k, sched[:weekly][k - 1], style: :sub_pct2, f: "SUM(#{col}#{first}:#{col}#{last})")
    end
    week_row = r
    r += 1
    sh.set(r, 1, nil, style: :total_label)
    sh.set(r, 2, 'KUMULATIF (KURVA S)', style: :total_text)
    4.upto(6) { |c| sh.set(r, c, nil, style: :total_text) }
    sh.set(r, 3, nil, style: :total_text)
    (1..w).each do |k|
      col = Xlsx.col_letter(6 + k)
      prev = Xlsx.col_letter(5 + k)
      sh.set(r, 6 + k, sched[:cumulative][k - 1], style: :total_pct2, f: k == 1 ? "#{col}#{week_row}" : "#{prev}#{r}+#{col}#{week_row}")
    end
    cum_row = r
    [5, 46, 16, 9, 8, 8].each_with_index { |wd, i| sh.width(i + 1, wd) }
    (7..last_col).each { |c| sh.width(c, 9.5) }
    sh.freeze_row = head_row
    lastl = Xlsx.col_letter(last_col)
    name = sheet_ref(SHEET_KURVA)
    sh.chart = Xlsx::Chart.new(
      anchor: [1, cum_row + 1, [last_col, 14].min, cum_row + 22], title: 'KURVA S', x_title: 'Minggu ke-', y_title: 'Progres kumulatif',
      name: 'KUMULATIF (KURVA S)', name_ref: "#{name}!$B$#{cum_row}",
      cats: (1..w).to_a, cats_ref: "#{name}!$G$#{head_row}:$#{lastl}$#{head_row}", vals: sched[:cumulative], vals_ref: "#{name}!$G$#{cum_row}:$#{lastl}$#{cum_row}",
      color: color
    )
  end

  # ── Ekspor daftar harga & analisa (JSON / Excel) ──────────────────────────

  MAX_EXPORT_ANA = 5000 unless defined?(MAX_EXPORT_ANA)

  # Semua harga dasar database dengan harga yang berlaku di model ini (bawaan file + file harga + ketikan user)
  def self.price_items(database, state)
    prices = effective_prices(database, state['prices'])
    database['harga_dasar'].map do |h|
      { 'kode' => h['kode'], 'jenis' => h['jenis'], 'nama' => h['nama'], 'satuan' => h['satuan'], 'harga' => prices[h['kode']] }
    end
  end

  def self.price_export_json(items, database, project)
    { 'format' => BoosokTools::RabIo::PRICE_FORMAT, 'versi' => 1,
      'meta' => { 'nama' => "Harga #{project}", 'sumber' => database.dig('meta', 'nama').to_s, 'dibuat' => Time.now.strftime('%Y-%m-%d') },
      'items' => items }
  end

  # Baris 1 = judul kolom (Kode, Jenis, Nama, Satuan, Harga), supaya mudah diedit lalu diimpor lagi
  TEMPLATE_BLANK_ROWS = 300 unless defined?(TEMPLATE_BLANK_ROWS) # baris kosong berbingkai di template
  EXPORT_SPARE_ROWS = 50 unless defined?(EXPORT_SPARE_ROWS) # baris kosong di bawah hasil ekspor, supaya mudah menambah

  # template: true -> tanpa data, hanya judul kolom + baris kosong + contoh pengisian di sheet Petunjuk
  def self.build_price_workbook(items, project, theme = nil, template: false)
    wb = Xlsx.new(theme)
    sh = wb.add_sheet('Harga')
    help = wb.add_sheet('Petunjuk')
    sh.selected = true
    ['Kode', 'Jenis', 'Nama', 'Satuan', 'Harga (Rp)'].each_with_index { |h, i| sh.set(1, i + 1, h, style: :head) }
    rows = items.size + (template ? TEMPLATE_BLANK_ROWS : EXPORT_SPARE_ROWS)
    rows.times do |i|
      it = items[i] || {}
      r = 2 + i
      sh.set(r, 1, it['kode'], style: :text)
      sh.set(r, 2, it['jenis'], style: :text)
      sh.set(r, 3, it['nama'], style: :text)
      sh.set(r, 4, it['satuan'], style: :center)
      sh.set(r, 5, it['harga']&.to_f, style: :in_rp)
    end
    sh.list(2, 2, rows + 1, BoosokTools::RabIo::JENIS)
    [11, 9, 58, 9, 16].each_with_index { |w, i| sh.width(i + 1, w) }
    sh.freeze_row = 1
    if template
      help.set(1, 1, 'TEMPLATE DAFTAR HARGA', style: :title)
      [
        'Isi sheet "Harga" mulai baris 2, satu baris per bahan / upah / alat. Jangan mengubah, menghapus atau memindah baris judul (baris 1).',
        'Kolom: Kode (opsional, mis. L.01), Jenis (pilih upah / bahan / alat; opsional), Nama (wajib), Satuan, Harga (Rp, wajib, angka).',
        'Baris tanpa Nama atau tanpa Harga dilewati. Harga dicocokkan ke harga dasar AHSP lewat Kode + Nama, lalu Nama + Satuan.',
        'Contoh: Kode L.01 | Jenis upah | Nama Pekerja | Satuan OH | Harga 150000',
        'Simpan sebagai .xlsx, lalu di RAB: tab Sumber Data > Daftar Harga > Impor harga (atau tab Harga Dasar > Impor harga).',
        "Dibuat #{Time.now.strftime('%d-%m-%Y')} oleh Boosok Tools."
      ].each_with_index { |line, i| help.set(3 + i, 1, line, style: :default) }
      help.width(1, 130)
    else
      help.set(1, 1, "DAFTAR HARGA - #{project}", style: :title)
      [
        'Ubah hanya kolom Harga (font biru). Jangan ubah Kode dan Nama supaya cocok saat diimpor.',
        'Baris yang Harganya kosong dilewati. Boleh menambah baris baru: dicocokkan lewat Nama + Satuan.',
        'Simpan sebagai .xlsx, lalu di RAB: tab Harga Dasar > Impor harga (atau tab Sumber Data > Impor harga).',
        "Dibuat #{Time.now.strftime('%d-%m-%Y')} oleh Boosok Tools."
      ].each_with_index { |line, i| help.set(3 + i, 1, line, style: :default) }
      help.width(1, 100)
    end
    wb
  end

  # Workbook AHSP yang bisa diedit & diimpor lagi: sheet Analisa, Komponen, Harga Dasar (+ Petunjuk).
  # data: hasil analysis_export_data ({ 'harga_dasar', 'ahsp' }); nil -> template kosong.
  def self.build_ahsp_workbook(data, project, theme = nil)
    template = data.nil?
    data ||= { 'harga_dasar' => [], 'ahsp' => [] }
    wb = Xlsx.new(theme)
    ana = wb.add_sheet('Analisa')
    comp = wb.add_sheet('Komponen')
    base = wb.add_sheet('Harga Dasar')
    last_base = data['harga_dasar'].size + (template ? TEMPLATE_BLANK_ROWS : EXPORT_SPARE_ROWS) + 1 # batas rumus pencari nama
    help = wb.add_sheet('Petunjuk')
    ana.selected = true
    ['Kode', 'Divisi', 'Kategori', 'Uraian', 'Satuan', 'Catatan'].each_with_index { |h, i| ana.set(1, i + 1, h, style: :head) }
    ['Kode Analisa', 'Kode Harga', 'Koefisien', 'Nama (otomatis)'].each_with_index { |h, i| comp.set(1, i + 1, h, style: :head) }
    ['Kode', 'Jenis', 'Nama', 'Satuan', 'Harga (Rp)'].each_with_index { |h, i| base.set(1, i + 1, h, style: :head) }

    spare = template ? TEMPLATE_BLANK_ROWS : EXPORT_SPARE_ROWS
    ahsp = data['ahsp']
    ahsp.each_with_index do |a, i|
      r = 2 + i
      [a['kode'], a['divisi'], a['kategori'], a['uraian'], a['satuan'], a['catatan']].each_with_index do |v, c|
        ana.set(r, c + 1, v, style: c == 4 ? :center : :text)
      end
    end
    spare.times { |i| (1..6).each { |c| ana.set(2 + ahsp.size + i, c, nil, style: c == 5 ? :center : :text) } }

    base_names = data['harga_dasar'].to_h { |b| [b['kode'], b['nama']] }
    lines = ahsp.flat_map { |a| a['komponen'].map { |c| [a['kode'], c['kode'], c['koef']] } }
    (lines.size + spare).times do |i|
      r = 2 + i
      ak, hk, koef = lines[i]
      comp.set(r, 1, ak, style: :text)
      comp.set(r, 2, hk, style: :text)
      comp.set(r, 3, koef&.to_f, style: :in_koef)
      comp.set(r, 4, base_names[hk].to_s, style: :text,
                     f: %(IFERROR(INDEX('Harga Dasar'!$C$2:$C$#{last_base},MATCH(B#{r},'Harga Dasar'!$A$2:$A$#{last_base},0)),"")))
    end

    items = data['harga_dasar']
    (items.size + spare).times do |i|
      it = items[i] || {}
      r = 2 + i
      base.set(r, 1, it['kode'], style: :text)
      base.set(r, 2, it['jenis'], style: :text)
      base.set(r, 3, it['nama'], style: :text)
      base.set(r, 4, it['satuan'], style: :center)
      base.set(r, 5, it['harga']&.to_f, style: :in_rp)
    end
    base.list(2, 2, items.size + spare + 1, BoosokTools::RabIo::JENIS)
    [14, 26, 26, 60, 9, 30].each_with_index { |w, i| ana.width(i + 1, w) }
    [16, 16, 14, 50].each_with_index { |w, i| comp.width(i + 1, w) }
    [14, 9, 58, 9, 16].each_with_index { |w, i| base.width(i + 1, w) }
    [ana, comp, base].each { |s| s.freeze_row = 1 }

    help.set(1, 1, template ? 'TEMPLATE AHSP' : "AHSP - #{project}", style: :title)
    [
      'Template ini punya 3 sheet yang saling terhubung lewat kode: Analisa, Komponen, Harga Dasar. Jangan mengubah, menghapus atau memindah baris judul (baris 1).',
      'Analisa: satu baris per pekerjaan. Kode dan Uraian wajib; Divisi, Kategori, Satuan, Catatan opsional. Kode U.nnn tidak boleh dipakai (cadangan analisa buatan sendiri di aplikasi).',
      'Komponen: satu baris per bahan / upah / alat dalam suatu analisa. Kode Analisa = kode di sheet Analisa, Kode Harga = kode di sheet Harga Dasar, Koefisien = angka lebih dari 0. Kolom Nama terisi otomatis.',
      'Harga Dasar: satu baris per bahan / upah / alat. Kode, Jenis (pilih upah / bahan / alat) dan Nama wajib; Harga boleh kosong kalau nanti diisi dari file Daftar Harga. Kode C.nnn tidak boleh dipakai.',
      'Kode Harga di Komponen boleh memakai kode dari file AHSP lain (mis. L.01 dari SE 47) asal file itu ikut dicentang di Sumber Data.',
      'Contoh: Analisa 1.1 | Pekerjaan Tanah | Galian | Galian tanah biasa | m3.  Komponen 1.1 | L.01 | 0,75.  Harga Dasar L.01 | upah | Pekerja | OH | 150000.',
      'Simpan sebagai .xlsx, lalu di RAB: tab Sumber Data > Analisa (AHSP) > Tambah file.',
      "Dibuat #{Time.now.strftime('%d-%m-%Y')} oleh Boosok Tools."
    ].each_with_index { |line, i| help.set(3 + i, 1, line, style: :default) }
    help.width(1, 150)
    wb
  end

  # Data ekspor analisa dalam format file AHSP (bisa langsung ditambahkan lagi di tab Sumber Data).
  # Analisa & harga dasar buatan sendiri (U.nnn / C.nnn) diganti kode SAYA.nnn / HSAYA.nnn supaya tidak bentrok saat dibaca ulang.
  def self.analysis_export_data(database, state, kodes, project)
    eff = effective_db(database, state)
    by_kode = eff['ahsp'].to_h { |a| [a['kode'], a] }
    base_by = eff['harga_dasar'].to_h { |h| [h['kode'], h] }
    prices = effective_prices(eff, state['prices'])
    picks = kodes.uniq.filter_map { |k| by_kode[k] }.first(MAX_EXPORT_ANA)
    ren_a = ->(k) { k.sub(/\AU\./, 'SAYA.') }
    ren_b = ->(k) { k.sub(/\AC\./, 'HSAYA.') }
    ahsp = picks.map do |a|
      item = { 'kode' => ren_a.call(a['kode']), 'divisi' => a['divisi'], 'kategori' => a['kategori'].to_s, 'uraian' => a['uraian'],
               'satuan' => a['satuan'], 'komponen' => a['komponen'].map { |c| { 'kode' => ren_b.call(c['kode']), 'koef' => c['koef'] } } }
      %w[keyakinan acuan catatan].each { |f| item[f] = a[f] if a[f] && a[f] != 'sendiri' }
      item
    end
    used = picks.flat_map { |a| a['komponen'].map { |c| c['kode'] } }.uniq.filter_map { |k| base_by[k] }
    harga = used.map do |b|
      { 'kode' => ren_b.call(b['kode']), 'jenis' => b['jenis'], 'nama' => b['nama'], 'satuan' => b['satuan'], 'harga' => prices[b['kode']] }
    end
    meta = { 'nama' => "Analisa #{project}", 'versi' => '1.0', 'sumber' => database.dig('meta', 'nama').to_s,
             'dibuat' => Time.now.strftime('%Y-%m-%d'), 'overhead_profit_persen' => state['op'], 'ppn_persen' => state['ppn'] }
    { 'meta' => meta, 'harga_dasar' => harga, 'ahsp' => ahsp }
  end

  def self.build_analysis_workbook(database, state, kodes, project, theme = nil)
    eff = effective_db(database, state)
    have = eff['ahsp'].to_h { |a| [a['kode'], true] }
    wb = Xlsx.new(theme || theme_for(state))
    sh_ahsp = wb.add_sheet('AHSP')
    sh_base = wb.add_sheet(SHEET_DHSP)
    sh_ahsp.selected = true
    fill_ahsp_sheets(sh_ahsp, sh_base, kodes.uniq.select { |k| have[k] }.first(MAX_EXPORT_ANA), eff, effective_prices(eff, state['prices']), state['op'], extras: true)
    sh_ahsp.set(4, 1, "Proyek : #{project}", style: :muted)
    wb
  end

  # ── Tema dokumen (Excel & PDF) ────────────────────────────────────────────

  def self.theme_data_dir
    File.join(File.dirname(user_data_dir), 'tema')
  end

  def self.theme_path(id)
    id.to_s.start_with?('user/') && id.match?(BoosokTools::RabTheme::THEME_ID_RE) ? File.join(theme_data_dir, id.split('/', 2).last) : nil
  end

  def self.available_theme_ids
    app = BoosokTools::RabTheme::BUILTIN.keys.map { |k| "app/#{k}" }
    user = json_files(theme_data_dir).map { |f| "user/#{f}" }.select { |id| id.match?(BoosokTools::RabTheme::THEME_ID_RE) }.sort
    app + user
  end

  def self.load_user_theme(id)
    path = theme_path(id)
    return nil unless path && File.exist?(path)

    mtime = File.mtime(path)
    @themes ||= {}
    cached = @themes[path]
    return cached['theme'] if cached && cached['mtime'] == mtime

    theme = begin
      BoosokTools::RabTheme.from_json(File.read(path, encoding: 'UTF-8').sub(/\A﻿/, ''))
    rescue StandardError
      nil
    end
    @themes[path] = { 'theme' => theme, 'mtime' => mtime }
    theme
  end

  # Tema yang dipilih model ini; id yang tidak ditemukan (file tema tidak ada di komputer ini) jatuh ke tema bawaan
  def self.theme_for(state)
    id = (state && state['theme']).to_s
    theme = id.start_with?('user/') ? load_user_theme(id) : BoosokTools::RabTheme.builtin(id)
    theme || BoosokTools::RabTheme.default
  end

  def self.themes_payload
    available_theme_ids.map do |id|
      theme = id.start_with?('user/') ? load_user_theme(id) : BoosokTools::RabTheme.builtin(id)
      { 'id' => id, 'kind' => id.start_with?('user/') ? 'user' : 'app', 'nama' => theme ? theme['nama'] : id.split('/', 2).last, 'error' => theme.nil? }
    end
  end

  # Template Excel: satu baris per peran gaya; ubah gaya sel contoh di kolom B lalu impor lagi
  TEMPLATE_STYLE = { 'title' => :title, 'muted' => :muted, 'text' => :text, 'head' => :head, 'band' => :divisi,
                     'total' => :total_text, 'input' => :in_text, 'grid' => :text }.freeze unless defined?(TEMPLATE_STYLE)

  def self.build_theme_template(theme)
    wb = Xlsx.new(theme)
    sh = wb.add_sheet('Tema')
    help = wb.add_sheet('Petunjuk')
    sh.selected = true
    sh.set(1, 1, 'TEMPLATE TEMA DOKUMEN RAB', style: :title)
    sh.set(2, 1, 'Ubah warna isian, warna huruf, jenis, ukuran atau tebal huruf pada sel di kolom B. Jangan ubah kolom A.', style: :muted)
    ['ID peran', 'Contoh (ubah gaya sel ini)', 'Dipakai untuk'].each_with_index { |h, i| sh.set(4, i + 1, h, style: :head) }
    BoosokTools::RabTheme::ROLES.each_with_index do |(id, spec), i|
      r = 5 + i
      sh.set(r, 1, id, style: :text)
      sh.set(r, 2, 'Contoh teks 1.234.567', style: TEMPLATE_STYLE[id])
      sh.set(r, 3, spec[:label], style: :text)
    end
    [14, 34, 52].each_with_index { |w, i| sh.width(i + 1, w) }
    help.set(1, 1, 'CARA MEMAKAI TEMPLATE', style: :title)
    [
      '1. Di sheet "Tema", ubah gaya sel di kolom B: warna isian (fill), warna huruf, jenis huruf, ukuran, tebal.',
      '2. Baris "text": huruf dasar dokumen (jenis & ukuran huruf Excel). Baris "grid": warna garis tepi sel.',
      '3. Jangan mengubah, menghapus atau mengurutkan ulang kolom A (ID peran).',
      '4. Simpan sebagai .xlsx, lalu di RAB pilih menu Tema > Impor template tema.',
      '5. PDF memakai warna yang sama; jenis huruf PDF tetap Helvetica.'
    ].each_with_index { |line, i| help.set(3 + i, 1, line) }
    help.width(1, 110)
    wb
  end

  # ── Pekerjaan bertahap dengan progress bar ────────────────────────────────
  # Ruby memblokir dialog selama bekerja, jadi pekerjaan dipecah jadi langkah-langkah: sebelum tiap langkah dialog diberi tahu
  # (progress bar di-update), lalu langkahnya dijalankan lewat timer supaya dialog sempat menggambar.

  class UserError < StandardError; end

  def self.defer(&blk)
    UI.start_timer(0.05, false, &blk)
  end

  # steps: [[kunci_teks, ->(hasil_langkah_sebelumnya) { ... }], ...]. Blok finish menerima hasil langkah terakhir; tanpa blok,
  # hasil langkah terakhir (String JavaScript) dijalankan di dialog. Progress 100% dikirim SEBELUM finish, jadi finish yang menutup progress.
  def self.run_job(dialog, steps, &finish)
    run = nil
    run = lambda do |i, prev|
      if i >= steps.size
        dialog.execute_script('rabProgress(100);')
        finish ? finish.call(prev) : dialog.execute_script(prev.to_s)
        next
      end
      key, fn = steps[i]
      dialog.execute_script("rabProgress(#{(i * 100.0 / steps.size).round}, #{key.to_json});")
      defer do
        result = fn.call(prev)
        run.call(i + 1, result)
      rescue UserError, BoosokTools::RabIo::Error, BoosokTools::RabTheme::Error => e
        dialog.execute_script("rabError(#{e.message.to_json});")
      rescue StandardError => e
        puts "[Boosok RAB] #{key}: #{e.class}: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
        dialog.execute_script("rabError(#{"#{key}: #{e.message}".to_json});")
      end
    end
    run.call(0, nil)
  end

  # ── Dialog ────────────────────────────────────────────────────────────────

  def self.project_name(model)
    t = model.title.to_s.strip
    t.empty? ? 'Tanpa judul' : t
  rescue StandardError
    'Tanpa judul'
  end

  # Scan ulang model lalu kirim tag + laporan ke dialog
  def self.refresh(model, state)
    @measures = scan(model)
    @scanned = true
    tags = tag_rows(model, @measures, state['map'].keys)
    { 'tags' => tags, 'report' => build_report(state_db(state), state, @measures) }
  end

  # Semua data yang dibutuhkan dialog: katalog + komponen asli (dari sumber terpilih), harga dasar, state, sumber, tag, laporan.
  # rescan: false memakai hasil scan terakhir (mis. hanya ganti sumber data, model tidak berubah).
  # initial: true (dialog baru dibuka) tidak memindai model; ukuran kosong sampai user menekan Scan Model.
  def self.dialog_payload(model, state, rescan: true, initial: false)
    if initial
      @measures = {}
      @scanned = false
    end
    database = state_db(state)
    base = (rescan && !initial) || @measures.nil? ? refresh(model, state) : nil
    @measures ||= scan(model)
    base ||= { 'tags' => tag_rows(model, @measures, state['map'].keys), 'report' => build_report(database, state, @measures) }
    base.merge(
      'catalog' => catalog(database), 'comps' => ahsp_comps(database), 'base' => database['harga_dasar'], 'state' => state,
      'meta' => database['meta'], 'sources' => sources_payload(state), 'themes' => themes_payload, 'project' => project_name(model),
      'scanned' => @scanned == true
    )
  end

  def self.send_init_data(dialog)
    return unless dialog

    model = Sketchup.active_model
    unless model
      dialog.execute_script("rabError(#{'Tidak ada model yang aktif.'.to_json});")
      return
    end

    dialog.execute_script("init(#{dialog_payload(model, load_state(model), initial: true).to_json});")
  rescue StandardError => e
    puts "[Boosok RAB] init: #{e.class}: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
    msg = "Gagal memuat RAB: #{e.message}"
    dialog.execute_script("rabError(#{msg.to_json});")
  end

  def self.parse_state(json)
    normalize_state(JSON.parse(json.to_s))
  rescue StandardError
    normalize_state({})
  end

  def self.default_dir(model)
    path = model.path.to_s
    return File.dirname(path) unless path.empty?

    docs = File.join(Dir.home, 'Documents')
    File.directory?(docs) ? docs : Dir.home
  end

  def self.safe_filename(text)
    text.to_s.gsub(/[\\\/:*?"<>|]/, '_').strip
  end

  def self.export_xlsx(dialog, state)
    model = Sketchup.active_model
    project = project_name(model)
    path = UI.savepanel('Export RAB ke Excel', default_dir(model), safe_filename("RAB - #{project}") + '.xlsx')
    return dialog.execute_script('onExported(null);') unless path

    path = "#{path}.xlsx" unless path.downcase.end_with?('.xlsx')
    run_job(dialog, [
      ['rab_pg_measure', ->(_) { refresh(model, state)['report'] }],
      ['rab_pg_book', ->(report) { build_workbook(report, state_db(state), state, project) }],
      ['rab_pg_write', lambda { |wb|
        wb.save(path)
        path
      }]
    ]) { |p| dialog.execute_script("onExported(#{p.to_json});") }
  end

  # Argumen callback pratinjau/PDF: JSON { "state": {...}, "parts": ["rab", "ahsp"] }
  def self.parse_print_args(json)
    raw = JSON.parse(json.to_s)
    parts = BoosokTools::RabPdf::PARTS & Array(raw['parts'])
    [normalize_state(raw['state']), parts.empty? ? %w[rab] : parts]
  rescue StandardError
    [normalize_state({}), %w[rab]]
  end

  # Laporan -> halaman siap tampil / siap jadi PDF (memakai hasil scan terakhir, tanpa scan ulang)
  def self.report_layout(state, parts)
    model = Sketchup.active_model
    @measures ||= scan(model)
    database = state_db(state)
    BoosokTools::RabPdf.layout(build_report(database, state, @measures), effective_db(database, state), state, project_name(model), parts,
                               Time.now, theme_for(state))
  end

  def self.send_preview(dialog, state, parts)
    dialog.execute_script("onPreview(#{report_layout(state, parts).to_json});")
  end

  def self.save_pdf(dialog, state, parts)
    model = Sketchup.active_model
    project = project_name(model)
    path = UI.savepanel('Simpan RAB sebagai PDF', default_dir(model), safe_filename("RAB - #{project}") + '.pdf')
    return dialog.execute_script('onPdfSaved(null);') unless path

    path = "#{path}.pdf" unless path.downcase.end_with?('.pdf')
    run_job(dialog, [
      ['rab_pg_layout', ->(_) { report_layout(state, parts) }],
      ['rab_pg_pdf', ->(layout) { BoosokTools::RabPdf.to_pdf(layout, "RAB - #{project}") }],
      ['rab_pg_write', lambda { |pdf|
        File.binwrite(path, pdf)
        path
      }]
    ]) { |p| dialog.execute_script("onPdfSaved(#{p.to_json});") }
  end

  # Ekspor / impor analisa buatan sendiri (file .json) supaya bisa dipakai di model lain
  def self.export_custom_file(dialog, state)
    path = UI.savepanel('Ekspor analisa saya', default_dir(Sketchup.active_model), 'Analisa saya.json')
    return dialog.execute_script('onCustomFile(null);') unless path

    path = "#{path}.json" unless path.downcase.end_with?('.json')
    run_job(dialog, [
      ['rab_pg_collect', ->(_) { JSON.pretty_generate(export_custom(state['custom'], state_db(state))) }],
      ['rab_pg_write', lambda { |text|
        File.write(path, text, encoding: 'UTF-8')
        path
      }]
    ]) { |p| dialog.execute_script("onCustomFile(#{{ 'path' => p }.to_json});") }
  end

  def self.import_custom_file(dialog, state)
    path = UI.openpanel('Impor analisa saya', default_dir(Sketchup.active_model), 'JSON|*.json||')
    return dialog.execute_script('onCustomFile(null);') unless path

    run_job(dialog, [
      ['rab_pg_read', lambda { |_|
        data = JSON.parse(File.read(path, encoding: 'UTF-8'))
        raise UserError, 'File ini bukan hasil ekspor analisa RAB.' unless data.is_a?(Hash) && data['format'] == CUSTOM_FORMAT

        data
      }],
      ['rab_pg_merge', ->(data) { import_custom(state['custom'], data, state_db(state)) }]
    ]) { |(custom, info)| dialog.execute_script("onCustomFile(#{{ 'path' => path, 'custom' => custom, 'info' => info }.to_json});") }
  end

  # ── Sumber data AHSP (file JSON) ──────────────────────────────────────────

  def self.safe_source_name(path)
    base = File.basename(path.to_s, '.*').gsub(/[\\\/:*?"<>|[:cntrl:]]/, '_').strip[0, 80]
    base = 'ahsp' if base.to_s.empty?
    "#{base}.json"
  end

  # Baca file yang dipilih user (.json atau template .xlsx). Return [json_string, pesan_error, peringatan]; error nil kalau berhasil.
  # File Excel diubah ke JSON AHSP yang sudah bersih, jadi yang disimpan di folder data user selalu JSON.
  def self.read_source_file(path)
    return [nil, 'File tidak ditemukan.'] unless File.file?(path)
    return [nil, 'File terlalu besar (maks 40 MB).'] if File.size(path) > 40 * 1024 * 1024
    return read_source_workbook(path) if File.extname(path).downcase == '.xlsx'

    text = File.read(path, encoding: 'UTF-8').sub(/\A﻿/, '')
    raw = JSON.parse(text)
    if raw.is_a?(Hash) && raw['items'].is_a?(Array) && !raw.key?('ahsp')
      return [nil, 'Ini file daftar harga, bukan AHSP. File AHSP harus punya daftar "ahsp" berisi analisa dan komponennya.']
    end

    data, = sanitize_source(raw)
    return [nil, 'Bukan file AHSP: tidak ada daftar "ahsp".'] unless data
    return [nil, 'File AHSP ini kosong (tidak ada analisa yang valid).'] if data['ahsp'].empty?

    [text, nil, []]
  rescue JSON::ParserError
    [nil, 'File bukan JSON yang valid.']
  end

  def self.read_source_workbook(path)
    book = BoosokTools::RabIo.read_ahsp_book(File.binread(path))
    meta = { 'nama' => File.basename(path, '.*')[0, 120], 'versi' => '1.0', 'sumber' => 'Template Excel Boosok Tools' }
    data, info = sanitize_source(book['data'].merge('meta' => meta))
    warn = book['warn'].dup
    warn << "#{info['reserved']} baris dilewati karena memakai kode cadangan U.nnn / C.nnn." if info['reserved'].positive?
    return [nil, 'File Excel ini kosong: tidak ada baris Analisa yang valid (butuh Kode dan Uraian).', warn] if data['ahsp'].empty?

    [JSON.generate(data), nil, warn]
  rescue BoosokTools::RabIo::Error => e
    [nil, e.message]
  end

  # Pilih file JSON atau template Excel, simpan sebagai JSON di folder data user, lalu aktifkan di model ini. Nama sama = diperbarui.
  def self.add_source_file(dialog, state)
    path = UI.openpanel('Tambah file AHSP', default_dir(Sketchup.active_model), 'Excel / JSON|*.xlsx;*.json||')
    return dialog.execute_script('onSourcesCancel();') unless path

    name = safe_source_name(path)
    run_job(dialog, [
      ['rab_pg_check', lambda { |_|
        text, err, warn = read_source_file(path)
        raise UserError, err if err

        [text, warn]
      }],
      ['rab_pg_save', lambda { |(text, warn)|
        FileUtils.mkdir_p(user_data_dir)
        updated = File.exist?(File.join(user_data_dir, name))
        File.write(File.join(user_data_dir, name), text, encoding: 'UTF-8')
        id = "user/#{name}"
        state['sources'] = [id] + (state['sources'] - [id]).first(MAX_SOURCES - 1)
        next_state = normalize_state(state)
        save_state(Sketchup.active_model, next_state)
        [next_state, updated, warn]
      }],
      ['rab_pg_reload', lambda { |(next_state, updated, warn)|
        note = { 'added' => name, 'updated' => updated }
        note['warn'] = warn if warn && !warn.empty?
        sources_script(next_state, note)
      }]
    ])
  end

  # Seluruh isi satu file sumber AHSP dalam format laporan AHSP (sheet AHSP berisi blok per analisa + sheet DHSP berisi semua harga dasar),
  # lengkap dengan kolom Divisi/Kategori/dst. di kanan, jadi bisa diimpor lagi tanpa kehilangan data.
  def self.build_source_workbook(data, label, theme = nil)
    base_by = data['harga_dasar'].to_h { |b| [b['kode'], b] }
    ahsp = data['ahsp'].map { |a| a.merge('komponen' => a['komponen'].select { |c| base_by.key?(c['kode']) }) } # komponen tanpa harga dasar tak bisa dirinci
    database = { 'meta' => data['meta'], 'harga_dasar' => data['harga_dasar'], 'ahsp' => ahsp }
    wb = Xlsx.new(theme)
    sh_ahsp = wb.add_sheet(SHEET_AHSP)
    sh_base = wb.add_sheet(SHEET_DHSP)
    sh_ahsp.selected = true
    op = (data['meta']['overhead_profit_persen'] || 10).to_f
    fill_ahsp_sheets(sh_ahsp, sh_base, ahsp.map { |a| a['kode'] }, database, base_by.transform_values { |b| b['harga'].to_f }, op, extras: true, all_base: true)
    sh_ahsp.set(4, 1, "Sumber : #{label}", style: :muted)
    wb
  end

  # Ekspor satu file sumber AHSP (termasuk yang bawaan) apa adanya: 'json' = file AHSP, 'book' = Excel format laporan yang bisa diimpor lagi
  def self.export_source_file(dialog, state, id, fmt)
    source = load_source(id)
    raise UserError, 'File AHSP ini tidak bisa dibaca.' unless source['data']

    data = source['data']
    ext = fmt == 'json' ? 'json' : 'xlsx'
    label = (data['meta']['nama'].to_s.empty? ? id.split('/', 2).last.sub(/\.json\z/i, '') : data['meta']['nama'])
    path = save_export('Ekspor file AHSP', label, ext)
    return dialog.execute_script('onFileSaved(null);') unless path

    run_job(dialog, [
      ['rab_pg_book', lambda { |_|
        ext == 'json' ? JSON.pretty_generate(data) : build_source_workbook(data, label, theme_for(state))
      }],
      ['rab_pg_write', lambda { |out|
        ext == 'json' ? File.write(path, out, encoding: 'UTF-8') : out.save(path)
        path
      }]
    ]) { |p| dialog.execute_script("onFileSaved(#{p.to_json});") }
  end

  # Template Excel kosong (kind: 'ahsp' atau 'harga') supaya user bisa menambah data sendiri lalu mengimpornya
  def self.export_template_file(dialog, state, kind)
    ahsp = kind == 'ahsp'
    path = save_export(ahsp ? 'Ekspor template AHSP' : 'Ekspor template daftar harga', ahsp ? 'Template AHSP' : 'Template daftar harga', 'xlsx')
    return dialog.execute_script('onFileSaved(null);') unless path

    run_job(dialog, [
      ['rab_pg_book', lambda { |_|
        theme = theme_for(state)
        ahsp ? build_ahsp_workbook(nil, '', theme) : build_price_workbook([], '', theme, template: true)
      }],
      ['rab_pg_write', lambda { |wb|
        wb.save(path)
        path
      }]
    ]) { |p| dialog.execute_script("onFileSaved(#{p.to_json});") }
  end

  # Impor daftar harga (.xlsx hasil edit di Excel, atau .json) -> disimpan sebagai file harga & diaktifkan
  def self.import_price_file(dialog, state)
    path = UI.openpanel('Impor daftar harga', default_dir(Sketchup.active_model), 'Excel / JSON|*.xlsx;*.json||')
    return dialog.execute_script('onSourcesCancel();') unless path

    name = safe_source_name(path)
    run_job(dialog, [
      ['rab_pg_read', ->(_) { BoosokTools::RabIo.read_price_file(path) }],
      ['rab_pg_save', lambda { |data|
        data['meta']['nama'] ||= File.basename(path, '.*')
        data['meta']['diimpor'] = Time.now.strftime('%Y-%m-%d')
        FileUtils.mkdir_p(price_data_dir)
        updated = File.exist?(File.join(price_data_dir, name))
        File.write(File.join(price_data_dir, name), JSON.generate({ 'format' => BoosokTools::RabIo::PRICE_FORMAT, 'versi' => 1 }.merge(data)), encoding: 'UTF-8')
        id = "harga/#{name}"
        state['price_sources'] = [id] + (state['price_sources'] - [id]).first(MAX_SOURCES - 1)
        next_state = normalize_state(state)
        save_state(Sketchup.active_model, next_state)
        row = price_sources_payload(next_state, combined_db(effective_source_ids(next_state['sources']))).fetch('items').find { |i| i['id'] == id }
        raise UserError, 'File harga tersimpan tapi tidak terbaca ulang.' unless row

        [next_state, updated, row]
      }],
      ['rab_pg_reload', lambda { |(next_state, updated, row)|
        sources_script(next_state, 'price_added' => name, 'updated' => updated, 'matched' => row['matched'].to_i, 'total' => row['items'].to_i)
      }]
    ])
  end

  def self.remove_source_file(dialog, state, id)
    run_job(dialog, [
      ['rab_pg_save', lambda { |_|
        if id.to_s.start_with?('user/')
          path = source_path(id)
          state['sources'] -= [id]
        elsif id.to_s.start_with?('harga/')
          path = price_path(id)
          state['price_sources'] -= [id]
        end
        File.delete(path) if path && File.exist?(path)
        @sources&.delete(path)
        @price_files&.delete(path)
        next_state = normalize_state(state)
        save_state(Sketchup.active_model, next_state)
        next_state
      }],
      ['rab_pg_reload', ->(next_state) { sources_script(next_state, 'removed' => id) }]
    ])
  end

  # JavaScript yang mengirim ulang semua data ke dialog setelah sumber / tema berubah (dibuat di langkah, dijalankan di akhir job)
  def self.sources_script(state, note = {})
    "onSources(#{dialog_payload(Sketchup.active_model, state, rescan: false).merge('note' => note).to_json});"
  end

  # Ganti sumber / tema yang dipakai (state dari dialog sudah membawa pilihan baru)
  def self.apply_state_change(dialog, state)
    run_job(dialog, [
      ['rab_pg_save', lambda { |_|
        save_state(Sketchup.active_model, state)
        state
      }],
      ['rab_pg_reload', ->(st) { sources_script(st) }]
    ])
  end

  # ── Tema: template Excel, impor, hapus ──

  def self.export_theme_template(dialog, state)
    path = save_export('Ekspor template tema', 'Template tema RAB', 'xlsx')
    return dialog.execute_script('onFileSaved(null);') unless path

    run_job(dialog, [
      ['rab_pg_book', ->(_) { build_theme_template(theme_for(state)) }],
      ['rab_pg_write', lambda { |wb|
        wb.save(path)
        path
      }]
    ]) { |p| dialog.execute_script("onFileSaved(#{p.to_json});") }
  end

  def self.import_theme_file(dialog, state)
    path = UI.openpanel('Impor template tema', default_dir(Sketchup.active_model), 'Excel|*.xlsx||')
    return dialog.execute_script('onSourcesCancel();') unless path

    name = safe_source_name(path)
    run_job(dialog, [
      ['rab_pg_read', lambda { |_|
        theme = BoosokTools::RabTheme.from_template(File.binread(path), theme_for(state))
        theme['nama'] = File.basename(path, '.*')[0, 80]
        theme
      }],
      ['rab_pg_save', lambda { |theme|
        FileUtils.mkdir_p(theme_data_dir)
        File.write(File.join(theme_data_dir, name), JSON.pretty_generate(BoosokTools::RabTheme.to_json_data(theme)), encoding: 'UTF-8')
        state['theme'] = "user/#{name}"
        next_state = normalize_state(state)
        save_state(Sketchup.active_model, next_state)
        next_state
      }],
      ['rab_pg_reload', ->(next_state) { sources_script(next_state, 'theme_added' => File.basename(name, '.json')) }]
    ])
  end

  def self.remove_theme_file(dialog, state, id)
    run_job(dialog, [
      ['rab_pg_save', lambda { |_|
        path = theme_path(id)
        File.delete(path) if path && File.exist?(path)
        @themes&.delete(path)
        state['theme'] = BoosokTools::RabTheme::DEFAULT_ID if state['theme'] == id
        next_state = normalize_state(state)
        save_state(Sketchup.active_model, next_state)
        next_state
      }],
      ['rab_pg_reload', ->(next_state) { sources_script(next_state, 'theme_removed' => true) }]
    ])
  end

  # Simpan ke file pilihan user; kembalikan path (atau nil kalau dibatalkan)
  def self.save_export(title, name, ext)
    model = Sketchup.active_model
    path = UI.savepanel(title, default_dir(model), "#{safe_filename(name)}.#{ext}")
    return nil unless path

    path.downcase.end_with?(".#{ext}") ? path : "#{path}.#{ext}"
  end

  def self.export_prices_file(dialog, state, fmt)
    project = project_name(Sketchup.active_model)
    ext = fmt == 'json' ? 'json' : 'xlsx'
    path = save_export('Ekspor daftar harga', "Harga - #{project}", ext)
    return dialog.execute_script('onFileSaved(null);') unless path

    database = state_db(state)
    run_job(dialog, [
      ['rab_pg_collect', ->(_) { price_items(database, state) }],
      ['rab_pg_book', lambda { |items|
        ext == 'json' ? JSON.pretty_generate(price_export_json(items, database, project)) : build_price_workbook(items, project, theme_for(state))
      }],
      ['rab_pg_write', lambda { |out|
        ext == 'json' ? File.write(path, out, encoding: 'UTF-8') : out.save(path)
        path
      }]
    ]) { |p| dialog.execute_script("onFileSaved(#{p.to_json});") }
  end

  def self.export_analyses_file(dialog, state, kodes, fmt)
    database = state_db(state)
    project = project_name(Sketchup.active_model)
    kodes = Array(kodes).select { |k| k.is_a?(String) }.first(MAX_EXPORT_ANA)
    have = effective_db(database, state)['ahsp'].to_h { |a| [a['kode'], true] }
    kodes = kodes.select { |k| have[k] }
    return dialog.execute_script("rabError(#{'Tidak ada analisa untuk diekspor.'.to_json});") if kodes.empty?

    # 'xlsx' = laporan AHSP + DHSP (untuk dibaca / dicetak); 'book' = sheet Analisa/Komponen/Harga Dasar yang bisa diimpor lagi
    ext = fmt == 'json' ? 'json' : 'xlsx'
    path = save_export('Ekspor analisa', "Analisa - #{project}", ext)
    return dialog.execute_script('onFileSaved(null);') unless path

    run_job(dialog, [
      ['rab_pg_book', lambda { |_|
        if ext == 'json' then JSON.pretty_generate(analysis_export_data(database, state, kodes, project))
        elsif fmt == 'book' then build_ahsp_workbook(analysis_export_data(database, state, kodes, project), project, theme_for(state))
        else build_analysis_workbook(database, state, kodes, project)
        end
      }],
      ['rab_pg_write', lambda { |out|
        ext == 'json' ? File.write(path, out, encoding: 'UTF-8') : out.save(path)
        path
      }]
    ]) { |p| dialog.execute_script("onFileSaved(#{p.to_json});") }
  end

  def self.attach_callbacks(dialog)
    return unless dialog
    return if @dialog.equal?(dialog) # sudah terdaftar di dialog ini (hindari handler bertumpuk)
    @dialog = dialog

    guarded = lambda do |label, &blk|
      blk.call
    rescue StandardError => e
      puts "[Boosok RAB] #{label}: #{e.class}: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
      msg = "#{label}: #{e.message}"
      dialog.execute_script("rabError(#{msg.to_json});")
    end

    # Hitung ulang dari state dialog (memakai hasil scan terakhir) dan simpan ke model
    dialog.add_action_callback('rab_calc') do |_ctx, json|
      guarded.call('hitung') do
        model = Sketchup.active_model
        next unless model

        state = parse_state(json)
        save_state(model, state)
        @measures ||= scan(model)
        dialog.execute_script("onReport(#{build_report(state_db(state), state, @measures).to_json});")
      end
    end

    dialog.add_action_callback('rab_scan') do |_ctx, json|
      guarded.call('scan') do
        model = Sketchup.active_model
        next unless model

        state = parse_state(json)
        save_state(model, state)
        dialog.execute_script("onScan(#{refresh(model, state).to_json});")
      end
    end

    dialog.add_action_callback('rab_export_xlsx') do |_ctx, json|
      guarded.call('export Excel') do
        state = parse_state(json)
        save_state(Sketchup.active_model, state)
        export_xlsx(dialog, state)
      end
    end

    dialog.add_action_callback('rab_preview') do |_ctx, json|
      guarded.call('pratinjau') do
        state, parts = parse_print_args(json)
        send_preview(dialog, state, parts)
      end
    end

    dialog.add_action_callback('rab_save_pdf') do |_ctx, json|
      guarded.call('simpan PDF') do
        state, parts = parse_print_args(json)
        save_state(Sketchup.active_model, state)
        save_pdf(dialog, state, parts)
      end
    end

    # Ganti sumber data / tema yang dipakai (state dari dialog sudah membawa pilihan baru)
    dialog.add_action_callback('rab_set_sources') do |_ctx, json|
      guarded.call('sumber data') { apply_state_change(dialog, parse_state(json)) }
    end

    dialog.add_action_callback('rab_add_source') do |_ctx, json|
      guarded.call('tambah file AHSP') { add_source_file(dialog, parse_state(json)) }
    end

    dialog.add_action_callback('rab_import_prices') do |_ctx, json|
      guarded.call('impor harga') { import_price_file(dialog, parse_state(json)) }
    end

    dialog.add_action_callback('rab_export_template') do |_ctx, json|
      guarded.call('ekspor template') do
        arg = JSON.parse(json.to_s)
        export_template_file(dialog, normalize_state(arg['state']), arg['kind'])
      end
    end

    dialog.add_action_callback('rab_export_source') do |_ctx, json|
      guarded.call('ekspor file AHSP') do
        arg = JSON.parse(json.to_s)
        export_source_file(dialog, normalize_state(arg['state']), arg['id'], arg['format'])
      end
    end

    dialog.add_action_callback('rab_export_prices') do |_ctx, json|
      guarded.call('ekspor harga') do
        arg = JSON.parse(json.to_s)
        export_prices_file(dialog, normalize_state(arg['state']), arg['format'])
      end
    end

    dialog.add_action_callback('rab_export_analyses') do |_ctx, json|
      guarded.call('ekspor analisa') do
        arg = JSON.parse(json.to_s)
        export_analyses_file(dialog, normalize_state(arg['state']), arg['kodes'], arg['format'])
      end
    end

    dialog.add_action_callback('rab_remove_source') do |_ctx, json|
      guarded.call('hapus file') do
        arg = JSON.parse(json.to_s)
        remove_source_file(dialog, normalize_state(arg['state']), arg['id'])
      end
    end

    dialog.add_action_callback('rab_theme_template') do |_ctx, json|
      guarded.call('template tema') { export_theme_template(dialog, parse_state(json)) }
    end

    dialog.add_action_callback('rab_theme_import') do |_ctx, json|
      guarded.call('impor tema') { import_theme_file(dialog, parse_state(json)) }
    end

    dialog.add_action_callback('rab_theme_remove') do |_ctx, json|
      guarded.call('hapus tema') do
        arg = JSON.parse(json.to_s)
        remove_theme_file(dialog, normalize_state(arg['state']), arg['id'])
      end
    end

    dialog.add_action_callback('rab_export_custom') do |_ctx, json|
      guarded.call('ekspor analisa') { export_custom_file(dialog, parse_state(json)) }
    end

    dialog.add_action_callback('rab_import_custom') do |_ctx, json|
      guarded.call('impor analisa') { import_custom_file(dialog, parse_state(json)) }
    end
  end
end

file_loaded(__FILE__)
