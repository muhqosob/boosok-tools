require 'sketchup'
require 'json'
require 'zlib'
require 'cgi'
require 'tmpdir'
Sketchup.require 'boosok_tools/ruby/titlebar'
Sketchup.require 'boosok_tools/ruby/locale' unless defined?(BoosokTools::Locale)

# RAB (Rencana Anggaran Biaya): ukur volume dari model lalu kalikan dengan harga satuan pekerjaan (AHSP).
#   1. Scan   : hitung jumlah / panjang / luas / volume per tag (group, component, face, edge yang terlihat)
#   2. Mapping: tiap tag dipasangkan ke satu item AHSP (disimpan di model, bukan di plugin)
#   3. Hitung : volume x harga satuan, subtotal per divisi, PPN, total
#   4. Export : Excel (.xlsx, formula hidup) atau cetak ke PDF lewat browser
# Data AHSP/harga dasar bawaan: data/ahsp_starter.json. Harga yang diubah user disimpan per model.
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
    'set' => 'count', 'pcs' => 'count', 'lbr' => 'count', 'btg' => 'count'
  }.freeze unless defined?(UNIT_BASIS)

  def self.release_dialog
    @dialog = nil
  end

  def self.run
    Sketchup.require 'boosok_tools/hub' unless defined?(BoosokTools::Hub)
    BoosokTools::Hub.open_or_show('rab')
  end

  # ── Database AHSP ─────────────────────────────────────────────────────────

  def self.db_path
    File.join(BoosokTools::SUPPORT_DIR, 'data', 'ahsp_starter.json')
  end

  # Dibaca ulang kalau file datanya berubah (hot reload saat dev)
  def self.db
    mtime = File.mtime(db_path)
    if @db.nil? || @db_mtime != mtime
      @db = JSON.parse(File.read(db_path, encoding: 'UTF-8'))
      @db_mtime = mtime
    end
    @db
  end

  def self.unit_basis(satuan)
    UNIT_BASIS[satuan.to_s.strip.downcase] || 'manual'
  end

  # Daftar item AHSP untuk dropdown di dialog
  def self.catalog(database = db)
    database['ahsp'].map do |a|
      { 'kode' => a['kode'], 'divisi' => a['divisi'], 'uraian' => a['uraian'], 'satuan' => a['satuan'],
        'basis' => unit_basis(a['satuan']), 'keyakinan' => a['keyakinan'] }
    end
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

  # Bersihkan state dari dialog / model: tipe dipaksa benar, kode tak dikenal dibuang.
  def self.normalize_state(raw, database = db)
    raw = {} unless raw.is_a?(Hash)
    kodes = database['ahsp'].map { |a| a['kode'] }
    base_kodes = database['harga_dasar'].map { |h| h['kode'] }

    map = {}
    (raw['map'].is_a?(Hash) ? raw['map'] : {}).each do |key, e|
      next unless e.is_a?(Hash) && kodes.include?(e['kode'])

      factor = num(e['factor'], 1.0)
      map[normalize_key(key)] = {
        'kode' => e['kode'],
        'basis' => BASES.include?(e['basis']) ? e['basis'] : 'auto',
        'factor' => factor.positive? ? factor : 1.0,
        'manual' => num(e['manual'], nil)
      }
    end

    prices = {}
    (raw['prices'].is_a?(Hash) ? raw['prices'] : {}).each do |kode, price|
      p = num(price, nil)
      prices[kode] = p if base_kodes.include?(kode) && p && p >= 0
    end

    meta = database['meta'] || {}
    {
      'map' => map,
      'prices' => prices,
      'op' => num(raw['op'], meta['overhead_profit_persen'] || 10).clamp(0, 100),
      'ppn' => num(raw['ppn'], meta['ppn_persen'] || 11).clamp(0, 100),
      'ppn_on' => raw.key?('ppn_on') ? raw['ppn_on'] == true : true
    }
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

  # Rincian satu AHSP: tiap komponen (koefisien x harga), jumlah bahan+upah, overhead & profit, harga satuan akhir.
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
      'jumlah' => jumlah, 'op' => op, 'hsp' => jumlah + op
    }
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
    rows.sort_by! { |r| [r['divisi'], r['kode'], r['kind'], r['tag'].downcase] }

    divisi = rows.group_by { |r| r['divisi'] }.map { |name, rs| { 'name' => name, 'subtotal' => rs.sum { |r| r['jumlah'] } } }
    subtotal = rows.sum { |r| r['jumlah'] }
    ppn = state['ppn_on'] ? subtotal * state['ppn'] / 100.0 : 0.0
    { 'rows' => rows, 'divisi' => divisi, 'subtotal' => subtotal, 'ppn_on' => state['ppn_on'],
      'ppn_pct' => state['ppn'], 'ppn' => ppn, 'total' => subtotal + ppn, 'op_pct' => state['op'] }
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
  class Xlsx
    FONTS = {
      default: '<font><sz val="11"/><name val="Calibri"/></font>',
      bold: '<font><b/><sz val="11"/><name val="Calibri"/></font>',
      white_bold: '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>',
      blue: '<font><sz val="11"/><color rgb="FF0000FF"/><name val="Calibri"/></font>',
      title: '<font><b/><sz val="14"/><name val="Calibri"/></font>',
      muted: '<font><i/><sz val="10"/><color rgb="FF71717A"/><name val="Calibri"/></font>'
    }.freeze
    FILLS = {
      none: '<fill><patternFill patternType="none"/></fill>',
      gray125: '<fill><patternFill patternType="gray125"/></fill>',
      dark: '<fill><patternFill patternType="solid"><fgColor rgb="FF1F3A5F"/><bgColor indexed="64"/></patternFill></fill>',
      light: '<fill><patternFill patternType="solid"><fgColor rgb="FFE8EEF5"/><bgColor indexed="64"/></patternFill></fill>',
      yellow: '<fill><patternFill patternType="solid"><fgColor rgb="FFFFF2CC"/><bgColor indexed="64"/></patternFill></fill>'
    }.freeze
    BORDER_THIN = '<border><left style="thin"><color rgb="FFBFBFBF"/></left><right style="thin"><color rgb="FFBFBFBF"/></right>' \
                  '<top style="thin"><color rgb="FFBFBFBF"/></top><bottom style="thin"><color rgb="FFBFBFBF"/></bottom><diagonal/></border>'.freeze
    BORDER_NONE = '<border><left/><right/><top/><bottom/><diagonal/></border>'.freeze
    # numFmt: 3 = #,##0   4 = #,##0.00   164 = #,##0.0000   165 = 0.0%
    NUMFMTS = { 164 => '#,##0.0000', 165 => '0.0%' }.freeze

    STYLES = {
      default: {},
      title: { font: :title },
      muted: { font: :muted },
      head: { font: :white_bold, fill: :dark, border: true, h: 'center', v: 'center', wrap: true },
      divisi: { font: :bold, fill: :light, border: true },
      text: { border: true },
      wrap: { border: true, wrap: true, v: 'top' },
      bold: { font: :bold, border: true },
      center: { border: true, h: 'center' },
      int: { border: true, numfmt: 3 },
      pct: { border: true, numfmt: 165 },
      sub_label: { font: :bold, fill: :light, border: true, h: 'right' },
      sub_rp: { font: :bold, fill: :light, border: true, numfmt: 3 },
      total_label: { font: :bold, fill: :yellow, border: true, h: 'right' },
      total_rp: { font: :bold, fill: :yellow, border: true, numfmt: 3 },
      in_rp: { font: :blue, border: true, numfmt: 3 },
      in_qty: { font: :blue, border: true, numfmt: 4 },
      in_koef: { font: :blue, border: true, numfmt: 164 },
      in_pct: { font: :blue, border: true, numfmt: 165 },
      in_text: { font: :blue, border: true }
    }.freeze

    Cell = Struct.new(:v, :f, :s)

    class Sheet
      attr_reader :name, :cells, :merges, :widths
      attr_accessor :freeze_row, :selected

      def initialize(name)
        @name = name
        @cells = {}
        @merges = []
        @widths = {}
        @freeze_row = nil
        @selected = false
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

    attr_reader :sheets

    def initialize
      @sheets = []
    end

    def add_sheet(name)
      sh = Sheet.new(name)
      @sheets << sh
      sh
    end

    def style_keys
      STYLES.keys
    end

    def styles_xml
      fonts = FONTS.keys
      fills = FILLS.keys
      xfs = STYLES.values.map do |st|
        numfmt = st[:numfmt] || 0
        align = %w[h v].any? { |k| st[k.to_sym] } || st[:wrap]
        attrs = %(numFmtId="#{numfmt}" fontId="#{fonts.index(st[:font] || :default)}" fillId="#{fills.index(st[:fill] || :none)}" ) +
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
        <fonts count="#{fonts.size}">#{FONTS.values.join}</fonts>
        <fills count="#{fills.size}">#{FILLS.values.join}</fills>
        <borders count="2">#{BORDER_NONE}#{BORDER_THIN}</borders>
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
      rows = sh.cells.keys.map(&:first).uniq.sort
      max_col = sh.cells.keys.map(&:last).max || 1
      data = rows.map do |r|
        cols = sh.cells.select { |(rr, _), _| rr == r }.sort_by { |(_, c), _| c }
        "<row r=\"#{r}\">#{cols.map { |(rr, c), cell| cell_xml(rr, c, cell) }.join}</row>"
      end.join
      cols = sh.widths.sort.map { |c, w| %(<col min="#{c}" max="#{c}" width="#{w}" customWidth="1"/>) }.join
      pane = ''
      if sh.freeze_row
        pane = %(<pane ySplit="#{sh.freeze_row}" topLeftCell="A#{sh.freeze_row + 1}" activePane="bottomLeft" state="frozen"/>)
      end
      merges = sh.merges.empty? ? '' : %(<mergeCells count="#{sh.merges.size}">#{sh.merges.map { |m| %(<mergeCell ref="#{m}"/>) }.join}</mergeCells>)
      <<~XML.delete("\n")
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>
        <dimension ref="A1:#{self.class.col_letter(max_col)}#{rows.last || 1}"/>
        <sheetViews><sheetView workbookViewId="0"#{sh.selected ? ' tabSelected="1"' : ''}>#{pane}</sheetView></sheetViews>
        <sheetFormatPr defaultRowHeight="15"/>
        #{cols.empty? ? '' : "<cols>#{cols}</cols>"}
        <sheetData>#{data}</sheetData>
        #{merges}
        <pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>
        <pageSetup paperSize="9" orientation="landscape" fitToHeight="0"/>
        </worksheet>
      XML
    end

    def package_files
      n = @sheets.size
      content_types = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">) +
                      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' \
                      '<Default Extension="xml" ContentType="application/xml"/>' \
                      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' \
                      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
                      (1..n).map { |i| %(<Override PartName="/xl/worksheets/sheet#{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>) }.join +
                      '</Types>'
      root_rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
                  '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
      workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ' \
                 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>' +
                 @sheets.each_with_index.map { |sh, i| %(<sheet name="#{self.class.esc(sh.name)}" sheetId="#{i + 1}" r:id="rId#{i + 1}"/>) }.join +
                 '</sheets><calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>'
      wb_rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
                (1..n).map { |i| %(<Relationship Id="rId#{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet#{i}.xml"/>) }.join +
                %(<Relationship Id="rId#{n + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>)
      files = [
        ['[Content_Types].xml', content_types], ['_rels/.rels', root_rels], ['xl/workbook.xml', workbook],
        ['xl/_rels/workbook.xml.rels', wb_rels], ['xl/styles.xml', styles_xml]
      ]
      @sheets.each_with_index { |sh, i| files << ["xl/worksheets/sheet#{i + 1}.xml", sheet_xml(sh)] }
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

  def self.build_workbook(report, database, state, project)
    base_by_kode = database['harga_dasar'].to_h { |h| [h['kode'], h] }
    ahsp_by_kode = database['ahsp'].to_h { |a| [a['kode'], a] }
    prices = effective_prices(database, state['prices'])
    op_pct = state['op']
    wb = Xlsx.new

    sh_rab = wb.add_sheet('RAB')
    sh_ahsp = wb.add_sheet('AHSP')
    sh_base = wb.add_sheet('Harga Dasar')
    sh_rab.selected = true

    # --- Harga Dasar ---
    sh_base.set(1, 1, 'HARGA DASAR BAHAN & UPAH', style: :title)
    sh_base.set(2, 1, 'Font biru = boleh diubah. Perubahan otomatis masuk ke sheet AHSP dan RAB.', style: :muted)
    %w[Kode Jenis Nama Satuan Harga\ Satuan\ (Rp)].each_with_index { |h, i| sh_base.set(4, i + 1, h, style: :head) }
    database['harga_dasar'].each_with_index do |h, i|
      r = 5 + i
      sh_base.set(r, 1, h['kode'], style: :text)
      sh_base.set(r, 2, h['jenis'], style: :text)
      sh_base.set(r, 3, h['nama'], style: :text)
      sh_base.set(r, 4, h['satuan'], style: :center)
      sh_base.set(r, 5, prices[h['kode']], style: :in_rp)
    end
    base_last = 4 + database['harga_dasar'].size
    [9, 8, 36, 9, 18].each_with_index { |w, i| sh_base.width(i + 1, w) }
    sh_base.freeze_row = 4
    lookup = lambda do |col, row|
      "INDEX('Harga Dasar'!$#{col}$5:$#{col}$#{base_last},MATCH($A#{row},'Harga Dasar'!$A$5:$A$#{base_last},0))"
    end

    # --- AHSP (hanya item yang dipakai di RAB) ---
    sh_ahsp.set(1, 1, 'ANALISA HARGA SATUAN PEKERJAAN (AHSP)', style: :title)
    sh_ahsp.set(2, 1, 'Koefisien berbasis SNI 7394:2008; verifikasi ke dokumen resmi sebelum dipakai. Font biru = boleh diubah.', style: :muted)
    sh_ahsp.set(3, 1, 'Overhead & Profit', style: :bold)
    sh_ahsp.set(3, 2, nil, style: :bold)
    sh_ahsp.set(3, 3, nil, style: :bold)
    sh_ahsp.set(3, 4, op_pct / 100.0, style: :in_pct)
    %w[Kode Uraian/Komponen Sat. Koefisien Harga\ Satuan Jumlah].each_with_index { |h, i| sh_ahsp.set(5, i + 1, h, style: :head) }
    hsp_cell = {} # kode AHSP -> alamat sel harga satuan akhir
    r = 6
    report['rows'].map { |row| row['kode'] }.uniq.each do |kode|
      item = ahsp_by_kode[kode]
      bd = ahsp_breakdown(item, base_by_kode, prices, op_pct)
      sh_ahsp.set(r, 1, item['kode'], style: :divisi)
      sh_ahsp.set(r, 2, item['uraian'], style: :divisi)
      sh_ahsp.set(r, 3, item['satuan'], style: :divisi)
      4.upto(6) { |c| sh_ahsp.set(r, c, nil, style: :divisi) }
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
      sh_ahsp.set(r, 2, 'Jumlah harga bahan + upah', style: :bold)
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

    # --- RAB ---
    sh_rab.set(1, 1, 'RENCANA ANGGARAN BIAYA (RAB)', style: :title)
    sh_rab.merge(1, 1, 1, 8)
    sh_rab.set(2, 1, "Proyek : #{project}")
    sh_rab.set(3, 1, "Tanggal : #{Time.now.strftime('%d-%m-%Y')}")
    %w[No Uraian\ Pekerjaan Sat. Volume Harga\ Satuan\ (Rp) Jumlah\ (Rp) Kode\ AHSP Sumber].each_with_index { |h, i| sh_rab.set(5, i + 1, h, style: :head) }
    r = 6
    sub_cells = []
    report['rows'].group_by { |row| row['divisi'] }.each do |divisi, rows|
      sh_rab.set(r, 1, divisi.upcase, style: :divisi)
      2.upto(8) { |c| sh_rab.set(r, c, nil, style: :divisi) }
      sh_rab.merge(r, 1, r, 8)
      r += 1
      first = r
      rows.each_with_index do |row, i|
        sh_rab.set(r, 1, i + 1, style: :center)
        sh_rab.set(r, 2, row['uraian'], style: :wrap)
        sh_rab.set(r, 3, row['satuan'], style: :center)
        sh_rab.set(r, 4, row['qty'], style: :in_qty)
        sh_rab.set(r, 5, row['hsp'], style: :int, f: hsp_cell[row['kode']])
        sh_rab.set(r, 6, row['jumlah'], style: :int, f: "D#{r}*E#{r}")
        sh_rab.set(r, 7, row['kode'], style: :center)
        sh_rab.set(r, 8, row['label'], style: :text)
        r += 1
      end
      sh_rab.set(r, 2, "Sub total #{divisi}", style: :sub_label)
      [1, 3, 4, 5, 7, 8].each { |c| sh_rab.set(r, c, nil, style: :sub_label) }
      sub = rows.sum { |row| row['jumlah'] }
      sh_rab.set(r, 6, sub, style: :sub_rp, f: "SUM(F#{first}:F#{r - 1})")
      sub_cells << "F#{r}"
      r += 1
    end
    r += 1
    sh_rab.set(r, 2, 'JUMLAH', style: :sub_label)
    [1, 3, 4, 5, 7, 8].each { |c| sh_rab.set(r, c, nil, style: :sub_label) }
    sh_rab.set(r, 6, report['subtotal'], style: :sub_rp, f: sub_cells.empty? ? '0' : sub_cells.join('+'))
    jumlah_row = r
    r += 1
    ppn_pct = report['ppn_on'] ? report['ppn_pct'] : 0.0
    sh_rab.set(r, 2, 'PPN', style: :sub_label)
    [1, 3, 4, 7, 8].each { |c| sh_rab.set(r, c, nil, style: :sub_label) }
    sh_rab.set(r, 5, ppn_pct / 100.0, style: :in_pct)
    sh_rab.set(r, 6, report['ppn'], style: :sub_rp, f: "F#{jumlah_row}*E#{r}")
    ppn_row = r
    r += 1
    sh_rab.set(r, 2, 'TOTAL', style: :total_label)
    [1, 3, 4, 5, 7, 8].each { |c| sh_rab.set(r, c, nil, style: :total_label) }
    sh_rab.set(r, 6, report['total'], style: :total_rp, f: "F#{jumlah_row}+F#{ppn_row}")
    r += 2
    sh_rab.set(r, 1, 'Volume (font biru) dan harga di sheet "Harga Dasar" boleh diubah; semua jumlah dihitung ulang otomatis.', style: :muted)
    [6, 52, 8, 12, 18, 18, 10, 24].each_with_index { |w, i| sh_rab.width(i + 1, w) }
    sh_rab.freeze_row = 5
    wb
  end

  # ── Cetak / PDF lewat browser ─────────────────────────────────────────────

  def self.build_print_html(report, project)
    h = ->(s) { CGI.escapeHTML(s.to_s) }
    body = +''
    report['rows'].group_by { |r| r['divisi'] }.each do |divisi, rows|
      body << "<tr class=\"div\"><td colspan=\"6\">#{h.call(divisi.upcase)}</td></tr>"
      rows.each_with_index do |r, i|
        body << "<tr><td class=\"c\">#{i + 1}</td><td>#{h.call(r['uraian'])}<div class=\"tag\">#{h.call(r['label'])} · #{h.call(r['kode'])}</div></td>" \
                "<td class=\"c\">#{h.call(r['satuan'])}</td><td class=\"n\">#{fmt_num(r['qty'], 2)}</td>" \
                "<td class=\"n\">#{fmt_num(r['hsp'])}</td><td class=\"n\">#{fmt_num(r['jumlah'])}</td></tr>"
      end
      sub = rows.sum { |r| r['jumlah'] }
      body << "<tr class=\"sub\"><td colspan=\"5\">Sub total #{h.call(divisi)}</td><td class=\"n\">#{fmt_num(sub)}</td></tr>"
    end
    body << "<tr class=\"sub\"><td colspan=\"5\">JUMLAH</td><td class=\"n\">#{fmt_num(report['subtotal'])}</td></tr>"
    body << "<tr class=\"sub\"><td colspan=\"5\">PPN #{fmt_num(report['ppn_on'] ? report['ppn_pct'] : 0, 1)}%</td><td class=\"n\">#{fmt_num(report['ppn'])}</td></tr>"
    body << "<tr class=\"tot\"><td colspan=\"5\">TOTAL</td><td class=\"n\">#{fmt_num(report['total'])}</td></tr>"
    <<~HTML
      <!DOCTYPE html>
      <html lang="id"><head><meta charset="UTF-8"><title>RAB - #{h.call(project)}</title>
      <style>
        body { font: 12px/1.4 "Segoe UI", Arial, sans-serif; color: #18181b; margin: 24px; }
        h1 { font-size: 18px; margin: 0 0 2px; } .meta { color: #52525b; margin-bottom: 14px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { border: 1px solid #bfbfbf; padding: 4px 6px; vertical-align: top; }
        th { background: #1f3a5f; color: #fff; }
        td.n { text-align: right; white-space: nowrap; } td.c { text-align: center; }
        tr.div td { background: #e8eef5; font-weight: 700; } tr.sub td { background: #e8eef5; font-weight: 700; text-align: right; }
        tr.sub td.n { text-align: right; } tr.tot td { background: #fff2cc; font-weight: 700; text-align: right; }
        .tag { color: #71717a; font-size: 10.5px; }
        .bar { margin-bottom: 12px; } button { padding: 6px 14px; font: inherit; cursor: pointer; }
        @media print { .bar { display: none; } body { margin: 10mm; } tr { page-break-inside: avoid; } thead { display: table-header-group; } }
      </style></head><body>
      <div class="bar"><button onclick="window.print()">Cetak / Simpan sebagai PDF</button></div>
      <h1>RENCANA ANGGARAN BIAYA (RAB)</h1>
      <div class="meta">Proyek : #{h.call(project)}<br>Tanggal : #{Time.now.strftime('%d-%m-%Y')}</div>
      <table><thead><tr><th style="width:36px">No</th><th>Uraian Pekerjaan</th><th style="width:48px">Sat.</th>
      <th style="width:80px">Volume</th><th style="width:110px">Harga Satuan (Rp)</th><th style="width:120px">Jumlah (Rp)</th></tr></thead>
      <tbody>#{body}</tbody></table>
      <script>window.addEventListener('load', function () { setTimeout(function () { window.print(); }, 400); });</script>
      </body></html>
    HTML
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
    tags = tag_rows(model, @measures, state['map'].keys)
    { 'tags' => tags, 'report' => build_report(db, state, @measures) }
  end

  def self.send_init_data(dialog)
    return unless dialog

    model = Sketchup.active_model
    unless model
      dialog.execute_script("rabError(#{'Tidak ada model yang aktif.'.to_json});")
      return
    end

    state = load_state(model)
    payload = refresh(model, state).merge(
      'catalog' => catalog, 'base' => db['harga_dasar'], 'state' => state,
      'meta' => db['meta'], 'project' => project_name(model)
    )
    dialog.execute_script("init(#{payload.to_json});")
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
    report = refresh(model, state)['report']
    project = project_name(model)
    name = safe_filename("RAB - #{project}") + '.xlsx'
    path = UI.savepanel('Export RAB ke Excel', default_dir(model), name)
    return dialog.execute_script('onExported(null);') unless path

    path = "#{path}.xlsx" unless path.downcase.end_with?('.xlsx')
    build_workbook(report, db, state, project).save(path)
    dialog.execute_script("onExported(#{path.to_json});")
  end

  def self.export_print(dialog, state)
    model = Sketchup.active_model
    report = refresh(model, state)['report']
    path = File.join(Dir.tmpdir, "boosok_rab_#{Time.now.to_i}.html")
    File.write(path, build_print_html(report, project_name(model)), encoding: 'UTF-8')
    UI.openURL(file_url(path))
    dialog.execute_script('onPrinted();')
  end

  # file:///C:/Users/... dengan karakter khusus (spasi dll.) di-escape
  def self.file_url(path)
    escaped = path.tr('\\', '/').gsub(%r{[^A-Za-z0-9\-._~/:]}) { |c| c.bytes.map { |b| format('%%%02X', b) }.join }
    "file:///#{escaped}"
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
        dialog.execute_script("onReport(#{build_report(db, state, @measures).to_json});")
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

    dialog.add_action_callback('rab_export_print') do |_ctx, json|
      guarded.call('cetak') do
        state = parse_state(json)
        save_state(Sketchup.active_model, state)
        export_print(dialog, state)
      end
    end
  end
end

file_loaded(__FILE__)
