require_relative 'test_helper'
require 'zlib'
require 'stringio'
require 'tmpdir'
require 'fileutils'

BoosokTools::SUPPORT_DIR = PLUGIN unless defined?(BoosokTools::SUPPORT_DIR)
load File.join(PLUGIN, 'ruby', 'paid', 'rab_io.rb')
load File.join(PLUGIN, 'ruby', 'paid', 'rab_theme.rb')
load File.join(PLUGIN, 'ruby', 'paid', 'rab_schedule.rb')
load File.join(PLUGIN, 'ruby', 'paid', 'rab_pdf.rb')
load File.join(PLUGIN, 'ruby', 'paid', 'rab.rb')

# Langkah pekerjaan (progress bar) normalnya dijalankan lewat timer SketchUp; di tes langsung dijalankan
module BoosokTools::Rab
  def self.defer(&blk)
    blk.call
  end
end

# Logika murni RAB (hitung & export). Scan model butuh SketchUp sungguhan, jadi tidak diuji di sini.
class RabTest < Minitest::Test
  R = BoosokTools::Rab

  def setup
    @db = JSON.parse(File.read(File.join(PLUGIN, 'data', 'ahsp_starter.json'), encoding: 'UTF-8'))
  end

  def state(map = {}, extra = {})
    R.normalize_state({ 'map' => map }.merge(extra), @db)
  end

  def measure(**kw)
    R.blank_measure.merge(kw.transform_keys(&:to_s))
  end

  # ── Data ────────────────────────────────────────────────────────────────

  def test_every_ahsp_component_exists_in_base_prices
    kodes = @db['harga_dasar'].map { |h| h['kode'] }
    @db['ahsp'].each do |a|
      a['komponen'].each { |c| assert_includes kodes, c['kode'], "#{a['kode']} memakai komponen tak dikenal #{c['kode']}" }
    end
  end

  def test_unit_basis
    assert_equal 'volume', R.unit_basis('m3')
    assert_equal 'area', R.unit_basis(' M2 ')
    assert_equal 'length', R.unit_basis('m')
    assert_equal 'count', R.unit_basis('bh')
    assert_equal 'manual', R.unit_basis('10 kg')
  end

  # ── HSP ─────────────────────────────────────────────────────────────────

  def test_hsp_matches_hand_calculation
    # Pasangan bata D.01: 70 bata + 11,5 kg PC + 0,043 m3 pasir + upah, lalu + 10% overhead & profit
    base = @db['harga_dasar'].to_h { |h| [h['kode'], h] }
    prices = R.effective_prices(@db, {})
    item = @db['ahsp'].find { |a| a['kode'] == 'D.01' }
    bd = R.ahsp_breakdown(item, base, prices, 10)
    bahan = (70 * 900) + (11.5 * 1400) + (0.043 * 280_000)
    upah = (0.3 * 120_000) + (0.1 * 150_000) + (0.01 * 165_000) + (0.015 * 175_000)
    assert_in_delta bahan, bd['bahan'], 1e-6
    assert_in_delta upah, bd['upah'], 1e-6
    assert_in_delta (bahan + upah) * 1.1, bd['hsp'], 1e-6
  end

  def test_price_override_changes_hsp_only_for_items_using_it
    base = @db['harga_dasar'].to_h { |h| [h['kode'], h] }
    cheap = R.effective_prices(@db, {})
    dear = R.effective_prices(@db, { 'M.01' => 2000 }) # semen
    bata = @db['ahsp'].find { |a| a['kode'] == 'D.01' }
    galian = @db['ahsp'].find { |a| a['kode'] == 'A.01' }
    assert_operator R.ahsp_breakdown(bata, base, dear, 10)['hsp'], :>, R.ahsp_breakdown(bata, base, cheap, 10)['hsp']
    assert_in_delta R.ahsp_breakdown(galian, base, dear, 10)['hsp'], R.ahsp_breakdown(galian, base, cheap, 10)['hsp'], 1e-9
  end

  # ── State ───────────────────────────────────────────────────────────────

  def test_normalize_drops_unknown_codes_and_bad_numbers
    st = R.normalize_state({
      'map' => { 'A' => { 'kode' => 'NOPE' }, 'B' => { 'kode' => 'D.01', 'basis' => 'zzz', 'factor' => -3, 'manual' => 'abc' } },
      'prices' => { 'M.01' => '1750', 'M.99' => 5, 'M.02' => -1 }, 'op' => 500, 'ppn' => 'x'
    }, @db)
    assert_equal ['tag:B'], st['map'].keys
    assert_equal 'auto', st['map']['tag:B']['basis']
    assert_equal 1.0, st['map']['tag:B']['factor']
    assert_nil st['map']['tag:B']['manual']
    assert_equal({ 'M.01' => 1750.0 }, st['prices'])
    assert_equal 100, st['op']
    assert_equal 11, st['ppn']
  end

  def test_normalize_survives_garbage
    assert_equal({}, R.normalize_state('bukan hash', @db)['map'])
    assert_equal({}, R.normalize_state(nil, @db)['map'])
  end

  # ── Volume per baris ────────────────────────────────────────────────────

  def test_quantity_follows_ahsp_unit
    m = measure('count' => 3, 'length' => 12.0, 'area' => 40.0, 'volume' => 2.5)
    e = { 'basis' => 'auto', 'factor' => 1.0, 'manual' => nil }
    assert_equal [2.5, 'volume', 'auto'], R.quantity(m, e, 'm3')
    assert_equal [40.0, 'area', 'auto'], R.quantity(m, e, 'm2')
    assert_equal [12.0, 'length', 'auto'], R.quantity(m, e, 'm')
    assert_equal [3, 'count', 'auto'], R.quantity(m, e, 'bh')
    assert_equal [0.0, 'manual', 'auto'], R.quantity(m, e, '10 kg')
  end

  def test_quantity_factor_basis_and_manual_override
    m = measure('area' => 40.0, 'volume' => 2.0)
    assert_equal [20.0, 'area', 'auto'], R.quantity(m, { 'basis' => 'area', 'factor' => 0.5, 'manual' => nil }, 'm3')
    assert_equal [7.0, 'manual', 'manual'], R.quantity(m, { 'basis' => 'auto', 'factor' => 1.0, 'manual' => 7.0 }, 'm3')
    assert_equal [0.0, 'manual', 'manual'], R.quantity(m, { 'basis' => 'auto', 'factor' => 1.0, 'manual' => 0.0 }, 'm3'), '0 manual tetap override'
  end

  # ── Laporan ─────────────────────────────────────────────────────────────

  def test_report_totals_and_ppn
    st = state({ 'Dinding' => { 'kode' => 'D.01' }, 'Lantai' => { 'kode' => 'E.02' } })
    ms = { 'tag:Dinding' => measure('area' => 100.0), 'tag:Lantai' => measure('area' => 50.0) }
    rep = R.build_report(@db, st, ms)
    assert_equal 2, rep['rows'].size
    dinding = rep['rows'].find { |r| r['tag'] == 'Dinding' }
    assert_equal 100.0, dinding['qty']
    assert_in_delta dinding['qty'] * dinding['hsp'], dinding['jumlah'], 1e-6
    assert_in_delta rep['rows'].sum { |r| r['jumlah'] }, rep['subtotal'], 1e-6
    assert_in_delta rep['subtotal'] * 0.11, rep['ppn'], 1e-6
    assert_in_delta rep['subtotal'] + rep['ppn'], rep['total'], 1e-6
    assert_in_delta rep['subtotal'], rep['divisi'].sum { |d| d['subtotal'] }, 1e-6
  end

  def test_report_ppn_off_and_warnings
    st = state({ 'Beton' => { 'kode' => 'C.02' }, 'Kosong' => { 'kode' => 'D.03' } }, 'ppn_on' => false)
    ms = { 'tag:Beton' => measure('volume' => 0.0, 'nonsolid' => 2) }
    rep = R.build_report(@db, st, ms)
    assert_equal 0.0, rep['ppn']
    assert_equal rep['subtotal'], rep['total']
    assert_equal 'nonsolid', rep['rows'].find { |r| r['tag'] == 'Beton' }['warn']
    assert_equal 'zero', rep['rows'].find { |r| r['tag'] == 'Kosong' }['warn']
  end

  def test_report_empty
    rep = R.build_report(@db, state, {})
    assert_equal 0.0, rep['total']
    assert_empty rep['rows']
  end

  def test_report_unpriced_and_used_base
    st = state({ 'Dinding' => { 'kode' => 'D.01' } })
    rep = R.build_report(@db, st, { 'tag:Dinding' => measure('area' => 10.0) })
    d01 = @db['ahsp'].find { |x| x['kode'] == 'D.01' }['komponen'].map { |c| c['kode'] }
    assert_equal d01, rep['used_base']
    assert_equal 0, rep['unpriced'], 'database contoh punya harga semua'
    free = st.merge('prices' => { 'M.01' => 0.0 })
    assert_equal 1, R.build_report(@db, free, { 'tag:Dinding' => measure('area' => 10.0) })['unpriced']
  end

  def test_kode_sort_key_orders_numerically_per_segment
    kodes = %w[1.10 1.2 1.2.1 2.2.1.1.3a 2.2.1.1.3 2.2.1.1.10 2.2.1.1.9]
    assert_equal %w[1.2 1.2.1 1.10 2.2.1.1.3 2.2.1.1.3a 2.2.1.1.9 2.2.1.1.10], kodes.sort_by { |k| R.kode_sort_key(k) }
  end

  # ── Database SE DJBK 47/2026 (hasil tools/extract-ahsp) ──────────────────

  def test_se47_database_is_consistent
    path = File.join(PLUGIN, 'data', 'ahsp_se47_2026.json')
    skip 'ahsp_se47_2026.json belum dibuat (jalankan tools/extract-ahsp)' unless File.exist?(path)

    db = JSON.parse(File.read(path, encoding: 'UTF-8'))
    kodes = db['harga_dasar'].map { |h| h['kode'] }
    assert_equal kodes.uniq.size, kodes.size, 'kode harga dasar harus unik'
    assert_equal db['ahsp'].map { |a| a['kode'] }.uniq.size, db['ahsp'].size, 'kode AHSP harus unik'
    assert_empty db['harga_dasar'].map { |h| h['jenis'] }.uniq - %w[upah bahan alat]
    db['ahsp'].each do |a|
      refute_empty a['komponen'], "#{a['kode']} tanpa komponen"
      a['komponen'].each do |c|
        assert_includes kodes, c['kode'], "#{a['kode']} memakai komponen tak dikenal #{c['kode']}"
        assert_operator c['koef'], :>, 0, "#{a['kode']} koefisien #{c['kode']} harus positif"
      end
    end
    cat = R.catalog(db)
    assert_equal db['ahsp'].size, cat.size
    assert(cat.all? { |c| c['kategori'].is_a?(String) })
  end

  def test_se47_hsp_matches_hand_calculation
    path = File.join(PLUGIN, 'data', 'ahsp_se47_2026.json')
    skip 'ahsp_se47_2026.json belum dibuat' unless File.exist?(path)

    db = JSON.parse(File.read(path, encoding: 'UTF-8'))
    # 1.3.1.2 (urukan pasir manual): 0,3 Pekerja + 0,015 Mandor + 1,2 m3 pasir uruk
    item = db['ahsp'].find { |a| a['kode'] == '1.3.1.2' }
    pasir = item['komponen'].find { |c| c['kode'].start_with?('M.') }['kode']
    base = db['harga_dasar'].to_h { |h| [h['kode'], h] }
    prices = R.effective_prices(db, { 'L.01' => 100_000, 'L.04' => 200_000, pasir => 250_000 })
    bd = R.ahsp_breakdown(item, base, prices, 10)
    assert_in_delta (0.3 * 100_000 + 0.015 * 200_000 + 1.2 * 250_000) * 1.1, bd['hsp'], 1e-6
    assert_equal 'm3', item['satuan']
    assert_equal 'volume', R.unit_basis(item['satuan'])
  end

  def test_volume_scale_is_determinant_of_parent_transform
    assert_in_delta 8.0, R.volume_scale(Geom::Transformation.scaling(2)), 1e-9
    assert_in_delta 1.0, R.volume_scale(Geom::Transformation.translation(100, 5, -3)), 1e-9
    assert_in_delta 1.0, R.volume_scale(Geom::Transformation.new), 1e-9
    assert_in_delta 6.0, R.volume_scale(Geom::Transformation.scaling(1, 2, 3)), 1e-9
    assert_in_delta 1.0, R.volume_scale(Geom::Transformation.scaling(-1, 1, 1)), 1e-9, 'cermin tidak boleh membuat volume negatif'
  end

# ── Sumber: tag vs material, luas bidang ────────────────────────────────

def test_keys_distinguish_tag_and_material_and_accept_legacy_keys
  st = state({ 'Brick' => { 'kode' => 'D.01' }, 'mat:Cat Putih' => { 'kode' => 'E.01' }, 'tag:Brick' => { 'kode' => 'D.02' } })
  assert_equal ['tag:Brick', 'mat:Cat Putih'].sort, st['map'].keys.sort
  assert_equal ['mat', 'Cat Putih'], R.split_key('mat:Cat Putih')
  assert_equal ['tag', 'A:B'], R.split_key('tag:A:B'), 'nama boleh memuat titik dua'
end

def test_material_source_prices_painted_area_without_double_counting
  st = state({ 'mat:Cat Putih' => { 'kode' => 'E.01' } })
  rep = R.build_report(@db, st, { 'mat:Cat Putih' => measure('area' => 171.0, 'count' => 12) })
  row = rep['rows'].first
  assert_equal 'mat', row['kind']
  assert_equal 'Material: Cat Putih', row['label']
  assert_equal 'area', row['basis']
  assert_equal 171.0, row['qty']
end

def test_plane_area_of_thick_wall_is_one_side_not_all_faces
  # dinding 0,1 x 3 x 5 m: dua sisi besar 15 m2, dua sisi samping 0,5 m2, dua ujung 0,3 m2
  faces = [[0, 1, 0, 15.0], [0, -1, 0, 15.0], [1, 0, 0, 0.3], [-1, 0, 0, 0.3], [0, 0, 1, 0.5], [0, 0, -1, 0.5]]
  assert_in_delta 15.0, R.plane_area(faces), 1e-9
  assert_in_delta 31.6, faces.sum { |f| f[3] }, 1e-9, 'jumlah semua face jauh lebih besar'
end

def test_plane_area_handles_rotated_and_empty
  s = Math.sqrt(0.5)
  rotated = [[s, s, 0, 10.0], [-s, -s, 0, 10.0], [s, -s, 0, 0.4], [-s, s, 0, 0.4]]
  assert_in_delta 10.0, R.plane_area(rotated), 1e-9
  assert_equal 0.0, R.plane_area([])
  assert_equal 0.0, R.plane_area([[0, 0, 0, 5.0]]), 'normal nol diabaikan'
end

def test_auto_m2_uses_plane_for_solid_but_all_faces_for_loose_faces
  e = { 'basis' => 'auto', 'factor' => 1.0, 'manual' => nil }
  solid = measure('area' => 31.6, 'plane' => 15.0, 'volume' => 1.5)
  assert_equal [15.0, 'plane', 'auto'], R.quantity(solid, e, 'm2')
  loose = measure('area' => 40.0)
  assert_equal [40.0, 'area', 'auto'], R.quantity(loose, e, 'm2')
  forced = { 'basis' => 'area', 'factor' => 1.0, 'manual' => nil }
  assert_equal [31.6, 'area', 'auto'], R.quantity(solid, forced, 'm2'), 'basis manual tetap menang'
end

def test_nonsolid_warning_applies_to_plane_too
  st = state({ 'tag:Dinding' => { 'kode' => 'D.01' } }.transform_keys { |k| k.delete_prefix('tag:') })
  rep = R.build_report(@db, st, { 'tag:Dinding' => measure('area' => 5.0, 'nonsolid' => 1) })
  assert_nil rep['rows'].first['warn'], 'luas face lepas tidak butuh solid'
  st2 = state({ 'Dinding' => { 'kode' => 'D.01', 'basis' => 'plane' } })
  rep2 = R.build_report(@db, st2, { 'tag:Dinding' => measure('nonsolid' => 1) })
  assert_equal 'nonsolid', rep2['rows'].first['warn']
end

def test_fmt_num_indonesian_style
    assert_equal '1.234.567', R.fmt_num(1_234_567)
    assert_equal '1.234,50', R.fmt_num(1234.5, 2)
    assert_equal '-9.800', R.fmt_num(-9800)
    assert_equal '0', R.fmt_num(0)
  end

  # ── XLSX ────────────────────────────────────────────────────────────────

  # Baca ZIP hasil tulisan sendiri: {nama => isi}. Sekaligus memverifikasi CRC & direktori pusat.
  def unzip(bin)
    eocd = bin.rindex([0x06054b50].pack('V'))
    refute_nil eocd, 'EOCD tidak ada'
    _sig, _d1, _d2, n, _n2, _size, cd_off = bin[eocd, 22].unpack('VvvvvVV')
    files = {}
    pos = cd_off
    n.times do
      f = bin[pos, 46].unpack('VvvvvvvVVVvvvvvVV')
      crc, csize, usize, nlen, xlen, clen, off = f[7], f[8], f[9], f[10], f[11], f[12], f[16]
      name = bin[pos + 46, nlen]
      lh = bin[off, 30].unpack('VvvvvvVVVvv')
      data_start = off + 30 + lh[9] + lh[10]
      raw = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(bin[data_start, csize])
      assert_equal usize, raw.bytesize, "#{name}: ukuran"
      assert_equal crc, Zlib.crc32(raw), "#{name}: crc"
      files[name] = raw.force_encoding('UTF-8')
      pos += 46 + nlen + xlen + clen
    end
    files
  end

  def sample_workbook
    st = state({ 'Dinding' => { 'kode' => 'D.01' }, 'Beton' => { 'kode' => 'C.02', 'manual' => 3.5 } }, 'prices' => { 'M.01' => 1500 })
    rep = R.build_report(@db, st, { 'tag:Dinding' => measure('area' => 80.0) })
    [R.build_workbook(rep, @db, st, 'Rumah <A> & B'), rep]
  end

  def test_xlsx_is_valid_zip_with_expected_parts
    wb, = sample_workbook
    files = unzip(wb.to_binary)
    %w[[Content_Types].xml _rels/.rels xl/workbook.xml xl/_rels/workbook.xml.rels xl/styles.xml
       xl/worksheets/sheet1.xml xl/worksheets/sheet2.xml xl/worksheets/sheet3.xml xl/worksheets/sheet4.xml xl/worksheets/sheet5.xml
       xl/drawings/drawing1.xml xl/charts/chart1.xml xl/worksheets/_rels/sheet5.xml.rels xl/drawings/_rels/drawing1.xml.rels].each do |part|
      assert files.key?(part), "bagian #{part} hilang"
    end
    names = files['xl/workbook.xml'].scan(/<sheet name="([^"]+)"/).flatten
    assert_equal ["Rekapitulasi", "RAB", "DHSP", "AHSP", "Kurva S"], names, 'urutan sheet: rekapitulasi, RAB, DHSP, AHSP, kurva S'
  end

  def test_xlsx_parts_are_well_formed_xml
    begin
      require 'rexml/document'
    rescue LoadError
      skip 'rexml tidak terpasang'
    end
    wb, = sample_workbook
    unzip(wb.to_binary).each do |name, xml|
      REXML::Document.new(xml)
    rescue StandardError => e
      flunk "#{name}: XML tidak valid (#{e.message})"
    end
  end

  def test_xlsx_escapes_text_and_keeps_formulas_live
    wb, rep = sample_workbook
    files = unzip(wb.to_binary)
    rab = files['xl/worksheets/sheet2.xml']
    assert_includes rab, 'Rumah &lt;A&gt; &amp; B'
    refute_includes rab, 'Rumah <A>'
    assert_match(%r{<f>D\d+\*E\d+</f>}, rab, 'Jumlah harus formula Volume x Harga')
    assert_match(%r{<f>AHSP!\$F\$\d+</f>}, rab, 'Harga satuan harus menunjuk sheet AHSP')
    assert_includes files['xl/worksheets/sheet4.xml'], 'INDEX(DHSP!', 'AHSP menarik harga dari sheet DHSP'
    assert_includes rab, "<v>#{format('%.12g', rep['total'])}</v>", 'nilai cache total'
  end

  def test_xlsx_price_override_is_written_to_base_sheet
    wb, = sample_workbook
    base = unzip(wb.to_binary)['xl/worksheets/sheet3.xml']
    assert_includes base, 'DAFTAR HARGA BAHAN (DHSP)'
    assert_includes base, '<v>1500</v>' # harga semen yang diubah
  end

  def test_xlsx_empty_report_still_builds
    st = state
    rep = R.build_report(@db, st, {})
    files = unzip(R.build_workbook(rep, @db, st, 'Kosong').to_binary)
    assert files['xl/worksheets/sheet2.xml'].include?('TOTAL')
    refute files.key?('xl/charts/chart1.xml'), 'tanpa pekerjaan tidak ada grafik'
  end

  def test_col_letters
    assert_equal 'A', R::Xlsx.col_letter(1)
    assert_equal 'Z', R::Xlsx.col_letter(26)
    assert_equal 'AA', R::Xlsx.col_letter(27)
  end

  # ── Analisa sendiri ─────────────────────────────────────────────────────

  def custom_sample
    {
      'base' => [{ 'kode' => 'C.001', 'jenis' => 'bahan', 'nama' => 'Keramik Sendiri 40x40', 'satuan' => 'm2', 'harga' => 1000 }],
      'ahsp' => [{ 'kode' => 'U.001', 'uraian' => 'Pasang keramik sendiri', 'satuan' => 'm2',
                   'komponen' => [{ 'kode' => 'L.01', 'koef' => 0.5 }, { 'kode' => 'C.001', 'koef' => 2 }] }]
    }
  end

  def test_custom_is_normalized_and_bad_entries_dropped
    raw = custom_sample
    raw['base'] << { 'kode' => 'M.01', 'nama' => 'Bentrok dengan resmi' } << { 'kode' => 'C.002', 'nama' => '   ' } << 'bukan hash'
    raw['ahsp'] << { 'kode' => 'A.01', 'uraian' => 'Bentrok' } << { 'kode' => 'U.002', 'uraian' => 'Komponen rusak',
                                                                    'komponen' => [{ 'kode' => 'NOPE', 'koef' => 1 }, { 'kode' => 'L.01', 'koef' => -2 }, { 'kode' => 'L.01', 'koef' => '3' }] }
    c = R.normalize_custom(raw, @db)
    assert_equal ['C.001'], c['base'].map { |x| x['kode'] }
    assert_equal %w[U.001 U.002], c['ahsp'].map { |x| x['kode'] }
    assert_equal [{ 'kode' => 'L.01', 'koef' => 3.0 }], c['ahsp'].last['komponen']
  end

  def test_custom_ahsp_is_usable_in_report_and_state
    st = state({ 'Lantai' => { 'kode' => 'U.001' } }, 'custom' => custom_sample)
    assert_equal ['tag:Lantai'], st['map'].keys, 'kode analisa sendiri harus dikenal'
    rep = R.build_report(@db, st, { 'tag:Lantai' => measure('area' => 10.0, 'plane' => 10.0) })
    row = rep['rows'].first
    assert_equal R::CUSTOM_DIVISI, row['divisi']
    assert_in_delta ((0.5 * 120_000) + (2 * 1000)) * 1.1, row['hsp'], 1e-6
    assert_includes rep['used_base'], 'C.001'
    st2 = state({ 'Lantai' => { 'kode' => 'U.001' } }, 'custom' => custom_sample, 'prices' => { 'C.001' => 5000 })
    assert_operator R.build_report(@db, st2, { 'tag:Lantai' => measure('area' => 10.0, 'plane' => 10.0) })['rows'].first['hsp'], :>, row['hsp']
    assert(R.catalog(R.merge_custom(@db, st['custom'])).any? { |c| c['kode'] == 'U.001' })
    assert(R.build_workbook(rep, @db, st, 'Tes').to_binary.bytesize.positive?)
  end

  def test_unknown_custom_code_is_dropped_without_custom_data
    assert_empty state({ 'Lantai' => { 'kode' => 'U.001' } })['map']
  end

  def test_custom_export_import_roundtrip_renumbers_and_matches_names
    custom = R.normalize_custom(custom_sample, @db)
    data = JSON.parse(JSON.generate(R.export_custom(custom, @db)))
    assert_equal R::CUSTOM_FORMAT, data['format']
    assert_equal 'Pekerja', data['ahsp'].first['komponen'].first['nama']
    # impor ke model yang sudah punya U.001 / C.001: nomor baru, harga dasar sendiri dipakai ulang (nama+satuan sama)
    merged, info = R.import_custom(custom, data, @db)
    assert_equal %w[U.001 U.002], merged['ahsp'].map { |a| a['kode'] }
    assert_equal ['C.001'], merged['base'].map { |b| b['kode'] }
    assert_equal 1, info['ahsp']
    # kode resmi berbeda tapi nama+satuan sama -> dipetakan ulang
    data['ahsp'].first['komponen'].first['kode'] = 'L.99'
    fresh, info2 = R.import_custom(R.blank_custom, data, @db)
    assert_equal 'L.01', fresh['ahsp'].first['komponen'].first['kode']
    assert_equal 1, info2['diganti']
    # komponen resmi yang tidak ada padanannya jadi harga dasar sendiri
    data['ahsp'].first['komponen'] << { 'kode' => 'M.9999', 'koef' => 1, 'nama' => 'Bahan Hilang', 'satuan' => 'kg', 'jenis' => 'bahan' }
    again, = R.import_custom(R.blank_custom, data, @db)
    assert(again['base'].any? { |b| b['nama'] == 'Bahan Hilang' && b['harga'].zero? })
    assert_equal [custom, 0], [R.import_custom(custom, { 'format' => 'lain' }, @db)[0], 0]
  end

  def test_ahsp_comps_lists_original_components
    comps = R.ahsp_comps(@db)
    d01 = @db['ahsp'].find { |a| a['kode'] == 'D.01' }
    assert_equal d01['komponen'].map { |c| [c['kode'], c['koef']] }, comps['D.01']
    assert_equal @db['ahsp'].size, comps.size
  end

  # ── Komponen AHSP resmi yang diubah user (override) ────────────────────

  def test_override_changes_official_ahsp_without_touching_database
    d01 = @db['ahsp'].find { |a| a['kode'] == 'D.01' }
    before = Marshal.load(Marshal.dump(d01))
    first = d01['komponen'].first
    ov = { 'D.01' => { 'komponen' => [{ 'kode' => first['kode'], 'koef' => first['koef'] * 2 }] } }
    plain = state({ 'Dinding' => { 'kode' => 'D.01' } })
    edited = state({ 'Dinding' => { 'kode' => 'D.01' } }, 'overrides' => ov)
    assert_equal ov, edited['overrides'].transform_values { |o| o.slice('komponen') }
    ms = { 'tag:Dinding' => measure('area' => 10.0, 'plane' => 10.0) }
    hsp = ->(st) { R.build_report(@db, st, ms)['rows'].first['hsp'] }
    prices = R.effective_prices(@db, {})
    expect = first['koef'] * 2 * prices[first['kode']] * 1.1
    assert_in_delta expect, hsp.call(edited), 1e-6
    refute_in_delta hsp.call(plain), hsp.call(edited), 1e-6
    assert_equal before, d01, 'database resmi tidak boleh berubah'
    assert_equal [first['kode']], R.build_report(@db, edited, ms)['used_base']
  end

  def test_override_drops_bad_components_but_keeps_unknown_ones_on_hold
    ov = { 'D.01' => { 'komponen' => [{ 'kode' => 'L.01', 'koef' => '2' }, { 'kode' => 'L.02', 'koef' => -1 }, { 'kode' => 'ZZ.9', 'koef' => 3 }, 'x'] },
           'NOPE.1' => { 'komponen' => [{ 'kode' => 'L.01', 'koef' => 1 }] } }
    st = state({}, 'overrides' => ov)
    assert_equal [{ 'kode' => 'L.01', 'koef' => 2.0 }], st['overrides']['D.01']['komponen']
    assert_equal [{ 'kode' => 'ZZ.9', 'koef' => 3.0 }], st['overrides']['D.01']['hold_komponen']
    assert_equal ['NOPE.1'], st['hold']['overrides'].keys, 'override untuk AHSP yang belum ada disimpan, bukan dibuang'
    assert_equal st, R.normalize_state(JSON.parse(JSON.generate(st)), @db), 'normalisasi harus idempoten'
  end

  # ── Pilihan yang sumber datanya sedang tidak dipakai tidak boleh hilang ──

  def test_choices_for_missing_source_are_held_and_restored
    raw = { 'map' => { 'Dinding' => { 'kode' => 'D.01', 'factor' => 2 } }, 'prices' => { 'M.01' => 1750 },
            'overrides' => { 'D.01' => { 'komponen' => [{ 'kode' => 'L.01', 'koef' => 1 }] } } }
    partial = @db.merge('ahsp' => @db['ahsp'].reject { |a| a['kode'] == 'D.01' },
                        'harga_dasar' => @db['harga_dasar'].reject { |h| h['kode'] == 'M.01' })
    off = R.normalize_state(raw, partial)
    assert_empty off['map']
    assert_empty off['prices']
    assert_equal ['tag:Dinding'], off['hold']['map'].keys
    assert_equal({ 'M.01' => 1750.0 }, off['hold']['prices'])
    assert_equal ['D.01'], off['hold']['overrides'].keys
    # round-trip lewat JSON (seperti dialog) lalu sumber aktif lagi
    on = R.normalize_state(JSON.parse(JSON.generate(off)), @db)
    assert_equal 2.0, on['map']['tag:Dinding']['factor']
    assert_equal({ 'M.01' => 1750.0 }, on['prices'])
    assert_equal ['D.01'], on['overrides'].keys
    assert_equal({ 'map' => {}, 'prices' => {}, 'overrides' => {} }, on['hold'])
  end

  def test_custom_components_with_unknown_code_are_held_not_dropped
    custom = custom_sample
    custom['ahsp'].first['komponen'] << { 'kode' => 'ZZ.9', 'koef' => 4 }
    c = R.normalize_custom(custom, @db)
    assert_equal [{ 'kode' => 'ZZ.9', 'koef' => 4.0 }], c['ahsp'].first['hold_komponen']
    refute(c['ahsp'].first['komponen'].any? { |k| k['kode'] == 'ZZ.9' })
    withzz = @db.merge('harga_dasar' => @db['harga_dasar'] + [{ 'kode' => 'ZZ.9', 'jenis' => 'bahan', 'nama' => 'Baru', 'satuan' => 'kg', 'harga' => 1 }])
    back = R.normalize_custom(JSON.parse(JSON.generate(c)), withzz)
    assert_includes back['ahsp'].first['komponen'].map { |k| k['kode'] }, 'ZZ.9'
    assert_nil back['ahsp'].first['hold_komponen']
  end

  # ── Sumber data (file JSON) ─────────────────────────────────────────────

  def source_json(extra = {})
    { 'meta' => { 'nama' => 'Sumber Uji', 'versi' => '1' },
      'harga_dasar' => [{ 'kode' => 'X.01', 'jenis' => 'bahan', 'nama' => 'Bahan X', 'satuan' => 'kg', 'harga' => 100 },
                        { 'kode' => 'X.01', 'jenis' => 'bahan', 'nama' => 'Dobel', 'satuan' => 'kg', 'harga' => 1 },
                        { 'kode' => 'C.001', 'jenis' => 'bahan', 'nama' => 'Bentrok C', 'satuan' => 'kg', 'harga' => 1 },
                        { 'kode' => 'X.02', 'jenis' => 'aneh', 'nama' => 'Jenis salah', 'satuan' => 'kg', 'harga' => 1 },
                        'sampah'],
      'ahsp' => [{ 'kode' => 'X.1', 'divisi' => 'Divisi X', 'uraian' => 'Pekerjaan X', 'satuan' => 'm2',
                   'komponen' => [{ 'kode' => 'X.01', 'koef' => 2 }, { 'kode' => 'L.01', 'koef' => 0.5 }, { 'kode' => 'NOPE', 'koef' => 1 }, { 'kode' => 'X.01', 'koef' => 0 }] },
                 { 'kode' => 'U.001', 'uraian' => 'Bentrok U', 'satuan' => 'm2', 'komponen' => [] },
                 { 'kode' => 'D.01', 'uraian' => 'Menimpa D.01', 'satuan' => 'm2', 'komponen' => [{ 'kode' => 'X.01', 'koef' => 1 }] },
                 { 'uraian' => 'tanpa kode' }] }.merge(extra)
  end

  def test_sanitize_source_filters_bad_entries
    data, info = R.sanitize_source(JSON.parse(JSON.generate(source_json)))
    assert_equal ['X.01'], data['harga_dasar'].map { |b| b['kode'] }
    assert_equal %w[X.1 D.01], data['ahsp'].map { |a| a['kode'] }
    assert_equal 2, info['reserved'], 'kode U.xxx / C.xxx dicadangkan untuk buatan sendiri'
    assert_equal 'Divisi X', data['ahsp'].first['divisi']
    assert_equal 'Lainnya', data['ahsp'].last['divisi']
    assert_equal [{ 'kode' => 'X.01', 'koef' => 2.0 }, { 'kode' => 'L.01', 'koef' => 0.5 }, { 'kode' => 'NOPE', 'koef' => 1.0 }], data['ahsp'].first['komponen']
    assert_nil R.sanitize_source('bukan hash').first
    assert_nil R.sanitize_source({ 'items' => [] }).first
  end

  # Folder sementara pengganti folder data bawaan & folder data user
  def with_sources(user_files = {})
    Dir.mktmpdir do |root|
      app = File.join(root, 'app')
      user = File.join(root, 'user')
      FileUtils.mkdir_p([app, user])
      FileUtils.cp(File.join(PLUGIN, 'data', 'ahsp_starter.json'), app)
      user_files.each { |name, content| File.write(File.join(user, name), content.is_a?(String) ? content : JSON.generate(content)) }
      R.stub(:app_data_dir, app) { R.stub(:user_data_dir, user) { yield app, user } }
    end
  end

  def test_sources_default_to_bundled_and_list_user_files_first
    with_sources('b.json' => source_json, 'a.json' => source_json) do
      assert_equal ['app/ahsp_starter.json'], R.default_sources
      assert_equal %w[user/a.json user/b.json app/ahsp_starter.json], R.available_source_ids
      assert_equal ['app/ahsp_starter.json'], R.normalize_state({})['sources']
      assert_equal %w[user/a.json], R.normalize_sources(['user/a.json', 'user/a.json', '../x.json', 'user/../b.json', 5, 'app/x.txt'])
      # id yang file-nya tidak ada tetap diingat di model, tapi tidak dipakai menghitung
      assert_equal %w[user/hilang.json], R.normalize_sources(['user/hilang.json'])
      assert_equal ['app/ahsp_starter.json'], R.effective_source_ids(['user/hilang.json'])
    end
  end

  def test_combined_db_uses_priority_and_drops_unknown_components
    with_sources('x.json' => source_json) do
      db = R.combined_db(%w[user/x.json app/ahsp_starter.json])
      x = db['ahsp'].find { |a| a['kode'] == 'X.1' }
      assert_equal %w[X.01 L.01], x['komponen'].map { |c| c['kode'] }, 'komponen tanpa harga dasar dibuang'
      d01 = db['ahsp'].select { |a| a['kode'] == 'D.01' }
      assert_equal 1, d01.size
      assert_equal 'Menimpa D.01', d01.first['uraian'], 'sumber di atas menang'
      assert_equal 1, db['harga_dasar'].count { |h| h['kode'] == 'L.01' }
      only = R.combined_db(['user/x.json'])
      assert_equal %w[X.01], only['harga_dasar'].map { |h| h['kode'] }
      assert_equal 'Sumber Uji', only['meta']['nama']
      assert_includes db['meta']['nama'], ' + '
    end
  end

  def test_state_uses_selected_sources_and_survives_switching
    with_sources('x.json' => source_json) do
      st = R.normalize_state({ 'sources' => ['user/x.json'], 'map' => { 'Dinding' => { 'kode' => 'X.1' } } })
      assert_equal ['tag:Dinding'], st['map'].keys
      rep = R.build_report(R.state_db(st), st, { 'tag:Dinding' => measure('area' => 4.0, 'plane' => 4.0) })
      assert_equal 'X.1', rep['rows'].first['kode']
      # pindah ke sumber bawaan saja: pilihan disimpan di hold; kembali lagi pulih
      off = R.normalize_state(JSON.parse(JSON.generate(st.merge('sources' => ['app/ahsp_starter.json']))))
      assert_empty off['map']
      assert_equal ['tag:Dinding'], off['hold']['map'].keys
      on = R.normalize_state(JSON.parse(JSON.generate(off.merge('sources' => ['user/x.json']))))
      assert_equal ['tag:Dinding'], on['map'].keys
      payload = R.sources_payload(st)
      assert_equal %w[user/x.json app/ahsp_starter.json], payload['items'].map { |i| i['id'] }
      assert_equal [true, false], payload['items'].map { |i| i['active'] }
      assert_equal [4, 2], payload['items'].first.values_at('skipped', 'reserved')
    end
  end

  def test_broken_source_files_are_reported_not_fatal
    with_sources('rusak.json' => '{ bukan json', 'harga.json' => { 'items' => [{ 'kode' => 'L01' }] }) do
      items = R.sources_payload(R.normalize_state({}))['items']
      assert_equal 'json', items.find { |i| i['id'] == 'user/rusak.json' }['error']
      assert_equal 'format', items.find { |i| i['id'] == 'user/harga.json' }['error']
      assert_equal ['app/ahsp_starter.json'], R.effective_source_ids(['user/rusak.json'])
      assert_equal @db['ahsp'].size, R.state_db(R.normalize_state({ 'sources' => ['user/rusak.json'] }))['ahsp'].size
    end
  end

  def test_read_source_file_validates_before_importing
    Dir.mktmpdir do |dir|
      write = ->(name, content) { File.join(dir, name).tap { |p| File.write(p, content.is_a?(String) ? content : JSON.generate(content)) } }
      text, err = R.read_source_file(write.call('ok.json', source_json))
      assert_nil err
      assert JSON.parse(text)['ahsp']
      assert_match(/bukan JSON/, R.read_source_file(write.call('a.json', '{ x'))[1])
      assert_match(/daftar harga/, R.read_source_file(write.call('b.json', { 'items' => [] }))[1])
      assert_match(/Bukan file AHSP/, R.read_source_file(write.call('c.json', [1, 2]))[1])
      assert_match(/kosong/, R.read_source_file(write.call('d.json', { 'ahsp' => [{ 'kode' => 'U.001', 'uraian' => 'x' }] }))[1])
      assert_match(/tidak ditemukan/, R.read_source_file(File.join(dir, 'nope.json'))[1])
    end
  end

  class FakeDialog
    attr_reader :scripts

    def initialize
      @scripts = []
    end

    def execute_script(js)
      @scripts << js
    end

    def last_payload(fn)
      JSON.parse(@scripts.last[/\A#{fn}\((.*)\);\z/m, 1])
    end
  end

  def test_add_and_remove_source_file_roundtrip_through_dialog
    with_sources do |_app, user|
      Dir.mktmpdir do |dir|
        picked = File.join(dir, 'AHSP Kota.json')
        File.write(picked, JSON.generate(source_json))
        UI.define_singleton_method(:openpanel) { |*| picked }
        dlg = FakeDialog.new
        R.stub(:scan, {}) do
          R.stub(:default_dir, dir) do
            R.add_source_file(dlg, R.normalize_state({}))
            p1 = dlg.last_payload('onSources')
            assert File.exist?(File.join(user, 'AHSP Kota.json')), 'file disalin ke folder data user'
            assert_equal %w[user/AHSP\ Kota.json app/ahsp_starter.json], p1['state']['sources']
            assert_equal({ 'added' => 'AHSP Kota.json', 'updated' => false }, p1['note'])
            assert(p1['catalog'].any? { |c| c['kode'] == 'X.1' }, 'analisa dari file baru ada di katalog')
            assert_equal 'X.01', p1['comps']['X.1'].first.first
            assert_equal %w[user/AHSP\ Kota.json app/ahsp_starter.json], p1['sources']['items'].map { |i| i['id'] }
            saved = JSON.parse(Sketchup.active_model.get_attribute(R::DICT, R::KEY))
            assert_equal p1['state']['sources'], saved['sources'], 'pilihan sumber disimpan di model'

            R.add_source_file(dlg, R.normalize_state(p1['state'])) # nama sama = diperbarui
            assert_equal true, dlg.last_payload('onSources')['note']['updated']

            R.remove_source_file(dlg, R.normalize_state(p1['state']), 'user/AHSP Kota.json')
            p2 = dlg.last_payload('onSources')
            refute File.exist?(File.join(user, 'AHSP Kota.json'))
            assert_equal ['app/ahsp_starter.json'], p2['state']['sources']
            refute(p2['catalog'].any? { |c| c['kode'] == 'X.1' })
            # app/ tidak pernah dihapus lewat jalur ini
            R.remove_source_file(dlg, R.normalize_state(p2['state']), 'app/ahsp_starter.json')
            assert File.exist?(File.join(R.app_data_dir, 'ahsp_starter.json'))
          end
        end
      end
    end
  end

  def test_normalize_sources_never_empty
    assert_equal R.default_sources, R.normalize_sources([])
    assert_equal R.default_sources, R.normalize_sources(['../../etc/passwd'])
    assert_equal R.default_sources, R.normalize_sources('bukan array')
  end

  # ── Daftar harga terpisah, impor/ekspor Excel & JSON ───────────────────

  IO_ = BoosokTools::RabIo

  # ZIP tanpa kompresi (method 0), meniru file yang disimpan alat lain
  def zip_store(files)
    out = String.new(encoding: Encoding::BINARY)
    central = String.new(encoding: Encoding::BINARY)
    files.each do |name, content|
      data = content.b
      crc = Zlib.crc32(data)
      off = out.bytesize
      out << [0x04034b50, 20, 0, 0, 0, 0, crc, data.bytesize, data.bytesize, name.bytesize, 0].pack('VvvvvvVVVvv') << name.b << data
      central << [0x02014b50, 20, 20, 0, 0, 0, 0, crc, data.bytesize, data.bytesize, name.bytesize, 0, 0, 0, 0, 0, off].pack('VvvvvvvVVVvvvvvVV') << name.b
    end
    cd = out.bytesize
    out << central << [0x06054b50, 0, 0, files.size, files.size, central.bytesize, cd, 0].pack('VvvvvVVv')
  end

  def test_parse_number_handles_indonesian_and_plain_formats
    [[1500, 1500.0], ['1.234.567', 1_234_567.0], ['1.234.567,50', 1_234_567.5], ['1,234,567.5', 1_234_567.5],
     ['Rp 1.500', 1500.0], ['12,5', 12.5], ['0.75', 0.75], ['1500', 1500.0]].each do |input, expected|
      assert_in_delta expected, IO_.parse_number(input), 1e-9, input.inspect
    end
    [nil, '', 'abc', '12 kg'].each { |bad| assert_nil IO_.parse_number(bad), bad.inspect }
  end

  def test_rows_to_items_finds_header_and_skips_junk
    rows = [['Daftar harga kota X'], [], ['No', 'Kode', 'Jenis', 'Uraian', 'Sat', 'Harga satuan (Rp)'],
            [1, 'M.01', 'BAHAN', 'Semen', 'kg', 1500.0], [2, nil, nil, 'Pasir', 'm3', '275.000'], [3, 'M.03', 'bahan', 'Tanpa harga', 'kg'],
            [4, 'M.04', 'bahan', '', 'kg', 10.0], [5, 'M.05', 'bahan', 'Minus', 'kg', -3.0]]
    items = IO_.rows_to_items(rows)
    assert_equal [{ 'nama' => 'Semen', 'satuan' => 'kg', 'harga' => 1500.0, 'kode' => 'M.01', 'jenis' => 'bahan' },
                  { 'nama' => 'Pasir', 'satuan' => 'm3', 'harga' => 275_000.0 }], items
    err = assert_raises(IO_::Error) { IO_.rows_to_items([%w[A B], [1, 2]]) }
    assert_match(/Nama.*Harga/, err.message)
  end

  def test_price_workbook_roundtrips_through_xlsx_reader
    items = [{ 'kode' => 'L.01', 'jenis' => 'upah', 'nama' => 'Pekerja & <Mandor>', 'satuan' => 'OH', 'harga' => 123_456.5 },
             { 'kode' => 'M.01', 'jenis' => 'bahan', 'nama' => 'Semen "PC"', 'satuan' => 'kg', 'harga' => 0.0 }]
    rows = IO_.read_xlsx(R.build_price_workbook(items, 'Rumah').to_binary)
    assert_equal %w[Kode Jenis Nama Satuan], rows.first.first(4)
    back = IO_.rows_to_items(rows)
    assert_equal 'Pekerja & <Mandor>', back[0]['nama']
    assert_equal 123_456.5, back[0]['harga']
    assert_equal [0.0, 'M.01'], [back[1]['harga'], back[1]['kode']]
  end

  def test_xlsx_reader_understands_excel_style_files
    shared = '<sst><si><t>Kode</t></si><si><t>Nama</t></si><si><t>Harga</t></si><si><t>Semen</t></si>' \
             '<si><r><t>Pa</t></r><r><t xml:space="preserve">sir &amp; batu</t></r></si><si><t>M.01</t><rPh><t>x</t></rPh></si></sst>'
    sheet = '<worksheet><sheetData>' \
            '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c></row>' \
            '<row r="2"><c r="A2" t="s"><v>5</v></c><c r="B2" t="s"><v>3</v></c><c r="C2" s="3"><v>1750.5</v></c></row>' \
            '<row r="4"><c r="B4" t="s"><v>4</v></c><c r="C4"><v>2E3</v></c><c r="D4" s="1"/></row></sheetData></worksheet>'
    wbxml = '<workbook xmlns:r="x"><sheets><sheet name="Hasil" sheetId="7" r:id="rId9"/></sheets></workbook>'
    rels = '<Relationships><Relationship Id="rId1" Type="t" Target="worksheets/sheet1.xml"/>' \
           '<Relationship Id="rId9" Type="t" Target="/xl/worksheets/sheet2.xml"/></Relationships>'
    bin = zip_store('xl/workbook.xml' => wbxml, 'xl/_rels/workbook.xml.rels' => rels, 'xl/sharedStrings.xml' => shared,
                    'xl/worksheets/sheet1.xml' => '<worksheet><sheetData><row r="1"><c r="A1"><v>999</v></c></row></sheetData></worksheet>',
                    'xl/worksheets/sheet2.xml' => sheet)
    rows = IO_.read_xlsx(bin)
    assert_equal [%w[Kode Nama Harga], ['M.01', 'Semen', 1750.5], [], [nil, 'Pasir & batu', 2000.0]], rows, 'sheet pertama menurut workbook.xml'
    assert_equal [{ 'nama' => 'Semen', 'satuan' => '', 'harga' => 1750.5, 'kode' => 'M.01' },
                  { 'nama' => 'Pasir & batu', 'satuan' => '', 'harga' => 2000.0 }], IO_.rows_to_items(rows)
  end

  def test_xlsx_reader_rejects_garbage
    assert_raises(IO_::Error) { IO_.read_xlsx('bukan zip') }
    assert_raises(IO_::Error) { IO_.read_xlsx(zip_store('a.txt' => 'x')) }
    bin = R.build_price_workbook([], 'x').to_binary
    assert_raises(IO_::Error) { IO_.read_xlsx(bin[0, bin.bytesize / 2]) }
  end

  def test_sanitize_prices_accepts_hsd_style_and_app_style
    hsd = { 'sumber' => 'BPJN', 'wilayah' => 'Kota Serang', 'tahun' => 2024,
            'items' => [{ 'jenis' => 'upah', 'kode' => 'L01', 'nama' => 'Pekerja', 'satuan' => 'Hari', 'harga' => 183_967 }, { 'nama' => '', 'harga' => 5 }, 'x'] }
    d = IO_.sanitize_prices(hsd)
    assert_equal 1, d['items'].size
    assert_equal({ 'sumber' => 'BPJN', 'wilayah' => 'Kota Serang', 'tahun' => '2024' }, d['meta'])
    assert_equal 'upah', d['items'].first['jenis']
    assert_nil IO_.sanitize_prices({ 'foo' => 1 })
    assert_equal 1, IO_.sanitize_prices([{ 'nama' => 'A', 'harga' => '1.000' }])['items'].size
    # file AHSP juga boleh dipakai sebagai sumber harga (memakai harga_dasar-nya)
    assert_equal @db['harga_dasar'].size, IO_.sanitize_prices(@db)['items'].size
  end

  def price_file(items, meta = {})
    JSON.generate({ 'format' => IO_::PRICE_FORMAT, 'versi' => 1, 'meta' => meta, 'items' => items })
  end

  def test_price_files_override_base_prices_by_code_then_name_unit
    semen = @db['harga_dasar'].find { |h| h['nama'] =~ /Semen/ }
    pekerja = @db['harga_dasar'].find { |h| h['kode'] == 'L.01' }
    with_sources do |_app, user|
      FileUtils.mkdir_p(File.join(File.dirname(user), 'harga'))
      put = ->(name, items, meta = {}) { File.write(File.join(File.dirname(user), 'harga', name), price_file(items, meta)) }
      put.call('a.json', [{ 'kode' => semen['kode'], 'nama' => semen['nama'], 'satuan' => semen['satuan'], 'harga' => 9999 },
                          { 'nama' => pekerja['nama'].upcase, 'satuan' => 'hari', 'harga' => 222_000 }, # nama + satuan (hari = OH)
                          { 'kode' => semen['kode'], 'nama' => 'Nama Salah', 'satuan' => 'tak ada', 'harga' => 1 }, # kode cocok tapi nama & satuan beda
                          { 'nama' => 'Barang Asing', 'satuan' => 'kg', 'harga' => 5 }], 'nama' => 'Harga A', 'wilayah' => 'Kota A', 'tahun' => '2026')
      put.call('b.json', [{ 'kode' => semen['kode'], 'nama' => semen['nama'], 'satuan' => semen['satuan'], 'harga' => 1111 }], 'nama' => 'Harga B')
      assert_equal %w[harga/a.json harga/b.json], R.available_price_ids

      st = R.normalize_state({ 'price_sources' => %w[harga/b.json harga/a.json harga/nope.json ../x] })
      assert_equal %w[harga/b.json harga/a.json harga/nope.json], st['price_sources']
      db = R.state_db(st)
      by = ->(kode) { db['harga_dasar'].find { |h| h['kode'] == kode } }
      assert_equal 9999.0, by.call(semen['kode'])['harga'], 'urutan file (a lebih dulu dari b) menentukan'
      assert_equal 'Harga A', by.call(semen['kode'])['sumber_harga']
      assert_equal 222_000.0, by.call('L.01')['harga']
      assert_equal @db['harga_dasar'].size, db['harga_dasar'].size
      assert_equal %w[Kota\ A 2026], db['meta']['harga'].values_at('wilayah', 'tahun_data')
      assert_operator db['meta']['harga']['terisi'], :>=, 2
      assert_equal semen['harga'], @db['harga_dasar'].find { |h| h['kode'] == semen['kode'] }['harga'], 'database asli tidak berubah'

      # harga yang diketik user per model tetap paling atas
      st2 = R.normalize_state({ 'price_sources' => ['harga/a.json'], 'prices' => { semen['kode'] => 5 } })
      assert_equal 5.0, R.effective_prices(R.state_db(st2), st2['prices'])[semen['kode']]
      # tanpa file harga aktif: harga bawaan file AHSP
      assert_equal semen['harga'], R.state_db(R.normalize_state({}))['harga_dasar'].find { |h| h['kode'] == semen['kode'] }['harga']

      payload = R.sources_payload(st)['prices']
      a = payload['items'].find { |i| i['id'] == 'harga/a.json' }
      assert_equal [4, 2, true, 'Harga A'], a.values_at('items', 'matched', 'active', 'nama')
      assert_equal ['harga/nope.json'], payload['missing']
    end
  end

  def test_price_export_then_edit_then_import_changes_prices
    with_sources do |_app, user|
      st = R.normalize_state({ 'prices' => { 'M.01' => 1234 } })
      database = R.state_db(st)
      items = R.price_items(database, st)
      assert_equal database['harga_dasar'].size, items.size
      assert_equal 1234.0, items.find { |i| i['kode'] == 'M.01' }['harga'], 'harga ketikan user ikut diekspor'
      json = JSON.parse(JSON.generate(R.price_export_json(items, database, 'Rumah')))
      assert_equal IO_::PRICE_FORMAT, json['format']
      # "edit di Excel": ubah satu harga lewat xlsx lalu baca lagi
      rows = IO_.read_xlsx(R.build_price_workbook(items, 'Rumah').to_binary)
      row = rows.find { |r| r[0] == 'M.02' }
      row[4] = 4321.0
      edited = IO_.rows_to_items(rows)
      pdir = File.join(File.dirname(user), 'harga')
      FileUtils.mkdir_p(pdir)
      File.write(File.join(pdir, 'edit.json'), price_file(edited, 'nama' => 'Edit'))
      st2 = R.normalize_state({ 'price_sources' => ['harga/edit.json'] })
      assert_equal 4321.0, R.state_db(st2)['harga_dasar'].find { |h| h['kode'] == 'M.02' }['harga']
    end
  end

  def test_import_and_remove_price_file_through_dialog
    with_sources do |_app, user|
      Dir.mktmpdir do |dir|
        xlsx = File.join(dir, 'Harga Serang.xlsx')
        items = R.price_items(@db, R.normalize_state({}, @db)).first(5).map { |i| i.merge('harga' => 777.0) }
        R.build_price_workbook(items, 'x').save(xlsx)
        UI.define_singleton_method(:openpanel) { |*| xlsx }
        dlg = FakeDialog.new
        R.stub(:scan, {}) do
          R.stub(:default_dir, dir) do
            R.import_price_file(dlg, R.normalize_state({}))
            p1 = dlg.last_payload('onSources')
            pf = File.join(File.dirname(user), 'harga', 'Harga Serang.json')
            assert File.exist?(pf), 'file harga disimpan sebagai JSON di folder harga'
            assert_equal ['harga/Harga Serang.json'], p1['state']['price_sources']
            assert_equal 'Harga Serang.json', p1['note']['price_added']
            assert_equal [5, 5], p1['note'].values_at('matched', 'total')
            assert_equal 777.0, p1['base'].find { |b| b['kode'] == items.first['kode'] }['harga']
            assert_equal 'Harga Serang', p1['sources']['prices']['items'].first['nama']

            UI.define_singleton_method(:openpanel) { |*| File.join(dir, 'rusak.xlsx').tap { |p| File.write(p, 'bukan zip') } }
            R.import_price_file(dlg, R.normalize_state(p1['state']))
            assert_match(/^rabError\(/, dlg.scripts.last)

            R.remove_source_file(dlg, R.normalize_state(p1['state']), 'harga/Harga Serang.json')
            refute File.exist?(pf)
            assert_empty dlg.last_payload('onSources')['state']['price_sources']
          end
        end
      end
    end
  end

  # ── Template Excel: harga & AHSP ────────────────────────────────────────

  def test_price_template_is_blank_with_headers_dropdown_and_help
    wb = R.build_price_workbook([], 'x', nil, template: true)
    bin = wb.to_binary
    rows = IO_.read_xlsx(bin)
    assert_equal ['Kode', 'Jenis', 'Nama', 'Satuan', 'Harga (Rp)'], rows.first.first(5)
    assert_equal 1, rows.size, 'baris kosong tidak dibaca sebagai data'
    sheet = unzip(bin)['xl/worksheets/sheet1.xml']
    assert_includes sheet, 'type="list"'
    assert_includes sheet, 'upah,bahan,alat'
    assert_match(/B2:B#{R::TEMPLATE_BLANK_ROWS + 1}/, sheet)
    assert_includes IO_.read_sheets(bin).keys, 'petunjuk'
    assert_match(/template Excel/, assert_raises(IO_::Error) { IO_.rows_to_items([%w[a b]]) }.message)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 't.xlsx')
      wb.save(path)
      assert_match(/Tidak ada baris harga/, assert_raises(IO_::Error) { IO_.read_price_file(path) }.message)
    end
  end

  def test_ahsp_workbook_roundtrips_through_importer
    st = state({}, 'custom' => custom_sample)
    data = JSON.parse(JSON.generate(R.analysis_export_data(@db, st, %w[D.01 U.001], 'Rumah')))
    bin = R.build_ahsp_workbook(data, 'Rumah').to_binary
    assert_equal %w[analisa komponen harga\ dasar petunjuk], IO_.read_sheets(bin).keys
    book = IO_.read_ahsp_book(bin)
    assert_empty book['warn']
    back, info = R.sanitize_source(book['data'])
    assert_equal [0, 0], info.values_at('skipped', 'reserved')
    assert_equal data['ahsp'].map { |a| a['kode'] }, back['ahsp'].map { |a| a['kode'] }
    data['ahsp'].zip(back['ahsp']).each do |want, got|
      assert_equal want['uraian'], got['uraian']
      assert_equal want['satuan'], got['satuan']
      assert_equal want['komponen'].map { |c| [c['kode'], c['koef'].to_f] }, got['komponen'].map { |c| [c['kode'], c['koef']] }
    end
    assert_equal data['harga_dasar'].map { |h| [h['kode'], h['jenis'], h['harga'].to_f] }, back['harga_dasar'].map { |h| [h['kode'], h['jenis'], h['harga']] }
    # hasil impor bisa langsung dipakai sebagai sumber AHSP
    assert_equal back['ahsp'].size, R.sanitize_source(JSON.parse(JSON.generate(back))).first['ahsp'].size
  end

  def test_ahsp_template_formula_names_components
    data = { 'harga_dasar' => [{ 'kode' => 'L.01', 'jenis' => 'upah', 'nama' => 'Pekerja', 'satuan' => 'OH', 'harga' => 1.0 }],
             'ahsp' => [{ 'kode' => '1.1', 'divisi' => 'D', 'kategori' => 'K', 'uraian' => 'Galian', 'satuan' => 'm3', 'komponen' => [{ 'kode' => 'L.01', 'koef' => 0.5 }] }] }
    comp = unzip(R.build_ahsp_workbook(data, 'x').to_binary)['xl/worksheets/sheet2.xml']
    assert_includes comp, '<f>IFERROR(INDEX('
    assert_includes comp, '<v>Pekerja</v>'
  end

  def ahsp_sheets(ana: [], comp: [], base: [])
    wb = R::Xlsx.new
    { 'Analisa' => [%w[Kode Divisi Kategori Uraian Satuan], ana], 'Komponen' => [['Kode Analisa', 'Kode Harga', 'Koefisien'], comp],
      'Harga Dasar' => [['Kode', 'Jenis', 'Nama', 'Satuan', 'Harga (Rp)'], base] }.each do |name, (head, rows)|
      sh = wb.add_sheet(name)
      ([head] + rows).each_with_index { |row, r| row.each_with_index { |v, c| sh.set(r + 1, c + 1, v) } }
    end
    wb.to_binary
  end

  def test_ahsp_import_reports_bad_rows_instead_of_dropping_silently
    bin = ahsp_sheets(
      ana: [['1.1', 'Tanah', 'Galian', 'Galian biasa', 'm3'], ['1.1', 'X', 'X', 'Kembar', 'm3'], ['U.001', 'X', 'X', 'Cadangan', 'm3'], [nil, nil, nil, 'Tanpa kode', 'm3']],
      comp: [['1.1', 'L.01', '0,75'], ['1.1', 'L.01', 0], ['9.9', 'L.01', 1], ['1.1', 'M.99', 2.0]],
      base: [['L.01', 'UPAH', 'Pekerja', 'OH', '150.000'], ['L.02', 'xxx', 'Jenis salah', 'OH', 1], ['L.03', 'alat', 'Tanpa harga', 'jam', nil]]
    )
    book = IO_.read_ahsp_book(bin)
    assert_equal %w[1.1 U.001], book['data']['ahsp'].map { |a| a['kode'] }
    assert_equal [{ 'kode' => 'L.01', 'koef' => 0.75 }, { 'kode' => 'M.99', 'koef' => 2.0 }], book['data']['ahsp'].first['komponen']
    assert_equal [['L.01', 'upah', 150_000.0], ['L.03', 'alat', 0.0]], book['data']['harga_dasar'].map { |h| h.values_at('kode', 'jenis', 'harga') }
    msgs = book['warn'].join(' | ')
    assert_match(/1 baris Analisa.*kembar/, msgs)
    assert_match(/1 baris Komponen.*kode analisa/, msgs)
    assert_match(/1 baris Komponen.*koefisien/, msgs)
    assert_match(/1 baris Harga Dasar/, msgs)
    assert_match(/1 komponen memakai kode harga yang tidak ada/, msgs)
  end

  def test_ahsp_import_rejects_non_template_workbooks
    price = R.build_price_workbook([{ 'kode' => 'L.01', 'jenis' => 'upah', 'nama' => 'Pekerja', 'satuan' => 'OH', 'harga' => 1.0 }], 'x').to_binary
    assert_match(/Bukan file AHSP Boosok/, assert_raises(IO_::Error) { IO_.read_ahsp_book(price) }.message)
    only_ana = R::Xlsx.new.tap { |w| w.add_sheet('Analisa').set(1, 1, 'Kode') }.to_binary
    assert_raises(IO_::Error) { IO_.read_ahsp_book(only_ana) }
    wrong_head = R::Xlsx.new.tap { |w| %w[Analisa Komponen].each { |n| w.add_sheet(n).set(1, 1, 'Foo') } }.to_binary
    assert_raises(IO_::Error) { IO_.read_ahsp_book(wrong_head) }
  end

  def test_read_source_file_accepts_ahsp_excel_and_rejects_others
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'AHSP Saya.xlsx')
      File.binwrite(path, ahsp_sheets(ana: [['1.1', 'Tanah', 'Galian', 'Galian biasa', 'm3']], comp: [['1.1', 'L.01', 0.75]],
                                      base: [['L.01', 'upah', 'Pekerja', 'OH', 150_000]]))
      text, err, warn = R.read_source_file(path)
      assert_nil err
      assert_empty warn
      data = JSON.parse(text)
      assert_equal 'AHSP Saya', data['meta']['nama']
      assert_equal ['1.1'], data['ahsp'].map { |a| a['kode'] }
      assert_equal [{ 'kode' => 'L.01', 'koef' => 0.75 }], data['ahsp'].first['komponen']

      blank = File.join(dir, 'blank.xlsx')
      R.build_ahsp_workbook(nil, '').save(blank)
      assert_match(/kosong/, R.read_source_file(blank)[1])
      price = File.join(dir, 'harga.xlsx')
      R.build_price_workbook([], 'x', nil, template: true).save(price)
      assert_match(/Bukan file AHSP Boosok/, R.read_source_file(price)[1])
      junk = File.join(dir, 'rusak.xlsx')
      File.write(junk, 'bukan zip')
      assert_match(/Bukan template AHSP|xlsx/, R.read_source_file(junk)[1])
    end
  end

  def test_add_ahsp_excel_source_file_through_dialog_and_warns
    with_sources do |_app, user|
      Dir.mktmpdir do |dir|
        picked = File.join(dir, 'AHSP Excel.xlsx')
        File.binwrite(picked, ahsp_sheets(ana: [['X.1', 'Div', 'Kat', 'Uraian X', 'm2']], comp: [['X.1', 'ZZ.1', 1.5]], base: []))
        UI.define_singleton_method(:openpanel) { |*| picked }
        dlg = FakeDialog.new
        R.stub(:scan, {}) do
          R.stub(:default_dir, dir) do
            R.add_source_file(dlg, R.normalize_state({}))
            p1 = dlg.last_payload('onSources')
            assert File.exist?(File.join(user, 'AHSP Excel.json')), 'Excel disimpan sebagai JSON bersih'
            assert_equal 'AHSP Excel.json', p1['note']['added']
            assert_match(/tidak ada di sheet Harga Dasar/, p1['note']['warn'].first)
            assert(p1['catalog'].any? { |c| c['kode'] == 'X.1' } || p1['sources']['items'].any? { |i| i['id'] == 'user/AHSP Excel.json' })
          end
        end
      end
    end
  end

  def test_builtin_source_exports_to_json_and_reimportable_excel
    with_sources do |_app, _user|
      id = R.app_source_ids.first
      source = R.load_source(id)['data']
      Dir.mktmpdir do |dir|
        dlg = FakeDialog.new
        json = File.join(dir, 'b.json')
        R.stub(:save_export, json) { R.export_source_file(dlg, R.normalize_state({}), id, 'json') }
        assert_equal "onFileSaved(#{json.to_json});", dlg.scripts.last
        assert_equal source['ahsp'].size, R.sanitize_source(JSON.parse(File.read(json))).first['ahsp'].size

        xlsx = File.join(dir, 'b.xlsx')
        R.stub(:save_export, xlsx) { R.export_source_file(dlg, R.normalize_state({}), id, 'book') }
        text, err, warn = R.read_source_file(xlsx)
        assert_nil err
        assert_empty warn
        back = JSON.parse(text)
        assert_equal source['ahsp'].map { |a| a['kode'] }, back['ahsp'].map { |a| a['kode'] }
        assert_equal source['ahsp'].sum { |a| a['komponen'].size }, back['ahsp'].sum { |a| a['komponen'].size }
        assert_equal source['harga_dasar'].size, back['harga_dasar'].size
        # format laporan AHSP: sheet AHSP (blok per analisa) + DHSP, dan tidak ada data yang hilang saat dibaca balik
        assert_equal %w[ahsp dhsp], IO_.read_sheets(File.binread(xlsx)).keys
        %w[divisi kategori uraian satuan keyakinan acuan catatan].each do |f|
          assert_equal source['ahsp'].map { |a| a[f].to_s }, back['ahsp'].map { |a| a[f].to_s }, f
        end
        assert_equal source['ahsp'].map { |a| a['komponen'].map { |c| [c['kode'], c['koef'].to_f] } }, back['ahsp'].map { |a| a['komponen'].map { |c| [c['kode'], c['koef']] } }
        assert_equal source['harga_dasar'].map { |b| b.values_at('kode', 'jenis', 'nama', 'satuan') }, back['harga_dasar'].map { |b| b.values_at('kode', 'jenis', 'nama', 'satuan') }
        assert_equal source['harga_dasar'].map { |b| b['harga'].to_f }, back['harga_dasar'].map { |b| b['harga'] }
      end
      assert_raises(R::UserError) { R.export_source_file(FakeDialog.new, R.normalize_state({}), 'user/nope.json', 'json') }
    end
  end

  def test_report_workbook_layout_and_overhead_roundtrip
    data = { 'meta' => { 'nama' => 'T', 'overhead_profit_persen' => 12.5 },
             'harga_dasar' => [{ 'kode' => 'L.01', 'jenis' => 'upah', 'nama' => 'Pekerja', 'satuan' => 'OH', 'harga' => 100.0 },
                               { 'kode' => 'M.01', 'jenis' => 'bahan', 'nama' => 'Semen', 'satuan' => 'kg', 'harga' => 2.0 },
                               { 'kode' => 'M.99', 'jenis' => 'bahan', 'nama' => 'Tak terpakai', 'satuan' => 'kg', 'harga' => 7.0 }],
             'ahsp' => [{ 'kode' => '1.1', 'divisi' => 'Tanah', 'kategori' => 'Galian', 'uraian' => 'Galian', 'satuan' => 'm3', 'keyakinan' => 'tinggi',
                          'komponen' => [{ 'kode' => 'L.01', 'koef' => 0.6 }, { 'kode' => 'L.01', 'koef' => 0.2 }, { 'kode' => 'M.01', 'koef' => 5 }] },
                        { 'kode' => '1.2', 'divisi' => 'Tanah', 'kategori' => '', 'uraian' => 'Urugan', 'satuan' => 'm3', 'komponen' => [{ 'kode' => 'M.01', 'koef' => 1.5 }] }] }
    bin = R.build_source_workbook(data, 'T').to_binary
    rows = IO_.read_sheets(bin)
    assert_equal ['Kode', 'Uraian/Komponen', 'Sat.', 'Koefisien', 'Harga Satuan', 'Jumlah', 'Divisi'], rows['ahsp'][4].first(7), 'baris judul sama dengan laporan AHSP'
    assert_equal 12.5 / 100, rows['ahsp'][2][3]
    assert_equal 3, rows['dhsp'].count { |r| r[0].to_s.match?(/\A[LM]\.\d+/) }, 'semua harga dasar ikut, termasuk yang tak terpakai'
    book = IO_.read_ahsp_book(bin)
    assert_empty book['warn']
    assert_equal 12.5, book['data']['meta']['overhead_profit_persen']
    back, = R.sanitize_source(book['data'])
    assert_equal [%w[1.1 Tanah Galian tinggi], ['1.2', 'Tanah', '', nil]], back['ahsp'].map { |a| a.values_at('kode', 'divisi', 'kategori', 'keyakinan') }
    assert_equal [[['L.01', 0.6], ['L.01', 0.2], ['M.01', 5.0]], [['M.01', 1.5]]], back['ahsp'].map { |a| a['komponen'].map { |c| [c['kode'], c['koef']] } }
    # laporan RAB/AHSP buatan aplikasi (tanpa kolom tambahan) juga bisa dibaca
    st = state
    plain = R.build_analysis_workbook(@db, st, %w[D.01], 'x').to_binary
    imported = IO_.read_ahsp_book(plain)['data']
    assert_equal ['D.01'], imported['ahsp'].map { |a| a['kode'] }
    assert_equal @db['ahsp'].find { |a| a['kode'] == 'D.01' }['komponen'].size, imported['ahsp'].first['komponen'].size
  end

  def test_export_template_file_writes_both_templates
    Dir.mktmpdir do |dir|
      dlg = FakeDialog.new
      %w[ahsp harga].each do |kind|
        path = File.join(dir, "#{kind}.xlsx")
        R.stub(:save_export, path) do
          R.export_template_file(dlg, R.normalize_state({}), kind)
        end
        assert_equal "onFileSaved(#{path.to_json});", dlg.scripts.last
        assert_equal kind == 'ahsp' ? %w[analisa komponen harga\ dasar petunjuk] : %w[harga petunjuk], IO_.read_sheets(File.binread(path)).keys
      end
      R.stub(:save_export, nil) { R.export_template_file(dlg, R.normalize_state({}), 'ahsp') }
      assert_equal 'onFileSaved(null);', dlg.scripts.last
    end
  end

  def test_export_analyses_json_is_a_loadable_ahsp_source
    d01 = @db['ahsp'].find { |a| a['kode'] == 'D.01' }
    first = d01['komponen'].first
    st = state({}, 'custom' => custom_sample,
                   'overrides' => { 'D.01' => { 'komponen' => [{ 'kode' => first['kode'], 'koef' => 7 }] } })
    data = JSON.parse(JSON.generate(R.analysis_export_data(@db, st, %w[D.01 U.001 NOPE D.01], 'Rumah')))
    assert_equal %w[D.01 SAYA.001], data['ahsp'].map { |a| a['kode'] }
    assert_equal [{ 'kode' => first['kode'], 'koef' => 7 }], data['ahsp'].first['komponen'], 'perubahan user ikut diekspor'
    assert_equal ['HSAYA.001'], data['harga_dasar'].map { |h| h['kode'] }.grep(/SAYA/)
    assert_equal data['ahsp'].flat_map { |a| a['komponen'].map { |c| c['kode'] } }.uniq.sort, data['harga_dasar'].map { |h| h['kode'] }.sort
    clean, info = R.sanitize_source(data)
    assert_equal [0, 0], info.values_at('skipped', 'reserved'), 'kode hasil ekspor tidak bentrok dengan kode cadangan'
    assert_equal 2, clean['ahsp'].size
    assert_equal 'Analisa Rumah', clean['meta']['nama']
  end

  def test_export_analyses_workbook_has_ahsp_and_prices_sheets
    st = state
    bin = R.build_analysis_workbook(@db, st, %w[D.01 A.01 NOPE], 'Rumah').to_binary
    files = unzip(bin)
    assert_includes files['xl/workbook.xml'], 'name="AHSP"'
    assert_includes files['xl/workbook.xml'], 'name="DHSP"'
    ahsp = files['xl/worksheets/sheet1.xml']
    assert_includes ahsp, 'D.01'
    assert_includes ahsp, 'A.01'
    refute_includes ahsp, 'NOPE'
    assert_includes ahsp, '<f>'
  end

  # APPDATA di Windows berisi backslash; Dir.glob menganggapnya escape sehingga file yang sudah disimpan tidak terdaftar
  def test_user_files_are_listed_when_appdata_has_backslashes
    skip 'khusus Windows' unless File::ALT_SEPARATOR
    Dir.mktmpdir do |root|
      old = ENV['APPDATA']
      ENV['APPDATA'] = root.tr('/', '\\')
      begin
        FileUtils.mkdir_p([R.price_data_dir, R.user_data_dir])
        File.write(File.join(R.price_data_dir, 'Harga - Tanpa judul.json'), price_file([{ 'nama' => 'A', 'harga' => 1 }]))
        File.write(File.join(R.user_data_dir, 'b.json'), JSON.generate(source_json))
        assert_equal ['harga/Harga - Tanpa judul.json'], R.available_price_ids
        assert_includes R.available_source_ids, 'user/b.json'
        refute_includes R.price_data_dir, '\\'
      ensure
        ENV['APPDATA'] = old
      end
    end
  end

  # ── Struktur Excel: rekapitulasi, RAB, DHSP, AHSP, kurva S ──────────────

  SCH = BoosokTools::RabSchedule
  TH = BoosokTools::RabTheme

  def schedule_report(n = 4)
    st = state({ 'Dinding' => { 'kode' => 'D.01' }, 'Lantai' => { 'kode' => 'E.02' } })
    rep = R.build_report(@db, st, { 'tag:Dinding' => measure('area' => 100.0, 'plane' => 100.0), 'tag:Lantai' => measure('area' => 50.0, 'plane' => 50.0) })
    rep['rows'] = (rep['rows'] * n).first(n) if n != rep['rows'].size
    [rep, st]
  end

  def test_schedule_defaults_are_staggered_and_inside_the_project
    assert_equal [], SCH.defaults(0, 12)
    assert_equal [[1, 12]], SCH.defaults(1, 12)
    plan = SCH.defaults(5, 12)
    assert_equal 5, plan.size
    assert_equal 1, plan.first.first
    assert_equal 12, plan.last.sum { |v| v } - 1, 'pekerjaan terakhir selesai di minggu terakhir'
    assert(plan.each_cons(2).all? { |a, b| b.first >= a.first }, 'mulai tidak mundur')
    plan.each { |s, d| assert_operator s + d - 1, :<=, 12 }
    assert_equal [12, 2, 104, 12], [SCH.weeks(nil), SCH.weeks(0), SCH.weeks(9999), SCH.weeks('x')]
  end

  def test_schedule_curve_reaches_100_percent
    rep, = schedule_report
    s = SCH.compute(rep, 10)
    assert_equal 10, s[:weekly].size
    assert_in_delta 1.0, s[:cumulative].last, 1e-9
    assert_in_delta 1.0, s[:items].sum { |i| i[:bobot] }, 1e-9
    assert(s[:cumulative].each_cons(2).all? { |a, b| b >= a - 1e-12 }, 'kumulatif tidak turun')
    assert_empty SCH.compute({ 'rows' => [] }, 6)[:items]
  end

  def test_workbook_has_five_sheets_with_linked_summary_and_schedule
    st = state({ 'Dinding' => { 'kode' => 'D.01' }, 'Beton' => { 'kode' => 'C.02', 'manual' => 3.5 } }, 'weeks' => 8)
    rep = R.build_report(@db, st, { 'tag:Dinding' => measure('area' => 80.0) })
    files = unzip(R.build_workbook(rep, @db, st, 'Rumah').to_binary)
    rekap = files['xl/worksheets/sheet1.xml']
    assert_includes rekap, 'REKAPITULASI RENCANA ANGGARAN BIAYA'
    assert_match(%r{<f>&#39;RAB&#39;!F\d+</f>}, rekap, 'jumlah per divisi ditarik dari sheet RAB')
    assert_includes rekap, 'Terbilang'
    assert_includes files['xl/worksheets/sheet3.xml'], 'DAFTAR HARGA BAHAN (DHSP)'
    assert_includes files['xl/worksheets/sheet4.xml'], 'ANALISA HARGA SATUAN PEKERJAAN (AHSP)'
    kurva = files['xl/worksheets/sheet5.xml']
    assert_includes kurva, 'TIME SCHEDULE (KURVA S)'
    assert_match(%r{<f>IF\(AND\(G\$5&gt;=\$E\d+,G\$5&lt;=\$E\d+\+\$F\d+-1\),\$D\d+/\$F\d+,0\)</f>}, kurva, 'rumus bobot per minggu')
    assert_includes kurva, '<c r="N5"', 'delapan kolom minggu (G..N)'
    refute_includes kurva, '<c r="O5"'
    assert_match(%r{<f>H\d+\+I\d+</f>|<f>G\d+\+H\d+</f>}, kurva, 'kumulatif = sebelumnya + minggu ini')
    chart = files['xl/charts/chart1.xml']
    assert_includes chart, '&#39;Kurva S&#39;!$G$5:$N$5'
    assert_match(/<c:ptCount val="8"\/>/, chart)
    assert_includes files['[Content_Types].xml'], '/xl/charts/chart1.xml'
    assert_includes kurva, '<drawing r:id="rId1"/>'
    assert_includes files['xl/worksheets/_rels/sheet5.xml.rels'], '../drawings/drawing1.xml'
    assert_includes files['xl/drawings/_rels/drawing1.xml.rels'], '../charts/chart1.xml'
  end

  # ── Tema dokumen ────────────────────────────────────────────────────────

  def test_theme_normalize_accepts_only_valid_values
    t = TH.normalize({ 'nama' => "Ku\u0000 tema", 'font' => 'Arial<>', 'size' => '99',
                       'roles' => { 'head' => { 'fill' => '#AABBCC', 'color' => 'zzz', 'bold' => false }, 'grid' => { 'border' => 'FF112233' }, 'nope' => { 'fill' => '000000' } } })
    assert_equal 'Ku tema', t['nama']
    assert_equal 'Arial', t['font']
    assert_equal 20.0, t['size']
    assert_equal({ 'fill' => 'aabbcc', 'color' => 'ffffff', 'bold' => false }, t['roles']['head'])
    assert_equal '112233', t['roles']['grid']['border']
    assert_equal TH.default['roles'].keys, t['roles'].keys
    assert_equal TH.default, TH.normalize('bukan hash')
    assert_equal 5, TH::BUILTIN.size
  end

  def test_theme_choice_is_stored_per_model_and_falls_back
    assert_equal 'app/biru', state['theme']
    assert_equal 'app/marun', state({}, 'theme' => 'app/marun')['theme']
    assert_equal 'app/biru', state({}, 'theme' => '../../x')['theme']
    assert_equal TH::BUILTIN['marun']['roles']['head']['fill'], R.theme_for(state({}, 'theme' => 'app/marun'))['roles']['head']['fill']
    assert_equal TH.default, R.theme_for(state({}, 'theme' => 'user/hilang.json')), 'tema user yang tak ada -> bawaan'
    assert_equal 12, state['weeks']
    assert_equal 30, state({}, 'weeks' => '30')['weeks']
    assert_equal 104, state({}, 'weeks' => 5000)['weeks']
  end

  def test_theme_colors_reach_excel_and_pdf
    rep, st = schedule_report
    marun = TH.builtin('app/marun')
    files = unzip(R.build_workbook(rep, @db, st, 'Rumah', marun).to_binary)
    assert_includes files['xl/styles.xml'], 'FF7B1E2B', 'warna judul kolom tema marun di styles.xml'
    refute_includes files['xl/styles.xml'], 'FF1F3A5F'
    assert_includes files['xl/charts/chart1.xml'], '7B1E2B'
    lay = P.layout(rep, @db, st, 'Uji', %w[rekap rab kurva], Time.now, marun)
    fills = lay['pages'].flat_map { |pg| pg['items'] }.select { |i| i['t'] == 'rect' && i['fill'] }.map { |i| i['fill'] }.uniq
    assert_includes fills, '7b1e2b'
    refute_includes fills, '1f3a5f'
    bw = TH.builtin('app/hitam-putih')
    assert_equal bw['roles']['text']['color'], R.chart_color(bw), 'judul kolom terang -> garis grafik pakai warna teks'
  end

  def zip_files(bin)
    unzip(bin)
  end

  def test_theme_template_roundtrip_and_restyle_in_excel
    theme = TH.builtin('app/hijau')
    bin = R.build_theme_template(theme).to_binary
    same = TH.from_template(bin)
    assert_equal theme['roles'], same['roles'], 'template tanpa perubahan menghasilkan tema yang sama'
    assert_equal theme['font'], same['font']
    # "edit di Excel": ganti warna judul kolom & isian di styles.xml, simpan ulang sebagai zip
    files = unzip(bin)
    files['xl/styles.xml'] = files['xl/styles.xml'].gsub('FF1E5631', 'FF123456').gsub('FFE3F1E6', 'FFABCDEF')
    edited = TH.from_template(zip_store(files))
    assert_equal '123456', edited['roles']['head']['fill']
    assert_equal 'abcdef', edited['roles']['band']['fill']
    assert_equal theme['roles']['total'], edited['roles']['total']
    assert_raises(TH::Error) { TH.from_template(R.build_price_workbook([], 'x').to_binary) }
    assert_raises(TH::Error) { TH.from_template('bukan zip') }
  end

  def test_styles_reader_resolves_theme_colors_with_tint
    styles = '<styleSheet><fonts count="2"><font><sz val="11"/><color theme="1"/><name val="Calibri"/></font>' \
             '<font><b/><sz val="14"/><color theme="4" tint="0.39997558519241921"/><name val="Arial"/></font></fonts>' \
             '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>' \
             '<fill><patternFill patternType="solid"><fgColor theme="5"/><bgColor indexed="64"/></patternFill></fill></fills>' \
             '<borders count="1"><border><left style="thin"><color rgb="FFAA0000"/></left><right/><top/><bottom/><diagonal/></border></borders>' \
             '<cellXfs count="2"><xf fontId="0" fillId="0" borderId="0"/><xf fontId="1" fillId="2" borderId="0"/></cellXfs></styleSheet>'
    out = IO_.read_styles('xl/styles.xml' => styles)
    assert_equal '000000', out[0]['font']['color']
    assert_equal 'Arial', out[1]['font']['name']
    assert_equal true, out[1]['font']['bold']
    assert_equal 'ed7d31', out[1]['fill']
    assert_equal '8faadc', out[1]['font']['color'], 'accent1 dengan tint 0.4 = "Biru, Aksen 1, Lebih Terang 40%" bawaan Office'
    border = IO_.read_styles('xl/styles.xml' => styles.sub('borderId="0"/><xf fontId="1"', 'borderId="0"/><xf fontId="1"')).then { |x| x }
    assert_equal 2, border.size
  end

  # ── PDF: bagian baru ────────────────────────────────────────────────────

  def pdf_text(lay)
    lay['pages'].flat_map { |p| p['items'] }.select { |i| i['t'] == 'text' }.map { |i| i['s'] }.join("\n")
  end

  def test_pdf_has_summary_and_s_curve_parts_in_canonical_order
    rep, st = schedule_report
    assert_equal %w[rekap rab harga ahsp kurva], P::PARTS
    lay = P.layout(rep, @db, st, 'Uji', %w[kurva ahsp harga rab rekap])
    text = pdf_text(lay)
    order = ['REKAPITULASI RENCANA ANGGARAN BIAYA', 'RENCANA ANGGARAN BIAYA (RAB)', 'DAFTAR HARGA BAHAN (DHSP)', 'ANALISA HARGA SATUAN PEKERJAAN (AHSP)', 'TIME SCHEDULE (KURVA S)']
    positions = order.map { |h| text.index(h) }
    refute_includes positions, nil
    assert_equal positions.sort, positions, 'urutan bagian: rekap, RAB, DHSP, AHSP, kurva S'
    assert_includes text, 'Kumulatif (%)'
    assert_includes text, 'Terbilang'
    lines = lay['pages'].flat_map { |p| p['items'] }.count { |i| i['t'] == 'line' && i['w'] == 1.6 }
    assert_equal SCH.weeks(st['weeks']) - 1, lines, 'garis kurva S menghubungkan tiap minggu'
  end

  # Hot reload di SketchUp: konstanta daftar bagian dari versi lama tidak boleh bertahan (bagian baru hilang dari pratinjau)
  def test_reloading_pdf_module_replaces_stale_parts_list
    P.send(:remove_const, :PARTS)
    P.const_set(:PARTS, %w[rab ahsp harga].freeze)
    load File.join(PLUGIN, 'ruby', 'paid', 'rab_pdf.rb')
    assert_equal %w[rekap rab harga ahsp kurva], P::PARTS
    _st, parts = R.parse_print_args(JSON.generate('state' => {}, 'parts' => %w[kurva rekap rab]))
    assert_equal %w[rekap rab kurva], parts, 'rekap dan kurva S lolos ke pratinjau, urutan baku'
  end

  def test_summary_lists_divisions_without_their_number
    assert_equal 'Pekerjaan Struktur', P.plain_division('02. Pekerjaan Struktur')
    assert_equal 'Pekerjaan Dinding', P.plain_division('D. Pekerjaan Dinding')
    assert_equal 'Analisa Saya', P.plain_division('00. Analisa Saya')
    assert_equal 'Persiapan 1.5 m', P.plain_division('Persiapan 1.5 m')
    rep, st = schedule_report
    names = rep['divisi'].map { |d| d['name'] }
    refute_empty names
    text = pdf_text(P.layout(rep, @db, st, 'Uji', %w[rekap]))
    names.each { |n| assert_includes text, P.plain_division(n) }
    assert(names.none? { |n| text.lines.map(&:strip).include?(n) }, 'di rekap PDF nama divisi tanpa nomor depan')
    sheet = unzip(R.build_workbook(rep, @db, st, 'Rumah').to_binary)['xl/worksheets/sheet1.xml']
    names.each do |n|
      assert_includes sheet, ">#{P.plain_division(n)}<"
      refute_includes sheet, ">#{n}<" unless n == P.plain_division(n)
    end
  end

  # ── Data pekerjaan (kepala dokumen) ─────────────────────────────────────

  def test_info_normalize_trims_caps_and_keeps_order
    assert_nil R.normalize_state({}, @db)['info']
    assert_equal [], R.normalize_state({ 'info' => [] }, @db)['info']
    raw = [{ 'label' => '  Lokasi ', 'value' => "Kota\nSerang" }, 'bukan hash', { 'label' => '', 'value' => '' }, { 'label' => 'Nilai Kontrak', 'value' => 'x' * 500 }]
    info = R.normalize_state({ 'info' => raw }, @db)['info']
    assert_equal [{ 'label' => 'Lokasi', 'value' => 'Kota Serang' }, { 'label' => 'Nilai Kontrak', 'value' => 'x' * 300 }], info
    assert_equal R::MAX_INFO, R.normalize_state({ 'info' => Array.new(50) { { 'label' => 'a', 'value' => 'b' } } }, @db)['info'].size
    assert_equal true, R.normalize_state({}, @db)['info_date']
    assert_equal false, R.normalize_state({ 'info_date' => false }, @db)['info_date']
  end

  def test_info_lines_skip_empty_values_and_optional_date
    now = Time.new(2026, 10, 10)
    assert_equal ['Proyek : Uji', 'Tanggal : 10-10-2026'], P.info_lines({}, 'Uji', now)
    st = { 'info' => [{ 'label' => 'Nama Pekerjaan', 'value' => 'Rumah' }, { 'label' => 'Lokasi', 'value' => '' }, { 'label' => '', 'value' => 'Catatan' }], 'info_date' => false }
    assert_equal ['Nama Pekerjaan : Rumah', 'Catatan'], P.info_lines(st, 'Uji', now)
    assert_equal [], P.info_lines({ 'info' => [], 'info_date' => false }, 'Uji', now)
  end

  def test_info_lines_show_in_pdf_and_move_excel_header_row
    rep, st = schedule_report
    st = st.merge('info' => [{ 'label' => 'Nama Pekerjaan', 'value' => 'Rumah Pak Budi' }, { 'label' => 'Lokasi', 'value' => 'Serang' },
                             { 'label' => 'Nomor Kontrak', 'value' => '123/ABC' }, { 'label' => 'Sumber Dana', 'value' => 'APBD' }])
    text = pdf_text(P.layout(rep, @db, st, 'Uji', %w[rekap rab kurva]))
    ['Nama Pekerjaan : Rumah Pak Budi', 'Lokasi : Serang', 'Nomor Kontrak : 123/ABC', 'Sumber Dana : APBD'].each { |s| assert_includes text, s }
    refute_includes text, 'Proyek :'
    files = unzip(R.build_workbook(rep, @db, st, 'Uji').to_binary)
    rekap = files['xl/worksheets/sheet1.xml']
    assert_includes rekap, 'Sumber Dana : APBD'
    # 4 baris data + 1 tanggal -> judul kolom di baris 8; freeze di bawahnya
    assert_match(/<c r="A8"[^>]*>.*?No/m, rekap)
    assert_includes rekap, 'ySplit="8"'
    assert_includes files['xl/worksheets/sheet5.xml'], 'ySplit="8"' # kurva S: 4 baris data + catatan + MINGGU + judul
  end

  def test_pdf_empty_report_for_new_parts
    st = state
    lay = P.layout(R.build_report(@db, st, {}), @db, st, 'Kosong', P::PARTS)
    assert P.to_pdf(lay).start_with?('%PDF')
  end

  # ── Progress bar ────────────────────────────────────────────────────────

  def test_run_job_reports_progress_then_finishes
    dlg = FakeDialog.new
    seen = []
    R.run_job(dlg, [['rab_pg_read', ->(_) { 1 }], ['rab_pg_book', ->(x) { x + 1 }], ['rab_pg_write', ->(x) { x * 10 }]]) { |res| seen << res }
    assert_equal [20], seen
    assert_equal ['rabProgress(0, "rab_pg_read");', 'rabProgress(33, "rab_pg_book");', 'rabProgress(67, "rab_pg_write");', 'rabProgress(100);'], dlg.scripts
  end

  def test_run_job_without_block_runs_final_script_after_progress_100
    dlg = FakeDialog.new
    R.run_job(dlg, [['rab_pg_save', ->(_) { 'onSources({});' }]])
    assert_equal ['rabProgress(0, "rab_pg_save");', 'rabProgress(100);', 'onSources({});'], dlg.scripts, 'progress 100 dikirim sebelum penutup, jadi penutup yang menyembunyikannya'
  end

  def test_run_job_failure_shows_error_and_stops
    dlg = FakeDialog.new
    ran = []
    R.run_job(dlg, [['rab_pg_read', ->(_) { raise R::UserError, 'File rusak' }], ['rab_pg_write', ->(_) { ran << 1 }]])
    assert_empty ran
    assert_equal 'rabError("File rusak");', dlg.scripts.last
    out, = capture_io { R.run_job(dlg, [['rab_pg_book', ->(_) { raise 'boom' }]]) }
    assert_match(/boom/, out)
    assert_match(/rabError\(.*boom.*\)/, dlg.scripts.last)
  end

  def test_theme_import_and_remove_through_dialog
    with_sources do |_app, user|
      Dir.mktmpdir do |dir|
        bin = R.build_theme_template(TH.builtin('app/abu')).to_binary
        files = unzip(bin)
        files['xl/styles.xml'] = files['xl/styles.xml'].gsub('FF3F4756', 'FF0A7B3E')
        tpl = File.join(dir, 'Tema Kantor.xlsx')
        File.binwrite(tpl, zip_store(files))
        UI.define_singleton_method(:openpanel) { |*| tpl }
        dlg = FakeDialog.new
        R.stub(:scan, {}) do
          R.stub(:default_dir, dir) do
            R.import_theme_file(dlg, R.normalize_state({}))
            p1 = dlg.last_payload('onSources')
            assert File.exist?(File.join(File.dirname(user), 'tema', 'Tema Kantor.json'))
            assert_equal 'user/Tema Kantor.json', p1['state']['theme']
            assert_equal 'Tema Kantor.json', "#{p1['note']['theme_added']}.json"
            ids = p1['themes'].map { |t| t['id'] }
            assert_equal (TH::BUILTIN.keys.map { |k| "app/#{k}" } + ['user/Tema Kantor.json']), ids
            assert_equal '0a7b3e', R.theme_for(p1['state'])['roles']['head']['fill']

            # tema user dipakai di Excel
            st = R.normalize_state(p1['state'])
            wb = R.build_price_workbook([], 'x', R.theme_for(st))
            assert_includes wb.styles_xml, 'FF0A7B3E'

            R.remove_theme_file(dlg, st, 'user/Tema Kantor.json')
            p2 = dlg.last_payload('onSources')
            refute File.exist?(File.join(File.dirname(user), 'tema', 'Tema Kantor.json'))
            assert_equal 'app/biru', p2['state']['theme']
            assert_equal true, p2['note']['theme_removed']

            UI.define_singleton_method(:openpanel) { |*| File.join(dir, 'x.xlsx').tap { |p| File.binwrite(p, R.build_price_workbook([], 'x').to_binary) } }
            R.import_theme_file(dlg, R.normalize_state({}))
            assert_match(/^rabError\(.*template tema/i, dlg.scripts.last)
          end
        end
      end
    end
  end

  def test_theme_template_export_writes_file
    with_sources do
      Dir.mktmpdir do |dir|
        out = File.join(dir, 'tpl.xlsx')
        UI.define_singleton_method(:savepanel) { |*| out }
        dlg = FakeDialog.new
        R.stub(:default_dir, dir) { R.export_theme_template(dlg, R.normalize_state({ 'theme' => 'app/hijau' })) }
        assert_equal "onFileSaved(#{out.to_json});", dlg.scripts.last
        assert_equal TH::BUILTIN['hijau']['roles']['head'], TH.from_template(File.binread(out))['roles']['head']
      end
    end
  end

  def test_safe_source_name
    assert_equal 'AHSP Banten 2025.json', R.safe_source_name('C:/x/AHSP Banten 2025.json')
    assert_equal 'a_b.json', R.safe_source_name('a?b.JSON')
    assert_equal 'ahsp.json', R.safe_source_name('')
  end

  # ── PDF ─────────────────────────────────────────────────────────────────

  P = BoosokTools::RabPdf

  def sample_report(extra_rows = 0)
    st = state({ 'Dinding' => { 'kode' => 'D.01' }, 'Lantai' => { 'kode' => 'E.02' } })
    rep = R.build_report(@db, st, { 'tag:Dinding' => measure('area' => 100.0, 'plane' => 100.0), 'tag:Lantai' => measure('area' => 50.0, 'plane' => 50.0) })
    extra_rows.times { |i| rep['rows'] << rep['rows'].first.merge('key' => "tag:Extra #{i}", 'tag' => "Extra #{i}", 'label' => "Tag: Extra #{i}") }
    [rep, st]
  end

  def test_pdf_number_format_and_terbilang
    assert_equal '1.234.568', P.num(1_234_567.891)
    assert_equal '1.234.567,89', P.num(1_234_567.891, 2)
    assert_equal '-5.000', P.num(-5000)
    assert_equal 'seratus dua puluh tiga', P.terbilang(123)
    assert_equal 'seribu', P.terbilang(1000)
    assert_equal 'dua ribu', P.terbilang(2000)
    assert_equal 'satu juta dua ratus ribu', P.terbilang(1_200_000)
    assert_equal 'sebelas', P.terbilang(11)
    assert_equal 'nol', P.terbilang(0)
  end

  def test_pdf_text_is_made_safe_and_measured
    assert_equal 'a >= b Ø', P.safe("a ≥ b ∅")
    assert_equal 'ab', P.safe("a
b").delete(' ')
    assert_equal '?', P.safe("中")
    assert_in_delta 2.78, P.text_width(' ', 'R', 10), 1e-6
    assert_operator P.text_width('Total', 'B', 10), :>, P.text_width('Total', 'R', 10)
    lines = P.wrap('Pemasangan dinding bata merah tebal satu batu campuran 1 pc : 4 ps', 'R', 8.5, 100)
    assert_operator lines.size, :>, 1
    assert(lines.all? { |l| P.text_width(l, 'R', 8.5) <= 100.01 })
    long = P.wrap('x' * 200, 'R', 8.5, 100)
    assert(long.all? { |l| P.text_width(l, 'R', 8.5) <= 100.01 })
  end

  def test_pdf_layout_paginates_and_repeats_header
    rep, st = sample_report(80)
    lay = P.layout(rep, @db, st, 'Rumah Uji', %w[rab])
    assert_operator lay['pages'].size, :>, 1
    texts = lay['pages'].map { |p| p['items'].select { |i| i['t'] == 'text' }.map { |i| i['s'] } }
    assert(texts.all? { |t| t.include?('Uraian Pekerjaan') }, 'header tabel diulang di tiap halaman')
    assert_includes texts.last.join(' '), 'Terbilang'
    assert_includes texts.first.last(2).join(' '), "Halaman 1 dari #{lay['pages'].size}"
    lay['pages'].each do |p|
      p['items'].each do |i|
        next unless i['t'] == 'text'

        assert_operator i['y'], :<=, P::PAGE_H - 30, 'teks tidak boleh masuk margin bawah selain footer'
      end
    end
  end

  def test_pdf_rekap_rab_kurva_are_landscape_others_portrait
    rep, st = sample_report(60)
    lay = P.layout(rep, @db, st, 'Uji', %w[rekap rab harga ahsp kurva])
    title_of = lambda do |pg|
      pg['items'].select { |i| i['t'] == 'text' }.map { |i| i['s'] }.find { |s| s.match?(/\A(REKAPITULASI|RENCANA ANGGARAN|DAFTAR HARGA|ANALISA|TIME SCHEDULE)/) }
    end
    land = ->(pg) { pg['w'] > pg['h'] }
    seen = {}
    current = nil
    lay['pages'].each do |pg|
      t = title_of.call(pg)
      current = t if t
      seen[current] = (seen[current] || []) << land.call(pg)
    end
    assert_equal [true], seen['REKAPITULASI RENCANA ANGGARAN BIAYA'].uniq
    assert_equal [true], seen['RENCANA ANGGARAN BIAYA (RAB)'].uniq
    assert_equal [true], seen['TIME SCHEDULE (KURVA S)'].uniq
    assert_equal [false], seen['DAFTAR HARGA BAHAN (DHSP)'].uniq
    assert_equal [false], seen['ANALISA HARGA SATUAN PEKERJAAN (AHSP)'].uniq
    assert_operator seen['RENCANA ANGGARAN BIAYA (RAB)'].size, :>, 1, 'RAB panjang menyambung di halaman landscape berikutnya'
    lay['pages'].each do |pg|
      pg['items'].each do |i|
        assert_operator (i['x'] || i['x2']), :<=, pg['w'], 'isi tidak melewati lebar halaman'
        assert_operator (i['y'] || i['y2']), :<=, pg['h'], 'isi tidak melewati tinggi halaman'
      end
    end
    pdf = P.to_pdf(lay)
    boxes = pdf.scan(%r{/MediaBox \[0 0 ([\d.]+) ([\d.]+)\]}).map { |w, h| w.to_f > h.to_f }
    assert_equal lay['pages'].map { |pg| land.call(pg) }, boxes, 'MediaBox PDF mengikuti orientasi tiap halaman'
  end

  def test_pdf_parts_ahsp_and_harga
    rep, st = sample_report
    lay = P.layout(rep, @db, st, 'Uji', %w[rab ahsp harga])
    all = lay['pages'].flat_map { |p| p['items'] }.select { |i| i['t'] == 'text' }.map { |i| i['s'] }.join("\n")
    assert_includes all, 'ANALISA HARGA SATUAN PEKERJAAN'
    assert_includes all, 'DAFTAR HARGA BAHAN (DHSP)'
    assert_includes all, 'Harga satuan pekerjaan per m2'
    assert_includes all, 'Semen Portland (PC)'
  end

  def test_pdf_file_is_wellformed
    rep, st = sample_report(30)
    lay = P.layout(rep, @db, st, 'Uji ± Ø (tes)', %w[rab ahsp])
    pdf = P.to_pdf(lay, 'RAB Uji (tes)')
    assert_equal Encoding::BINARY, pdf.encoding
    assert pdf.start_with?('%PDF-1.4')
    assert pdf.end_with?("%%EOF\n")
    assert_equal lay['pages'].size, pdf.scan(%r{/Type /Page /Parent}).size
    # tabel xref harus menunjuk tepat ke awal tiap objek
    startxref = pdf[/startxref\n(\d+)/, 1].to_i
    entries = pdf[startxref..].lines.drop(3).take_while { |l| l =~ /\A\d{10} 00000 n/ }
    refute_empty entries
    entries.each_with_index do |l, i|
      assert_equal "#{i + 1} 0 obj", pdf.byteslice(l[0, 10].to_i, 12)[/\A\d+ 0 obj/], "offset objek #{i + 1}"
    end
  end

  def test_pdf_empty_report
    st = state
    lay = P.layout(R.build_report(@db, st, {}), @db, st, 'Kosong', %w[rab ahsp harga])
    assert_operator lay['pages'].size, :>=, 1
    assert P.to_pdf(lay).start_with?('%PDF')
  end
end
