require_relative 'test_helper'
require 'zlib'
require 'stringio'

load File.join(PLUGIN, 'ruby', 'paid', 'rab.rb')

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
       xl/worksheets/sheet1.xml xl/worksheets/sheet2.xml xl/worksheets/sheet3.xml].each do |part|
      assert files.key?(part), "bagian #{part} hilang"
    end
    assert_includes files['xl/workbook.xml'], 'name="RAB"'
    assert_includes files['xl/workbook.xml'], 'name="Harga Dasar"'
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
    rab = files['xl/worksheets/sheet1.xml']
    assert_includes rab, 'Rumah &lt;A&gt; &amp; B'
    refute_includes rab, 'Rumah <A>'
    assert_match(%r{<f>D\d+\*E\d+</f>}, rab, 'Jumlah harus formula Volume x Harga')
    assert_match(%r{<f>AHSP!\$F\$\d+</f>}, rab, 'Harga satuan harus menunjuk sheet AHSP')
    assert_includes files['xl/worksheets/sheet2.xml'], 'INDEX(&#39;Harga Dasar&#39;', 'AHSP menarik harga dari sheet Harga Dasar'
    assert_includes rab, "<v>#{format('%.12g', rep['total'])}</v>", 'nilai cache total'
  end

  def test_xlsx_price_override_is_written_to_base_sheet
    wb, = sample_workbook
    base = unzip(wb.to_binary)['xl/worksheets/sheet3.xml']
    assert_includes base, '<v>1500</v>' # harga semen yang diubah
  end

  def test_xlsx_empty_report_still_builds
    st = state
    rep = R.build_report(@db, st, {})
    files = unzip(R.build_workbook(rep, @db, st, 'Kosong').to_binary)
    assert files['xl/worksheets/sheet1.xml'].include?('TOTAL')
  end

  def test_col_letters
    assert_equal 'A', R::Xlsx.col_letter(1)
    assert_equal 'Z', R::Xlsx.col_letter(26)
    assert_equal 'AA', R::Xlsx.col_letter(27)
  end

  # ── Cetak ───────────────────────────────────────────────────────────────

  def test_print_html_escapes_and_totals
    st = state({ 'Tag <x>' => { 'kode' => 'D.01' } })
    rep = R.build_report(@db, st, { 'tag:Tag <x>' => measure('area' => 10.0) })
    html = R.build_print_html(rep, 'Proyek "Q"')
    refute_includes html, 'Tag <x>'
    assert_includes html, 'Tag &lt;x&gt;'
    assert_includes html, R.fmt_num(rep['total'])
  end

  def test_file_url_escapes_spaces
    assert_equal 'file:///C:/Users/A%20B/x.html', R.file_url('C:\\Users\\A B\\x.html')
  end
end
