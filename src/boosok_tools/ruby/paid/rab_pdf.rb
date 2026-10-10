require 'zlib'
require 'time'

# Laporan RAB sebagai PDF tanpa browser dan tanpa library luar.
#   1. layout : laporan -> halaman berisi elemen sederhana (teks / garis / kotak) dalam satuan point, A4. Rekap, RAB, dan kurva S landscape; harga & AHSP portrait (ukuran per halaman).
#               Hasil layout yang sama dipakai untuk pratinjau di dialog (SVG) dan untuk file PDF, jadi pratinjau = hasil.
#   2. to_pdf : elemen -> file PDF 1.4 (font standar Helvetica, tanpa embed, teks WinAnsi, isi halaman di-deflate).
# Lebar teks dihitung dari tabel lebar huruf Helvetica (AFM), jadi pembungkusan baris di pratinjau dan PDF identik.
module BoosokTools::RabPdf
  PAGE_W = 595.28 unless defined?(PAGE_W)
  PAGE_H = 841.89 unless defined?(PAGE_H)
  # Bagian yang dicetak landscape (tabel lebar / grafik); sisanya portrait
  LANDSCAPE_PARTS = %w[rekap rab kurva].freeze unless defined?(LANDSCAPE_PARTS)
  # Urutan bagian dokumen: rekapitulasi, RAB, daftar harga bahan (DHSP), analisa (AHSP), time schedule kurva S
  remove_const(:PARTS) if const_defined?(:PARTS, false) # muat ulang (hot reload) harus menimpa daftar lama, bukan mempertahankannya
  PARTS = %w[rekap rab harga ahsp kurva].freeze

  # Lebar huruf Helvetica / Helvetica-Bold (per 1000 em) untuk ASCII 32..126
  W_REG = [
    278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
    1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
    333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
    556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584
  ].freeze unless defined?(W_REG)
  W_BOLD = [
    278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278,
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611,
    975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778,
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556,
    333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611,
    611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584
  ].freeze unless defined?(W_BOLD)
  # Karakter di luar ASCII yang ada di WinAnsi: [reguler, tebal]
  W_EXTRA = {
    '·' => [278, 278], '–' => [556, 556], '—' => [1000, 1000], '±' => [584, 584], '²' => [333, 333], '³' => [333, 333],
    '°' => [400, 400], '×' => [584, 584], '½' => [834, 834], 'Ø' => [778, 778], 'ø' => [611, 611], '•' => [350, 350],
    '…' => [1000, 1000], '‘' => [222, 278], '’' => [222, 278], '“' => [333, 500], '”' => [333, 500]
  }.freeze unless defined?(W_EXTRA)

  TRANSLIT = {
    '≥' => '>=', '≤' => '<=', '∅' => 'Ø', 'φ' => 'Ø', 'ϕ' => 'Ø', 'ф' => 'Ø', 'Δ' => 'Delta ', 'µ' => 'u', 'μ' => 'u',
    '≈' => '~', '→' => '->', '←' => '<-', '⁄' => '/', " " => ' ', "\t" => ' ', '‐' => '-', '‑' => '-', '−' => '-'
  }.freeze unless defined?(TRANSLIT)

  # ── Teks ──────────────────────────────────────────────────────────────────

  # Ubah ke teks yang bisa ditampilkan font standar PDF (WinAnsi): huruf di luar itu diganti padanan / '?'
  def self.safe(text)
    s = text.to_s.dup.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    s = s.gsub(/[\r\n]+/, ' ')
    s = s.gsub(/[^\u0000-\u007f]/) do |ch|
      next ch if W_EXTRA.key?(ch)

      TRANSLIT[ch] || begin
        base = ch.unicode_normalize(:nfd).gsub(/[^\u0000-\u007f]/, '')
        base.empty? ? '?' : base
      rescue StandardError
        '?'
      end
    end
    s.gsub(/[\u0000-\u001f]/, ' ')
  end

  def self.char_width(ch, bold)
    code = ch.ord
    return (bold ? W_BOLD : W_REG)[code - 32] if code >= 32 && code <= 126

    extra = W_EXTRA[ch]
    extra ? extra[bold ? 1 : 0] : 556
  end

  # Lebar teks dalam point
  def self.text_width(text, font, size)
    bold = font == 'B'
    text.to_s.each_char.sum { |c| char_width(c, bold) } * size / 1000.0
  end

  # Bungkus teks jadi baris-baris selebar `width` (kata terlalu panjang dipotong per huruf)
  def self.wrap(text, font, size, width)
    lines = []
    safe(text).split(/ +/).reject(&:empty?).each do |word|
      cur = lines.last
      if cur && text_width("#{cur} #{word}", font, size) <= width
        lines[-1] = "#{cur} #{word}"
      elsif text_width(word, font, size) <= width
        lines << word
      else
        chunk = +''
        word.each_char do |c|
          if !chunk.empty? && text_width(chunk + c, font, size) > width
            lines << chunk
            chunk = +''
          end
          chunk << c
        end
        lines << chunk unless chunk.empty?
      end
    end
    lines.empty? ? [''] : lines
  end

  # ── Angka ─────────────────────────────────────────────────────────────────

  # 1234567.891 -> "1.234.568" (d = 0) atau "1.234.567,89" (d = 2)
  def self.num(value, digits = 0)
    s = format("%.#{digits}f", value.to_f.round(digits))
    int, frac = s.split('.')
    sign = int.start_with?('-') ? '-' : ''
    int = int.sub('-', '').reverse.scan(/\d{1,3}/).join('.').reverse
    out = sign + int
    digits.positive? ? "#{out},#{frac}" : out
  end

  SATUAN = %w[nol satu dua tiga empat lima enam tujuh delapan sembilan sepuluh sebelas].freeze unless defined?(SATUAN)

  def self.terbilang(n)
    n = n.to_i
    return 'minus ' + terbilang(-n) if n.negative?

    rest = ->(r) { r.positive? ? " #{terbilang(r)}" : '' }
    if n < 12 then SATUAN[n]
    elsif n < 20 then "#{terbilang(n - 10)} belas"
    elsif n < 100 then "#{terbilang(n / 10)} puluh#{rest.call(n % 10)}"
    elsif n < 200 then "seratus#{rest.call(n - 100)}"
    elsif n < 1000 then "#{terbilang(n / 100)} ratus#{rest.call(n % 100)}"
    elsif n < 2000 then "seribu#{rest.call(n - 1000)}"
    elsif n < 1_000_000 then "#{terbilang(n / 1000)} ribu#{rest.call(n % 1000)}"
    elsif n < 1_000_000_000 then "#{terbilang(n / 1_000_000)} juta#{rest.call(n % 1_000_000)}"
    elsif n < 1_000_000_000_000 then "#{terbilang(n / 1_000_000_000)} miliar#{rest.call(n % 1_000_000_000)}"
    else "#{terbilang(n / 1_000_000_000_000)} triliun#{rest.call(n % 1_000_000_000_000)}"
    end
  end

  # ── Pembangun halaman ─────────────────────────────────────────────────────

  class Builder
    attr_reader :pages, :dims, :ml, :mr, :mt, :mb, :c
    attr_accessor :y

    # colors: { ink:, muted:, grid:, head_bg:, head_fg:, band_bg:, band_fg:, total_bg:, total_fg: } (hex 6 digit) dari RabTheme.pdf_colors
    def initialize(colors)
      @c = colors
      @ml = 40.0
      @mr = 40.0
      @mt = 44.0
      @mb = 52.0
      @pages = []
      @dims = []
      new_page(false)
    end

    # Ukuran halaman terakhir (point): portrait atau landscape
    def page_w
      @dims.last[0]
    end

    def page_h
      @dims.last[1]
    end

    def width
      page_w - @ml - @mr
    end

    def bottom
      page_h - @mb
    end

    def space_left
      bottom - @y
    end

    # landscape nil = ikut orientasi halaman sebelumnya (tabel yang menyambung ke halaman berikutnya)
    def new_page(landscape = nil)
      landscape = page_w > page_h if landscape.nil?
      @pages << []
      @dims << (landscape ? [PAGE_H, PAGE_W] : [PAGE_W, PAGE_H])
      @y = @mt
    end

    # Awal bagian dokumen: halaman baru dengan orientasinya (halaman terakhir yang masih kosong dipakai ulang)
    def start_part(landscape)
      if @pages.last.empty?
        @dims[-1] = landscape ? [PAGE_H, PAGE_W] : [PAGE_W, PAGE_H]
        @y = @mt
      else
        new_page(landscape)
      end
    end

    def add(item)
      (@forced_page ? @pages[@forced_page] : @pages.last) << item
    end

    def page_index
      @pages.size - 1
    end

    # Semua gambar di dalam blok masuk ke halaman nomor `index` (bukan halaman terakhir)
    def on_page(index)
      old = @forced_page
      @forced_page = index
      yield
    ensure
      @forced_page = old
    end

    def text(x, baseline, str, font: 'R', size: 9, align: 'l', color: nil)
      s = BoosokTools::RabPdf.safe(str)
      return if s.empty?

      color ||= @c[:ink]
      add('t' => 'text', 'x' => x.round(2), 'y' => baseline.round(2), 's' => s, 'f' => font, 'z' => size, 'a' => align, 'c' => color)
    end

    def line(x1, y1, x2, y2, width: 0.5, color: nil)
      color ||= @c[:grid]
      add('t' => 'line', 'x1' => x1.round(2), 'y1' => y1.round(2), 'x2' => x2.round(2), 'y2' => y2.round(2), 'w' => width, 'c' => color)
    end

    def rect(x, y, w, h, fill: nil, stroke: nil, sw: 0.5)
      add('t' => 'rect', 'x' => x.round(2), 'y' => y.round(2), 'w' => w.round(2), 'h' => h.round(2), 'fill' => fill, 'stroke' => stroke, 'sw' => sw)
    end

    # Tinggi baris tabel untuk sel-sel tertentu (tanpa menggambar)
    def row_height(cols, cells, size: 8.5, pad: 3.0)
      layout_cells(cols, cells, size, pad).map { |c| c[:h] }.max
    end

    # Gambar satu baris tabel. cells: [{ text:, align:, font:, color:, sub:, span: }]. Pindah halaman kalau tidak muat
    # (header_proc dipanggil di halaman baru supaya header tabel diulang). Return tinggi baris.
    def table_row(cols, cells, size: 8.5, pad: 3.0, fill: nil, header_proc: nil, grid: true)
      laid = layout_cells(cols, cells, size, pad)
      h = laid.map { |c| c[:h] }.max
      if h > space_left && @y > @mt + 1
        new_page
        header_proc&.call
      end
      top = @y
      rect(@ml, top, cols.sum, h, fill: fill) if fill
      laid.each do |c|
        rect(c[:x], top, c[:w], h, stroke: @c[:grid]) if grid
        ty = top + pad + (size * 0.82)
        c[:lines].each do |ln|
          tx = c[:align] == 'r' ? c[:x] + c[:w] - pad : (c[:align] == 'c' ? c[:x] + (c[:w] / 2.0) : c[:x] + pad)
          text(tx, ty, ln, font: c[:font], size: size, align: c[:align], color: c[:color])
          ty += size * 1.28
        end
        c[:sub_lines].each do |ln|
          tx = c[:align] == 'r' ? c[:x] + c[:w] - pad : c[:x] + pad
          text(tx, ty, ln, size: size - 1.5, align: c[:align], color: @c[:muted])
          ty += (size - 1.5) * 1.28
        end
      end
      @y += h
      h
    end

    private

    def layout_cells(cols, cells, size, pad)
      x = @ml
      idx = 0
      cells.map do |cell|
        span = cell[:span] || 1
        w = cols[idx, span].sum
        font = cell[:font] || 'R'
        lines = BoosokTools::RabPdf.wrap(cell[:text], font, size, w - (2 * pad))
        sub = cell[:sub] ? BoosokTools::RabPdf.wrap(cell[:sub], 'R', size - 1.5, w - (2 * pad)) : []
        h = (2 * pad) + (lines.size * size * 1.28) + (sub.size * (size - 1.5) * 1.28)
        out = { x: x, w: w, lines: lines, sub_lines: sub, font: font, align: cell[:align] || 'l', color: cell[:color] || @c[:ink], h: h }
        x += w
        idx += span
        out
      end
    end
  end

  # ── Susun laporan ─────────────────────────────────────────────────────────

  JENIS_LABEL = { 'upah' => 'TENAGA KERJA', 'bahan' => 'BAHAN', 'alat' => 'PERALATAN' }.freeze unless defined?(JENIS_LABEL)
  JENIS_HURUF = { 'upah' => 'A', 'bahan' => 'B', 'alat' => 'C' }.freeze unless defined?(JENIS_HURUF)

  # parts: subset dari PARTS (urutan tetap: rekap, rab, harga, ahsp, kurva). theme: hash dari RabTheme (nil = bawaan).
  # Return { 'w', 'h', 'pages' => [{ 'items' => [...] }] }
  def self.layout(report, database, state, project, parts = %w[rab], now = Time.now, theme = nil)
    parts = PARTS & Array(parts)
    parts = %w[rab] if parts.empty?
    colors = BoosokTools::RabTheme.pdf_colors(theme || BoosokTools::RabTheme.default)
    b = Builder.new(colors)
    parts.each do |part|
      b.start_part(LANDSCAPE_PARTS.include?(part))
      case part
      when 'rekap' then part_rekap(b, report, state, project, now)
      when 'rab' then part_rab(b, report, state, project, now)
      when 'harga' then part_harga(b, report, database, state)
      when 'ahsp' then part_ahsp(b, report, database, state)
      when 'kurva' then part_kurva(b, report, state, project, now)
      end
    end
    finish(b, project, now)
  end

  def self.finish(b, project, now)
    total = b.pages.size
    c = b.c
    b.pages.each_with_index do |items, i|
      pw, ph = b.dims[i]
      y = ph - b.mb + 14
      items << { 't' => 'line', 'x1' => b.ml, 'y1' => y - 10, 'x2' => pw - b.mr, 'y2' => y - 10, 'w' => 0.5, 'c' => c[:grid] }
      items << { 't' => 'text', 'x' => b.ml, 'y' => y, 's' => safe("RAB - #{project} - #{now.strftime('%d-%m-%Y')}"), 'f' => 'R', 'z' => 7.5, 'a' => 'l', 'c' => c[:muted] }
      items << { 't' => 'text', 'x' => pw - b.mr, 'y' => y, 's' => "Halaman #{i + 1} dari #{total}", 'f' => 'R', 'z' => 7.5, 'a' => 'r', 'c' => c[:muted] }
    end
    # w/h tingkat atas = ukuran terbesar (untuk zoom pratinjau); ukuran sebenarnya ada per halaman
    { 'w' => b.dims.map(&:first).max, 'h' => b.dims.map(&:last).max,
      'pages' => b.pages.each_with_index.map { |items, i| { 'w' => b.dims[i][0], 'h' => b.dims[i][1], 'items' => items } } }
  end

  # Baris data pekerjaan di atas tabel ("Label : isi"), diatur user di tab RAB (state['info']).
  # State lama tanpa 'info' -> satu baris "Proyek : <judul model>". date: false untuk dokumen yang tidak memuat tanggal.
  def self.info_lines(state, project, now, date: true)
    info = state['info']
    rows = info.nil? ? [['Proyek', project]] : info.map { |e| [e['label'], e['value']] }
    lines = rows.reject { |_l, v| v.to_s.strip.empty? }.map do |l, v|
      l.to_s.strip.empty? ? v.to_s.strip : "#{l.to_s.strip} : #{v.to_s.strip}"
    end
    lines << "Tanggal : #{now.strftime('%d-%m-%Y')}" if date && state['info_date'] != false
    lines
  end

  def self.heading(b, title, subtitle_lines = [])
    b.text(b.ml, b.y + 12, title, font: 'B', size: 14)
    b.y += 20
    subtitle_lines.each do |s|
      wrap(s, 'R', 9, b.width).each do |ln|
        b.text(b.ml, b.y + 9, ln, size: 9, color: b.c[:muted])
        b.y += 12
      end
    end
    b.y += 6
  end

  # Judul kolom: teks di atas warna judul tema
  def self.head_cells(b, specs)
    specs.map { |text, align| { text: text, align: align, font: 'B', color: b.c[:head_fg] } }
  end

  def self.band(b, text, opts = {})
    { text: text, font: 'B', color: b.c[:band_fg] }.merge(opts)
  end

  def self.total_cell(b, text, opts = {})
    { text: text, font: 'B', color: b.c[:total_fg] }.merge(opts)
  end

  def self.part_terbilang(b, total)
    words = terbilang(total.round)
    b.y += 8
    wrap("Terbilang : #{words.capitalize} rupiah", 'B', 9, b.width).each do |ln|
      b.new_page if b.space_left < 14
      b.text(b.ml, b.y + 9, ln, font: 'B', size: 9)
      b.y += 12
    end
  end

  # Nama divisi tanpa nomor depan ("02. Pekerjaan Struktur" -> "Pekerjaan Struktur"): di rekapitulasi kolom No sudah ada
  def self.plain_division(name)
    name.to_s.sub(/\A\s*[0-9A-Za-z]{1,3}\.\s+/, '')
  end

  # REKAPITULASI: jumlah per divisi, bobot, PPN, total
  def self.part_rekap(b, report, state, project, now)
    heading(b, 'REKAPITULASI RENCANA ANGGARAN BIAYA', info_lines(state, project, now))
    cols = [34.0, b.width - 34.0 - 150.0 - 100.0, 150.0, 100.0]
    head = -> { b.table_row(cols, head_cells(b, [['No', 'c'], ['Uraian Pekerjaan', 'l'], ['Jumlah Harga (Rp)', 'r'], ['Bobot (%)', 'r']]), fill: b.c[:head_bg]) }
    head.call
    if report['rows'].empty?
      b.table_row(cols, [{ text: 'Belum ada pekerjaan yang dipilih.', span: 4, color: b.c[:muted] }])
      return
    end
    subtotal = report['subtotal'].to_f
    report['divisi'].each_with_index do |d, i|
      pct = subtotal.positive? ? d['subtotal'] / subtotal * 100 : 0
      b.table_row(cols, [{ text: (i + 1).to_s, align: 'c' }, { text: plain_division(d['name']) }, { text: num(d['subtotal']), align: 'r' }, { text: num(pct, 2), align: 'r' }], header_proc: head)
    end
    fill = b.c[:band_bg]
    b.table_row(cols, [band(b, 'JUMLAH', align: 'r', span: 2), band(b, num(subtotal), align: 'r'), band(b, '100,00', align: 'r')], fill: fill, header_proc: head)
    ppn_label = "PPN #{num(report['ppn_on'] ? report['ppn_pct'] : 0, 1)}%"
    b.table_row(cols, [band(b, ppn_label, align: 'r', span: 2), band(b, num(report['ppn']), align: 'r'), band(b, '', align: 'r')], fill: fill, header_proc: head)
    b.table_row(cols, [total_cell(b, 'TOTAL', align: 'r', span: 2), total_cell(b, num(report['total']), align: 'r'), total_cell(b, '', align: 'r')],
                fill: b.c[:total_bg], header_proc: head)
    part_terbilang(b, report['total'])
  end

  def self.part_rab(b, report, state, project, now)
    heading(b, 'RENCANA ANGGARAN BIAYA (RAB)', info_lines(state, project, now))
    cols = [30.0, b.width - 30.0 - 46.0 - 70.0 - 110.0 - 120.0, 46.0, 70.0, 110.0, 120.0]
    head = lambda do
      b.table_row(cols, head_cells(b, [['No', 'c'], ['Uraian Pekerjaan', 'l'], ['Sat.', 'c'], ['Volume', 'r'], ['Harga Satuan (Rp)', 'r'], ['Jumlah (Rp)', 'r']]),
                  fill: b.c[:head_bg])
    end
    head.call
    if report['rows'].empty?
      b.table_row(cols, [{ text: 'Belum ada pekerjaan yang dipilih. Pilih pekerjaan (AHSP) untuk tiap tag di tab RAB.', span: 6, color: b.c[:muted] }])
      return
    end
    report['rows'].group_by { |r| r['divisi'] }.each do |divisi, rows|
      b.table_row(cols, [band(b, divisi.upcase, span: 6)], fill: b.c[:band_bg], header_proc: head)
      rows.each_with_index do |r, i|
        b.table_row(cols, [
          { text: (i + 1).to_s, align: 'c' }, { text: r['uraian'], sub: "#{r['label']} - #{r['kode']}" },
          { text: r['satuan'], align: 'c' }, { text: num(r['qty'], 2), align: 'r' },
          { text: num(r['hsp']), align: 'r' }, { text: num(r['jumlah']), align: 'r' }
        ], header_proc: head)
      end
      b.table_row(cols, [band(b, "Sub total #{divisi}", align: 'r', span: 5), band(b, num(rows.sum { |r| r['jumlah'] }), align: 'r')],
                  fill: b.c[:band_bg], header_proc: head)
    end
    ppn_label = "PPN #{num(report['ppn_on'] ? report['ppn_pct'] : 0, 1)}%"
    b.table_row(cols, [band(b, 'JUMLAH', align: 'r', span: 5), band(b, num(report['subtotal']), align: 'r')], fill: b.c[:band_bg], header_proc: head)
    b.table_row(cols, [band(b, ppn_label, align: 'r', span: 5), band(b, num(report['ppn']), align: 'r')], fill: b.c[:band_bg], header_proc: head)
    b.table_row(cols, [total_cell(b, 'TOTAL', align: 'r', span: 5), total_cell(b, num(report['total']), align: 'r')], fill: b.c[:total_bg], header_proc: head)
    part_terbilang(b, report['total'])
  end

  def self.part_ahsp(b, report, database, state)
    base_by_kode = database['harga_dasar'].to_h { |h| [h['kode'], h] }
    ahsp_by_kode = database['ahsp'].to_h { |a| [a['kode'], a] }
    prices = BoosokTools::Rab.effective_prices(database, state['prices'])
    heading(b, 'ANALISA HARGA SATUAN PEKERJAAN (AHSP)', ["Overhead & Profit : #{num(state['op'], 1)}%", database.dig('meta', 'sumber').to_s])
    cols = [24.0, 214.0, 48.0, 36.0, 54.0, 70.0, 69.0]
    head = lambda do
      b.table_row(cols, head_cells(b, [['No', 'c'], ['Uraian / Komponen', 'l'], ['Kode', 'l'], ['Sat.', 'c'], ['Koefisien', 'r'], ['Harga Satuan', 'r'], ['Jumlah', 'r']]),
                  size: 8, fill: b.c[:head_bg])
    end
    kodes = report['rows'].map { |r| r['kode'] }.uniq
    if kodes.empty?
      b.table_row(cols, [{ text: 'Belum ada pekerjaan yang dipilih.', span: 7, color: b.c[:muted] }], size: 8)
      return
    end
    head.call
    kodes.each do |kode|
      item = ahsp_by_kode[kode]
      next unless item

      bd = BoosokTools::Rab.ahsp_breakdown(item, base_by_kode, prices, state['op'])
      rows = analisa_rows(item, bd, state['op'], b.c)
      need = rows.sum { |cells, _opts| b.row_height(cols, cells, size: 8) }
      if need > b.space_left && need < b.page_h - b.mt - b.mb
        b.new_page
        head.call
      end
      rows.each { |cells, opts| b.table_row(cols, cells, size: 8, header_proc: head, **(opts || {}).slice(:fill)) }
      b.y += 6
    end
  end

  # Baris-baris satu analisa: judul, kelompok upah/bahan/alat dengan subtotal, jumlah, overhead & profit, harga satuan
  def self.analisa_rows(item, bd, op_pct, colors)
    bandc = { color: colors[:band_fg] }
    totc = { color: colors[:total_fg] }
    rows = []
    rows << [[{ text: "#{item['kode']}  #{item['uraian']}  (per #{item['satuan']})", font: 'B', span: 7 }.merge(bandc)], { fill: colors[:band_bg] }]
    %w[upah bahan alat].each do |jenis|
      comps = bd['comps'].select { |c| c['jenis'] == jenis }
      next if comps.empty?

      rows << [[{ text: "#{JENIS_HURUF[jenis]}.  #{JENIS_LABEL[jenis]}", font: 'B', span: 7 }], nil]
      comps.each_with_index do |c, i|
        rows << [[{ text: (i + 1).to_s, align: 'c' }, { text: c['nama'] }, { text: c['kode'] }, { text: c['satuan'], align: 'c' },
                  { text: num(c['koef'], 4), align: 'r' }, { text: num(c['harga']), align: 'r' }, { text: num(c['jumlah']), align: 'r' }], nil]
      end
      rows << [[{ text: "Jumlah #{JENIS_LABEL[jenis].downcase}", font: 'B', align: 'r', span: 6 }, { text: num(comps.sum { |c| c['jumlah'] }), font: 'B', align: 'r' }], nil]
    end
    rows << [[{ text: 'Jumlah harga upah, bahan dan peralatan', font: 'B', align: 'r', span: 6 }, { text: num(bd['jumlah']), font: 'B', align: 'r' }], nil]
    rows << [[{ text: "Overhead & profit #{num(op_pct, 1)}%", align: 'r', span: 6 }, { text: num(bd['op']), align: 'r' }], nil]
    rows << [[{ text: "Harga satuan pekerjaan per #{item['satuan']}", font: 'B', align: 'r', span: 6 }.merge(totc),
              { text: num(bd['hsp']), font: 'B', align: 'r' }.merge(totc)], { fill: colors[:total_bg] }]
    rows
  end

  def self.part_harga(b, report, database, state)
    ahsp_by_kode = database['ahsp'].to_h { |a| [a['kode'], a] }
    prices = BoosokTools::Rab.effective_prices(database, state['prices'])
    used = report['rows'].flat_map { |r| (ahsp_by_kode[r['kode']] || { 'komponen' => [] })['komponen'].map { |c| c['kode'] } }.uniq
    heading(b, 'DAFTAR HARGA BAHAN (DHSP)', ['Upah, bahan dan alat yang dipakai di pekerjaan di atas.'])
    cols = [58.0, 262.0, 46.0, 52.0, 97.0]
    head = lambda do
      b.table_row(cols, head_cells(b, [['Kode', 'l'], ['Nama', 'l'], ['Jenis', 'l'], ['Sat.', 'c'], ['Harga Satuan (Rp)', 'r']]), fill: b.c[:head_bg])
    end
    head.call
    rows = database['harga_dasar'].select { |h| used.include?(h['kode']) }
    if rows.empty?
      b.table_row(cols, [{ text: 'Belum ada komponen yang dipakai.', span: 5, color: b.c[:muted] }])
      return
    end
    rows.each do |h|
      price = prices[h['kode']].to_f
      b.table_row(cols, [
        { text: h['kode'] }, { text: h['nama'] }, { text: h['jenis'] }, { text: h['satuan'], align: 'c' },
        { text: price.positive? ? num(price) : 'belum diisi', align: 'r', color: price.positive? ? b.c[:ink] : 'b45309' }
      ], header_proc: head)
    end
  end

  # TIME SCHEDULE (KURVA S): (1) uraian + bobot di kiri, (2) grafik kurva S di kanan dan lebih lebar, (3) rencana per minggu di bawahnya
  KURVA_TABLE_W = 188.0 unless defined?(KURVA_TABLE_W)
  KURVA_GAP = 12.0 unless defined?(KURVA_GAP)

  def self.part_kurva(b, report, state, project, now)
    heading(b, 'TIME SCHEDULE (KURVA S)', info_lines(state, project, now) +
                                          ['Mulai & durasi awal disebar otomatis; ubah di file Excel (sheet Kurva S) kalau jadwal berbeda.'])
    sched = BoosokTools::RabSchedule.compute(report, state['weeks'])
    if sched[:items].empty?
      b.table_row([b.width], [{ text: 'Belum ada pekerjaan yang dipilih.', color: b.c[:muted] }])
      return
    end
    cols = [18.0, 120.0, 50.0]
    head = lambda do
      b.table_row(cols, head_cells(b, [['No', 'c'], ['Uraian Pekerjaan', 'l'], ['Bobot (%)', 'r']]), size: 8, fill: b.c[:head_bg])
    end
    chart_page = b.page_index
    top = b.y
    head.call
    no = 0
    sched[:items].group_by { |it| it[:row]['divisi'] }.each do |divisi, list|
      b.table_row(cols, [band(b, divisi.upcase, span: 3)], size: 8, fill: b.c[:band_bg], header_proc: head)
      list.each do |it|
        no += 1
        b.table_row(cols, [{ text: no.to_s, align: 'c' }, { text: it[:row]['uraian'] }, { text: num(it[:bobot] * 100, 2), align: 'r' }], size: 8, header_proc: head)
      end
    end
    same_page = b.page_index == chart_page
    table_bottom = same_page ? b.y : b.bottom
    # Grafik setinggi tabel di halaman pertamanya (tidak kurang dari 250 dan tidak lebih dari 340 pt), mulai sejajar judul kolom
    height = [[table_bottom - top, 250.0].max, 340.0].min
    x0 = b.ml + KURVA_TABLE_W + KURVA_GAP
    b.on_page(chart_page) { kurva_chart(b, sched, x0, top, b.page_w - b.mr - x0, height) }
    b.y = [b.y, top + height].max if same_page
    b.y += 12
    kurva_weekly(b, sched)
  end

  # Tabel kecil rencana per minggu & kumulatif (dipecah per WEEKS_PER_ROW minggu supaya muat)
  WEEKS_PER_ROW = 20 unless defined?(WEEKS_PER_ROW)

  def self.kurva_weekly(b, sched)
    w = sched[:weeks]
    sched[:weekly].each_slice(WEEKS_PER_ROW).with_index do |_chunk, idx|
      base = idx * WEEKS_PER_ROW
      label_w = 90.0
      cell_w = (b.width - label_w) / WEEKS_PER_ROW.to_f
      cols = [label_w] + Array.new(WEEKS_PER_ROW, cell_w)
      need = 3 * 16
      b.new_page if b.space_left < need
      labels = [{ text: 'Minggu ke-', font: 'B', color: b.c[:head_fg] }] + Array.new(WEEKS_PER_ROW) { |i| { text: base + i < w ? (base + i + 1).to_s : '', align: 'c', font: 'B', color: b.c[:head_fg] } }
      b.table_row(cols, labels, size: 8, fill: b.c[:head_bg])
      week = [{ text: 'Rencana (%)', font: 'B' }] + Array.new(WEEKS_PER_ROW) { |i| { text: base + i < w ? num(sched[:weekly][base + i] * 100, 1) : '', align: 'r' } }
      b.table_row(cols, week, size: 7.5)
      cum = [band(b, 'Kumulatif (%)')] + Array.new(WEEKS_PER_ROW) { |i| band(b, base + i < w ? num(sched[:cumulative][base + i] * 100, 1) : '', align: 'r') }
      b.table_row(cols, cum, size: 7.5, fill: b.c[:band_bg])
      b.y += 6
    end
  end

  # Grafik garis kurva S (kumulatif) di kotak x0, y0 selebar w setinggi h; digambar dengan garis & kotak biasa, jadi sama persis
  # di pratinjau dan PDF
  def self.kurva_chart(b, sched, x0, y0, w, h)
    c = b.c
    b.rect(x0, y0, w, h, stroke: c[:grid])
    b.text(x0 + 8, y0 + 14, 'KURVA S', font: 'B', size: 10)
    left = x0 + 34
    right = x0 + w - 12
    top = y0 + 26
    bottom = y0 + h - 34
    weeks = sched[:weeks]
    b.rect(left, top, right - left, bottom - top, stroke: c[:grid])
    (1..4).each do |i|
      y = bottom - ((bottom - top) * i / 5.0)
      b.line(left, y, right, y, width: 0.3, color: c[:grid])
    end
    (0..5).each { |i| b.text(left - 4, bottom - ((bottom - top) * i / 5.0) + 2.5, "#{i * 20}%", size: 7, align: 'r', color: c[:muted]) }
    step = (right - left) / weeks.to_f
    xs = (0...weeks).map { |i| left + (step * (i + 0.5)) }
    skip = [(weeks / 12.0).ceil, 1].max
    xs.each_with_index do |x, i|
      b.line(x, top, x, bottom, width: 0.25, color: c[:grid])
      b.text(x, bottom + 10, (i + 1).to_s, size: 7, align: 'c', color: c[:muted]) if (i % skip).zero?
    end
    b.text((left + right) / 2.0, bottom + 23, 'Minggu ke-', size: 7.5, align: 'c', color: c[:muted])
    pts = sched[:cumulative].each_with_index.map { |v, i| [xs[i], bottom - ((bottom - top) * v.clamp(0, 1))] }
    lc = BoosokTools::RabTheme.line_color(c[:head_bg], c[:ink])
    pts.each_cons(2) { |(x1, y1), (x2, y2)| b.line(x1, y1, x2, y2, width: 1.6, color: lc) }
    pts.each { |x, y| b.rect(x - 1.6, y - 1.6, 3.2, 3.2, fill: lc) }
  end

  # ── Penulis PDF ───────────────────────────────────────────────────────────

  def self.hex_rgb(hex)
    h = hex.to_s.delete('#')
    h = '000000' unless h =~ /\A\h{6}\z/
    h.scan(/../).map { |c| format('%.3f', c.hex / 255.0) }.join(' ')
  end

  def self.pdf_str(text)
    bytes = text.to_s.encode('Windows-1252', invalid: :replace, undef: :replace, replace: '?').force_encoding('BINARY')
    '(' + bytes.gsub(/[\\()]/n) { |m| "\\#{m}" } + ')'
  end

  def self.page_stream(page)
    fmt = ->(v) { format('%.2f', v) }
    page_h = page['h'] || PAGE_H
    out = ''.b
    page['items'].each do |it|
      case it['t']
      when 'rect'
        y = page_h - it['y'] - it['h']
        if it['fill']
          out << "#{hex_rgb(it['fill'])} rg #{fmt.call(it['x'])} #{fmt.call(y)} #{fmt.call(it['w'])} #{fmt.call(it['h'])} re f\n"
        end
        if it['stroke']
          out << "#{hex_rgb(it['stroke'])} RG #{it['sw']} w #{fmt.call(it['x'])} #{fmt.call(y)} #{fmt.call(it['w'])} #{fmt.call(it['h'])} re S\n"
        end
      when 'line'
        out << "#{hex_rgb(it['c'])} RG #{it['w']} w #{fmt.call(it['x1'])} #{fmt.call(page_h - it['y1'])} m #{fmt.call(it['x2'])} #{fmt.call(page_h - it['y2'])} l S\n"
      when 'text'
        width = text_width(it['s'], it['f'], it['z'])
        x = case it['a'] when 'r' then it['x'] - width when 'c' then it['x'] - (width / 2.0) else it['x'] end
        font = it['f'] == 'B' ? '/F2' : '/F1'
        out << "BT #{hex_rgb(it['c'])} rg #{font} #{it['z']} Tf #{fmt.call(x)} #{fmt.call(page_h - it['y'])} Td #{pdf_str(it['s'])} Tj ET\n"
      end
    end
    out.force_encoding('BINARY')
  end

  # layout (hasil .layout) -> isi file PDF (String biner)
  def self.to_pdf(layout, title = 'RAB')
    pages = layout['pages']
    objs = []
    objs[1] = '<< /Type /Catalog /Pages 2 0 R >>'
    kids = pages.each_index.map { |i| "#{6 + (i * 2)} 0 R" }.join(' ')
    objs[2] = "<< /Type /Pages /Kids [#{kids}] /Count #{pages.size} >>"
    objs[3] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'
    objs[4] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>'
    objs[5] = "<< /Title #{pdf_str(safe(title))} /Creator (Boosok Tools RAB) /Producer (Boosok Tools) >>"
    pages.each_with_index do |page, i|
      page_no = 6 + (i * 2)
      stream = Zlib::Deflate.deflate(page_stream(page))
      objs[page_no] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{page['w'] || PAGE_W} #{page['h'] || PAGE_H}] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents #{page_no + 1} 0 R >>"
      objs[page_no + 1] = [stream, "<< /Filter /FlateDecode /Length #{stream.bytesize} >>"]
    end

    out = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n".b
    offsets = []
    (1...objs.size).each do |n|
      offsets[n] = out.bytesize
      body = objs[n]
      if body.is_a?(Array)
        out << "#{n} 0 obj\n#{body[1]}\nstream\n".b << body[0] << "\nendstream\nendobj\n".b
      else
        out << "#{n} 0 obj\n#{body}\nendobj\n".b
      end
    end
    xref = out.bytesize
    out << "xref\n0 #{objs.size}\n0000000000 65535 f \n".b
    (1...objs.size).each { |n| out << format("%010d 00000 n \n", offsets[n]).b }
    out << "trailer\n<< /Size #{objs.size} /Root 1 0 R /Info 5 0 R >>\nstartxref\n#{xref}\n%%EOF\n".b
    out
  end
end

file_loaded(__FILE__)
