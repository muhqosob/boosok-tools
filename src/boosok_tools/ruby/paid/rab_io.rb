require 'json'
require 'zlib'

# Baca-tulis data RAB yang murni (tanpa SketchUp): pembaca .xlsx minimal dan pembersih file daftar harga.
# Penulis .xlsx ada di rab.rb (Xlsx); di sini hanya sisi baca, supaya harga yang diedit di Excel bisa diimpor lagi.
module BoosokTools::RabIo
  MAX_UNZIPPED = 60 * 1024 * 1024 unless defined?(MAX_UNZIPPED)
  MAX_CELLS = 400_000 unless defined?(MAX_CELLS)
  MAX_PRICE_ITEMS = 60_000 unless defined?(MAX_PRICE_ITEMS)
  PRICE_FORMAT = 'boosok-rab-harga'.freeze unless defined?(PRICE_FORMAT)
  JENIS = %w[upah bahan alat].freeze unless defined?(JENIS)

  class Error < StandardError; end

  # ── ZIP (hanya membaca, tanpa ZIP64) ──────────────────────────────────────

  # Return { "nama/dalam/zip" => isi (BINARY) }, hanya entri yang namanya dipilih blok (tidak mengembang yang lain).
  def self.unzip(bytes, &want)
    data = bytes.b
    eocd = data.rindex([0x06054b50].pack('V'))
    raise Error, 'Bukan file .xlsx yang valid.' unless eocd && data.bytesize >= eocd + 22

    count, _size, offset = data.byteslice(eocd + 10, 12).unpack('vVV')
    pos = offset
    out = {}
    total = 0
    count.times do
      raise Error, 'Bukan file .xlsx yang valid.' unless data.byteslice(pos, 4) == [0x02014b50].pack('V')

      method, _t, _d, _crc, csize, usize, nlen, elen, clen = data.byteslice(pos + 10, 26).unpack('vvvVVVvvv')
      local = data.byteslice(pos + 42, 4).unpack1('V')
      name = data.byteslice(pos + 46, nlen).force_encoding('UTF-8')
      pos += 46 + nlen + elen + clen
      next unless want.call(name)

      total += usize
      raise Error, 'File terlalu besar.' if total > MAX_UNZIPPED

      lnlen, lelen = data.byteslice(local + 26, 4).unpack('vv')
      raw = data.byteslice(local + 30 + lnlen + lelen, csize)
      out[name] = case method
                  when 0 then raw
                  when 8 then inflate(raw)
                  else raise Error, 'Kompresi .xlsx tidak didukung.'
                  end
    end
    out
  end

  def self.inflate(raw)
    z = Zlib::Inflate.new(-Zlib::MAX_WBITS)
    out = String.new(encoding: Encoding::BINARY)
    pos = 0
    while pos < raw.bytesize
      out << z.inflate(raw.byteslice(pos, 16_384))
      raise Error, 'File terlalu besar.' if out.bytesize > MAX_UNZIPPED

      pos += 16_384
    end
    out << z.finish
  ensure
    z&.close
  end

  # ── XLSX: sheet pertama menjadi baris-baris sel ───────────────────────────

  XML_ENT = { 'amp' => '&', 'lt' => '<', 'gt' => '>', 'quot' => '"', 'apos' => "'" }.freeze unless defined?(XML_ENT)

  def self.unxml(text)
    text.gsub(/&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);/) do
      e = Regexp.last_match(1)
      if e.start_with?('#x') then [e[2..].to_i(16)].pack('U')
      elsif e.start_with?('#') then [e[1..].to_i].pack('U')
      else XML_ENT[e]
      end
    end
  rescue RangeError
    text
  end

  def self.col_index(letters)
    letters.upcase.each_char.reduce(0) { |n, c| (n * 26) + (c.ord - 64) }
  end

  def self.shared_strings(xml)
    return [] unless xml

    xml.scan(%r{<si\b[^>]*>(.*?)</si>}m).map do |(body)|
      body = body.gsub(%r{<rPh\b.*?</rPh>}m, '')
      unxml(body.scan(%r{<t\b[^>]*>(.*?)</t>}m).flatten.join)
    end
  end

  # Path sheet pertama menurut urutan tab di workbook.xml (bukan sekadar sheet1.xml)
  def self.first_sheet_path(files)
    wb = files['xl/workbook.xml'].to_s
    rid = wb[/<sheet\b[^>]*\br:id="([^"]+)"/, 1]
    rels = files['xl/_rels/workbook.xml.rels'].to_s
    if rid
      rels.scan(%r{<Relationship\b[^>]*>}).each do |tag|
        next unless tag[/\bId="([^"]+)"/, 1] == rid

        target = tag[/\bTarget="([^"]+)"/, 1].to_s
        path = target.start_with?('/') ? target[1..] : "xl/#{target}"
        return path if files.key?(path)
      end
    end
    files.keys.grep(%r{\Axl/worksheets/[^/]+\.xml\z}).min
  end

  def self.unzip_book(bytes)
    unzip(bytes) do |n|
      %w[xl/workbook.xml xl/_rels/workbook.xml.rels xl/sharedStrings.xml xl/styles.xml xl/theme/theme1.xml].include?(n) || n.match?(%r{\Axl/worksheets/[^/]+\.xml\z})
    end
  end

  # Semua sheet menurut urutan tab: [[nama, path_dalam_zip]]
  def self.sheet_list(files)
    wb = files['xl/workbook.xml'].to_s.dup.force_encoding('UTF-8')
    rels = files['xl/_rels/workbook.xml.rels'].to_s
    wb.scan(%r{<sheet\b[^>]*>}).filter_map do |tag|
      rid = tag[/\br:id="([^"]+)"/, 1]
      name = unxml(tag[/\bname="([^"]*)"/, 1].to_s)
      target = rels.scan(%r{<Relationship\b[^>]*>}).find { |r| r[/\bId="([^"]+)"/, 1] == rid }&.then { |r| r[/\bTarget="([^"]+)"/, 1].to_s }
      next unless target

      path = target.start_with?('/') ? target[1..] : "xl/#{target}"
      [name, path] if files.key?(path)
    end
  end

  # Isi sheet pertama: { cells: { baris => { kolom => [nilai, id_gaya] } }, files: {...} }. Sel kosong dilewati.
  def self.read_book(bytes)
    files = unzip_book(bytes)
    path = first_sheet_path(files)
    raise Error, 'Tidak ada sheet di file Excel ini.' unless path

    { cells: parse_sheet(files[path], shared_strings(files['xl/sharedStrings.xml']&.force_encoding('UTF-8'))), files: files }
  end

  # { "Nama sheet" (huruf kecil) => baris-baris sel } untuk semua sheet (template dengan beberapa sheet)
  def self.read_sheets(bytes)
    files = unzip_book(bytes)
    strings = shared_strings(files['xl/sharedStrings.xml']&.force_encoding('UTF-8'))
    list = sheet_list(files)
    raise Error, 'Tidak ada sheet di file Excel ini.' if list.empty?

    total = 0
    list.to_h do |name, path|
      cells = parse_sheet(files[path], strings)
      total += cells.values.sum(&:size)
      raise Error, 'Sheet terlalu besar.' if total > MAX_CELLS
      [name.strip.downcase, cells_to_rows(cells)]
    end
  end

  def self.cells_to_rows(rows)
    return [] if rows.empty?

    (1..rows.keys.max).map do |r|
      cols = rows[r] || {}
      cols.empty? ? [] : (1..cols.keys.max).map { |c| cols[c]&.first }
    end
  end

  def self.parse_sheet(xml, strings)
    xml = xml.dup.force_encoding('UTF-8')
    rows = {}
    count = 0
    xml.scan(%r{<c\b([^>]*?)(?:/>|>(.*?)</c>)}m) do |attrs, body|
      ref = attrs[/\br="([A-Za-z]+)(\d+)"/]
      next unless ref

      col = col_index(Regexp.last_match(1))
      row = Regexp.last_match(2).to_i
      count += 1
      raise Error, 'Sheet terlalu besar.' if count > MAX_CELLS

      type = attrs[/\bt="([^"]+)"/, 1]
      value = nil
      if body
        if type == 'inlineStr'
          value = unxml(body.scan(%r{<t\b[^>]*>(.*?)</t>}m).flatten.join)
        else
          v = body[%r{<v>(.*?)</v>}m, 1]
          unless v.nil?
            value = case type
                    when 's' then strings[v.to_i]
                    when 'str', 'e' then unxml(v)
                    when 'b' then v == '1' ? 1.0 : 0.0
                    else Float(v, exception: false)
                    end
          end
        end
      end
      next if value.nil? || (value.is_a?(String) && value.strip.empty?)

      (rows[row] ||= {})[col] = [value, attrs[/\bs="(\d+)"/, 1].to_i]
    end
    rows
  end

  # Return array of rows; tiap baris array sel (String / Float / nil), indeks 0 = kolom A
  def self.read_xlsx(bytes)
    cells_to_rows(read_book(bytes)[:cells])
  end

  # ── Gaya sel (untuk impor template tema) ──────────────────────────────────

  OFFICE_THEME = %w[ffffff 000000 e7e6e6 44546a 4472c4 ed7d31 a5a5a5 ffc000 5b9bd5 70ad47].freeze unless defined?(OFFICE_THEME)
  THEME_TAGS = %w[lt1 dk1 lt2 dk2 accent1 accent2 accent3 accent4 accent5 accent6].freeze unless defined?(THEME_TAGS)

  def self.theme_palette(xml)
    return OFFICE_THEME unless xml

    text = xml.dup.force_encoding('UTF-8')
    THEME_TAGS.each_with_index.map do |tag, i|
      body = text[%r{<a:#{tag}>(.*?)</a:#{tag}>}m, 1].to_s
      (body[/srgbClr val="(\h{6})"/, 1] || body[/lastClr="(\h{6})"/, 1] || OFFICE_THEME[i]).downcase
    end
  end

  # Warna dari atribut elemen (<color rgb=".." / theme=".." tint=".."/>) -> "rrggbb" atau nil
  def self.color_of(attrs, palette)
    return nil unless attrs

    if (rgb = attrs[/\brgb="(\h{6,8})"/, 1])
      return rgb[-6, 6].downcase
    end
    return nil unless (idx = attrs[/\btheme="(\d+)"/, 1])

    base = palette[idx.to_i]
    return nil unless base

    tint = attrs[/\btint="(-?[\d.]+)"/, 1].to_f
    tint.zero? ? base : apply_tint(base, tint)
  end

  # Tint Excel: mengubah kecerahan (L pada HSL), bukan mencampur dengan putih/hitam di ruang RGB
  def self.apply_tint(hex, tint)
    r, g, b = hex.scan(/../).map { |h| h.hex / 255.0 }
    max = [r, g, b].max
    min = [r, g, b].min
    l = (max + min) / 2.0
    d = max - min
    if d.zero?
      h = s = 0.0
    else
      s = l > 0.5 ? d / (2.0 - max - min) : d / (max + min)
      h = case max
          when r then ((g - b) / d) % 6
          when g then ((b - r) / d) + 2
          else ((r - g) / d) + 4
          end / 6.0
    end
    l = tint.negative? ? l * (1 + tint) : (l * (1 - tint)) + tint
    q = l < 0.5 ? l * (1 + s) : l + s - (l * s)
    p = (2 * l) - q
    channel = lambda do |t|
      t += 1 if t.negative?
      t -= 1 if t > 1
      v = if t < 1.0 / 6 then p + ((q - p) * 6 * t)
          elsif t < 0.5 then q
          elsif t < 2.0 / 3 then p + ((q - p) * ((2.0 / 3) - t) * 6)
          else p
          end
      format('%02x', (v * 255).round.clamp(0, 255))
    end
    [h + (1.0 / 3), h, h - (1.0 / 3)].map { |t| channel.call(t) }.join
  end

  # styles.xml -> daftar gaya per id sel: [{ 'font' => {name,size,bold,italic,color}, 'fill' => hex|nil, 'border' => hex|nil }]
  def self.read_styles(files)
    xml = files['xl/styles.xml']&.dup&.force_encoding('UTF-8')
    return [] unless xml

    palette = theme_palette(files['xl/theme/theme1.xml'])
    section = ->(tag) { xml[%r{<#{tag}\b[^>]*>(.*?)</#{tag}>}m, 1].to_s }
    fonts = section.call('fonts').scan(%r{<font(?:\s[^>]*)?>(.*?)</font>}m).map do |(body)|
      { 'name' => body[/<name val="([^"]+)"/, 1], 'size' => body[/<sz val="([\d.]+)"/, 1]&.to_f,
        'bold' => body.match?(%r{<b\s*/>|<b\s+val="(?:1|true)"\s*/>}), 'italic' => body.match?(%r{<i\s*/>|<i\s+val="(?:1|true)"\s*/>}),
        'color' => color_of(body[%r{<color\b([^>]*?)/?>}m, 1], palette) }
    end
    fills = section.call('fills').scan(%r{<fill>(.*?)</fill>}m).map do |(body)|
      body.match?(/patternType="solid"/) ? color_of(body[%r{<fgColor\b([^>]*?)/?>}m, 1], palette) : nil
    end
    borders = section.call('borders').scan(%r{<border(?:\s[^>]*)?>(.*?)</border>}m).map do |(body)|
      %w[left right top bottom].filter_map { |side| body[%r{<#{side}\b[^>]*\bstyle="[^"]+"[^>]*>\s*<color\b([^>]*?)/?>}m, 1] }.filter_map { |c| color_of(c, palette) }.first
    end
    section.call('cellXfs').scan(%r{<xf\b([^>]*?)(?:/>|>.*?</xf>)}m).map do |(attrs)|
      { 'font' => fonts[attrs[/\bfontId="(\d+)"/, 1].to_i] || {}, 'fill' => fills[attrs[/\bfillId="(\d+)"/, 1].to_i],
        'border' => borders[attrs[/\bborderId="(\d+)"/, 1].to_i] }
    end
  end

  # ── Daftar harga ─────────────────────────────────────────────────────────

  def self.clean(value, max)
    value.to_s.gsub(/[[:cntrl:]]+/, ' ').strip[0, max].to_s
  end

  # "1.234.567,50" / "1234567.5" / "Rp 1.500" / 1500.0 -> Float (nil kalau bukan angka)
  def self.parse_number(value)
    return (value.finite? ? value.to_f : nil) if value.is_a?(Numeric)

    s = value.to_s.gsub(/rp\.?|\s/i, '')
    return nil if s.empty? || s.match?(/[^0-9.,\-]/)

    if s.include?(',') && s.include?('.')
      s = s.rindex(',') > s.rindex('.') ? s.delete('.').tr(',', '.') : s.delete(',')
    elsif s.include?(',')
      s = s.match?(/\A-?\d{1,3}(,\d{3})+\z/) ? s.delete(',') : s.tr(',', '.')
    elsif s.match?(/\A-?\d{1,3}(\.\d{3})+\z/)
      s = s.delete('.')
    end
    Float(s, exception: false)
  end

  def self.jenis_of(value)
    j = value.to_s.strip.downcase
    return j if JENIS.include?(j)

    { 'tenaga kerja' => 'upah', 'tenaga' => 'upah', 'material' => 'bahan', 'peralatan' => 'alat' }[j]
  end

  # Baris-baris tabel (dari Excel) -> item harga. Baris judul dicari otomatis dalam 25 baris pertama:
  # harus ada kolom "Nama" (atau Uraian) dan "Harga". Kolom lain (Kode, Jenis, Sat/Satuan) opsional.
  def self.rows_to_items(rows)
    head_at = nil
    cols = {}
    rows.first(25).each_with_index do |row, i|
      found = {}
      row.each_with_index do |cell, c|
        h = cell.to_s.strip.downcase
        next if h.empty?

        found[:kode] ||= c if h.match?(/\Akode/)
        found[:jenis] ||= c if h.match?(/\A(jenis|tipe|golongan)/)
        found[:nama] ||= c if h.match?(/\A(nama|uraian|item|bahan)/)
        found[:satuan] ||= c if h.match?(/\Asat/)
        found[:harga] ||= c if h.match?(/harga/)
      end
      if found[:nama] && found[:harga]
        head_at = i
        cols = found
        break
      end
    end
    raise Error, 'Kolom "Nama" dan "Harga" tidak ditemukan di 25 baris pertama sheet. Pakai template Excel daftar harga dari tab Sumber Data.' unless head_at

    rows.drop(head_at + 1).filter_map do |row|
      nama = clean(row[cols[:nama]], 160)
      harga = parse_number(row[cols[:harga]])
      next if nama.empty? || harga.nil? || harga.negative?

      item = { 'nama' => nama, 'satuan' => cols[:satuan] ? clean(row[cols[:satuan]], 16) : '', 'harga' => harga }
      kode = cols[:kode] ? clean(row[cols[:kode]], 40) : ''
      item['kode'] = kode unless kode.empty?
      jenis = cols[:jenis] ? jenis_of(row[cols[:jenis]]) : nil
      item['jenis'] = jenis if jenis
      item
    end.first(MAX_PRICE_ITEMS)
  end

  # JSON mentah -> { 'meta' => {...}, 'items' => [...] } atau nil kalau bukan daftar harga.
  # Diterima: hasil ekspor aplikasi ('items'), file HSD ('items' + sumber/wilayah/tahun di atas), 'harga_dasar' milik file AHSP, atau array item.
  def self.sanitize_prices(raw)
    list = raw.is_a?(Array) ? raw : (raw.is_a?(Hash) ? (raw['items'] || raw['harga_dasar']) : nil)
    return nil unless list.is_a?(Array)

    items = list.first(MAX_PRICE_ITEMS).filter_map do |i|
      next unless i.is_a?(Hash)

      nama = clean(i['nama'], 160)
      harga = parse_number(i['harga'])
      next if nama.empty? || harga.nil? || harga.negative?

      item = { 'nama' => nama, 'satuan' => clean(i['satuan'], 16), 'harga' => harga }
      kode = clean(i['kode'], 40)
      item['kode'] = kode unless kode.empty?
      jenis = jenis_of(i['jenis'])
      item['jenis'] = jenis if jenis
      item
    end
    src = raw.is_a?(Hash) ? (raw['meta'].is_a?(Hash) ? raw['meta'].merge(raw) { |_k, a, _b| a } : raw) : {}
    meta = {}
    %w[nama sumber wilayah url catatan].each { |f| meta[f] = clean(src[f], 300) unless clean(src[f], 300).empty? }
    tahun = clean(src['tahun'] || src['tahun_data'], 12)
    meta['tahun'] = tahun unless tahun.empty?
    { 'meta' => meta, 'items' => items }
  end

  # ── AHSP dalam Excel: dua format yang bisa diimpor ────────────────────────
  # 1. Laporan: sheet "AHSP" (blok per analisa: baris Kode/Uraian/Sat lalu baris komponen) + sheet "Harga Dasar" / "DHSP".
  #    Ini format hasil ekspor file AHSP & laporan AHSP; kolom Divisi, Kategori, dst. di sebelah kanan membawa data yang tak ada di laporan cetak.
  # 2. Template datar: sheet Analisa + Komponen + Harga Dasar (satu baris per analisa / komponen), paling mudah diisi manual.
  # Dikenali lewat nama sheet & judul kolom, jadi file Excel lain ditolak dengan pesan jelas.

  AHSP_SHEET_ANA = 'analisa'.freeze unless defined?(AHSP_SHEET_ANA)
  AHSP_SHEET_COMP = 'komponen'.freeze unless defined?(AHSP_SHEET_COMP)
  AHSP_SHEET_BASE = 'harga dasar'.freeze unless defined?(AHSP_SHEET_BASE)
  AHSP_SHEET_REPORT = 'ahsp'.freeze unless defined?(AHSP_SHEET_REPORT)
  AHSP_SHEET_DHSP = 'dhsp'.freeze unless defined?(AHSP_SHEET_DHSP)
  AHSP_NOT_TEMPLATE = 'Bukan file AHSP Boosok Tools. Pakai file hasil ekspor AHSP (sheet AHSP + Harga Dasar) atau Template Excel dari tab Sumber Data (sheet Analisa, Komponen, Harga Dasar).'.freeze unless defined?(AHSP_NOT_TEMPLATE)

  # Judul kolom -> kunci. required: kolom yang wajib ada supaya sheet dianggap benar.
  AHSP_COLUMNS = {
    AHSP_SHEET_ANA => { cols: { kode: /\Akode/, divisi: /\Adivisi/, kategori: /\Akategori/, uraian: /\A(uraian|nama|pekerjaan)/, satuan: /\Asat/,
                                catatan: /\A(catatan|keterangan)/ }, required: %i[kode uraian] },
    AHSP_SHEET_COMP => { cols: { analisa: /\Akode\s*(analisa|ahsp|pekerjaan)/, harga: /\Akode\s*(harga|komponen|bahan)/, koef: /\Akoef/ },
                         required: %i[analisa harga koef] },
    AHSP_SHEET_BASE => { cols: { kode: /\Akode/, jenis: /\A(jenis|tipe|golongan)/, nama: /\A(nama|uraian)/, satuan: /\Asat/, harga: /harga/ },
                         required: %i[kode nama] },
    AHSP_SHEET_REPORT => { cols: { kode: /\Akode/, uraian: /\Auraian/, satuan: /\Asat/, koef: /\Akoef/, divisi: /\Adivisi/, kategori: /\Akategori/,
                                   keyakinan: /\Akeyakinan/, acuan: /\Aacuan/, catatan: /\A(catatan|keterangan)/ }, required: %i[kode uraian koef] }
  }.freeze unless defined?(AHSP_COLUMNS)

  # [indeks_baris_judul, { kunci => indeks_kolom }] atau nil kalau judul wajib tidak ada di 15 baris pertama
  def self.find_columns(rows, sheet)
    spec = AHSP_COLUMNS.fetch(sheet)
    rows.first(15).each_with_index do |row, i|
      found = {}
      row.each_with_index do |cell, c|
        h = cell.to_s.strip.downcase
        next if h.empty?

        spec[:cols].each { |key, re| found[key] ||= c if !found.value?(c) && h.match?(re) }
      end
      return [i, found] if spec[:required].all? { |k| found.key?(k) }
    end
    nil
  end

  def self.cell_text(row, cols, key, max)
    cols[key] ? clean(row[cols[key]], max) : ''
  end

  # Sheet harga dasar (judul kolom: Kode, Jenis, Nama, Satuan, Harga). Return [daftar_harga, jumlah_baris_tak_valid]
  def self.read_base_sheet(rows)
    head_at, cols = find_columns(rows, AHSP_SHEET_BASE)
    raise Error, AHSP_NOT_TEMPLATE unless cols

    bad = 0
    base = rows.drop(head_at + 1).filter_map do |row|
      kode = cell_text(row, cols, :kode, 40)
      nama = cell_text(row, cols, :nama, 160)
      next if kode.empty? && nama.empty?

      jenis = cols[:jenis] ? jenis_of(row[cols[:jenis]]) : nil
      raw = cols[:harga] ? row[cols[:harga]] : nil
      harga = raw.nil? || raw.to_s.strip.empty? ? 0.0 : parse_number(raw) # harga boleh kosong: diisi dari file harga
      if kode.empty? || nama.empty? || jenis.nil? || harga.nil? || harga.negative?
        bad += 1
        next
      end
      { 'kode' => kode, 'jenis' => jenis, 'nama' => nama, 'satuan' => cell_text(row, cols, :satuan, 16), 'harga' => harga }
    end
    [base, bad]
  end

  # Isi workbook AHSP -> { 'data' => { 'meta', 'harga_dasar', 'ahsp' } (belum disaring), 'warn' => [pesan] }
  def self.read_ahsp_book(bytes)
    sheets = read_sheets(bytes)
    if sheets[AHSP_SHEET_ANA] && sheets[AHSP_SHEET_COMP]
      read_flat_book(sheets)
    elsif sheets[AHSP_SHEET_REPORT] && find_columns(sheets[AHSP_SHEET_REPORT], AHSP_SHEET_REPORT)
      read_report_book(sheets)
    else
      raise Error, AHSP_NOT_TEMPLATE
    end
  end

  def self.finish_book(meta, by_kode, base, notes)
    base_codes = base.to_h { |b| [b['kode'], true] }
    outside = by_kode.values.sum { |a| a['komponen'].count { |c| !base_codes.key?(c['kode']) } }
    warn = []
    warn << "#{notes[:dup]} baris Analisa dilewati karena kodenya kembar." if notes[:dup].to_i.positive?
    warn << "#{notes[:orphan]} baris Komponen dilewati: kode analisa tidak ada di sheet Analisa atau kode harga kosong." if notes[:orphan].to_i.positive?
    warn << "#{notes[:bad_koef]} baris Komponen dilewati: koefisien harus angka lebih dari 0." if notes[:bad_koef].to_i.positive?
    warn << "#{notes[:bad_base]} baris Harga Dasar dilewati: kode, nama, jenis (upah/bahan/alat) atau harga tidak valid." if notes[:bad_base].to_i.positive?
    if outside.positive?
      warn << "#{outside} komponen memakai kode harga yang tidak ada di sheet Harga Dasar; baru terhitung kalau file AHSP lain yang memuat kodenya ikut dicentang."
    end
    { 'data' => { 'meta' => meta, 'harga_dasar' => base, 'ahsp' => by_kode.values }, 'warn' => warn }
  end

  # Template datar: Analisa + Komponen + Harga Dasar
  def self.read_flat_book(sheets)
    ana_rows = sheets[AHSP_SHEET_ANA]
    comp_rows = sheets[AHSP_SHEET_COMP]
    ana_head, ana_cols = find_columns(ana_rows, AHSP_SHEET_ANA)
    comp_head, comp_cols = find_columns(comp_rows, AHSP_SHEET_COMP)
    raise Error, AHSP_NOT_TEMPLATE unless ana_cols && comp_cols

    notes = { dup: 0, orphan: 0, bad_koef: 0 }
    by_kode = {}
    ana_rows.drop(ana_head + 1).each do |row|
      kode = cell_text(row, ana_cols, :kode, 40)
      uraian = cell_text(row, ana_cols, :uraian, 240)
      next if kode.empty? || uraian.empty?

      if by_kode.key?(kode)
        notes[:dup] += 1
        next
      end
      item = { 'kode' => kode, 'divisi' => cell_text(row, ana_cols, :divisi, 120), 'kategori' => cell_text(row, ana_cols, :kategori, 120),
               'uraian' => uraian, 'satuan' => cell_text(row, ana_cols, :satuan, 16), 'komponen' => [] }
      catatan = cell_text(row, ana_cols, :catatan, 400)
      item['catatan'] = catatan unless catatan.empty?
      by_kode[kode] = item
    end

    comp_rows.drop(comp_head + 1).each do |row|
      ak = cell_text(row, comp_cols, :analisa, 40)
      hk = cell_text(row, comp_cols, :harga, 40)
      next if ak.empty? && hk.empty?

      koef = parse_number(row[comp_cols[:koef]])
      if ak.empty? || hk.empty? || !by_kode.key?(ak)
        notes[:orphan] += 1
      elsif koef.nil? || !koef.positive?
        notes[:bad_koef] += 1
      else
        by_kode[ak]['komponen'] << { 'kode' => hk, 'koef' => koef }
      end
    end

    base, notes[:bad_base] = sheets[AHSP_SHEET_BASE] ? read_base_sheet(sheets[AHSP_SHEET_BASE]) : [[], 0]
    finish_book({}, by_kode, base, notes)
  end

  # Laporan AHSP: baris analisa = Kode + Uraian terisi, kolom Koefisien kosong; baris komponen = Kode + Koefisien terisi.
  # Baris lain (judul, jumlah, overhead, harga satuan) tidak punya kode di kolom pertama sehingga dilewati.
  def self.read_report_book(sheets)
    rows = sheets[AHSP_SHEET_REPORT]
    head_at, cols = find_columns(rows, AHSP_SHEET_REPORT)
    price_rows = sheets[AHSP_SHEET_DHSP] || sheets[AHSP_SHEET_BASE]
    raise Error, 'File AHSP ini tidak punya sheet Harga Dasar (DHSP).' unless price_rows

    notes = { dup: 0, orphan: 0, bad_koef: 0 }
    meta = {}
    op = rows.first(head_at).filter_map { |r| r[cols[:koef]] if r[0].to_s.strip.downcase.start_with?('overhead') }.first
    meta['overhead_profit_persen'] = (op * 100).round(4) if op.is_a?(Numeric) && op.positive? && op <= 1

    by_kode = {}
    current = nil
    rows.drop(head_at + 1).each do |row|
      kode = cell_text(row, cols, :kode, 40)
      next if kode.empty?

      raw_koef = row[cols[:koef]]
      if raw_koef.nil? || raw_koef.to_s.strip.empty?
        uraian = cell_text(row, cols, :uraian, 240)
        next if uraian.empty?

        if by_kode.key?(kode)
          notes[:dup] += 1
          current = nil
          next
        end
        current = { 'kode' => kode, 'divisi' => cell_text(row, cols, :divisi, 120), 'kategori' => cell_text(row, cols, :kategori, 120),
                    'uraian' => uraian, 'satuan' => cell_text(row, cols, :satuan, 16), 'komponen' => [] }
        %i[keyakinan acuan catatan].each do |f|
          v = cell_text(row, cols, f, 400)
          current[f.to_s] = v unless v.empty?
        end
        by_kode[kode] = current
      elsif current.nil?
        notes[:orphan] += 1
      else
        koef = parse_number(raw_koef)
        if koef&.positive?
          current['komponen'] << { 'kode' => kode, 'koef' => koef }
        else
          notes[:bad_koef] += 1
        end
      end
    end
    base, notes[:bad_base] = read_base_sheet(price_rows)
    finish_book(meta, by_kode, base, notes)
  end

  # Isi file harga yang dipilih user (.xlsx atau .json) -> data bersih. Raise Error dengan pesan siap tampil.
  def self.read_price_file(path)
    raise Error, 'File tidak ditemukan.' unless File.file?(path)
    raise Error, 'File terlalu besar (maks 60 MB).' if File.size(path) > MAX_UNZIPPED

    if File.extname(path).downcase == '.json'
      text = File.read(path, encoding: 'UTF-8').sub(/\A﻿/, '')
      data = sanitize_prices(JSON.parse(text))
      raise Error, 'Bukan file daftar harga: tidak ada daftar "items".' unless data
    else
      data = { 'meta' => {}, 'items' => rows_to_items(read_xlsx(File.binread(path))) }
    end
    raise Error, 'Tidak ada baris harga yang valid (butuh nama dan harga angka).' if data['items'].empty?

    data
  rescue JSON::ParserError
    raise Error, 'File bukan JSON yang valid.'
  end
end
