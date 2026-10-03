require 'sketchup'
require 'json'
Sketchup.require 'boosok_tools/ruby/titlebar'
Sketchup.require 'boosok_tools/ruby/paid/void' unless defined?(BoosokTools::Void)
Sketchup.require 'boosok_tools/ruby/locale' unless defined?(BoosokTools::Locale)

# Slice: potong group/component solid dengan garis yang ditarik di viewport.
# Garis (satu segmen, atau banyak segmen diakhiri Enter) dihitung di koordinat LAYAR lalu diubah jadi
# volume pemotong: prisma (proyeksi paralel) atau piramida dari posisi kamera (perspektif), sehingga
# potongannya persis mengikuti garis yang terlihat di layar.
#   - Hasil "split"  : 2 group terpisah (sisi kiri & kanan garis)
#   - Hasil "keep"   : 1 group, satu sisi dibuang; Tab mengganti sisi yang dibuang
module BoosokTools::Slice
  DEFAULTS = { 'line' => 'single', 'result' => 'split' }.freeze unless defined?(DEFAULTS)
  MIN_PX = 4.0 unless defined?(MIN_PX) # jarak minimum antar titik (px layar)

  def self.release_dialog
    @dialog = nil
  end

  def self.run
    Sketchup.require 'boosok_tools/hub' unless defined?(BoosokTools::Hub)
    BoosokTools::Hub.open_or_show('slice')
  end

  # ── Mode kamera ───────────────────────────────────────────────────────────

  # Slice butuh proyeksi paralel (garis di layar = bidang potong yang sama di seluruh kedalaman). Kalau user
  # sedang di perspektif, dipaksa paralel selama dialog Slice terbuka lalu dikembalikan saat keluar.
  def self.enter
    model = Sketchup.active_model
    return unless model

    view = model.active_view
    return unless view.camera.perspective?

    @forced_parallel = true
    set_perspective(view, false)
  end

  def self.leave
    return unless @forced_parallel

    @forced_parallel = false
    model = Sketchup.active_model
    set_perspective(model.active_view, true) if model && model.valid?
  end

  def self.set_perspective(view, on)
    cam = view.camera
    cam.perspective = on
    view.invalidate
  rescue StandardError => e
    puts "[Boosok Slice] set_perspective: #{e.message}"
  end

  # ── Pengaturan ────────────────────────────────────────────────────────────

  def self.options
    {
      'line' => Sketchup.read_default('BoosokTools', 'slice_line', DEFAULTS['line']).to_s,
      'result' => Sketchup.read_default('BoosokTools', 'slice_result', DEFAULTS['result']).to_s
    }
  end

  def self.save_options(opts)
    line = opts['line'] == 'multi' ? 'multi' : 'single'
    result = opts['result'] == 'keep' ? 'keep' : 'split'
    Sketchup.write_default('BoosokTools', 'slice_line', line)
    Sketchup.write_default('BoosokTools', 'slice_result', result)
    { 'line' => line, 'result' => result }
  end

  # ── Geometri layar ────────────────────────────────────────────────────────

  # Normal "kiri jalan" di layar (sumbu y ke bawah)
  def self.left_normal(dx, dy)
    len = Math.hypot(dx, dy)
    return [0.0, 0.0] if len < 1e-9

    [dy / len, -dx / len]
  end

  def self.dedupe(path)
    path.each_with_object([]) do |p, out|
      out << p if out.empty? || Math.hypot(p[0] - out.last[0], p[1] - out.last[1]) >= MIN_PX
    end
  end

  def self.segments_cross?(a, b, c, d)
    orient = ->(p, q, r) { ((q[0] - p[0]) * (r[1] - p[1])) - ((q[1] - p[1]) * (r[0] - p[0])) }
    o1 = orient.call(a, b, c)
    o2 = orient.call(a, b, d)
    o3 = orient.call(c, d, a)
    o4 = orient.call(c, d, b)
    (o1 * o2).negative? && (o3 * o4).negative?
  end

  def self.simple_polygon?(poly)
    n = poly.size
    n.times do |i|
      a = poly[i]
      b = poly[(i + 1) % n]
      (i + 2...n).each do |j|
        next if i.zero? && j == n - 1 # sisi pertama & terakhir bersebelahan

        c = poly[j]
        d = poly[(j + 1) % n]
        return false if segments_cross?(a, b, c, d)
      end
    end
    true
  end

  # Titik keluar sinar (pt + t*dir, t>0) dari bingkai [minx, miny, maxx, maxy]
  def self.ray_to_frame(pt, dir, frame)
    minx, miny, maxx, maxy = frame
    tmax = Float::INFINITY
    tmax = [tmax, (maxx - pt[0]) / dir[0]].min if dir[0] > 1e-12
    tmax = [tmax, (minx - pt[0]) / dir[0]].min if dir[0] < -1e-12
    tmax = [tmax, (maxy - pt[1]) / dir[1]].min if dir[1] > 1e-12
    tmax = [tmax, (miny - pt[1]) / dir[1]].min if dir[1] < -1e-12
    [pt[0] + (dir[0] * tmax), pt[1] + (dir[1] * tmax)]
  end

  # Posisi titik di keliling bingkai, searah jarum jam dari pojok kiri atas (layar: y ke bawah)
  def self.perimeter_pos(pt, frame)
    minx, miny, maxx, maxy = frame
    w = maxx - minx
    h = maxy - miny
    eps = 1e-6 * [w, h].max
    if (pt[1] - miny).abs < eps then pt[0] - minx
    elsif (pt[0] - maxx).abs < eps then w + (pt[1] - miny)
    elsif (pt[1] - maxy).abs < eps then w + h + (maxx - pt[0])
    else (2 * w) + h + (maxy - pt[1])
    end
  end

  def self.frame_corners(frame)
    minx, miny, maxx, maxy = frame
    w = maxx - minx
    h = maxy - miny
    [[0.0, [minx, miny]], [w, [maxx, miny]], [w + h, [maxx, maxy]], [(2 * w) + h, [minx, maxy]]]
  end

  # Pojok bingkai yang dilewati saat berjalan dari posisi keliling a ke b (cw = searah jarum jam)
  def self.corners_between(frame, from_pos, to_pos, clockwise)
    total = 2 * ((frame[2] - frame[0]) + (frame[3] - frame[1]))
    span = clockwise ? (to_pos - from_pos) % total : (from_pos - to_pos) % total
    list = frame_corners(frame).map do |pos, pt|
      dist = clockwise ? (pos - from_pos) % total : (from_pos - pos) % total
      [dist, pt]
    end
    list.select { |dist, _| dist.positive? && dist < span }.sort_by(&:first).map(&:last)
  end

  def self.point_in_polygon?(pt, poly)
    inside = false
    j = poly.size - 1
    poly.each_with_index do |pi, i|
      pj = poly[j]
      if ((pi[1] > pt[1]) != (pj[1] > pt[1])) &&
         (pt[0] < ((pj[0] - pi[0]) * (pt[1] - pi[1]) / (pj[1] - pi[1])) + pi[0])
        inside = !inside
      end
      j = i
    end
    inside
  end

  # Poligon (koordinat layar) untuk sisi yang dibuang. Garis diperpanjang di kedua ujung sampai bingkai besar
  # (jauh di luar layar), lalu poligon ditutup menyusuri bingkai ke arah yang melingkupi sisi `side`
  # (+1 = kiri arah garis, -1 = kanan). Bentuk garis apa pun (U, zig-zag, ...) tetap valid selama garisnya
  # sendiri tidak berpotongan.
  def self.region_polygon(path, side, margin, center)
    frame = [center[0] - margin, center[1] - margin, center[0] + margin, center[1] + margin]
    d0 = [path[0][0] - path[1][0], path[0][1] - path[1][1]]       # arah keluar dari ujung awal
    dn = [path[-1][0] - path[-2][0], path[-1][1] - path[-2][1]]   # arah keluar dari ujung akhir
    d0 = d0.map { |v| v / Math.hypot(*d0) }
    dn = dn.map { |v| v / Math.hypot(*dn) }
    hit_start = ray_to_frame(path[0], d0, frame)
    hit_end = ray_to_frame(path[-1], dn, frame)
    pos_start = perimeter_pos(hit_start, frame)
    pos_end = perimeter_pos(hit_end, frame)

    # Titik uji tepat di sisi `side` dari segmen pertama: calon poligon yang memuatnya adalah yang benar
    mid = [(path[0][0] + path[1][0]) / 2.0, (path[0][1] + path[1][1]) / 2.0]
    nrm = left_normal(path[1][0] - path[0][0], path[1][1] - path[0][1])
    probe = [mid[0] + (side * nrm[0] * 2.0), mid[1] + (side * nrm[1] * 2.0)]

    [true, false].each do |clockwise|
      poly = [hit_start] + path + [hit_end] + corners_between(frame, pos_end, pos_start, clockwise)
      return poly if point_in_polygon?(probe, poly)
    end
    [hit_start] + path + [hit_end]
  end

  # ── Volume pemotong ───────────────────────────────────────────────────────

  # Titik-titik (koordinat DUNIA) pembentuk volume pemotong untuk poligon layar `poly`:
  #   perspektif → piramida dari posisi kamera (apex + alas di kejauhan)
  #   paralel    → prisma (alas dekat + alas jauh)
  # Dibuat sekali, lalu dibangun di konteks mana pun (build_cutter) dengan transformasi konteks itu.
  def self.cutter_spec(model, view, poly)
    cam = view.camera
    dir = cam.direction.normalize
    bounds = model.bounds
    center = bounds.center
    radius = [bounds.diagonal, 100.0].max

    if cam.perspective?
      eye = cam.eye
      far = ((center - eye).dot(dir)) + (radius * 2)
      far = radius if far < 1
      base = poly.map do |x, y|
        vec = view.pickray(x, y)[1].normalize
        eye.offset(vec, far / vec.dot(dir))
      end
      { persp: true, apex: eye, base: base }
    else
      rays = poly.map { |x, y| view.pickray(x, y)[0] }
      {
        persp: false,
        near: rays.map { |o| o.offset(dir, ((center - o).dot(dir)) - radius) },
        far: rays.map { |o| o.offset(dir, ((center - o).dot(dir)) + radius) }
      }
    end
  end

  # Bangun group solid pemotong di `entities`; `ctx_tr` = transformasi koleksi itu ke dunia. Hasil: Group atau nil.
  def self.build_cutter(entities, spec, ctx_tr)
    inv = ctx_tr.inverse
    group = entities.add_group
    ents = group.entities
    if spec[:persp]
      apex = inv * spec[:apex]
      base = spec[:base].map { |pt| inv * pt }
      ents.add_face(base)
      base.each_with_index { |pt, i| ents.add_face(apex, pt, base[(i + 1) % base.size]) }
    else
      near = spec[:near].map { |pt| inv * pt }
      far = spec[:far].map { |pt| inv * pt }
      ents.add_face(near)
      ents.add_face(far)
      near.each_with_index do |pt, i|
        j = (i + 1) % near.size
        ents.add_face(pt, near[j], far[j], far[i])
      end
    end

    return group if BoosokTools::Void.solid?(group)

    group.erase!
    nil
  rescue StandardError => e
    puts "[Boosok Slice] build_cutter: #{e.class}: #{e.message}"
    group.erase! if group && group.valid?
    nil
  end

  # ── Operasi solid ─────────────────────────────────────────────────────────

  def self.solid_targets(model)
    entities = model.active_entities
    sel = model.selection.select { |e| BoosokTools::Void.container?(e) }
    list = sel.empty? ? entities.select { |e| BoosokTools::Void.container?(e) } : sel
    list.reject { |e| !e.valid? || e.hidden? || BoosokTools::Void.void?(e) || BoosokTools::Void.role(e) == 'source' }
  end

  # Sisi yang valid: hasil ada, volume > 0, dan tidak keluar dari bounding box target (pengaman arah operasi).
  def self.valid_piece?(piece, target_bounds, target_volume)
    return false unless piece && piece.valid?

    vol = BoosokTools::Void.volume_of(piece)
    return false if vol && vol <= target_volume * 1e-6

    b = piece.bounds
    BoosokTools::Void.inside?(b.min.to_a, b.max.to_a, target_bounds.min.to_a, target_bounds.max.to_a)
  end

  # Operasi solid memakai salinan target & pemotong. Kalau gagal (hasil nil) salinan itu tidak boleh tertinggal
  # di model (pemotongnya sangat besar: kelihatan sebagai garis/bidang raksasa).
  def self.solid_op(entities, target, cutter)
    t = BoosokTools::Void.duplicate(entities, target)
    c = BoosokTools::Void.duplicate(entities, cutter)
    result = yield(t, c)
    BoosokTools::Void.erase_if_valid(t) unless result.equal?(t)
    BoosokTools::Void.erase_if_valid(c) unless result.equal?(c)
    result
  rescue StandardError
    BoosokTools::Void.erase_if_valid(t)
    BoosokTools::Void.erase_if_valid(c)
    raise
  end

  # target ∩ cutter
  def self.part_inside(entities, target, cutter)
    solid_op(entities, target, cutter) { |t, c| t.intersect(c) }
  end

  # target - cutter  (Group#subtract: receiver.subtract(x) = x - receiver)
  def self.part_outside(entities, target, cutter)
    solid_op(entities, target, cutter) { |t, c| c.subtract(t) }
  end

  # Seluruh bounding box target berada di dalam (true) / di luar (false) area potong? (dites di koordinat layar)
  def self.box_side?(env, target, ctx_tr, inside)
    box = target.bounds
    pts = (0..7).map do |i|
      sp = env[:view].screen_coords(ctx_tr * box.corner(i))
      point_in_polygon?([sp.x, sp.y], env[:poly])
    end
    pts.all? { |v| v == inside }
  end

  def self.unchanged_volume?(vol, ref)
    vol && ref && (vol - ref).abs <= ref.abs * 1e-6
  end

  # Satu bagian dari target SOLID: bagian di dalam area potong (want_inside) atau di luarnya.
  # Hasil: [bagian atau nil, terpengaruh?, ok?]. nil yang sah (kosong) hanya diterima kalau bounding box target
  # memang seluruhnya di satu sisi; selain itu dianggap gagal supaya tidak ada yang terhapus diam-diam.
  def self.leaf_piece(env, entities, target, ctx_tr, want_inside)
    cutter = build_cutter(entities, env[:spec], ctx_tr)
    return [nil, false, false] unless cutter

    box = target.bounds
    tb = Geom::BoundingBox.new.add(box.min, box.max)
    tv = BoosokTools::Void.volume_of(target) || 1.0
    piece = want_inside ? part_inside(entities, target, cutter) : part_outside(entities, target, cutter)
    BoosokTools::Void.erase_if_valid(cutter)

    if valid_piece?(piece, tb, tv)
      affected = want_inside || !unchanged_volume?(BoosokTools::Void.volume_of(piece), tv)
      return [piece, affected, true]
    end

    BoosokTools::Void.erase_if_valid(piece)
    # Sisi "di dalam" kosong = solid tidak menyentuh area potong (sah). Sisi "di luar" kosong hanya sah kalau
    # bounding box target seluruhnya di dalam area; selain itu dianggap gagal supaya tidak ada yang hilang diam-diam.
    return [nil, false, true] if want_inside
    return [nil, true, true] if box_side?(env, target, ctx_tr, true)

    [nil, false, false]
  end

  # ── Geometri lepas (face/edge): dipotong seperti Intersect Faces + buang sisi yang tidak diinginkan ──

  # Tambahkan volume pemotong sementara (sebagai group di `ents`) lalu panggil intersect_with agar face/edge yang
  # menyilang terbelah di sepanjang permukaan pemotong. entities2 harus berupa SATU Entity; bentuk argumen dicoba
  # berurutan (group dengan recurse, group tanpa recurse, lalu face pemotong satu per satu) dan yang berhasil
  # menambah edge dipakai. Hasil percobaan dicatat di Ruby Console supaya mudah ditelusuri.
  def self.raw_cut(env, ents, ctx_tr)
    tmp = build_cutter(ents, env[:spec], ctx_tr)
    return false unless tmp

    ident = Geom::Transformation.new
    edges0 = ents.grep(Sketchup::Edge).size
    bounds0 = Geom::BoundingBox.new # kotak geometri asli, sebelum pemotong ditambahkan
    ents.grep(Sketchup::Edge).each { |e| bounds0.add(e.start.position, e.end.position) }
    attempts = [
      ['group, recurse', ->(e) { e.intersect_with(true, ident, e, ident, true, tmp) }],
      ['group', ->(e) { e.intersect_with(false, ident, e, ident, true, tmp) }],
      ['faces', ->(e) { tmp.entities.grep(Sketchup::Face).each { |f| e.intersect_with(false, ident, e, ident, true, f) } }]
    ]
    done = nil
    attempts.each do |name, call|
      call.call(ents)
      if ents.grep(Sketchup::Edge).size != edges0
        done = name
        break
      end
    rescue StandardError => e
      puts "[Boosok Slice] intersect_with (#{name}): #{e.class}: #{e.message}"
    end
    stray = remove_stray_edges(ents, bounds0)
    puts "[Boosok Slice] raw_cut: #{done || 'tidak ada edge baru'} (edge #{edges0} -> #{ents.grep(Sketchup::Edge).size}, edge liar dibuang: #{stray})"
    true
  rescue StandardError => e
    puts "[Boosok Slice] raw_cut: #{e.class}: #{e.message}"
    false
  ensure
    BoosokTools::Void.erase_if_valid(tmp)
  end

  # intersect_with(recurse) juga menyilangkan group pemotong dengan dirinya sendiri dan menaruh tepi pemotong
  # (raksasa) sebagai edge liar di `ents`. Edge hasil perpotongan yang sah selalu berada di dalam kotak geometri asli.
  def self.remove_stray_edges(ents, box)
    return 0 if box.empty?

    tol = [box.diagonal * 0.01, 0.01].max
    inside = lambda do |pt|
      (0..2).all? { |i| pt[i] >= box.min[i] - tol && pt[i] <= box.max[i] + tol }
    end
    stray = ents.grep(Sketchup::Edge).reject { |e| inside.call(e.start.position) && inside.call(e.end.position) }
    ents.erase_entities(stray) unless stray.empty?
    stray.size
  end

  def self.centroid(points)
    n = points.size.to_f
    Geom::Point3d.new(points.sum { |pt| pt.x } / n, points.sum { |pt| pt.y } / n, points.sum { |pt| pt.z } / n)
  end

  # Titik pusat entity untuk menentukan sisi (nil kalau tidak bisa ditentukan, mis. guide tak hingga)
  def self.center_of(ent)
    case ent
    when Sketchup::Face then centroid(ent.outer_loop.vertices.map(&:position))
    when Sketchup::Edge then Geom.linear_combination(0.5, ent.start.position, 0.5, ent.end.position)
    when Sketchup::ConstructionLine then nil
    else
      return ent.position if ent.respond_to?(:position)

      box = ent.respond_to?(:bounds) ? ent.bounds : nil
      box && !box.empty? ? box.center : nil
    end
  rescue StandardError
    nil
  end

  def self.loose_other?(ent)
    ent.is_a?(Sketchup::Drawingelement) && !ent.is_a?(Sketchup::Face) && !ent.is_a?(Sketchup::Edge) &&
      !BoosokTools::Void.container?(ent) && !ent.is_a?(Sketchup::ConstructionLine)
  end

  # Bagi face/edge lepas (dan entity lain seperti teks/titik bantu) menurut posisi terhadap area potong.
  # Hasil: [face_in, face_out, edge_in, edge_out, lain_in, lain_out]
  def self.raw_classify(env, ents, tr)
    inside = lambda do |pt|
      return false unless pt

      sp = env[:view].screen_coords(tr * pt)
      point_in_polygon?([sp.x, sp.y], env[:poly])
    end
    fin, fout = ents.grep(Sketchup::Face).partition { |f| inside.call(center_of(f)) }
    loose = ents.grep(Sketchup::Edge).select { |e| e.faces.empty? }
    lin, lout = loose.partition { |e| inside.call(center_of(e)) }
    oin, oout = ents.select { |e| loose_other?(e) }.partition { |e| inside.call(center_of(e)) }
    [fin, fout, lin, lout, oin, oout]
  end

  # Hapus face + edge yang jadi yatim karenanya, serta edge lepas dan entity lain yang ditunjuk
  def self.raw_remove(ents, faces, loose_edges, others = [])
    attached = ents.grep(Sketchup::Edge).reject { |e| e.faces.empty? }
    ents.erase_entities(faces.select(&:valid?)) unless faces.empty?
    extra = (loose_edges + others).select(&:valid?)
    ents.erase_entities(extra) unless extra.empty?
    orphans = attached.select { |e| e.valid? && e.faces.empty? }
    ents.erase_entities(orphans) unless orphans.empty?
  end

  def self.raw_geometry?(ents)
    ents.any? { |e| e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge) || loose_other?(e) }
  end

  def self.faces_or_edges?(ents)
    ents.any? { |e| e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge) }
  end

  # Potong geometri lepas di `ents` dan buang sisi yang tidak diinginkan. Hasil: [terpengaruh?, ok?]
  def self.raw_slice_entities(env, ents, tr, want_inside)
    return [false, true] unless raw_geometry?(ents)
    return [false, false] if faces_or_edges?(ents) && !raw_cut(env, ents, tr)

    manual = faces_or_edges?(ents) ? split_straddlers(env, ents, tr) : 0
    puts "[Boosok Slice] pembelah manual: #{manual} face dibelah" if manual.positive?
    fin, fout, lin, lout, oin, oout = raw_classify(env, ents, tr)
    affected = [fin, lin, oin].any?(&:any?)
    log_straddlers(env, ents, tr, fin.size, fout.size)
    want_inside ? raw_remove(ents, fout, lout, oout) : raw_remove(ents, fin, lin, oin)
    [affected, true]
  end

  # ── Pembelah manual: face yang melintas garis tetapi tidak terbelah oleh intersect_with ──

  def self.vertex_sides(env, face, tr)
    face.outer_loop.vertices.map do |v|
      sp = env[:view].screen_coords(tr * v.position)
      point_in_polygon?([sp.x, sp.y], env[:poly])
    end
  end

  # Bidang melalui segmen layar a-b (dunia): [titik, normal]. nil kalau degenerat.
  def self.patch_plane(view, a, b)
    cam = view.camera
    ra = view.pickray(a[0], a[1])
    rb = view.pickray(b[0], b[1])
    if cam.perspective?
      eye = cam.eye
      normal = ra[1].normalize.cross(rb[1].normalize)
      normal.length > 1e-9 ? [eye, normal] : nil
    else
      normal = cam.direction.cross(rb[0] - ra[0])
      normal.length > 1e-9 ? [ra[0], normal] : nil
    end
  end

  # Jarak titik layar ke segmen a-b dan parameter proyeksinya (0..1 = di dalam segmen)
  def self.seg_dist(pt, a, b)
    dx = b[0] - a[0]
    dy = b[1] - a[1]
    len2 = (dx * dx) + (dy * dy)
    return [Math.hypot(pt[0] - a[0], pt[1] - a[1]), 0.0] if len2 < 1e-12

    t = (((pt[0] - a[0]) * dx) + ((pt[1] - a[1]) * dy)) / len2
    cx = a[0] + (t * dx)
    cy = a[1] + (t * dy)
    [Math.hypot(pt[0] - cx, pt[1] - cy), t]
  end

  # Bagian-bagian garis perpotongan face dengan bidang (koordinat dunia): array [titik1, titik2]
  def self.face_plane_segments(face, tr, plane)
    origin = tr * face.outer_loop.vertices.first.position
    normal = face.normal.transform(tr).normalize
    line = Geom.intersect_plane_plane([origin, normal], plane)
    return [] unless line

    p0, dir = line
    dir = dir.normalize
    ux, vx = normal.axes[0], normal.axes[1]
    to2d = ->(pt) { [(pt - origin).dot(ux), (pt - origin).dot(vx)] }
    q0 = to2d.call(p0)
    d2 = [dir.dot(ux), dir.dot(vx)]
    ts = []
    face.loops.each do |lp|
      pts = lp.vertices.map { |v| tr * v.position }
      pts.each_with_index do |pa, i|
        pb = pts[(i + 1) % pts.size]
        a2 = to2d.call(pa)
        e2 = [to2d.call(pb)[0] - a2[0], to2d.call(pb)[1] - a2[1]]
        den = (d2[0] * e2[1]) - (d2[1] * e2[0])
        next if den.abs < 1e-12

        diff = [a2[0] - q0[0], a2[1] - q0[1]]
        sedge = ((diff[0] * d2[1]) - (diff[1] * d2[0])) / den
        next if sedge < -1e-9 || sedge > 1 + 1e-9

        ts << (((diff[0] * e2[1]) - (diff[1] * e2[0])) / den)
      end
    end
    ts = ts.sort.each_with_object([]) { |t, out| out << t if out.empty? || (t - out.last).abs > 1e-6 }
    ts.each_slice(2).select { |pair| pair.size == 2 }.map { |t1, t2| [p0.offset(dir, t1), p0.offset(dir, t2)] }
  rescue StandardError
    []
  end

  # Belah face `face` di sepanjang satu segmen potong (a-b, koordinat layar). Hasil: true kalau ada edge ditambahkan.
  def self.split_face_on_segment(env, ents, face, tr, inv, seg)
    plane = patch_plane(env[:view], seg[0], seg[1])
    return false unless plane

    added = false
    face_plane_segments(face, tr, plane).each do |w1, w2|
      mid = Geom.linear_combination(0.5, w1, 0.5, w2)
      ends = [w1, w2, mid].map do |pt|
        sp = env[:view].screen_coords(pt)
        seg_dist([sp.x, sp.y], seg[0], seg[1])
      end
      next unless ends.all? { |dist, t| dist < 2.0 && t > -0.001 && t < 1.001 }

      ents.add_line(inv * w1, inv * w2)
      added = true
    end
    added
  rescue StandardError => e
    puts "[Boosok Slice] split_face: #{e.class}: #{e.message}"
    false
  end

  # Belah face yang masih melintas garis (sudutnya di dua sisi). Diulang beberapa putaran karena tiap belahan
  # mengganti face. Hasil: jumlah face yang berhasil dibelah.
  def self.split_straddlers(env, ents, tr)
    path = env[:cut_path]
    return 0 unless path && path.size >= 2

    inv = tr.inverse
    done = 0
    6.times do
      todo = ents.grep(Sketchup::Face).select { |f| vertex_sides(env, f, tr).uniq.size > 1 }
      break if todo.empty?

      progressed = false
      todo.each do |f|
        next unless f.valid?

        path.each_cons(2) do |seg|
          next unless split_face_on_segment(env, ents, f, tr, inv, seg)

          progressed = true
          done += 1
          break
        end
      end
      break unless progressed
    end
    done
  end

  # Diagnosa: face yang titik-titik sudutnya berada di dua sisi garis tetapi tidak terbelah (utuh di satu sisi)
  def self.log_straddlers(env, ents, tr, n_in, n_out)
    count = 0
    ents.grep(Sketchup::Face).each do |f|
      sides = f.outer_loop.vertices.map do |v|
        sp = env[:view].screen_coords(tr * v.position)
        point_in_polygon?([sp.x, sp.y], env[:poly])
      end
      count += 1 if sides.uniq.size > 1
    end
    puts "[Boosok Slice] raw leaf: face=#{n_in + n_out} (in #{n_in}/out #{n_out}), face melintas tak terbelah=#{count}" if count.positive?
  rescue StandardError
    nil
  end

  # Satu bagian dari target yang geometrinya lepas (bukan solid / tanpa isi group): salinan yang dipotong
  # pada permukaan pemotong lalu sisi yang tidak diinginkan dibuang (tanpa tutup, seperti Intersect Faces).
  def self.raw_piece(env, entities, target, ctx_tr, want_inside)
    work = BoosokTools::Void.duplicate(entities, target)
    work.make_unique if work.is_a?(Sketchup::ComponentInstance)
    ents = BoosokTools::Void.entities_of(work)
    affected, ok = raw_slice_entities(env, ents, ctx_tr * work.transformation, want_inside)
    unless ok
      BoosokTools::Void.erase_if_valid(work)
      return [nil, false, false]
    end

    if ents.length.zero?
      BoosokTools::Void.erase_if_valid(work)
      return [nil, affected, true]
    end
    [work, affected, true]
  end

  # Geometri lepas di tingkat yang JUGA berisi group/component (biasanya sedikit: garis bantu, dsb): tidak
  # di-intersect (recurse akan ikut menyilangkan isi group dan menaruh edge liar di tingkat ini, dan
  # memindahkan geometri ke group sementara terbukti membuat SketchUp crash). Cukup dipilah per sisi menurut
  # titik pusatnya; yang di sisi yang tidak diinginkan dihapus.
  def self.raw_slice_loose(env, ents, tr, want_inside)
    return [false, true] unless raw_geometry?(ents)

    fin, fout, lin, lout, oin, oout = raw_classify(env, ents, tr)
    affected = [fin, lin, oin].any?(&:any?)
    want_inside ? raw_remove(ents, fout, lout, oout) : raw_remove(ents, fin, lin, oin)
    [affected, true]
  rescue StandardError => e
    puts "[Boosok Slice] raw_slice_loose: #{e.class}: #{e.message}"
    [false, false]
  end

  # Satu bagian dari target yang berisi group/component lain (mis. dynamic component): salinan dengan tiap isi
  # diganti bagian yang sesuai (rekursif); geometri lepas di tingkat ini ikut dipotong.
  def self.container_piece(env, entities, target, ctx_tr, want_inside)
    copy = BoosokTools::Void.duplicate(entities, target)
    copy.make_unique if copy.is_a?(Sketchup::ComponentInstance)
    inner = BoosokTools::Void.entities_of(copy)
    inner_tr = ctx_tr * copy.transformation
    affected = false

    inner.select { |e| BoosokTools::Void.container?(e) }.each do |kid|
      piece, aff, ok = side_copy(env, inner, kid, inner_tr, want_inside)
      unless ok
        BoosokTools::Void.erase_if_valid(copy)
        return [nil, false, false]
      end
      affected ||= aff
      if piece
        BoosokTools::Void.copy_properties(kid, piece)
        piece.hidden = kid.hidden? # duplicate/solid-op membuat hasil terlihat; kembalikan status asli
      end
      kid.erase!
    end

    sweep_wrong_side(env, inner, inner_tr, want_inside)
    aff_raw, ok = raw_slice_loose(env, inner, inner_tr, want_inside)
    unless ok
      BoosokTools::Void.erase_if_valid(copy)
      return [nil, false, false]
    end
    affected ||= aff_raw

    if inner.length.zero?
      BoosokTools::Void.erase_if_valid(copy)
      return [nil, affected, true]
    end
    [copy, affected, true]
  end

  # Pengaman akhir: group/component yang bounding box-nya seluruhnya di sisi yang tidak diinginkan dihapus
  def self.sweep_wrong_side(env, ents, tr, want_inside)
    stray = ents.select do |e|
      BoosokTools::Void.container?(e) && box_side?(env, e, tr, !want_inside)
    rescue StandardError
      false
    end
    return if stray.empty?

    puts "[Boosok Slice] sweep: #{stray.size} group/component sisa di sisi yang dibuang dihapus"
    ents.erase_entities(stray)
  end

  # Hitung sisa entity yang pusatnya masih di dalam area potong (untuk diagnosa mode keep)
  def self.audit_inside(env, ents, tr, tally)
    ents.each do |e|
      if BoosokTools::Void.container?(e)
        audit_inside(env, BoosokTools::Void.entities_of(e), tr * e.transformation, tally)
      else
        pt = center_of(e)
        next unless pt

        sp = env[:view].screen_coords(tr * pt)
        tally[e.class.name.split('::').last] += 1 if point_in_polygon?([sp.x, sp.y], env[:poly])
      end
    end
  end

  # Solid → operasi solid (ada tutup di bidang potong). Gagal / bukan solid → potong sebagai geometri lepas.
  def self.side_copy(env, entities, target, ctx_tr, want_inside)
    if BoosokTools::Void.solid?(target)
      res = leaf_piece(env, entities, target, ctx_tr, want_inside)
      return res if res[2]

      raw_piece(env, entities, target, ctx_tr, want_inside)
    elsif BoosokTools::Void.nested(target).empty?
      raw_piece(env, entities, target, ctx_tr, want_inside)
    else
      container_piece(env, entities, target, ctx_tr, want_inside)
    end
  end

  # Potong satu target tingkat atas. Hasil: array bagian (kosong kalau tidak terpotong / gagal).
  def self.slice_target(env, entities, target, ctx_tr, result_mode, stats)
    want = result_mode == 'split' ? [false, true] : [false]
    results = want.map { |inside| side_copy(env, entities, target, ctx_tr, inside) }
    pieces = results.map(&:first).compact

    if results.any? { |r| !r[2] }
      pieces.each { |pc| BoosokTools::Void.erase_if_valid(pc) }
      stats[:failed] += 1
      return []
    end

    unless results.any? { |r| r[1] } # tidak ada isi yang terkena area potong
      pieces.each { |pc| BoosokTools::Void.erase_if_valid(pc) }
      stats[:notcut] += 1
      return []
    end

    pieces.each { |pc| BoosokTools::Void.copy_properties(target, pc) }
    target.erase!
    stats[:cut] += 1
    pieces
  end

  # Jalankan slice untuk garis `world_path` (titik di koordinat dunia: menempel ke model, ikut saat orbit);
  # diproyeksikan ke layar menurut kamera SAAT INI untuk membentuk bidang potong. Hasil: stats atau string error.
  def self.perform(view, world_path, side, result_mode)
    model = Sketchup.active_model
    path = dedupe(world_path.map { |pt| sp = view.screen_coords(pt); [sp.x, sp.y] })
    return 'Garis terlalu pendek.' if path.size < 2

    margin = [view.vpwidth, view.vpheight].max * 20.0
    poly = region_polygon(path, side, margin, [view.vpwidth / 2.0, view.vpheight / 2.0])
    return 'Garis tidak boleh saling berpotongan.' unless simple_polygon?(poly)

    targets = solid_targets(model)
    return 'Tidak ada group/component untuk dipotong.' if targets.empty?

    env = { view: view, poly: poly, spec: cutter_spec(model, view, poly), cut_path: poly[0..path.size + 1] }
    ctx_tr = model.edit_transform
    stats = { cut: 0, skipped: 0, notcut: 0, failed: 0, pieces: 0 }
    model.start_operation('Slice', true)
    begin
      pieces = []
      targets.each do |t|
        pieces.concat(slice_target(env, model.active_entities, t, ctx_tr, result_mode, stats))
      rescue StandardError => e
        puts "[Boosok Slice] #{e.class}: #{e.message}"
        stats[:failed] += 1
      end
      stats[:pieces] = pieces.size
      if result_mode == 'keep'
        tally = Hash.new(0)
        pieces.each { |pc| audit_inside(env, BoosokTools::Void.entities_of(pc), ctx_tr * pc.transformation, tally) if pc.valid? }
        puts "[Boosok Slice] sisa di area buang (pusat entity): #{tally.inspect}" unless tally.empty?
      end
      model.selection.clear
      model.selection.add(pieces.select(&:valid?))
      model.commit_operation
    rescue StandardError => e
      model.abort_operation
      return "Gagal: #{e.message}"
    end
    stats
  end

  # ── HUD di viewport (gaya subtitle Select Tool: judul + keterangan tombol, di tengah bawah) ──

  def self.loc(key, fallback)
    defined?(BoosokTools::Locale) ? BoosokTools::Locale.t(key, fallback) : fallback
  end

  HUD_SEP = '   |   '.freeze unless defined?(HUD_SEP)

  # Lebar teks sebenarnya (px) lewat View#text_bounds; perkiraan per karakter kalau tidak tersedia
  def self.hud_width(view, text, size, bold)
    @hud_widths ||= {}
    @hud_widths[[text, size, bold]] ||= begin
      view.text_bounds(Geom::Point3d.new(0, 0, 0), text, font: 'Segoe UI', size: size, bold: bold).width
    rescue StandardError
      text.length * size * (bold ? 0.62 : 0.56)
    end
  end

  def self.hud_text(view, y, text, size, bold, color)
    return if text.nil? || text.empty?

    x = (view.vpwidth - hud_width(view, text, size, bold)) / 2.0
    view.draw_text(Geom::Point3d.new(x, y, 0), text, color: color, font: 'Segoe UI', size: size, bold: bold)
  end

  # Baris berupa array bagian: digabung dengan pemisah kalau muat di viewport, kalau tidak tiap bagian satu baris
  def self.hud_rows(view, lines, size)
    max = view.vpwidth - 24
    lines.flat_map do |line|
      next [line] unless line.is_a?(Array)

      joined = line.join(HUD_SEP)
      hud_width(view, joined, size, false) <= max ? [joined] : line
    end.reject { |t| t.nil? || t.empty? }
  end

  # Subtitle di tengah bawah viewport (gaya Select Tool): judul tebal + baris keterangan. Lebih besar dari
  # sebelumnya, rata tengah menurut lebar teks sebenarnya, dan bertumpu di bawah supaya jumlah baris bebas.
  def self.draw_hud(view, title, lines)
    title_size = 14
    first_size = 12
    sub_size = 11
    rows = hud_rows(view, lines, sub_size)
    height = 24 + (rows.size * 20)
    y = view.vpheight - 22 - height
    hud_text(view, y, title, title_size, true, Sketchup::Color.new(24, 24, 27))
    rows.each_with_index do |text, i|
      color = i.zero? ? Sketchup::Color.new(60, 60, 66) : Sketchup::Color.new(105, 105, 115)
      hud_text(view, y + 26 + (i * 20), text, i.zero? ? first_size : sub_size, false, color)
    end
  rescue StandardError
    nil
  end

  # ── Tool ──────────────────────────────────────────────────────────────────

  class SliceTool
    def initialize(opts)
      @opts = opts
      @side = 1 # sisi yang dibuang pada mode keep (+1 kiri, -1 kanan)
      @ip = Sketchup::InputPoint.new
      reset
    end

    def options=(opts)
      @opts = opts
      update_status
    end

    def reset
      @pts = [] # titik garis di koordinat DUNIA (menempel ke model)
      @mouse = nil
    end

    def activate
      BoosokTools::Slice.slice_active = true
      reset
      update_status
    end

    def deactivate(view)
      BoosokTools::Slice.slice_active = false
      view.invalidate
    end

    def resume(view)
      update_status
      view.invalidate
    end

    def suspend(view)
      view.invalidate
    end

    # Gambar memakai koordinat layar yang diproyeksikan ulang tiap frame, jadi cukup bounds model
    def getExtents
      Sketchup.active_model.bounds
    end

    # Mode banyak garis: Esc (reason 0) hanya mundur satu titik; tanpa titik lagi tidak ada yang berubah.
    # Mode satu garis (atau undo/ganti tool): batalkan garis yang sedang ditarik.
    def onCancel(reason, view)
      if multi? && reason.zero? && @pts.any?
        @pts.pop
      else
        reset
      end
      update_status
      view.invalidate
    end

    def multi?
      @opts['line'] == 'multi'
    end

    def keep?
      @opts['result'] == 'keep'
    end

    def update_status
      Sketchup.status_text = 'Slice'
    end

    def screen_xy(view, pt)
      sp = view.screen_coords(pt)
      [sp.x, sp.y]
    end

    # Titik pada sinar piksel (x, y) yang kedalamannya sama dengan titik acuan `ref`
    def unproject(view, x, y, ref)
      origin, vec = view.pickray(x, y)
      dir = view.camera.direction
      origin.offset(vec, (ref - origin).dot(dir) / vec.dot(dir))
    end

    # Titik dunia dari inferensi (snap ke model). Saat Shift ditahan dan sudah ada titik sebelumnya, titik snap
    # diproyeksikan ke arah kelipatan 45° (di layar) dari titik sebelumnya: garis lurus, tetap menempel ke snap.
    def current_point(view)
      pos = Sketchup.active_model.edit_transform * @ip.position # InputPoint memakai koordinat konteks edit aktif
      return pos unless @shift && @pts.any?

      base = screen_xy(view, @pts.last)
      pt = screen_xy(view, pos)
      dx = pt[0] - base[0]
      dy = pt[1] - base[1]
      return pos if Math.hypot(dx, dy) < 1.0

      step = Math::PI / 4
      ang = (Math.atan2(dy, dx) / step).round * step
      ux = Math.cos(ang)
      uy = Math.sin(ang)
      len = (dx * ux) + (dy * uy)
      unproject(view, base[0] + (ux * len), base[1] + (uy * len), pos)
    end

    def refresh_mouse(view)
      return unless @last_xy

      @ip.pick(view, *@last_xy)
      @mouse = current_point(view)
      view.invalidate
    end

    def onMouseMove(flags, x, y, view)
      @last_xy = [x, y]
      @shift = (flags & CONSTRAIN_MODIFIER_MASK) != 0
      @ip.pick(view, x, y)
      @mouse = current_point(view)
      view.tooltip = @ip.tooltip
      view.invalidate
    end

    def onKeyUp(key, _repeat, _flags, view)
      return unless key == CONSTRAIN_MODIFIER_KEY

      @shift = false
      refresh_mouse(view)
    end

    def onLButtonDown(flags, x, y, view)
      @last_xy = [x, y]
      @shift = (flags & CONSTRAIN_MODIFIER_MASK) != 0
      @ip.pick(view, x, y)
      pt = current_point(view)
      if @pts.any?
        a = screen_xy(view, pt)
        b = screen_xy(view, @pts.last)
        return if Math.hypot(a[0] - b[0], a[1] - b[1]) < BoosokTools::Slice::MIN_PX
      end

      @pts << pt
      finish(view) if !multi? && @pts.size == 2
      view.invalidate
    end

    def onReturn(view)
      finish(view) if multi? && @pts.size >= 2
    end

    def onKeyDown(key, repeat, _flags, view)
      if key == CONSTRAIN_MODIFIER_KEY
        @shift = true
        refresh_mouse(view)
      elsif key == 9 && repeat == 1 && keep? # Tab
        flip_side(view)
      end
    end

    def getMenu(menu)
      menu.add_item('Ganti sisi yang dibuang (Tab)') { flip_side(Sketchup.active_model.active_view) } if keep?
      menu.add_item('Selesai (Enter)') { onReturn(Sketchup.active_model.active_view) } if multi? && @pts.size >= 2
    end

    def flip_side(view)
      @side = -@side
      view.invalidate
    end

    def finish(view)
      path = @pts.dup
      reset
      result = BoosokTools::Slice.perform(view, path, @side, @opts['result'])
      BoosokTools::Slice.report(result)
      update_status
      view.invalidate
    end

    # Keterangan tombol yang mengambang di viewport (menyesuaikan mode & langkah)
    def hud_lines
      sl = BoosokTools::Slice
      first = if @pts.empty?
                sl.loc('slice_hud_p1', 'Klik titik awal garis potong')
              elsif multi?
                sl.loc('slice_hud_pn', 'Klik titik berikutnya')
              else
                sl.loc('slice_hud_p2', 'Klik titik akhir garis potong')
              end
      keys1 = [sl.loc('slice_hud_shift', 'Shift: garis lurus (kunci 45°)'),
               multi? ? sl.loc('slice_hud_esc_multi', 'Esc: mundur 1 titik') : sl.loc('slice_hud_esc', 'Esc: batal')]
      keys2 = []
      keys2 << sl.loc('slice_hud_enter', 'Enter: selesai garis') if multi?
      keys2 << sl.loc('slice_hud_tab', 'Tab: ganti sisi yang dibuang') if keep?
      [first, keys1, keys2].reject { |l| l.respond_to?(:empty?) && l.empty? }
    end

    # Garis (menempel di titik model, ikut saat orbit) + tanda arsir pada sisi yang akan dibuang (mode keep)
    def draw(view)
      @ip.draw(view)
      BoosokTools::Slice.draw_hud(view, BoosokTools::Slice.loc('slice_hud_title', 'SLICE'), hud_lines)
      world = @pts + (@mouse ? [@mouse] : [])
      return if world.size < 2

      path = world.map { |pt| screen_xy(view, pt) }
      view.line_width = 2
      view.drawing_color = Sketchup::Color.new(220, 38, 38)
      view.draw2d(GL_LINE_STRIP, path.map { |x, y| Geom::Point3d.new(x, y, 0) })
      if @shift && @mouse # penanda titik terkunci
        mx, my = path.last
        view.draw2d(GL_LINE_LOOP, [[mx - 5, my - 5], [mx + 5, my - 5], [mx + 5, my + 5], [mx - 5, my + 5]].map { |x, y| Geom::Point3d.new(x, y, 0) })
      end
      return unless keep?

      ticks = []
      path.each_cons(2) do |a, b|
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        len = Math.hypot(dx, dy)
        next if len < 1.0

        nx, ny = BoosokTools::Slice.left_normal(dx, dy)
        (0..(len / 16).floor).each do |i|
          t = (i * 16.0) / len
          px = a[0] + (dx * t)
          py = a[1] + (dy * t)
          ticks << Geom::Point3d.new(px, py, 0)
          ticks << Geom::Point3d.new(px + (@side * nx * 9), py + (@side * ny * 9), 0)
        end
      end
      view.line_width = 1
      view.draw2d(GL_LINES, ticks) unless ticks.empty?
    end
  end

  # Tool pilih face: hanya highlight face di bawah kursor; klik = luruskan tampilan tegak lurus face.
  class FacePickTool
    def initialize(on_done)
      @on_done = on_done
      @face = nil
      @tr = nil
    end

    def activate
      Sketchup.status_text = 'Align View'
    end

    def deactivate(view)
      view.invalidate
    end

    def suspend(view)
      view.invalidate
    end

    def resume(view)
      activate
      view.invalidate
    end

    def getExtents
      Sketchup.active_model.bounds
    end

    def onCancel(_reason, _view)
      @on_done.call
    end

    def onMouseMove(_flags, x, y, view)
      pick(view, x, y)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      pick(view, x, y)
      return unless @face

      align(view)
      @on_done.call
    end

    # Hanya face (edge/group diabaikan); tr = transformasi face ke koordinat dunia
    def pick(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      @face = ph.picked_face
      @tr = nil
      return unless @face

      idx = (0...ph.count).find { |i| ph.leaf_at(i) == @face } || 0
      @tr = ph.transformation_at(idx)
    end

    def align(view)
      normal = @face.normal.transform(@tr).normalize
      cam = view.camera
      dir = normal.dot(cam.direction) <= 0 ? normal.reverse : normal
      center = @tr * @face.bounds.center
      dist = [(cam.eye - cam.target).length, Sketchup.active_model.bounds.diagonal].max
      up = dir.parallel?(Z_AXIS) ? Y_AXIS : Z_AXIS
      cam.set(center.offset(dir.reverse, dist), center, up)
      view.invalidate
    end

    def draw(view)
      sl = BoosokTools::Slice
      sl.draw_hud(view, sl.loc('slice_hud_align_title', 'ALIGN VIEW'),
                  [sl.loc('slice_hud_align', 'Klik sebuah face untuk meluruskan tampilan'), sl.loc('slice_hud_esc', 'Esc: batal')])
      return unless @face && @face.valid? && @tr

      mesh = @face.mesh(0)
      lift = @face.normal.transform(@tr).normalize
      lift.length = view.pixels_to_model(2, @tr * @face.bounds.center)
      tris = []
      mesh.polygons.each do |poly|
        pts = poly.map { |i| (@tr * mesh.point_at(i.abs)).offset(lift) }
        (1...(pts.size - 1)).each { |k| tris.push(pts[0], pts[k], pts[k + 1]) }
      end
      view.drawing_color = Sketchup::Color.new(0, 120, 255, 90)
      view.draw(GL_TRIANGLES, tris) unless tris.empty?
      view.drawing_color = Sketchup::Color.new(0, 90, 220)
      view.line_width = 3
      view.draw(GL_LINE_LOOP, @face.outer_loop.vertices.map { |v| (@tr * v.position).offset(lift) })
    end
  end

  # ── Dialog ────────────────────────────────────────────────────────────────

  class << self
    attr_accessor :slice_active
  end

  def self.start_align
    model = Sketchup.active_model
    return unless model

    was_slice = slice_active # SliceTool dinonaktifkan oleh FacePickTool; ingat untuk dikembalikan nanti
    model.select_tool(FacePickTool.new(lambda do
      if was_slice
        start_tool(options)
      else
        model.select_tool(nil)
      end
    end))
  end

  def self.report(result)
    dlg = @dialog
    return unless dlg

    if result.is_a?(String)
      dlg.execute_script("showToast(#{result.to_json}, 'error');")
    else
      dlg.execute_script("onSliced(#{result.to_json});")
    end
  end

  def self.send_init_data(dialog)
    return unless dialog

    enter # halaman Slice dimuat → paksa proyeksi paralel (dikembalikan lewat leave)
    dialog.execute_script("if (typeof init === 'function') init(#{options.to_json});")
  end

  def self.start_tool(opts)
    model = Sketchup.active_model
    return unless model

    @tool = SliceTool.new(opts)
    model.select_tool(@tool)
  end

  def self.attach_callbacks(dialog)
    return unless dialog
    return if @dialog.equal?(dialog) # sudah terdaftar di dialog ini (hindari handler bertumpuk)
    @dialog = dialog

    dialog.add_action_callback("slice_options") do |_ctx, json|
      opts = save_options(JSON.parse(json.to_s)) rescue options
      @tool.options = opts if @tool
    end

    dialog.add_action_callback("slice_align") do |_ctx|
      start_align
    end

    dialog.add_action_callback("slice_start") do |_ctx, json|
      opts = save_options(JSON.parse(json.to_s)) rescue options
      start_tool(opts)
    end
  end
end

file_loaded(__FILE__)
