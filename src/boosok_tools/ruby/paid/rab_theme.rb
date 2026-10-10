require 'json'

# Tema tampilan dokumen RAB (Excel dan PDF): warna, huruf, tebal. Murni data, tanpa SketchUp.
#   - Tema bawaan (id "app/<nama>") dan tema milik user (id "user/<nama>.json", disimpan di folder tema user).
#   - Tema bisa dibuat dari template Excel: ekspor template (tiap peran gaya = satu sel contoh), ubah warna/huruf sel itu di
#     Excel, lalu impor lagi. Yang dibaca hanya gaya sel contoh, jadi cukup pakai alat pewarna/huruf Excel biasa.
module BoosokTools::RabTheme
  DEFAULT_ID = 'app/biru'.freeze unless defined?(DEFAULT_ID)
  THEME_ID_RE = %r{\A(app/[a-z0-9-]{1,30}|user/[^/\\:*?"<>|]{1,120}\.json)\z} unless defined?(THEME_ID_RE)
  TEMPLATE_FORMAT = 'boosok-rab-tema'.freeze unless defined?(TEMPLATE_FORMAT)

  class Error < StandardError; end

  # Peran gaya (urutan = urutan baris di template). Tiap peran: label, bidang yang dipakai.
  ROLES = {
    'title' => { label: 'Judul dokumen', fields: %w[color size bold] },
    'muted' => { label: 'Keterangan kecil (proyek, tanggal, catatan)', fields: %w[color] },
    'text' => { label: 'Isi tabel (huruf dasar dan garis tabel)', fields: %w[color name size] },
    'head' => { label: 'Judul kolom tabel', fields: %w[fill color bold] },
    'band' => { label: 'Baris divisi dan sub total', fields: %w[fill color bold] },
    'total' => { label: 'Baris TOTAL', fields: %w[fill color bold] },
    'input' => { label: 'Sel yang boleh diubah (Excel)', fields: %w[color] },
    'grid' => { label: 'Garis tabel (warna garis tepi sel contoh)', fields: %w[border] }
  }.freeze unless defined?(ROLES)

  def self.make(nama, head, band, total, input: '0000ff', ink: '18181b', grid: 'bfbfbf', head_fg: 'ffffff', band_fg: nil, total_fg: nil)
    { 'nama' => nama, 'font' => 'Calibri', 'size' => 11.0,
      'roles' => {
        'title' => { 'color' => ink, 'size' => 14.0, 'bold' => true },
        'muted' => { 'color' => '71717a' },
        'text' => { 'color' => ink },
        'head' => { 'fill' => head, 'color' => head_fg, 'bold' => true },
        'band' => { 'fill' => band, 'color' => band_fg || ink, 'bold' => true },
        'total' => { 'fill' => total, 'color' => total_fg || ink, 'bold' => true },
        'input' => { 'color' => input },
        'grid' => { 'border' => grid }
      } }
  end

  BUILTIN = {
    'biru' => make('Biru (bawaan)', '1f3a5f', 'e8eef5', 'fff2cc'),
    'hijau' => make('Hijau', '1e5631', 'e3f1e6', 'fff3bf', input: '1d4ed8'),
    'marun' => make('Marun', '7b1e2b', 'f6e7e9', 'ffe8b3', input: '1d4ed8'),
    'abu' => make('Abu-abu', '3f4756', 'e9ecf1', 'fdf1c7'),
    'hitam-putih' => make('Hitam putih (hemat tinta)', 'd9d9d9', 'f2f2f2', 'e6e6e6', input: '000000', ink: '000000', head_fg: '000000', grid: '808080')
  }.freeze unless defined?(BUILTIN)

  def self.deep_dup(obj)
    Marshal.load(Marshal.dump(obj))
  end

  def self.default
    deep_dup(BUILTIN['biru'])
  end

  def self.builtin(id)
    t = BUILTIN[id.to_s.sub(%r{\Aapp/}, '')]
    t && deep_dup(t)
  end

  def self.hex(value, fallback = nil)
    h = value.to_s.strip.delete('#')
    h = h[-6, 6] if h.length == 8
    h.match?(/\A\h{6}\z/) ? h.downcase : fallback
  end

  # Tema acak (dari file / dialog) -> tema lengkap & valid; yang tidak valid memakai nilai `base`
  def self.normalize(raw, base = default)
    out = deep_dup(base)
    return out unless raw.is_a?(Hash)

    nama = raw['nama'].to_s.gsub(/[[:cntrl:]\s]+/, ' ').strip[0, 80]
    out['nama'] = nama unless nama.empty?
    font = raw['font'].to_s.gsub(/[[:cntrl:]<>&"]+/, '').strip[0, 40]
    out['font'] = font unless font.empty?
    size = Float(raw['size'], exception: false)
    out['size'] = size.clamp(7.0, 20.0) if size
    roles = raw['roles'].is_a?(Hash) ? raw['roles'] : {}
    ROLES.each_key do |role|
      src = roles[role]
      next unless src.is_a?(Hash)

      dst = out['roles'][role]
      %w[color fill border].each { |f| dst[f] = hex(src[f], dst[f]) if src.key?(f) && dst.key?(f) }
      if dst.key?('size') && src.key?('size') && (v = Float(src['size'], exception: false))
        dst['size'] = v.clamp(7.0, 28.0)
      end
      dst['bold'] = src['bold'] == true if dst.key?('bold') && src.key?('bold')
    end
    out
  end

  # Isi file tema user (JSON) -> tema, atau nil
  def self.from_json(text)
    raw = JSON.parse(text)
    raw.is_a?(Hash) && raw['format'] == TEMPLATE_FORMAT ? normalize(raw) : nil
  rescue JSON::ParserError
    nil
  end

  def self.to_json_data(theme)
    { 'format' => TEMPLATE_FORMAT, 'versi' => 1 }.merge(theme)
  end

  # Warna garis grafik (kurva S): warna judul kolom, kecuali terlalu terang untuk kertas putih -> warna teks
  def self.line_color(head, ink)
    r, g, b = head.scan(/../).map(&:hex)
    (((0.299 * r) + (0.587 * g) + (0.114 * b)) / 255.0) > 0.7 ? ink : head
  end

  # Warna untuk PDF
  def self.pdf_colors(theme)
    r = theme['roles']
    { ink: r['text']['color'], muted: r['muted']['color'], grid: r['grid']['border'],
      head_bg: r['head']['fill'], head_fg: r['head']['color'], band_bg: r['band']['fill'], band_fg: r['band']['color'],
      total_bg: r['total']['fill'], total_fg: r['total']['color'] }
  end

  # ── Template Excel: baca ──────────────────────────────────────────────────

  # Baris template: kolom A = id peran, kolom B = sel contoh yang gayanya diubah user.
  # Return tema (peran yang tidak ditemukan memakai `base`). Raise Error kalau ini bukan template tema.
  def self.from_template(bytes, base = default)
    io = BoosokTools::RabIo
    book = begin
      io.read_book(bytes)
    rescue io::Error => e
      raise Error, e.message
    end
    styles = io.read_styles(book[:files])
    found = {}
    book[:cells].each_value do |cols|
      id = cols[1]&.first
      sample = cols[2]
      next unless id.is_a?(String) && ROLES.key?(id.strip) && sample

      found[id.strip] = styles[sample[1]]
    end
    raise Error, 'Bukan template tema Boosok: baris peran gaya (title, head, band, …) tidak ditemukan.' if found.empty?

    roles = {}
    font = size = nil
    found.each do |role, st|
      f = st['font'] || {}
      case role
      when 'title' then roles[role] = { 'color' => f['color'], 'size' => f['size'], 'bold' => f['bold'] }
      when 'muted', 'input' then roles[role] = { 'color' => f['color'] }
      when 'text'
        roles[role] = { 'color' => f['color'] }
        font = f['name']
        size = f['size']
      when 'head', 'band', 'total' then roles[role] = { 'fill' => st['fill'], 'color' => f['color'], 'bold' => f['bold'] }
      when 'grid' then roles[role] = { 'border' => st['border'] }
      end
    end
    roles.each_value { |h| h.delete_if { |_k, v| v.nil? } }
    normalize({ 'font' => font, 'size' => size, 'roles' => roles }, base)
  end
end

file_loaded(__FILE__)
