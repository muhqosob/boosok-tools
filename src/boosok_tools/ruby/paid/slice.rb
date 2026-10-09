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

  # ── Penyaring cepat di ruang layar ────────────────────────────────────────

  BOUNDARY_PX = 2.0 unless defined?(BOUNDARY_PX) # hull yang sedekat ini dengan garis potong tidak dianggap jelas

  # Cangkang cembung (monotone chain) dari titik-titik layar
  def self.convex_hull(points)
    pts = points.uniq.sort
    return pts if pts.size < 3

    cross = ->(o, a, b) { ((a[0] - o[0]) * (b[1] - o[1])) - ((a[1] - o[1]) * (b[0] - o[0])) }
    build = lambda do |list|
      chain = []
      list.each do |pt|
        chain.pop while chain.size >= 2 && cross.call(chain[-2], chain[-1], pt) <= 0
        chain << pt
      end
      chain.pop
      chain
    end
    build.call(pts) + build.call(pts.reverse)
  end

  # Jarak titik ke SEGMEN a-b (px) kurang dari tol?
  def self.near_segment?(pt, a, b, tol)
    dist, t = seg_dist(pt, a, b)
    return Math.hypot(pt[0] - a[0], pt[1] - a[1]) <= tol if t < 0
    return Math.hypot(pt[0] - b[0], pt[1] - b[1]) <= tol if t > 1

    dist <= tol
  end

  # Posisi entity terhadap area potong, dari bayangan bounding box-nya di layar (cangkang cembung 8 sudut):
  #   :outside = bayangan seluruhnya di luar area (tidak tersentuh), :inside = seluruhnya di dalam area,
  #   :cross   = memotong / ragu-ragu (termasuk bersinggungan dengan garis atau ada sudut di belakang kamera).
  # Hasil :outside / :inside pasti benar, jadi pemanggil boleh melewati operasi mahal.
  def self.region_class(env, target, ctx_tr)
    box = target.bounds
    return :cross if box.empty?

    view = env[:view]
    cam = view.camera
    pts = (0..7).map do |i|
      world = ctx_tr * box.corner(i)
      return :cross if cam.perspective? && (world - cam.eye).dot(cam.direction) <= 0

      sp = view.screen_coords(world)
      [sp.x, sp.y]
    end
    hull = convex_hull(pts)
    poly = env[:poly]
    edges = poly.each_index.map { |i| [poly[i], poly[(i + 1) % poly.size]] }
    return :cross if hull.any? { |h| edges.any? { |a, b| near_segment?(h, a, b, BOUNDARY_PX) } }

    hull_edges = hull.size < 2 ? [] : hull.each_index.map { |i| [hull[i], hull[(i + 1) % hull.size]] }
    return :cross if hull_edges.any? { |h1, h2| edges.any? { |a, b| segments_cross?(h1, h2, a, b) } }

    inside = hull.map { |h| point_in_polygon?(h, poly) }
    return :inside if inside.all?
    return :cross if inside.any?
    return :cross if hull.size >= 3 && poly.any? { |v| point_in_polygon?(v, hull) }

    :outside
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

  # ── Geometri lepas (face/edge): dibelah di Ruby murni sepanjang bidang potong, lalu sisi yang tidak diinginkan dibuang ──

  def self.centroid(points)
    n = points.size.to_f
    Geom::Point3d.new(points.sum { |pt| pt.x } / n, points.sum { |pt| pt.y } / n, points.sum { |pt| pt.z } / n)
  end

  # Titik di dalam face: pusat sudut untuk segitiga, selain itu pusat segitiga pertama dari mesh (aman untuk face
  # cekung yang pusat sudutnya bisa jatuh di luar face)
  def self.face_center(face)
    verts = face.outer_loop.vertices
    return centroid(verts.map(&:position)) if verts.size <= 3

    mesh = face.mesh(0)
    tri = mesh.polygons.first
    tri ? centroid(tri.map { |i| mesh.point_at(i.abs) }) : centroid(verts.map(&:position))
  end

  # Titik pusat entity untuk menentukan sisi (nil kalau tidak bisa ditentukan, mis. guide tak hingga)
  def self.center_of(ent)
    case ent
    when Sketchup::Face then face_center(ent)
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

  # Buang sisi yang tidak diinginkan dari geometri lepas yang SUDAH dibelah. Hasil: ada isi di dalam area potong?
  def self.raw_keep_side(env, ents, tr, want_inside)
    fin, fout, lin, lout, oin, oout = raw_classify(env, ents, tr)
    affected = [fin, lin, oin].any?(&:any?)
    puts "[Boosok Slice] raw_keep_side: face #{fin.size} dalam/#{fout.size} luar, edge lepas #{lin.size}/#{lout.size}, " \
         "lain #{oin.size}/#{oout.size}, simpan sisi #{want_inside ? 'dalam' : 'luar'}"
    want_inside ? raw_remove(ents, fout, lout, oout) : raw_remove(ents, fin, lin, oin)
    affected
  end

  # Potong geometri lepas di `ents` dan buang sisi yang tidak diinginkan. Hasil: [terpengaruh?, ok?]
  def self.raw_slice_entities(env, ents, tr, want_inside)
    return [false, true] unless raw_geometry?(ents)
    return [false, false] if faces_or_edges?(ents) && !raw_split(env, ents, tr)

    [raw_keep_side(env, ents, tr, want_inside), true]
  end

  # ── Pembelah geometri lepas ──

  PX_EPS = 0.01 unless defined?(PX_EPS) # toleransi jarak ke garis potong (px layar)

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

  # Jarak bertanda (px) titik layar ke garis lurus a-b; positif di sisi kiri arah a→b
  def self.signed_dist(pt, a, b)
    dx = b[0] - a[0]
    dy = b[1] - a[1]
    len = Math.hypot(dx, dy)
    return 0.0 if len < 1e-9

    ((dx * (pt[1] - a[1])) - (dy * (pt[0] - a[0]))) / len
  end

  # Perpotongan face dengan bidang potong (dunia): array [titik1, titik2], tiap pasang = bagian garis yang ada di
  # dalam face. Sisi dengan ujung tepat di bidang dihitung setengah-terbuka supaya paritas tetap benar.
  def self.face_plane_chords(face, tr, plane)
    base, pn = plane
    pn = pn.normalize
    dir = face.normal.transform(tr).normalize.cross(pn)
    return [] if dir.length < 1e-9

    dir = dir.normalize
    origin = tr * face.outer_loop.vertices.first.position
    hits = []
    face.loops.each do |lp|
      pts = lp.vertices.map { |v| tr * v.position }
      ds = pts.map { |pt| (pt - base).dot(pn) }
      pts.each_index do |i|
        j = (i + 1) % pts.size
        next if (ds[i] > 0) == (ds[j] > 0)

        s = ds[i] / (ds[i] - ds[j])
        hits << Geom.linear_combination(1 - s, pts[i], s, pts[j])
      end
    end
    hits.sort_by { |pt| (pt - origin).dot(dir) }
        .each_slice(2).select { |a, b| b && a.distance(b) > 1e-6 }
  end

  # Bagian chord [w1, w2] yang berada di rentang segmen layar a-b (t 0..1; ujung garis potong sudah diperpanjang
  # sampai bingkai). nil kalau tidak ada.
  def self.clip_chord(view, w1, w2, a, b)
    s1 = view.screen_coords(w1)
    s2 = view.screen_coords(w2)
    t1 = seg_dist([s1.x, s1.y], a, b)[1]
    t2 = seg_dist([s2.x, s2.y], a, b)[1]
    return nil if (t2 - t1).abs < 1e-9

    lo = [0.0, [t1, t2].min].max
    hi = [1.0, [t1, t2].max].min
    return nil if hi - lo < 1e-6

    at = lambda do |t|
      u = (t - t1) / (t2 - t1)
      Geom.linear_combination(1 - u, w1, u, w2)
    end
    [at.call(lo), at.call(hi)]
  end

  JOIN_TOL = 1e-4 unless defined?(JOIN_TOL) # inci; ujung dua potongan dianggap bertemu

  # Gabungkan potongan garis [p, q] yang bersambung dan segaris menjadi satu garis. SketchUp hanya membelah face
  # kalau SATU garis menghubungkan dua titik di tepinya; rantai potongan yang bersambung tidak membelahnya.
  def self.merge_pieces(pieces)
    lines = pieces.map(&:dup)
    loop do
      joined = nil
      lines.combination(2).each do |l1, l2|
        joined = join_lines(l1, l2)
        next unless joined

        lines.delete_if { |l| l.equal?(l1) || l.equal?(l2) }
        lines << joined
        break
      end
      break unless joined
    end
    lines
  end

  # Satu garis kalau l1 dan l2 bersambung di salah satu ujung dan searah; kalau tidak nil
  def self.join_lines(l1, l2)
    a, b = l1
    c, d = l2
    ends = if b.distance(c) < JOIN_TOL then [a, d, b]
           elsif b.distance(d) < JOIN_TOL then [a, c, b]
           elsif a.distance(c) < JOIN_TOL then [b, d, a]
           elsif a.distance(d) < JOIN_TOL then [b, c, a]
           end
    return nil unless ends

    from, to, mid = ends
    v1 = mid - from
    v2 = to - mid
    return nil if v1.length < JOIN_TOL || v2.length < JOIN_TOL

    sin = v1.cross(v2).length / (v1.length * v2.length)
    sin < 1e-6 && v1.dot(v2).positive? ? [from, to] : nil
  end

  # Belah face yang melintas garis potong dengan menggambar garis perpotongannya (add_line). Semua segmen dihitung
  # sekaligus dari bentuk face semula, potongan yang segaris digabung jadi satu garis per chord, dan kalau masih
  # ada tikungan, find_faces dipanggil supaya face terbelah. Hanya face yang sudutnya ada di kedua sisi garis
  # lurus segmen yang dihitung. Hasil: jumlah garis ditambahkan.
  def self.split_faces(env, ents, tr, scr)
    view = env[:view]
    segs = env[:cut_path].each_cons(2).filter_map do |a, b|
      plane = patch_plane(view, a, b)
      [a, b, plane] if plane
    end
    inv = tr.inverse
    added = 0
    ents.grep(Sketchup::Face).each do |f|
      next unless f.valid?

      verts = f.outer_loop.vertices.map { |v| scr.call(v) }
      pieces = []
      segs.each do |a, b, plane|
        ds = verts.map { |pt| signed_dist(pt, a, b) }
        next unless ds.min < -PX_EPS && ds.max > PX_EPS

        face_plane_chords(f, tr, plane).each do |w1, w2|
          clipped = clip_chord(view, w1, w2, a, b)
          pieces << clipped if clipped
        end
      end
      next if pieces.empty?

      lines = merge_pieces(pieces)
      edges = lines.map { |p, q| ents.add_line(inv * p, inv * q) }.compact
      edges.each { |e| e.find_faces if e.valid? } if lines.size > 1
      added += lines.size
    end
    added
  end

  # Edge lepas (tanpa face) yang menyeberangi segmen potong dipecah di titik silangnya.
  def self.split_loose_edges_on_segment(ents, seg, scr)
    a, b = seg
    done = 0
    ents.grep(Sketchup::Edge).each do |e|
      next unless e.valid? && e.faces.empty?

      p1 = scr.call(e.start)
      p2 = scr.call(e.end)
      d1 = signed_dist(p1, a, b)
      d2 = signed_dist(p2, a, b)
      next unless (d1 > PX_EPS && d2 < -PX_EPS) || (d1 < -PX_EPS && d2 > PX_EPS)

      s = d1 / (d1 - d2)
      cross = [p1[0] + (s * (p2[0] - p1[0])), p1[1] + (s * (p2[1] - p1[1]))]
      t = seg_dist(cross, a, b)[1]
      next unless t > 0.0 && t < 1.0

      e.split(s)
      done += 1
    end
    done
  end

  # Jumlah face/edge lepas yang masih melintas garis: sudut-sudutnya (di luar garis itu sendiri) ada di dalam DAN di luar area
  def self.unsplit_faces(env, ents, scr)
    path = env[:cut_path]
    sides_of = lambda do |verts|
      verts.filter_map do |v|
        pt = scr.call(v)
        next if path.each_cons(2).any? { |a, b| near_segment?(pt, a, b, 0.5) }

        point_in_polygon?(pt, env[:poly])
      end.uniq.size > 1
    end
    faces = ents.grep(Sketchup::Face).count { |f| sides_of.call(f.outer_loop.vertices) }
    edges = ents.grep(Sketchup::Edge).count { |e| e.faces.empty? && sides_of.call([e.start, e.end]) }
    faces + edges
  end

  # Belah semua face/edge lepas di `ents` sepanjang garis potong (tiap segmen = satu bidang tegak). Posisi layar
  # tiap vertex dihitung sekali (cache). Hasil: false kalau terjadi error.
  def self.raw_split(env, ents, tr)
    path = env[:cut_path]
    return true unless path && path.size >= 2

    view = env[:view]
    cache = {}
    scr = lambda do |v|
      cache[v.entityID] ||= begin
        sp = view.screen_coords(tr * v.position)
        [sp.x, sp.y]
      end
    end
    added = 0
    left = 0
    3.times do |round|
      added += split_faces(env, ents, tr, scr)
      path.each_cons(2) { |seg| added += split_loose_edges_on_segment(ents, seg, scr) }
      left = unsplit_faces(env, ents, scr)
      break if left.zero?

      puts "[Boosok Slice] raw_split putaran #{round + 1}: #{left} face masih melintas garis"
    end
    puts "[Boosok Slice] raw_split: garis/edge ditambahkan=#{added}, face melintas tersisa=#{left}"
    # Face yang tetap melintas akan dibuang/dipertahankan utuh menurut pusatnya: itu bisa menghapus isi group
    # diam-diam, jadi lebih aman membatalkan potongan ini (group asli tidak disentuh).
    left.zero?
  rescue StandardError => e
    puts "[Boosok Slice] raw_split: #{e.class}: #{e.message}"
    false
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
      puts "[Boosok Slice] raw_piece: seluruh isi #{target.name.inspect} jatuh di sisi yang dibuang (group habis)"
      BoosokTools::Void.erase_if_valid(work)
      return [nil, affected, true]
    end
    [work, affected, true]
  end

  # Kedua sisi sekaligus (mode split) untuk target geometri lepas: SATU salinan dibelah, lalu digandakan dan tiap
  # salinan membuang sisi lawannya. Hasil: [[bagian luar, terpengaruh?, ok?], [bagian dalam, terpengaruh?, ok?]]
  def self.raw_pair(env, entities, target, ctx_tr)
    void = BoosokTools::Void
    outer = void.duplicate(entities, target)
    outer.make_unique if outer.is_a?(Sketchup::ComponentInstance)
    ents = void.entities_of(outer)
    if raw_geometry?(ents) && faces_or_edges?(ents) && !raw_split(env, ents, ctx_tr * outer.transformation)
      void.erase_if_valid(outer)
      return [[nil, false, false], [nil, false, false]]
    end

    inner = void.duplicate(entities, outer)
    inner.make_unique if inner.is_a?(Sketchup::ComponentInstance)
    [[outer, false], [inner, true]].map do |work, want_inside|
      wents = void.entities_of(work)
      affected = raw_geometry?(wents) && raw_keep_side(env, wents, ctx_tr * work.transformation, want_inside)
      if wents.length.zero?
        void.erase_if_valid(work)
        work = nil
      end
      [work, affected, true]
    end
  end

  def self.raw_leaf?(target)
    !BoosokTools::Void.solid?(target) && BoosokTools::Void.nested(target).empty?
  end

  # Geometri lepas di tingkat yang JUGA berisi group/component (face/edge di samping sub-group): dibelah dengan
  # raw_split, yang hanya menyentuh face/edge langsung di tingkat ini (tidak menyentuh isi sub-group). Tanpa
  # pembelahan, face yang melintas garis dibuang/dipertahankan utuh menurut pusatnya, sehingga group 2D bisa
  # lenyap alih-alih terpotong.
  def self.raw_slice_loose(env, ents, tr, want_inside)
    return [false, true] unless raw_geometry?(ents)
    return [false, false] if faces_or_edges?(ents) && !raw_split(env, ents, tr)

    [raw_keep_side(env, ents, tr, want_inside), true]
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
      # Anak yang seluruhnya di satu sisi tidak perlu dipotong: sisi yang diinginkan dibiarkan, sisi lain dihapus
      cls = region_class(env, kid, inner_tr)
      unless cls == :cross
        tick(env, leaves_of(env, kid)) unless want_inside
        affected ||= cls == :inside
        kid.erase! unless cls == (want_inside ? :inside : :outside)
        next
      end

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
  # Satu daun dihitung selesai sekali, di putaran sisi luar (selalu dijalankan di kedua mode)
  def self.side_copy(env, entities, target, ctx_tr, want_inside)
    if BoosokTools::Void.solid?(target)
      res = leaf_piece(env, entities, target, ctx_tr, want_inside)
      res = raw_piece(env, entities, target, ctx_tr, want_inside) unless res[2]
      tick(env) unless want_inside
      res
    elsif BoosokTools::Void.nested(target).empty?
      res = raw_piece(env, entities, target, ctx_tr, want_inside)
      tick(env) unless want_inside
      res
    else
      container_piece(env, entities, target, ctx_tr, want_inside)
    end
  end

  # Potong satu target tingkat atas. Hasil: array bagian (kosong kalau tidak terpotong / gagal).
  def self.slice_target(env, entities, target, ctx_tr, result_mode, stats)
    # Seluruh target di satu sisi garis: tidak ada yang perlu dipotong (mode keep: yang di area buang dihapus)
    cls = region_class(env, target, ctx_tr)
    puts "[Boosok Slice] target #{target.name.inspect} (#{target.class.name.split('::').last}##{target.persistent_id}): #{cls}"
    case cls
    when :outside
      tick(env, leaves_of(env, target))
      stats[:notcut] += 1
      return []
    when :inside
      tick(env, leaves_of(env, target))
      if result_mode == 'keep'
        target.erase!
        stats[:cut] += 1
      else
        stats[:notcut] += 1
      end
      return []
    end

    want = result_mode == 'split' ? [false, true] : [false]
    results = if result_mode == 'split' && raw_leaf?(target)
                raw_pair(env, entities, target, ctx_tr).tap { tick(env) }
              else
                want.map { |inside| side_copy(env, entities, target, ctx_tr, inside) }
              end
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
    env[:progress] = self.progress = Progress.new(view, targets.sum { |t| leaves_of(env, t) }, loc('slice_progress_cut', 'Memotong...'))
    begin
      progress.phase(progress.label)
      BoosokTools::Void.hold_live { run_slice(model, targets, env, ctx_tr, result_mode, stats) }
    ensure
      self.progress = nil
      Sketchup.status_text = 'Slice'
      view.invalidate
    end
  end

  # Jalankan Void lagi di dalam operasi Slice. Potongan yang terlubangi tersembunyi sebagai "sumber" dan yang
  # terlihat adalah hasilnya, jadi daftar potongan (untuk seleksi) diganti dengan hasil itu.
  def self.reapply_holes(model, pieces, stats)
    void = BoosokTools::Void
    results = void.rebuild(model, void.new_stats)
    by_link = results.each_with_object({}) { |r, h| h[void.link_of(r)] = r }
    pieces.select(&:valid?).map do |pc|
      void.role(pc) == 'source' ? by_link[void.link_of(pc)] : pc
    end.compact
  rescue StandardError => e
    puts "[Boosok Slice] lubang void gagal dibuat ulang: #{e.class}: #{e.message}"
    stats[:failed] += 1
    pieces
  end

  # Lubang Void dibatalkan dulu (target berlubang dikembalikan ke sumbernya yang utuh), baru dipotong, lalu
  # Void dijalankan lagi pada potongannya supaya lubangnya terbentuk kembali. Satu operasi = satu langkah Undo.
  def self.run_slice(model, targets, env, ctx_tr, result_mode, stats)
    entities = model.active_entities
    model.start_operation('Slice', true)
    begin
      targets, holes = BoosokTools::Void.restore_holes(entities, targets)
      extra = holes.positive? ? [(env[:progress].total * 0.3).ceil, 1].max : 0
      env[:progress].extend_total(extra)
      pieces = []
      targets.each do |t|
        pieces.concat(slice_target(env, entities, t, ctx_tr, result_mode, stats))
      rescue StandardError => e
        puts "[Boosok Slice] #{e.class}: #{e.message}"
        stats[:failed] += 1
      end
      if holes.positive?
        env[:progress].phase(loc('slice_progress_void', 'Membuat ulang lubang Void...'))
        pieces = reapply_holes(model, pieces, stats)
        env[:progress].tick(extra)
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

  # ── Progress bar di viewport ─────────────────────────────────────────────

  # Slice berjalan sinkron dalam satu operasi, jadi layar hanya tergambar ulang kalau kita memanggil View#refresh.
  # Satuan kerja = satu daun (group solid / geometri lepas); tick dipanggil tiap daun selesai.
  class Progress
    REFRESH_EVERY = 0.1 # detik; batasi gambar ulang supaya tidak memperlambat

    attr_reader :total

    def initialize(view, total, label)
      @view = view
      @total = [total, 1].max
      @done = 0
      @label = label
      @last = 0.0
    end

    def fraction
      [@done.to_f / @total, 1.0].min
    end

    def percent
      (fraction * 100).floor
    end

    attr_reader :label

    def extend_total(count)
      @total += count
    end

    def tick(count = 1)
      @done += count
      refresh(false)
    end

    def phase(label)
      @label = label
      refresh(true)
    end

    def refresh(force)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return unless force || now - @last >= REFRESH_EVERY

      @last = now
      Sketchup.status_text = "Slice #{percent}%"
      @view.refresh
    rescue StandardError
      nil
    end
  end

  # Jumlah "daun" (group solid / geometri lepas) di dalam entity; sama dengan cabang yang dipilih side_copy
  def self.leaves_of(env, ent)
    cache = (env[:leaves] ||= {})
    cache[ent.persistent_id] ||= begin
      kids = BoosokTools::Void.nested(ent)
      if BoosokTools::Void.solid?(ent) || kids.empty?
        1
      else
        kids.sum { |k| leaves_of(env, k) }
      end
    end
  end

  def self.tick(env, count = 1)
    env[:progress]&.tick(count)
  end

  # Palet tema Boosok (sama dengan css/ui.css: zinc monokrom, aksen = warna ink; gelap/terang mengikuti pilihan
  # tema yang disimpan dialog)
  PROGRESS_THEME = {
    light: { surface: [255, 255, 255, 246], line: [230, 230, 233], track: [228, 228, 231], ink: [24, 24, 27],
             muted: [113, 113, 122], fill: [24, 24, 27], ok: [22, 163, 74] },
    dark: { surface: [30, 30, 34, 246], line: [46, 46, 52], track: [46, 46, 52], ink: [244, 244, 246],
            muted: [148, 148, 158], fill: [255, 255, 255], ok: [34, 197, 94] }
  }.freeze unless defined?(PROGRESS_THEME)

  def self.progress_theme
    dark = Sketchup.read_default('BoosokTools', 'theme', 'light').to_s == 'dark'
    PROGRESS_THEME[dark ? :dark : :light]
  rescue StandardError
    PROGRESS_THEME[:light]
  end

  # Titik poligon cembung persegi bulat (koordinat layar)
  def self.rounded_rect(x0, y0, x1, y1, radius)
    r = [radius, (x1 - x0) / 2.0, (y1 - y0) / 2.0].min
    corners = [[x1 - r, y0 + r, -90], [x1 - r, y1 - r, 0], [x0 + r, y1 - r, 90], [x0 + r, y0 + r, 180]]
    corners.flat_map do |cx, cy, start|
      (0..4).map do |i|
        ang = (start + (i * 22.5)) * Math::PI / 180.0
        Geom::Point3d.new(cx + (r * Math.cos(ang)), cy + (r * Math.sin(ang)), 0)
      end
    end
  end

  def self.theme_color(rgb, alpha = nil)
    Sketchup::Color.new(rgb[0], rgb[1], rgb[2], alpha || rgb[3] || 255)
  end

  def self.hud_text_at(view, x, y, text, size, bold, color)
    view.draw_text(Geom::Point3d.new(x, y, 0), text, color: color, font: 'Segoe UI', size: size, bold: bold)
  end

  # Panel kecil di tengah layar: judul + persentase, bar, keterangan tahap (gaya kartu dialog Boosok)
  def self.draw_progress(view)
    pg = progress
    return unless pg

    th = progress_theme
    pw = 340.0
    ph = 82.0
    px = (view.vpwidth - pw) / 2.0
    py = (view.vpheight * 0.40) - (ph / 2.0)
    pad = 16.0
    bx = px + pad
    bw = pw - (2 * pad)
    by = py + 38.0
    bh = 8.0

    view.drawing_color = Sketchup::Color.new(0, 0, 0, 38) # bayangan lembut
    view.draw2d(GL_POLYGON, rounded_rect(px, py + 3, px + pw, py + ph + 3, 12))
    view.drawing_color = theme_color(th[:surface])
    view.draw2d(GL_POLYGON, rounded_rect(px, py, px + pw, py + ph, 12))
    view.line_width = 1
    view.drawing_color = theme_color(th[:line])
    view.draw2d(GL_LINE_LOOP, rounded_rect(px, py, px + pw, py + ph, 12))

    view.drawing_color = theme_color(th[:track])
    view.draw2d(GL_POLYGON, rounded_rect(bx, by, bx + bw, by + bh, 4))
    done = pg.fraction
    if done.positive?
      view.drawing_color = theme_color(done >= 1.0 ? th[:ok] : th[:fill])
      view.draw2d(GL_POLYGON, rounded_rect(bx, by, bx + [bw * done, 2.0 * 4].max, by + bh, 4))
    end

    pct = "#{pg.percent}%"
    hud_text_at(view, bx, py + 12, 'SLICE', 13, true, theme_color(th[:ink]))
    hud_text_at(view, bx + bw - hud_width(view, pct, 13, true), py + 12, pct, 13, true, theme_color(th[:ink]))
    hud_text_at(view, bx, by + bh + 8, pg.label.to_s, 11, false, theme_color(th[:muted]))
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
      BoosokTools::Slice.draw_progress(view)
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
    attr_accessor :slice_active, :progress
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
