require 'sketchup'
require 'json'
Sketchup.require 'boosok_tools/ruby/titlebar'
Sketchup.require 'boosok_tools/ruby/locale' unless defined?(BoosokTools::Locale)
Sketchup.require 'boosok_tools/ruby/paid/slice' unless defined?(BoosokTools::Slice) # HUD viewport bersama

# Trowel: Push/Pull dan Offset pada face yang berada di dalam group/component (tersarang berapa pun) TANPA
# membuka group-nya. Hasil bisa langsung mengubah geometri di dalam group ("inplace") atau dibuat sebagai
# group baru terpisah ("newgroup") sehingga geometri asli tidak berubah.
module BoosokTools::Trowel
  DEFAULTS = { 'output' => 'inplace' }.freeze unless defined?(DEFAULTS)
  EPS = 1e-6 unless defined?(EPS)
  SNAP_PX = 14 unless defined?(SNAP_PX) # jarak (px layar) kursor ke sudut / titik tengah di mana jarak "menempel"

  def self.release_dialog
    @dialog = nil
  end

  def self.run
    Sketchup.require 'boosok_tools/hub' unless defined?(BoosokTools::Hub)
    BoosokTools::Hub.open_or_show('trowel')
  end

  # ── Pengaturan ────────────────────────────────────────────────────────────

  def self.options
    {
      'output' => Sketchup.read_default('BoosokTools', 'trowel_output', DEFAULTS['output']).to_s
    }
  end

  def self.save_options(opts)
    output = opts['output'] == 'newgroup' ? 'newgroup' : 'inplace'
    Sketchup.write_default('BoosokTools', 'trowel_output', output)
    { 'output' => output }
  end

  # ── Geometri ──────────────────────────────────────────────────────────────

  def self.container?(ent)
    ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
  end

  # Loop face dalam koordinat dunia; loop luar pertama
  def self.world_loops(face, tr)
    ([face.outer_loop] + (face.loops - [face.outer_loop])).map do |lp|
      lp.vertices.map { |v| tr * v.position }
    end
  end

  def self.centroid(points)
    n = points.size.to_f
    Geom::Point3d.new(points.sum(&:x) / n, points.sum(&:y) / n, points.sum(&:z) / n)
  end

  # Face baru di `ents` dari loop-loop titik (loop pertama = luar, sisanya lubang). Hasil: Face atau nil.
  def self.build_face(ents, loops)
    ents.add_face(loops[0])
    loops[1..].each do |hole|
      hf = ents.add_face(hole)
      hf.erase! if hf && hf.valid? # menghapus isi lubang; garis tepinya tetap membentuk lubang
    end
    ents.grep(Sketchup::Face).max_by(&:area)
  rescue StandardError => e
    puts "[Boosok Trowel] build_face: #{e.class}: #{e.message}"
    nil
  end

  # ── Operasi (tanpa start/commit: dipanggil tiap gerakan mouse di dalam satu operasi yang terbuka) ──

  # Push/Pull face. dist_world = jarak bertanda sepanjang normal dunia hit[:normal_world].
  # Hasil: [ok, pesan_error, group_baru_atau_nil]
  def self.do_pushpull(model, hit, face, dist_world, output)
    return [true, nil, nil] if dist_world.abs < EPS

    if output == 'newgroup'
      group = model.active_entities.add_group
      base = build_face(group.entities, hit[:virtual_loops] || world_loops(face, hit[:tr]))
      return [false, 'Gagal membuat face dasar.', group] unless base

      base.reverse! if base.normal.dot(hit[:normal_world]) < 0
      base.pushpull(dist_world)
      [true, nil, group]
    else
      face.pushpull(dist_world / hit[:scale])
      [true, nil, nil]
    end
  rescue StandardError => e
    [false, "Gagal: #{e.message}", nil]
  end

  # ── Hasil Void (mis. dinding berlubang) yang diubah Trowel ──────────────────────────────────────────────────────
  # Dinding berlubang oleh Void adalah "hasil" yang dibangun ulang dari "sumber" utuh yang tersembunyi tiap kali void
  # digeser. Kalau hasil diubah Trowel tanpa mengubah sumber, perubahan itu hilang saat dibangun ulang (dinding
  # kembali ke ukuran awal). Jadi perubahan Push/Pull disalin juga ke sumber; selain itu hasil dilepas dari kendali Void.

  def self.void_result?(ent)
    ent && BoosokTools::Void.container?(ent) && BoosokTools::Void.role(ent) == 'result'
  end

  def self.find_void_source(owner)
    link = BoosokTools::Void.link_of(owner)
    owner.parent.entities.find do |e|
      BoosokTools::Void.container?(e) && BoosokTools::Void.role(e) == 'source' && BoosokTools::Void.link_of(e) == link
    end
  end

  # Salin Push/Pull ke face yang sama di sumber (dicocokkan lewat bidang dan titik di dalam face). Hasil: true/false.
  def self.sync_void_source(hit, owner, dist_world)
    source = find_void_source(owner)
    return false unless source

    parent_tr = hit[:tr] * owner.transformation.inverse
    src_tr = parent_tr * source.transformation
    inv = src_tr.inverse
    n = hit[:normal_world]
    loop0 = hit[:loops][0]
    probes = [hit[:origin]] + loop0 + loop0.each_index.map { |i| Geom.linear_combination(0.5, loop0[i], 0.5, loop0[(i + 1) % loop0.size]) }
    inside = [Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex]
    found = nil
    BoosokTools::Void.entities_of(source).grep(Sketchup::Face).each do |f|
      fn = f.normal.transform(src_tr)
      next if fn.length < EPS

      un = fn.normalize
      next unless un.dot(n).abs > 0.9999
      next unless ((src_tr * f.vertices.first.position) - hit[:origin]).dot(un).abs < 0.01
      next unless probes.any? { |pt| inside.include?(f.classify_point(inv * pt)) }

      found = [f, fn.length, un.dot(n) >= 0 ? 1.0 : -1.0]
      break
    end
    return false unless found

    face, scale, orient = found
    face.pushpull((dist_world * orient) / scale)
    true
  rescue StandardError => e
    puts "[Boosok Trowel] sync_void_source: #{e.class}: #{e.message}"
    false
  end

  # Lepas hasil dari kendali Void: hasil jadi group biasa (perubahan Trowel dipertahankan), sumber tersembunyi dihapus.
  def self.detach_void(model, owner)
    source = find_void_source(owner)
    BoosokTools::Void.clear_roles(owner)
    source.erase! if source && source.valid?
    BoosokTools::Void.invalidate_scan_cache
    BoosokTools::Void.rescan(model)
  end

  # Titik snap (sudut dan titik tengah edge, dunia) dari face-face di dalam definition yang sama (termasuk group
  # tersarang), kecuali face di `skip`. Dihitung SEKALI di awal tarikan dari geometri asli, jadi tidak ikut bergerak
  # saat tarikan live (tidak ada efek terkunci ke posisi sendiri). Hasil: array [titik, label].
  def self.own_snap_points(entities, tr, skip, out = [], depth = 0)
    entities.each do |e|
      break if out.size > 20_000

      if e.is_a?(Sketchup::Face)
        next if skip.include?(e)

        pts = e.outer_loop.vertices.map { |v| tr * v.position }
        pts.each_index do |i|
          out << [pts[i], 'Sudut']
          out << [Geom.linear_combination(0.5, pts[i], 0.5, pts[(i + 1) % pts.size]), 'Titik tengah']
        end
      elsif container?(e) && depth < 4
        own_snap_points(e.definition.entities, tr * e.transformation, skip, out, depth + 1)
      end
    end
    out
  end

  # Setelah Push/Pull sampai sejajar dengan permukaan di sekitarnya (mis. dasar lubang didorong sampai rata dengan
  # permukaan atas), edge di antara face yang sebidang dan bermaterial sama dihapus supaya face menyatu bersih tanpa
  # sisa garis. Setelah Push/Pull, edge tepi face yang bergerak adalah edge BARU (id lama tidak berlaku), jadi yang
  # diperiksa adalah edge di definition yang sama yang terletak tepat di atas jejak tepi face asal (dilihat dari arah
  # tarikan) dan memisahkan dua face sebidang. Face tanpa luas (dinding setinggi nol) di jejak itu ikut dibuang.
  def self.merge_coplanar_edges(model, hit)
    ents = hit[:parent].entities
    tr = hit[:tr]
    inv = tr.inverse
    n = hit[:normal_world]
    ux, vx = n.axes
    flat = ->(pt) { [pt.x * ux.x + pt.y * ux.y + pt.z * ux.z, pt.x * vx.x + pt.y * vx.y + pt.z * vx.z] }
    rim = hit[:loops].flat_map do |lp|
      lp.each_index.map { |i| [flat.call(lp[i]), flat.call(lp[(i + 1) % lp.size])] }
    end
    on_rim = lambda do |pt|
      q = flat.call(pt)
      rim.any? do |a, b|
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        len2 = (dx * dx) + (dy * dy)
        t = len2 < 1e-12 ? 0.0 : [[(((q[0] - a[0]) * dx) + ((q[1] - a[1]) * dy)) / len2, 0.0].max, 1.0].min
        Math.hypot(q[0] - (a[0] + (t * dx)), q[1] - (a[1] + (t * dy))) < 1e-3
      end
    end

    # Dinding setinggi nol di jejak tepi (hasil menarik tepat sampai sebidang)
    ents.grep(Sketchup::Face).each do |f|
      next unless f.valid? && f.area < 1e-6

      f.erase! if f.vertices.all? { |v| on_rim.call(tr * v.position) }
    end

    # Edge tepi: dua face sebidang di kedua sisinya. Begitu satu edge dihapus, kedua face menyatu jadi SATU face dan
    # edge tepi lain yang tersisa tinggal berada di tengah face itu (faces.size < 2), jadi dihapus juga bila titik
    # tengahnya jatuh di dalam face sebidang.
    flat_faces = ents.grep(Sketchup::Face)
    merged = 0
    ents.grep(Sketchup::Edge).each do |e|
      next unless e.valid?
      next unless on_rim.call(tr * e.start.position) && on_rim.call(tr * e.end.position)

      if e.faces.size == 2
        f1, f2 = e.faces
        next unless f1.normal.dot(f2.normal) > 0.99999
        next unless (f1.vertices.first.position - f2.vertices.first.position).dot(f2.normal).abs < 1e-3
        next unless f1.material == f2.material && f1.back_material == f2.back_material
      else
        mid = Geom.linear_combination(0.5, e.start.position, 0.5, e.end.position)
        next unless flat_faces.any? do |f|
          f.valid? && f.classify_point(mid) == Sketchup::Face::PointInside && f.normal.dot(n.transform(inv).normalize).abs > 0.99999
        end
      end

      e.erase!
      merged += 1
    end
    puts "[Boosok Trowel] merge_coplanar_edges: #{merged} edge dihapus" if merged.zero?
    merged
  rescue StandardError => e
    puts "[Boosok Trowel] merge_coplanar_edges: #{e.class}: #{e.message}"
    0
  end

  # Face hasil Offset yang harus ditarik: face yang loop luarnya paling mirip dengan loop luar hasil offset (ke dalam:
  # face di dalam; ke luar: cincin baru). Kemiripan = jarak terjauh titik loop hasil offset ke titik terdekat di loop
  # face (Hausdorff sederhana). Face dengan kemiripan terbaik dipilih bila cukup dekat. Hasil: [face, info_debug].
  def self.find_inner_face(hit, loops, _dist)
    outer = loops[0]
    faces = hit[:parent].entities.grep(Sketchup::Face)
    best = nil
    faces.each do |f|
      pts = f.outer_loop.vertices.map { |v| hit[:tr] * v.position }
      score = outer.map { |q| pts.map { |pt| pt.distance(q) }.min }.max
      score2 = pts.map { |pt| outer.map { |q| pt.distance(q) }.min }.max
      s = [score, score2].max
      best = [s, f, pts.size] if best.nil? || s < best[0]
    end
    info = "faces=#{faces.size} loop=#{outer.size} terbaik=#{best ? best[0].round(4) : '-'} (titik #{best ? best[2] : '-'})"
    face = best && best[0] < 0.5 ? best[1] : nil
    [face, info]
  end

  # Edge aman dihapus (Shift + klik): hanya edge di DALAM face, yaitu pemisah dua face sebidang (kedua face menyatu),
  # garis yang tertanam di dalam satu face, atau garis lepas. Edge sudut / tepi bentuk (pemisah dua face yang tidak
  # sebidang, atau tepi satu-satunya face) TIDAK boleh karena menghapusnya ikut menghapus face dan merusak group.
  def self.edge_erasable?(edge)
    faces = edge.faces
    case faces.size
    when 0 then true
    when 1 then faces[0].loops.none? { |lp| lp.edges.include?(edge) }
    when 2
      f1, f2 = faces
      f1.normal.dot(f2.normal) > 0.99999 && (f1.vertices.first.position - f2.vertices.first.position).dot(f2.normal).abs < 1e-3
    else false
    end
  end

  # Semua edge aman-hapus yang saling terhubung (lewat titik sudut) dengan `edge` dan berada di bidang yang sama,
  # supaya satu klik menghapus seluruh garis bentuk (mis. persegi hasil Offset di dalam face). Edge sudut / tepi
  # bentuk tidak ikut. Hasil: array edge (termasuk `edge`).
  def self.erasable_chain(edge)
    plane = edge.faces.first
    base = plane && [plane.vertices.first.position, plane.normal]
    same_plane = lambda do |e|
      if base
        e.faces.all? { |f| f.normal.dot(base[1]).abs > 0.99999 && (f.vertices.first.position - base[0]).dot(base[1]).abs < 1e-3 }
      else
        e.faces.empty?
      end
    end
    seen = { edge.entityID => edge }
    queue = [edge]
    until queue.empty? || seen.size > 2000
      cur = queue.shift
      [cur.start, cur.end].each do |v|
        v.edges.each do |nb|
          next if seen[nb.entityID] || !edge_erasable?(nb) || !same_plane.call(nb)

          seen[nb.entityID] = nb
          queue << nb
        end
      end
    end
    seen.values
  end

  # Kotak (titik min & maks, dunia) dari semua face di definition yang sama yang BUKAN bagian dari cangkang face ini
  # (bagian lain yang bisa tertabrak). nil kalau tidak ada.
  def self.other_shells_box(face, tr)
    shell = face.all_connected.grep(Sketchup::Face)
    others = face.parent.entities.grep(Sketchup::Face).reject { |f| shell.include?(f) }
    return nil if others.empty?

    box = Geom::BoundingBox.new
    others.each { |f| (0..7).each { |i| box.add(tr * f.bounds.corner(i)) } }
    [box.min, box.max]
  rescue StandardError
    nil
  end

  # Apakah balok hasil tarikan (face asal sampai face baru) beririsan dengan kotak bagian lain?
  def self.collides?(hit, dist_view)
    return false unless hit[:other_box]

    pts = hit[:loops][0]
    pts = pts + pts.map { |pt| moved_point(pt, hit[:axis], dist_view) }
    lo = [pts.map(&:x).min, pts.map(&:y).min, pts.map(&:z).min]
    hi = [pts.map(&:x).max, pts.map(&:y).max, pts.map(&:z).max]
    omin, omax = hit[:other_box]
    (lo[0] <= omax.x && hi[0] >= omin.x) && (lo[1] <= omax.y && hi[1] >= omin.y) && (lo[2] <= omax.z && hi[2] >= omin.z)
  end

  # Push/Pull yang menjaga group tetap SOLID ketika bagian yang ditarik menabrak bagian lain di dalam group yang sama.
  # Face.pushpull biasa membuat permukaan yang saling menembus (group tidak lagi solid). Di sini balok hasil tarikan
  # dibuat sebagai solid sendiri, lalu: tarik keluar (jarak > 0) = union dengan group; tekan ke dalam (jarak < 0) =
  # group dikurangi balok. Tabrakan otomatis menyatu / tembus tanpa sisa permukaan di dalam. Hasil: group baru atau nil.
  def self.solid_pushpull(model, hit, inst, face, dist_world)
    parent_ents = inst.parent.entities
    inv = (hit[:tr] * inst.transformation.inverse).inverse # dunia -> koordinat induk instance
    src_loops = face ? world_loops(face, hit[:tr]) : hit[:loops]
    loops = src_loops.map { |lp| lp.map { |pt| inv * pt } }
    nraw = hit[:normal_world].transform(inv)
    return nil if nraw.length < EPS

    n_local = nraw.normalize
    tmp = parent_ents.add_group
    base = build_face(tmp.entities, loops)
    unless base
      tmp.erase!
      return nil
    end

    base.reverse! if base.normal.dot(n_local) < 0
    base.pushpull(dist_world * nraw.length)
    unless BoosokTools::Void.solid?(tmp)
      tmp.erase!
      return nil
    end

    # Operasi solid MENGHAPUS kedua operannya, jadi dipakai salinan group; properti diambil dari group asli (yang
    # masih utuh) lalu group asli dihapus.
    work = BoosokTools::Void.duplicate(parent_ents, inst)
    result = dist_world > 0 ? work.union(tmp) : tmp.subtract(work)
    unless result
      puts '[Boosok Trowel] solid_pushpull: union/subtract mengembalikan nil (salah satu operan bukan solid?)'
      BoosokTools::Void.erase_if_valid(work)
      BoosokTools::Void.erase_if_valid(tmp)
      return nil
    end

    BoosokTools::Void.copy_properties(inst, result)
    inst.erase!
    result
  rescue StandardError => e
    puts "[Boosok Trowel] solid_pushpull: #{e.class}: #{e.message}"
    nil
  end

  # Titik digeser sepanjang vektor `dir` sejauh `k`. Vector3d#* di SketchUp hanya untuk dot product (tidak menerima
  # angka), jadi penggeseran dihitung per komponen.
  def self.moved_point(pt, dir, k)
    Geom::Point3d.new(pt.x + (dir.x * k), pt.y + (dir.y * k), pt.z + (dir.z * k))
  end

  # Apakah titik `pt` (pada bidang face) berada di dalam face (genap-ganjil, termasuk lubang)?
  def self.loops_contain?(loops, origin, u, dir, pt)
    px = (pt - origin).dot(u)
    py = (pt - origin).dot(dir)
    inside = false
    loops.each do |pts|
      pts.each_index do |i|
        a = pts[i]
        b = pts[(i + 1) % pts.size]
        xa = (a - origin).dot(u)
        ya = (a - origin).dot(dir)
        xb = (b - origin).dot(u)
        yb = (b - origin).dot(dir)
        next unless (ya > py) != (yb > py)

        inside = !inside if px < xa + ((py - ya) * (xb - xa) / (yb - ya))
      end
    end
    inside
  end

  # ── Offset SATU edge (kursor di edge tanpa Push/Pull berjalan) ───────────────────────────────────────────────────
  # Rentang jarak [min, max] seluruh titik loop face searah `dir` dari `origin` (batas offset).
  def self.loops_range(loops, origin, dir)
    ds = loops.flat_map { |pts| pts.map { |pt| (pt - origin).dot(dir) } }
    [[ds.min.to_f, 0.0].min, [ds.max.to_f, 0.0].max]
  end

  # Titik potong garis sejajar edge pada jarak `d` (searah `dir`) dengan batas face. Koordinat 2D: X = searah edge
  # (`u`), Y = searah offset (`dir`), keduanya dari `origin` (titik tengah edge).
  def self.crossings(loops, origin, u, dir, axis_is_y, level)
    out = []
    loops.each do |pts|
      pts.each_index do |i|
        a = pts[i]
        b = pts[(i + 1) % pts.size]
        xa = (a - origin).dot(u)
        ya = (a - origin).dot(dir)
        xb = (b - origin).dot(u)
        yb = (b - origin).dot(dir)
        if axis_is_y # garis Y = level, hasil: nilai X
          next unless (ya <= level) != (yb <= level)

          out << (xa + ((level - ya) * (xb - xa) / (yb - ya)))
        else # garis X = level, hasil: nilai Y
          next unless (xa <= level) != (xb <= level)

          out << (ya + ((level - xa) * (yb - ya) / (xb - xa)))
        end
      end
    end
    out.sort
  end

  # Garis offset PENUH: dari batas face ke batas face (bukan sepanjang edge asal), sehingga membelah face. Pada
  # jarak d dipilih ruas yang memuat titik di seberang titik tengah edge (atau yang terdekat). Hasil: [p1, p2] dunia / nil.
  def self.offset_segment(loops, origin, u, dir, d)
    xs = crossings(loops, origin, u, dir, true, d)
    segs = xs.each_slice(2).select { |pair| pair.size == 2 }
    return nil if segs.empty?

    seg = segs.find { |a, b| a <= 0 && b >= 0 } || segs.min_by { |a, b| [a.abs, b.abs].min }
    [moved_point(moved_point(origin, u, seg[0]), dir, d), moved_point(moved_point(origin, u, seg[1]), dir, d)]
  end

  # Batas face berikutnya di seberang garis offset, searah gerak (d >= 0: maju, d < 0: mundur), diukur sepanjang garis
  # X = x_level (posisi lateral dari titik tengah edge). Hasil: nilai Y batas itu (dari origin) atau nil.
  def self.far_y(loops, origin, u, dir, d, x_level = 0.0)
    ys = crossings(loops, origin, u, dir, false, x_level)
    d >= 0 ? ys.find { |y| y > d + EPS } : ys.reverse.find { |y| y < d - EPS }
  end

  # Offset SATU edge: garis sejajar edge sejauh dist_world, dipotong batas face. Hasil: [ok, pesan_error, group_baru_atau_nil]
  def self.do_offset_edge(model, hit, edge, dist_world, output)
    return [true, nil, nil] if dist_world.abs < EPS

    seg = offset_segment(hit[:loops_active], hit[:origin], hit[:edge_dir_world], hit[:offset_dir_world], dist_world)
    return [true, nil, nil] unless seg # pada jarak ini garis tidak memotong face

    if output == 'newgroup'
      group = model.active_entities.add_group
      group.entities.add_line(seg[0], seg[1])
      [true, nil, group]
    else
      inv = hit[:tr].inverse
      # Garis dibuat di face TARGET (bisa face lain / group lain), bukan di edge acuan
      target = hit[:target_pid] && model.find_entity_by_persistent_id(hit[:target_pid])
      host = target && target.valid? ? target : edge
      host.parent.entities.add_line(inv * seg[0], inv * seg[1])
      [true, nil, nil]
    end
  rescue StandardError => e
    [false, "Gagal: #{e.message}", nil]
  end

  # ── Offset seluruh garis tepi face (ke dalam), seperti Offset bawaan SketchUp ─────────────────────────────────────
  # Perhitungan 2D di bidang face: tiap edge digeser d ke sisi dalam face, lalu titik sudut baru = perpotongan dua
  # garis bersebelahan (sudut runcing / miter). Loop luar mengecil, lubang membesar.

  def self.poly_area(poly)
    sum = 0.0
    poly.each_index do |i|
      a = poly[i]
      b = poly[(i + 1) % poly.size]
      sum += (a[0] * b[1]) - (b[0] * a[1])
    end
    sum / 2.0
  end

  def self.inset_poly(poly, outer, d)
    n = poly.size
    area = poly_area(poly)
    return nil if n < 3 || area.abs < 1e-9

    s = (area.positive? ? 1.0 : -1.0) * (outer ? 1.0 : -1.0)
    lines = []
    poly.each_index do |i|
      a = poly[i]
      b = poly[(i + 1) % n]
      dx = b[0] - a[0]
      dy = b[1] - a[1]
      len = Math.hypot(dx, dy)
      return nil if len < 1e-9

      lines << [[a[0] + (-dy / len * s * d), a[1] + (dx / len * s * d)], [dx / len, dy / len]]
    end
    poly.each_index.map do |i|
      p1, d1 = lines[(i - 1) % n]
      p2, d2 = lines[i]
      cross = (d1[0] * d2[1]) - (d1[1] * d2[0])
      if cross.abs < 1e-9
        p2 # edge bersebelahan lurus: titik awal garis yang sudah digeser
      else
        t = (((p2[0] - p1[0]) * d2[1]) - ((p2[1] - p1[1]) * d2[0])) / cross
        [p1[0] + (d1[0] * t), p1[1] + (d1[1] * t)]
      end
    end
  end

  def self.orient2(a, b, c)
    ((b[0] - a[0]) * (c[1] - a[1])) - ((b[1] - a[1]) * (c[0] - a[0]))
  end

  def self.segs_cross?(a, b, c, d)
    o1 = orient2(a, b, c)
    o2 = orient2(a, b, d)
    o3 = orient2(c, d, a)
    o4 = orient2(c, d, b)
    (o1 * o2 < -1e-9) && (o3 * o4 < -1e-9)
  end

  def self.point_in_poly?(pt, poly)
    inside = false
    poly.each_index do |i|
      a = poly[i]
      b = poly[(i + 1) % poly.size]
      next unless (a[1] > pt[1]) != (b[1] > pt[1])

      inside = !inside if pt[0] < a[0] + ((pt[1] - a[1]) * (b[0] - a[0]) / (b[1] - a[1]))
    end
    inside
  end

  # Hasil offset sah bila: tiap loop tidak terbalik (luas searah, arah edge sama) dan tidak ada edge yang saling
  # memotong (di loop yang sama maupun antar loop).
  def self.valid_inset?(orig, news)
    segs = []
    news.each_with_index do |poly, li|
      return false if poly_area(poly) * poly_area(orig[li]) <= 0
      return false if li.positive? && !point_in_poly?(poly[0], news[0]) # lubang harus tetap di dalam loop luar

      poly.each_index do |i|
        a = poly[i]
        b = poly[(i + 1) % poly.size]
        oa = orig[li][i]
        ob = orig[li][(i + 1) % poly.size]
        return false if (((b[0] - a[0]) * (ob[0] - oa[0])) + ((b[1] - a[1]) * (ob[1] - oa[1]))) <= 0

        segs << [li, i, poly.size, a, b]
      end
    end
    segs.each_index do |i|
      ((i + 1)...segs.size).each do |j|
        l1, i1, n1, a, b = segs[i]
        l2, i2, = segs[j]
        c, dd = segs[j][3], segs[j][4]
        next if l1 == l2 && (((i1 - i2).abs == 1) || ((i1 - i2).abs == n1 - 1))

        return false if segs_cross?(a, b, c, dd)
      end
    end
    true
  end

  def self.loops_to_2d(loops, normal)
    ux, vx = normal.axes
    o = loops[0][0]
    polys = loops.map do |lp|
      lp.map do |pt|
        v = pt - o
        [v.dot(ux), v.dot(vx)]
      end
    end
    [polys, o, ux, vx]
  end

  # Loop-loop face (dunia) digeser ke dalam sejauh d. Hasil: array loop baru (dunia) atau nil bila tidak sah.
  def self.inset_loops(loops, normal, d)
    polys, o, ux, vx = loops_to_2d(loops, normal)
    news = polys.each_with_index.map { |poly, i| inset_poly(poly, i.zero?, d) }
    return nil if news.any?(&:nil?) || !valid_inset?(polys, news)

    news.map do |poly|
      poly.map { |x, y| moved_point(moved_point(o, ux, x), vx, y) }
    end
  end

  # Jarak offset terbesar yang masih menghasilkan bentuk sah (dicari dengan pembagian dua).
  def self.max_inset(loops, normal)
    polys, = loops_to_2d(loops, normal)
    xs = polys[0].map { |pt| pt[0] }
    ys = polys[0].map { |pt| pt[1] }
    hi = [xs.max - xs.min, ys.max - ys.min].min / 2.0
    return 0.0 if hi < EPS
    return hi * 0.999 if inset_loops(loops, normal, hi * 0.999)

    lo = 0.0
    28.times do
      mid = (lo + hi) / 2.0
      if inset_loops(loops, normal, mid)
        lo = mid
      else
        hi = mid
      end
    end
    lo * 0.999
  end

  # Jarak offset ke LUAR terbesar yang masih menghasilkan bentuk sah (dibatasi sebesar ukuran face).
  def self.max_outset(loops, normal)
    polys, = loops_to_2d(loops, normal)
    xs = polys[0].map { |pt| pt[0] }
    ys = polys[0].map { |pt| pt[1] }
    hi = [xs.max - xs.min, ys.max - ys.min].max
    return hi if inset_loops(loops, normal, -hi)

    lo = 0.0
    28.times do
      mid = (lo + hi) / 2.0
      if inset_loops(loops, normal, -mid)
        lo = mid
      else
        hi = mid
      end
    end
    lo * 0.999
  end

  # Offset: seluruh garis tepi face digeser sejauh dist_world (positif = ke dalam, negatif = ke luar), pada face yang dipilih (hit[:loops_active]).
  # Hasil: [ok, pesan_error, group_baru_atau_nil]
  def self.do_offset(model, hit, edge, dist_world, output)
    hit[:all] ? do_offset_all(model, hit, edge, dist_world, output) : do_offset_edge(model, hit, edge, dist_world, output)
  end

  def self.do_offset_all(model, hit, edge, dist_world, output)
    return [true, nil, nil] if dist_world.abs < EPS

    loops = inset_loops(hit[:loops_active], hit[:plane_normal], dist_world)
    return [false, 'Offset terlalu besar untuk bentuk face ini.', nil] unless loops

    if output == 'newgroup'
      [true, nil, nil] # Group baru: offset hanya "virtual" (pratinjau); bentuknya dipakai Push/Pull lanjutan
    else
      inv = hit[:tr].inverse
      ents = edge.parent.entities
      n_local = hit[:plane_normal].transform(inv)
      loops.each_with_index do |lp, i|
        pts = lp.map { |pt| inv * pt }
        # Loop luar jadi FACE (membelah face asal menjadi cincin + face dalam, seperti Offset bawaan). add_edges saja
        # tidak otomatis membentuk face untuk loop yang seluruhnya berada di dalam face lain.
        if i.zero?
          begin
            face = ents.add_face(pts)
            face.reverse! if face && face.normal.dot(n_local) < 0
          rescue ArgumentError
            added = ents.add_edges(pts + [pts[0]])
            added.first.find_faces if added.is_a?(Array) && added.first
          end
        else
          added = ents.add_edges(pts + [pts[0]])
          added.first.find_faces if added.is_a?(Array) && added.first
        end
      end
      [true, nil, nil]
    end
  rescue StandardError => e
    [false, "Gagal: #{e.message}", nil]
  end

  # ── Tool ──────────────────────────────────────────────────────────────────

  class TrowelTool
    def initialize(opts)
      @opts = opts
      @hover = nil
      @drag = nil
      @dist = 0.0
      @op_open = false
    end

    def options=(opts)
      @opts = opts
      end_drag_keeping_result
    end

    # Selesai tanpa membatalkan: kalau sedang di keadaan "jarak sudah diketik", hasilnya dipertahankan (commit);
    # selain itu tarikan yang belum selesai dibatalkan.
    def end_drag_keeping_result
      if @drag && @typed
        finish(Sketchup.active_model.active_view)
      else
        cancel_drag
      end
    end

    # Fungsi ditentukan oleh yang ditunjuk kursor: edge = Offset, face = Push/Pull
    def mode
      hit = @drag || @hover
      hit && hit[:kind] == :edge ? 'offset' : 'pushpull'
    end

    def newgroup?
      @opts['output'] == 'newgroup'
    end

    def activate
      reset
      update_vcb
    end

    def deactivate(view)
      end_drag_keeping_result
      view.invalidate
    end

    def suspend(view)
      view.invalidate
    end

    def resume(view)
      view.invalidate
    end

    def getExtents
      Sketchup.active_model.bounds
    end

    def reset
      @hover = nil
      cancel_drag
    end

    # Batalkan: operasi yang masih terbuka di-abort sehingga model kembali seperti sebelum klik pertama
    def cancel_drag
      if @op_open
        Sketchup.active_model.abort_operation
        @op_open = false
      end
      @drag = nil
      @rim_hot = nil
      @typed = false
      @snap = nil
      @dist = 0.0
      @applied = nil
      @live_group = nil
      @live_error = nil
      Sketchup.vcb_value = ''
    end

    def onCancel(_reason, view)
      if @drag && @typed
        finish(view) # setelah jarak diketik + Enter, Esc = selesai (hasilnya dipertahankan)
        return
      elsif @drag
        back = @drag[:kind] == :edge ? @return_hover : nil
        cancel_drag
        @return_hover = nil
        if back && @last_xy
          @hover = back
          @suppress_switch = true
          begin_drag(view, @last_xy[1])
        end
      else
        @hover = nil
      end
      view.invalidate
    end

    def enableVCB?
      true
    end

    def update_vcb
      Sketchup.vcb_label = mode == 'offset' ? 'Offset' : 'Jarak'
      Sketchup.vcb_value = @drag ? Sketchup.format_length(@dist.abs) : ''
    end

    # ── Picking face (tembus ke dalam group tanpa membukanya) ──

    def pick(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      @hover = nil
      edge = ph.picked_edge
      if edge && edge.valid? && !newgroup? # Hasil group baru: hanya Push/Pull face (tidak ada Offset / edge)
        pick_edge(view, ph, x, y)
      else
        pick_face(ph)
      end
      return unless @hover
      return @hover = nil if @hover[:path].any? { |e| e.respond_to?(:locked?) && e.locked? }
    end

    def pick_context(ph, ent)
      idx = (0...ph.count).find { |i| ph.leaf_at(i) == ent } || 0
      [ph.transformation_at(idx), (ph.path_at(idx) || []).select { |e| BoosokTools::Trowel.container?(e) }]
    end

    # Push/Pull: hanya face
    def pick_face(ph)
      face = ph.picked_face
      return unless face && face.valid?

      tr, path = pick_context(ph, face)
      normal_world = face.normal.transform(tr)
      return if normal_world.length < EPS

      @hover = { kind: :face, face: face, tr: tr, path: path, normal_world: normal_world.normalize,
                 scale: normal_world.length, plane_scale: plane_scale_of(tr) }
    end

    # Offset: hanya edge. Bidang offset = bidang face yang menempel di edge (yang paling menghadap kamera);
    # edge lepas memakai bidang sejajar layar.
    # Offset: cukup edge yang di-hover. SEMUA face yang menempel di edge menjadi pilihan arah (ditandai), face yang
    # dipakai ditentukan nanti oleh arah gerak kursor setelah klik. Edge lepas (tanpa face) tidak bisa di-offset.
    def pick_edge(view, ph, _x, _y)
      edge = ph.picked_edge
      return unless edge && edge.valid?

      tr, path = pick_context(ph, edge)
      @hover = edge_hover(edge, tr, path)
    end

    # Data hover untuk Offset di edge `edge`. Face yang menempel di edge menjadi pilihan; `only_face` membatasi ke satu
    # face saja (dipakai saat beralih dari Push/Pull face itu). Arah offset (dir_world) mengarah ke DALAM face.
    def edge_hover(edge, tr, path, only_face = nil, all = false)
      edir = ((tr * edge.end.position) - (tr * edge.start.position))
      return nil if edir.length < EPS

      edir = edir.normalize
      mid = Geom.linear_combination(0.5, tr * edge.start.position, 0.5, tr * edge.end.position)
      cands = (only_face ? [only_face] : edge.faces).map do |f|
        n = f.normal.transform(tr)
        next nil if n.length < EPS

        n = n.normalize
        dir = n.cross(edir)
        next nil if dir.length < EPS

        dir = dir.normalize
        loops = BoosokTools::Trowel.world_loops(f, tr)
        probe = BoosokTools::Trowel.moved_point(mid, dir, 1e-3)
        dir = dir.reverse unless BoosokTools::Trowel.loops_contain?(loops, mid, edir, dir, probe)
        { face: f, dir_world: dir, dir_local: dir.transform(tr.inverse).normalize, normal_world: n, loops: loops }
      end.compact
      return nil if cands.empty?

      first = cands.first
      { kind: :edge, all: all, edge: edge, edge_dir_world: edir, cands: cands, ref_face: first[:face], tr: tr, path: path,
        plane_scale: plane_scale_of(tr), offset_dir_world: first[:dir_world], offset_dir_local: first[:dir_local] }
    end

    # Setelah klik: face yang dipakai = face (di antara yang menempel di edge) yang ada di bawah kursor, yaitu titik
    # potong sinar kursor dengan bidangnya jatuh di dalam face itu. Kalau tidak ada, face sebelumnya dipertahankan.
    def select_candidate(view, x, y)
      cands = @drag[:cands]
      return if cands.nil? || cands.size < 2

      ray = view.pickray(x, y)
      origin = @drag[:origin]
      u = @drag[:edge_dir_world]
      best = cands.find do |c|
        pt = Geom.intersect_line_plane(ray, [origin, c[:normal_world]])
        pt && BoosokTools::Trowel.loops_contain?(c[:loops], origin, u, c[:dir_world], pt)
      end
      return if best.nil? || best.equal?(@drag[:active])

      activate_candidate(best)
    end

    # Offset SATU edge: face tempat garis diterapkan ditentukan oleh face di bawah kursor. Bisa face yang menempel di
    # edge acuan, face lain (mis. sisi belakang / bawah), bahkan face di group lain. Arah garis = arah edge acuan
    # yang diproyeksikan ke bidang face itu.
    def retarget(view, x, y)
      return select_candidate(view, x, y) if @drag[:all]

      ph = view.pick_helper
      ph.do_pick(x, y)
      face = ph.picked_face
      return unless face && face.valid?

      tr_f, path_f = pick_context(ph, face)
      return if path_f.any? { |e| e.respond_to?(:locked?) && e.locked? }

      nf = face.normal.transform(tr_f)
      return if nf.length < BoosokTools::Trowel::EPS

      nf = nf.normalize
      p0 = tr_f * face.vertices.first.position
      ray = view.pickray(x, y)
      pool = @drag[:cands] + (@drag[:active][:foreign] ? [@drag[:active]] : [])
      known = pool.find do |c|
        next false unless nf.dot(c[:normal_world]).abs > 0.9999 && (p0 - c[:loops][0][0]).dot(c[:normal_world]).abs < 1e-3

        pt = Geom.intersect_line_plane(ray, [c[:loops][0][0], c[:normal_world]])
        ux, vx = c[:normal_world].axes
        pt && BoosokTools::Trowel.loops_contain?(c[:loops], c[:loops][0][0], ux, vx, pt)
      end
      if known
        activate_candidate(known) unless known.equal?(@drag[:active])
        return
      end

      cand = target_cand(face, tr_f, path_f)
      activate_candidate(cand) if cand
    end

    # Face target di luar edge acuan. Titik asal = garis batas face pada sisi terdekat ke edge (jarak 0), dan jarak
    # diukur tegak lurus garis (searah dir_world) dari situ.
    def target_cand(face, tr, path)
      n = face.normal.transform(tr)
      return nil if n.length < BoosokTools::Trowel::EPS

      n = n.normalize
      u = @drag[:ref_dir]
      k = u.dot(n)
      up = Geom::Vector3d.new(u.x - (n.x * k), u.y - (n.y * k), u.z - (n.z * k))
      return nil if up.length < 0.2 # edge acuan hampir tegak lurus bidang face: garis tidak terdefinisi

      up = up.normalize
      dir = n.cross(up).normalize
      loops = BoosokTools::Trowel.world_loops(face, tr)
      ref = loops[0][0]
      ys = loops.flat_map { |lp| lp.map { |pt| (pt - ref).dot(dir) } }
      lo = ys.min
      hi = ys.max
      own = []
      loops[0].each_index do |i|
        own << [loops[0][i], 'Sudut']
        own << [Geom.linear_combination(0.5, loops[0][i], 0.5, loops[0][(i + 1) % loops[0].size]), 'Titik tengah']
      end
      BoosokTools::Trowel.own_snap_points(face.parent.entities, tr, [], own)
      owner = path.last
      { foreign: true, face: face, dir_world: dir, dir_local: dir.transform(tr.inverse).normalize, normal_world: n,
        loops: loops, min: 0.0, max: hi - lo, tr: tr, path: path, parent: face.parent,
        origin: BoosokTools::Trowel.moved_point(ref, dir, lo), edge_dir_world: up, own_pts: own,
        owner_pid: owner && owner.persistent_id, plane_scale: plane_scale_of(tr) }
    end

    # Face target di luar edge acuan: titik asal ikut bergeser sepanjang garis (searah edge) ke bawah kursor, supaya ruas
    # face yang dipotong garis adalah yang ada di bawah kursor. Jarak tegak lurus tidak berubah.
    def shift_origin(view, x, y)
      pt = Geom.intersect_line_plane(view.pickray(x, y), [@drag[:origin], @drag[:plane_normal]])
      return unless pt

      k = (pt - @drag[:origin]).dot(@drag[:edge_dir_world])
      @drag[:origin] = BoosokTools::Trowel.moved_point(@drag[:origin], @drag[:edge_dir_world], k) if k.is_a?(Numeric) && k.finite?
    end

    def activate_candidate(best)
      # Konteks (transformasi, group, titik asal, arah garis) milik face target; face yang menempel di edge acuan memakai
      # konteks asal (@drag[:home])
      ctx = best[:foreign] ? best : @drag[:home]
      @drag[:tr] = ctx[:tr]
      @drag[:path] = ctx[:path]
      @drag[:parent] = ctx[:parent]
      @drag[:origin] = ctx[:origin]
      @drag[:edge_dir_world] = ctx[:edge_dir_world]
      @drag[:own_pts] = ctx[:own_pts]
      @drag[:owner_pid] = ctx[:owner_pid]
      @drag[:plane_scale] = ctx[:plane_scale]
      @drag[:target_pid] = best[:foreign] ? best[:face].persistent_id : nil
      @drag[:active] = best
      @drag[:axis] = best[:dir_world]
      @drag[:offset_dir_world] = best[:dir_world]
      @drag[:offset_dir_local] = best[:dir_local]
      @drag[:ref_face] = best[:face]
      @drag[:plane_normal] = best[:normal_world]
      @drag[:loops_active] = best[:loops]
      @drag[:min_dist] = best[:min]
      @drag[:max_dist] = best[:max]
    end

    def plane_scale_of(tr)
      (tr.xaxis.length + tr.yaxis.length + tr.zaxis.length) / 3.0
    end

    # Kesalahan di callback tool tidak boleh hilang diam-diam: dicetak ke Ruby Console dan ditampilkan sebagai toast
    def onMouseMove(flags, x, y, view)
      handle_mouse_move(flags, x, y, view)
    rescue StandardError => e
      fail_report('onMouseMove', e)
    end

    def onLButtonDown(flags, x, y, view)
      handle_click(flags, x, y, view)
    rescue StandardError => e
      fail_report('onLButtonDown', e)
    end

    def fail_report(where, err)
      puts "[Boosok Trowel] #{where}: #{err.class}: #{err.message}"
      puts err.backtrace.first(4)
      BoosokTools::Trowel.report(false, "Trowel #{where}: #{err.message}", nil)
    end

    def handle_mouse_move(flags, x, y, view)
      @last_xy = [x, y]
      @shift = (flags & CONSTRAIN_MODIFIER_MASK) != 0
      @erase_hover = @shift && !@drag ? erase_target_at(view, x, y) : nil
      if @drag && @typed
        view.invalidate # jarak sudah diketik: gerak mouse tidak mengubahnya
        return
      end

      # Push/Pull berjalan: kursor di tepi face = tepi disorot (klik di situ beralih ke Offset)
      @rim_hot = nil
      if @drag && @drag[:kind] == :face && !@drag[:virtual_loops]
        near = rim_segment_near(view, x, y)
        @suppress_switch = false unless near
        @rim_hot = near unless @suppress_switch
      end

      # Kursor di tepi face (siap klik untuk Offset): tarikan dikembalikan ke 0 dan ditahan, supaya model tidak ikut
      # bergerak / hilang selama kursor berada di tepi.
      if @drag && @rim_hot
        @dist = 0.0
        @snap = nil
        update_live(view, 0.0) if @applied.nil? || @applied.abs > BoosokTools::Trowel::EPS
        view.tooltip = 'Offset'
        update_vcb
        view.invalidate
        return
      end

      if @drag
        retarget(view, x, y) if @drag[:kind] == :edge
        shift_origin(view, x, y) if @drag[:kind] == :edge && @drag[:active][:foreign]
        raw = drag_distance(view, x, y) - (@drag[:raw0] || 0.0)
        # Snap hanya ke SUDUT atau TITIK TENGAH edge dari face yang sedang ditunjuk kursor (milik objek lain)
        result = face_point_snap(view, x, y) || own_point_snap(view, x, y) || [raw, nil]
        @dist = clamp_offset(result[0])
        @snap = result[1]
        view.tooltip = @rim_hot ? 'Offset' : (@snap ? @snap[:label] : '')
        update_live(view, @dist)
        update_vcb
      else
        pick(view, x, y)
      end
      view.invalidate
    end

    RIM_PX = 6 unless defined?(RIM_PX)

    # Saat Push/Pull berjalan: tepi face yang sedang ditarik yang berada dalam RIM_PX piksel dari kursor.
    # Hasil: [jarak, indeks_loop, indeks_edge] atau nil.
    def rim_segment_near(view, x, y)
      best = nil
      @drag[:loops].each_with_index do |lp, li|
        lp.each_index do |i|
          a = view.screen_coords(lp[i])
          b = view.screen_coords(lp[(i + 1) % lp.size])
          dx = b.x - a.x
          dy = b.y - a.y
          len2 = (dx * dx) + (dy * dy)
          t = len2 < 1e-9 ? 0.0 : [[(((x - a.x) * dx) + ((y - a.y) * dy)) / len2, 0.0].max, 1.0].min
          d = Math.hypot(x - (a.x + (t * dx)), y - (a.y + (t * dy)))
          best = [d, li, i] if d <= RIM_PX && (best.nil? || d < best[0])
        end
      end
      best
    end

    # Push/Pull -> Offset: tepi face yang sedang ditarik diklik. Tarikan live dibatalkan, lalu seluruh
    # garis tepi face itu di-offset (ke dalam atau ke luar mengikuti kursor). Esc di Offset kembali ke Push/Pull face itu.
    def switch_to_offset(view, x, y, li, i)
      hit = @drag
      lp = hit[:loops][li]
      seg = [lp[i], lp[(i + 1) % lp.size]]
      tr = hit[:tr]
      path = hit[:path]
      pid = hit[:pid]
      cancel_drag
      face = Sketchup.active_model.find_entity_by_persistent_id(pid)
      return unless face && face.valid?

      edge = face.edges.find do |e|
        p1 = tr * e.start.position
        p2 = tr * e.end.position
        (p1.distance(seg[0]) < 1e-3 && p2.distance(seg[1]) < 1e-3) || (p1.distance(seg[1]) < 1e-3 && p2.distance(seg[0]) < 1e-3)
      end
      return unless edge

      n = face.normal.transform(tr)
      @return_hover = { kind: :face, face: face, tr: tr, path: path, normal_world: n.normalize, scale: n.length,
                        plane_scale: plane_scale_of(tr) }
      @hover = edge_hover(edge, tr, path, face, true) # dari Push/Pull: offset SEMUA garis tepi face
      return unless @hover

      begin_drag(view, y, x)
      onMouseMove(0, x, y, view)
    end

    def view_normal(view, hit)
      hit[:normal_world].dot(view.camera.direction) > 0 ? hit[:normal_world].reverse : hit[:normal_world]
    end

    # Jarak bertanda dari posisi mouse: Push/Pull = sepanjang normal face; Offset = sepanjang arah offset edge.
    # Titik asal dan arah dihitung sekali saat klik pertama (geometri berubah selama live).
    def drag_distance(view, x, y)
      origin = @drag[:origin]
      axis = @drag[:axis]
      ray = view.pickray(x, y)
      if @drag[:kind] == :edge && @drag[:plane_normal]
        # Offset: titik di bawah kursor pada bidang face (bukan titik terdekat ke garis), supaya garis offset tepat
        # berada di titik kursor dari sudut pandang mana pun.
        pt = Geom.intersect_line_plane(ray, [origin, @drag[:plane_normal]])
        if pt
          d = (pt - origin).dot(axis)
          return d if d.is_a?(Numeric) && d.finite?
        end
      end
      closest = Geom.closest_points([origin, axis], ray)
      if closest && ray[1].cross(axis).length > 1e-4
        (closest[0] - origin).dot(axis)
      else
        # Pandangan sejajar sumbu: pakai gerak vertikal mouse
        (@drag_y - y) * view.pixels_to_model(1, origin)
      end
    end

    # Face di bawah kursor milik objek lain (bukan objek yang sedang ditarik)? Mengembalikan [face, transformasi] atau nil.
    def foreign_face(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      face = ph.picked_face
      return nil unless face && face.valid?

      idx = (0...ph.count).find { |i| ph.leaf_at(i) == face } || 0
      path = (ph.path_at(idx) || []).select { |e| BoosokTools::Trowel.container?(e) }
      innermost = @drag[:path].last
      return nil if innermost && path.include?(innermost)
      return nil if @drag[:parent] && face.parent == @drag[:parent]

      [face, ph.transformation_at(idx)]
    rescue StandardError
      nil
    end

    # Snap ke sudut / titik tengah face di dalam group SENDIRI (Push/Pull maupun Offset). Titik-titiknya diambil dari
    # snapshot geometri asli di awal tarikan, supaya tidak ikut bergerak saat live. Titik yang jaraknya 0 dilewati.
    def own_point_snap(view, x, y)
      best = (@drag[:own_pts] || []).map do |pt, label|
        sp = view.screen_coords(pt)
        [Math.hypot(sp.x - x, sp.y - y), pt, label]
      end.min_by(&:first)
      return nil unless best && best[0] <= BoosokTools::Trowel::SNAP_PX

      d = (best[1] - @drag[:origin]).dot(@drag[:axis])
      return nil unless d.is_a?(Numeric) && d.finite? && d.abs > BoosokTools::Trowel::EPS

      [d, { point: best[1], label: best[2] }]
    end

    # Snap ke sudut (corner) atau titik tengah (mid) edge dari face yang ditunjuk kursor, kalau kursor berada dalam
    # SNAP_PX piksel dari titik itu. Hasil: [jarak, {point:, label:}] atau nil. Hanya titik yang ditandai (tanpa sorot
    # group/edge/face), supaya tampilan tetap bersih.
    def face_point_snap(view, x, y)

      face, tr = foreign_face(view, x, y)
      return nil unless face

      pts = face.outer_loop.vertices.map { |v| tr * v.position }
      cands = pts.map { |pt| [pt, 'Sudut'] }
      pts.each_index { |i| cands << [Geom.linear_combination(0.5, pts[i], 0.5, pts[(i + 1) % pts.size]), 'Titik tengah'] }
      best = cands.map do |pt, label|
        sp = view.screen_coords(pt)
        [Math.hypot(sp.x - x, sp.y - y), pt, label]
      end.min_by(&:first)
      return nil unless best && best[0] <= BoosokTools::Trowel::SNAP_PX

      d = (best[1] - @drag[:origin]).dot(@drag[:axis])
      return nil unless d.is_a?(Numeric) && d.finite?

      [d, { point: best[1], label: best[2] }]
    end

    # Offset hanya boleh ke dalam face: 0 .. jarak terjauh yang masih di dalam face. Mengarah keluar face tidak dibolehkan.
    def clamp_offset(dist)
      return dist unless @drag && @drag[:kind] == :edge

      clamped = [[dist, @drag[:min_dist]].max, @drag[:max_dist]].min
      Sketchup.status_text = 'Trowel: offset terbatas sampai bentuk face masih sah' if clamped != dist
      clamped
    end

    def begin_drag(view, y, x = nil)
      x ||= @last_xy && @last_xy[0]
      hit = @hover
      if hit[:kind] == :edge
        origin = Geom.linear_combination(0.5, hit[:tr] * hit[:edge].start.position, 0.5, hit[:tr] * hit[:edge].end.position)
        cands = hit[:cands].map do |c|
          c = c.merge(face_pid: c[:face].persistent_id)
          if hit[:all]
            c.merge(min: -BoosokTools::Trowel.max_outset(c[:loops], c[:normal_world]),
                    max: BoosokTools::Trowel.max_inset(c[:loops], c[:normal_world]))
          else
            lo, hi = BoosokTools::Trowel.loops_range(c[:loops], origin, c[:dir_world])
            c.merge(min: lo, max: hi)
          end
        end
        own = []
        cands.each do |c|
          pts = c[:loops][0]
          pts.each_index do |i|
            own << [pts[i], 'Sudut']
            own << [Geom.linear_combination(0.5, pts[i], 0.5, pts[(i + 1) % pts.size]), 'Titik tengah']
          end
        end
        BoosokTools::Trowel.own_snap_points(hit[:edge].parent.entities, hit[:tr], [], own)
        first = cands.first
        @drag = hit.merge(own_pts: own, pid: hit[:edge].persistent_id, origin: origin, cands: cands, active: first, axis: first[:dir_world],
                          offset_dir_world: first[:dir_world], offset_dir_local: first[:dir_local], ref_face: first[:face],
                          plane_normal: first[:normal_world], loops_active: first[:loops], min_dist: first[:min], max_dist: first[:max],
                          owner_pid: hit[:path].last && hit[:path].last.persistent_id,
                          was_solid: !!(hit[:path].last && BoosokTools::Void.solid?(hit[:path].last)))
      else
        loops = hit[:virtual_loops] || BoosokTools::Trowel.world_loops(hit[:face], hit[:tr])
        loops = [loops[0]] if hit[:fill] # cincin hasil Offset ke luar: tarik seluruh area di dalam garis offset
        origin = BoosokTools::Trowel.centroid(loops[0])
        owner = hit[:path].last
        own = BoosokTools::Trowel.own_snap_points(hit[:face].parent.entities, hit[:tr], [hit[:face]])
        @drag = hit.merge(own_pts: own, pid: hit[:face].persistent_id, loops: loops, origin: origin, axis: view_normal(view, hit),
                          owner_pid: owner && owner.persistent_id,
                          was_solid: hit.key?(:was_solid) ? hit[:was_solid] : !!(owner && BoosokTools::Void.solid?(owner)),
                          other_box: BoosokTools::Trowel.other_shells_box(hit[:face], hit[:tr]))
      end
      @drag[:parent] = (hit[:face] || hit[:ref_face] || hit[:edge]).parent
      if @drag[:kind] == :edge
        @drag[:ref_dir] = @drag[:edge_dir_world]
        @drag[:home] = { tr: @drag[:tr], path: @drag[:path], parent: @drag[:parent], origin: @drag[:origin],
                         edge_dir_world: @drag[:edge_dir_world], own_pts: @drag[:own_pts], owner_pid: @drag[:owner_pid],
                         plane_scale: @drag[:plane_scale] }
      end
      @drag_y = y
      # Push/Pull dimulai dari jarak 0 di titik klik dan mengikuti GERAKAN kursor (selisih), bukan posisi mutlaknya;
      # posisi mutlak hanya dipakai saat kursor snap ke titik.
      @drag[:raw0] = @drag[:kind] == :face && x ? drag_distance(view, x, y) : 0.0
      @dist = 0.0
      @applied = 0.0 # jarak yang sudah diterapkan ke model (untuk Push/Pull inkremental)
      @snap = nil
      Sketchup.active_model.start_operation(mode == 'offset' ? 'Trowel Offset' : 'Trowel Push/Pull', true)
      @op_open = true
      update_vcb
    end

    # LIVE. Push/Pull dalam group: inkremental (face cukup digeser selisih jaraknya) → ringan dan mulus. Group baru:
    # group lama dihapus lalu dibuat ulang. Offset: kembali ke keadaan awal (abort) lalu terapkan ulang, karena garis
    # offset yang menyentuh tepi face memecah face sehingga tidak aman dihapus satu per satu.
    def update_live(view, dist_view)
      return if @drag[:kind] == :face && @drag[:fill] && @opts['output'] != 'newgroup' # pratinjau digambar, hasil dibuat saat selesai
      return update_live_scratch(dist_view) if mode == 'offset'

      # Group: SketchUp tidak menggambar ulang isi group saat definition-nya diubah lewat API di tengah operasi yang
      # terbuka (hanya kotak pembatasnya yang bergerak). Jalur abort + terapkan ulang memaksa tampilan diperbarui.
      # Component dan geometri lepas memakai jalur inkremental yang ringan.
      return update_live_scratch(dist_view) if @drag[:path].any? { |e| e.is_a?(Sketchup::Group) }

      model = Sketchup.active_model
      sign = @drag[:axis].dot(@drag[:normal_world]) >= 0 ? 1.0 : -1.0
      face = model.find_entity_by_persistent_id(@drag[:pid])
      if @opts['output'] == 'newgroup'
        @live_group.erase! if @live_group && @live_group.valid?
        @live_group = nil
        @live_error = nil
        return @live_error = 'Objek tidak ditemukan lagi.' unless face && face.valid?

        ok, err, @live_group = BoosokTools::Trowel.do_pushpull(model, @drag, face, dist_view * sign, 'newgroup')
        @live_error = err unless ok
        return
      end

      if face && face.valid? && @applied
        begin
          delta = (dist_view - @applied) * sign
          face.pushpull(delta / @drag[:scale]) if delta.abs > BoosokTools::Trowel::EPS
          @applied = dist_view
          @live_error = nil
          return
        rescue StandardError
          # jatuh ke jalur penuh di bawah
        end
      end
      update_live_scratch(dist_view)
    end

    # Jalur penuh: kembalikan model ke keadaan sebelum klik pertama (abort), lalu terapkan jarak sekarang dari nol.
    # Entity dicari ulang lewat persistent_id karena abort bisa mengganti objek Ruby-nya.
    def update_live_scratch(dist_view)
      model = Sketchup.active_model
      model.abort_operation if @op_open
      model.start_operation(mode == 'offset' ? 'Trowel Offset' : 'Trowel Push/Pull', true)
      @op_open = true
      @live_group = nil
      @live_error = nil
      ent = model.find_entity_by_persistent_id(@drag[:pid])
      unless ent && ent.valid?
        @live_error = 'Objek tidak ditemukan lagi.'
        return
      end

      ok, err, group =
        if mode == 'offset'
          BoosokTools::Trowel.do_offset(model, @drag, ent, dist_view, @opts['output'])
        else
          sign = @drag[:axis].dot(@drag[:normal_world]) >= 0 ? 1.0 : -1.0
          BoosokTools::Trowel.do_pushpull(model, @drag, ent, dist_view * sign, @opts['output'])
        end
      @live_group = group
      @applied = ok ? dist_view : nil
      @live_error = err unless ok
      Sketchup.status_text = err.to_s unless ok
    end

    # Enter tanpa angka: menyelesaikan hasil yang sudah diketik
    def onReturn(view)
      finish(view) if @drag && @typed
    end

    # Shift + klik pada edge = hapus edge (hanya edge di dalam face; edge sudut ditolak)
    def erase_edge_click(view, x, y)
      target = erase_target_at(view, x, y)
      return unless target

      unless target[:ok]
        BoosokTools::Trowel.report(false, 'Edge sudut / tepi bentuk tidak bisa dihapus (merusak group). Hanya edge di dalam face.', nil)
        return
      end

      model = Sketchup.active_model
      model.start_operation('Trowel Hapus Edge', true)
      begin
        target[:edges].each { |e| e.erase! if e.valid? }
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        BoosokTools::Trowel.report(false, "Gagal menghapus edge: #{e.message}", nil)
      end
      @erase_hover = nil
      @hover = nil
    end

    # Edge di bawah kursor (boleh di dalam group) untuk dihapus. Hasil: {edge:, tr:, ok:} atau nil.
    def erase_target_at(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      edge = ph.picked_edge
      return nil unless edge && edge.valid?

      tr, path = pick_context(ph, edge)
      return nil if path.any? { |e| e.respond_to?(:locked?) && e.locked? }

      ok = BoosokTools::Trowel.edge_erasable?(edge)
      { edge: edge, edges: ok ? BoosokTools::Trowel.erasable_chain(edge) : [edge], tr: tr, ok: ok }
    rescue StandardError
      nil
    end

    def onKeyDown(key, _repeat, _flags, view)
      refresh_erase_hover(view, true) if key == CONSTRAIN_MODIFIER_KEY
    end

    def onKeyUp(key, _repeat, _flags, view)
      refresh_erase_hover(view, false) if key == CONSTRAIN_MODIFIER_KEY
    end

    def refresh_erase_hover(view, on)
      @shift = on
      @erase_hover = on && !@drag && @last_xy ? erase_target_at(view, @last_xy[0], @last_xy[1]) : nil
      view.invalidate
    end

    def handle_click(flags, x, y, view)
      if !@drag && (flags & CONSTRAIN_MODIFIER_MASK) != 0
        erase_edge_click(view, x, y)
      elsif @drag && @drag[:kind] == :face && !@typed && !@drag[:virtual_loops] && !@suppress_switch && (near = rim_segment_near(view, x, y))
        switch_to_offset(view, x, y, near[1], near[2]) # klik di tepi face yang sedang ditarik = Offset
      elsif @drag
        finish(view)
      elsif @hover
        begin_drag(view, y, x)
      end
      view.invalidate
    end

    # Ketik angka lalu Enter: jarak persis; tanda mengikuti arah gerak mouse (angka negatif membalik arah)
    def onUserText(text, view)
      return unless @drag

      value = text.to_l
      sign = @dist.negative? ? -1.0 : 1.0
      @dist = value.abs * sign * (value.negative? ? -1.0 : 1.0)
      @snap = nil
      @dist = clamp_offset(@dist)
      # Hasil langsung diterapkan, tetapi operasi dibiarkan terbuka: mengetik jarak lain + Enter menggantikan hasil
      # sebelumnya (dihitung dari edge/face awal), seperti Offset bawaan. Klik, Enter kosong, atau Esc menyelesaikan.
      update_live(view, @dist)
      @typed = true
      update_vcb
      view.invalidate
    rescue ArgumentError
      Sketchup.status_text = 'Trowel: angka tidak valid'
    end

    # Objek yang diubah adalah hasil Void? Push/Pull dalam group disalin ke sumbernya (:synced); selain itu (Offset, atau
    # face tidak ditemukan di sumber) hasil dilepas dari Void agar perubahannya tidak hilang (:void). nil = bukan hasil Void.
    def sync_with_void(model, hit)
      return nil if @opts['output'] == 'newgroup'

      owner = model.find_entity_by_persistent_id(hit[:owner_pid])
      return nil unless BoosokTools::Trowel.void_result?(owner)

      if hit[:kind] == :face
        sign = hit[:axis].dot(hit[:normal_world]) >= 0 ? 1.0 : -1.0
        return :synced if BoosokTools::Trowel.sync_void_source(hit, owner, @dist * sign)
      end
      BoosokTools::Trowel.detach_void(model, owner)
      :void
    end

    # Klik kedua / Enter: hasil live dijadikan permanen (satu langkah Undo)
    # Group asalnya solid: batalkan hasil face.pushpull biasa dan ulangi dengan operasi solid (union / subtract), supaya
    # tarikan yang menembus / menyentuh bagian lain di group yang sama (juga bagian yang tersambung, mis. sisi lain
    # bentuk L) menyatu jadi satu solid bersih tanpa permukaan sisa. Hasil true = operasi solid berhasil; kalau gagal,
    # Push/Pull biasa dipertahankan.
    def keep_group_solid(model)
      hit = @drag
      return unless hit[:kind] == :face && @opts['output'] != 'newgroup' && hit[:was_solid]

      owner = model.find_entity_by_persistent_id(hit[:owner_pid])
      return unless owner && owner.valid?

      sign = hit[:axis].dot(hit[:normal_world]) >= 0 ? 1.0 : -1.0
      model.abort_operation
      model.start_operation('Trowel Push/Pull', true)
      owner = model.find_entity_by_persistent_id(hit[:owner_pid])
      face = model.find_entity_by_persistent_id(hit[:pid])
      return unless owner && face && owner.valid? && face.valid?

      # Offset ke luar: yang ditarik seluruh area di dalam garis offset (bukan hanya cincinnya). Cincin sisa Offset
      # dihapus dulu supaya group kembali solid, lalu balok seluruh area di-union.
      solid_face = face
      if hit[:fill]
        ring_edges = face.edges
        face.erase!
        ring_edges.each { |e| e.erase! if e.valid? && e.faces.empty? } # garis sisa cincin yang tidak dipakai face lain
        solid_face = nil
      end
      return true if BoosokTools::Trowel.solid_pushpull(model, hit, owner, solid_face, @dist * sign)

      puts '[Boosok Trowel] keep_group_solid: operasi solid gagal, memakai Push/Pull biasa'
      # Gagal: kembali ke hasil Push/Pull biasa
      model.abort_operation
      model.start_operation('Trowel Push/Pull', true)
      face = model.find_entity_by_persistent_id(hit[:pid])
      face.pushpull((@dist * sign) / hit[:scale]) if face && face.valid?
      false
    end

    def finish(view)
      hit = @drag
      model = Sketchup.active_model
      if @live_error || @dist.abs < BoosokTools::Trowel::EPS
        err = @live_error || 'Jarak terlalu kecil.'
        cancel_drag
        @hover = nil
        BoosokTools::Trowel.report(false, err, hit)
      else
        if @live_group && @live_group.valid?
          model.selection.clear
          model.selection.add(@live_group)
        end
        synced = sync_with_void(model, hit)
        solid = synced ? false : keep_group_solid(model)
        BoosokTools::Trowel.merge_coplanar_edges(model, hit) if !solid && hit[:kind] == :face && @opts['output'] != 'newgroup'
        model.commit_operation
        @op_open = false
        dist = @dist
        cancel_drag
        @hover = nil
        @return_hover = nil
        chain_push(view, hit, dist)
        # Sumber sudah diperbarui: bangun ulang hasil dari sumber (lubang mengikuti void, ukuran baru dipertahankan)
        if synced == :synced && BoosokTools::Void.live?(model) && BoosokTools::Void.licensed?
          begin
            BoosokTools::Void.run_rebuild(model, 'Update Void', true)
          rescue StandardError => e
            puts "[Boosok Trowel] update void: #{e.class}: #{e.message}"
          end
        end
        BoosokTools::Trowel.report(true, nil, hit)
      end
      view.invalidate
    end

    # Setelah Offset selesai, langsung lanjut Push/Pull pada face di dalam garis offset (Esc membatalkan Push/Pull saja,
    # hasil Offset tetap). Tidak untuk hasil group baru (tidak ada face).
    def chain_push(view, hit, dist)
      return unless hit[:kind] == :edge && hit[:all]

      return chain_push_newgroup(view, hit, dist) if @opts['output'] == 'newgroup'

      loops = BoosokTools::Trowel.inset_loops(hit[:loops_active], hit[:plane_normal], dist)
      unless loops
        puts "[Boosok Trowel] chain_push: bentuk offset tidak sah (jarak #{dist})"
        BoosokTools::Trowel.report(false, 'Lanjut Push/Pull gagal: bentuk offset tidak sah.', hit)
        return
      end

      face, info = BoosokTools::Trowel.find_inner_face(hit, loops, dist)
      unless face
        puts "[Boosok Trowel] chain_push: face hasil offset tidak ditemukan (#{info})"
        BoosokTools::Trowel.report(false, "Lanjut Push/Pull gagal: face di dalam offset tidak ditemukan (#{info}).", hit)
        return
      end

      n = face.normal.transform(hit[:tr])
      return if n.length < BoosokTools::Trowel::EPS

      x, y = @last_xy || [view.vpwidth / 2, view.vpheight / 2]
      @hover = { kind: :face, face: face, tr: hit[:tr], path: hit[:path], normal_world: n.normalize, scale: n.length,
                 plane_scale: hit[:plane_scale], was_solid: hit[:was_solid], fill: dist.negative? && hit[:was_solid] }
      @suppress_switch = true # kursor masih di garis offset: jangan langsung beralih ke Offset lagi
      begin_drag(view, y, x)
    rescue StandardError => e
      puts "[Boosok Trowel] chain_push: #{e.class}: #{e.message}"
      BoosokTools::Trowel.report(false, "Lanjut Push/Pull gagal: #{e.message}", hit)
      @hover = nil
    end

    # Hasil Group baru: bentuk hasil Offset (virtual, belum ada di model) langsung ditarik menjadi group baru.
    def chain_push_newgroup(view, hit, dist)
      loops = BoosokTools::Trowel.inset_loops(hit[:loops_active], hit[:plane_normal], dist)
      return unless loops

      face = Sketchup.active_model.find_entity_by_persistent_id(hit[:active][:face_pid])
      return unless face && face.valid?

      n = face.normal.transform(hit[:tr])
      x, y = @last_xy || [view.vpwidth / 2, view.vpheight / 2]
      @hover = { kind: :face, face: face, tr: hit[:tr], path: hit[:path], normal_world: hit[:plane_normal], scale: n.length,
                 plane_scale: hit[:plane_scale], was_solid: false, virtual_loops: loops }
      begin_drag(view, y, x)
    rescue StandardError => e
      puts "[Boosok Trowel] chain_push_newgroup: #{e.class}: #{e.message}"
      BoosokTools::Trowel.report(false, "Lanjut Push/Pull gagal: #{e.message}", hit)
      @hover = nil
    end

    # ── Gambar ──

    def draw_face(view, hit, fill, line)
      mesh = hit[:face].mesh(0)
      tris = []
      mesh.polygons.each do |poly|
        pts = poly.map { |i| hit[:tr] * mesh.point_at(i.abs) }
        (1...(pts.size - 1)).each { |k| tris.push(pts[0], pts[k], pts[k + 1]) }
      end
      view.drawing_color = fill
      view.draw(GL_TRIANGLES, tris) unless tris.empty?
      view.drawing_color = line
      view.line_width = 2
      view.draw(GL_LINE_LOOP, hit[:face].outer_loop.vertices.map { |v| hit[:tr] * v.position })
    end

    # Pratinjau balok untuk Push/Pull "isi" (geometri asli belum diubah): sisi-sisi transparan + garis tepi
    def draw_fill_preview(view)
      return unless @drag && @drag[:kind] == :face && @drag[:fill] && @dist.abs > BoosokTools::Trowel::EPS

      tr = BoosokTools::Trowel
      base = @drag[:loops][0]
      top = base.map { |pt| tr.moved_point(pt, @drag[:axis], @dist) }
      green = Sketchup::Color.new(0, 200, 100)
      quads = []
      base.each_index do |i|
        j = (i + 1) % base.size
        quads.push(base[i], base[j], top[j], top[i])
      end
      view.drawing_color = Sketchup::Color.new(0, 200, 100, 50)
      view.draw(GL_QUADS, quads)
      view.drawing_color = green
      view.line_width = 2
      view.draw(GL_LINE_LOOP, top)
      view.draw(GL_LINES, base.each_index.flat_map { |i| [base[i], top[i]] })
    rescue StandardError => e
      puts "[Boosok Trowel] draw_fill_preview: #{e.class}: #{e.message}"
    end

    # Hasil Group baru: bentuk hasil Offset belum ada di model, jadi digambar sebagai garis biru
    def draw_offset_preview(view)
      hit = @drag
      return unless hit && hit[:kind] == :edge && hit[:all] && newgroup? && @dist.abs > BoosokTools::Trowel::EPS

      loops = BoosokTools::Trowel.inset_loops(hit[:loops_active], hit[:plane_normal], @dist)
      return unless loops

      view.drawing_color = Sketchup::Color.new(0, 90, 220)
      view.line_width = 3
      loops.each { |lp| view.draw(GL_LINE_LOOP, lp) }
    end

    # Push/Pull: kursor di tepi face = seluruh garis tepi face disorot (klik untuk Offset)
    def draw_rim_hot(view)
      return unless @drag && @drag[:kind] == :face && @rim_hot

      view.drawing_color = Sketchup::Color.new(0, 200, 100)
      view.line_width = 4
      @drag[:loops].each { |lp| view.draw(GL_LINE_LOOP, lp) }
    end

    # Offset: satu edge yang di-hover disorot (seluruh garis tepi face bila berasal dari Push/Pull)
    def draw_edge(view, hit, color)
      view.drawing_color = color
      view.line_width = 4
      if hit[:all]
        hit[:cands].first[:loops].each { |lp| view.draw(GL_LINE_LOOP, lp) }
      else
        view.draw(GL_LINES, [hit[:tr] * hit[:edge].start.position, hit[:tr] * hit[:edge].end.position])
      end
    end

    # Push/Pull: garis ukur hijau dari titik tengah face ke posisi tarikan, dengan label jaraknya
    def draw_pushpull_dim(view)
      hit = @drag
      return unless hit && hit[:kind] != :edge && @dist.abs > BoosokTools::Trowel::EPS

      tr = BoosokTools::Trowel
      origin = hit[:origin]
      to = tr.moved_point(origin, hit[:axis], @dist)
      green = Sketchup::Color.new(0, 170, 90)
      view.line_width = 1
      view.line_stipple = '-'
      view.drawing_color = green
      view.draw(GL_LINES, [origin, to])
      view.line_stipple = ''
      view.draw_points([origin, to], 8, 2, green)
      draw_label(view, Geom.linear_combination(0.5, origin, 0.5, to), Sketchup.format_length(@dist.abs), green)
    rescue StandardError => e
      puts "[Boosok Trowel] draw_pushpull_dim: #{e.class}: #{e.message}"
    end

    # Label kecil berbingkai di titik 3D `pt`
    def draw_label(view, pt, text, color)
      sp = view.screen_coords(pt)
      w = BoosokTools::Slice.hud_width(view, text, 11, true) + 12
      x = sp.x - (w / 2.0)
      y = sp.y - 11
      box = [[x, y], [x + w, y], [x + w, y + 22], [x, y + 22]].map { |a, b| Geom::Point3d.new(a, b, 0) }
      view.drawing_color = Sketchup::Color.new(255, 255, 255)
      view.draw2d(GL_QUADS, box)
      view.drawing_color = color
      view.line_width = 1
      view.draw2d(GL_LINE_LOOP, box)
      view.draw_text(Geom::Point3d.new(x + 6, y + 4, 0), text, color: color, size: 11, bold: true)
    end

    # Offset SATU edge: dua garis ukur hijau, jarak edge asal ke garis offset dan sisa jarak ke batas face di seberang
    def draw_dims_edge(view)
      hit = @drag
      tr = BoosokTools::Trowel
      origin = hit[:origin]
      u = hit[:edge_dir_world]
      dir = hit[:offset_dir_world]
      seg = tr.offset_segment(hit[:loops_active], origin, u, dir, @dist)
      return unless seg

      p_off = tr.moved_point(origin, dir, @dist)
      # Garis ukur kedua diukur di tengah garis offset yang terbentuk, karena di posisi edge asal face bisa saja tidak
      # ada di sisi itu (mis. takik berbentuk L)
      x_mid = (((seg[0] - origin).dot(u)) + ((seg[1] - origin).dot(u))) / 2.0
      base = tr.moved_point(origin, u, x_mid)
      from = tr.moved_point(base, dir, @dist)
      far = tr.far_y(hit[:loops_active], origin, u, dir, @dist, x_mid)
      p_far = far ? tr.moved_point(base, dir, far) : nil
      green = Sketchup::Color.new(0, 170, 90)
      view.line_width = 1
      view.line_stipple = '-'
      view.drawing_color = green
      view.draw(GL_LINES, [origin, p_off])
      view.draw(GL_LINES, [from, p_far]) if p_far
      view.line_stipple = ''
      points = [origin]
      points << p_far if p_far
      view.draw_points(points, 8, 2, green)
      draw_label(view, Geom.linear_combination(0.5, origin, 0.5, p_off), Sketchup.format_length(@dist.abs), green)
      draw_label(view, Geom.linear_combination(0.5, from, 0.5, p_far), Sketchup.format_length((far - @dist).abs), green) if p_far
    end

    # Offset: garis ukur hijau dari titik tengah edge asal ke garis offset, dengan label jaraknya
    def draw_dims(view)
      hit = @drag
      return unless hit && hit[:kind] == :edge && @dist.abs > BoosokTools::Trowel::EPS
      return draw_dims_edge(view) unless hit[:all]

      origin = hit[:origin]
      p_off = BoosokTools::Trowel.moved_point(origin, hit[:offset_dir_world], @dist)
      green = Sketchup::Color.new(0, 170, 90)
      view.line_width = 1
      view.line_stipple = '-'
      view.drawing_color = green
      view.draw(GL_LINES, [origin, p_off])
      view.line_stipple = ''
      view.draw_points([origin, p_off], 8, 2, green)
      draw_label(view, Geom.linear_combination(0.5, origin, 0.5, p_off), Sketchup.format_length(@dist.abs), green)
    rescue StandardError => e
      puts "[Boosok Trowel] draw_dims: #{e.class}: #{e.message}"
    end

    # Kotak pembatas group/component yang sedang diubah: sedikit lebih besar dari group-nya, garis putus-putus hijau
    def draw_group_box(view, hit)
      inst = hit[:path].last
      return unless inst && inst.valid?

      bb = inst.definition.bounds
      return if bb.empty?

      center = hit[:tr] * bb.center
      pad = view.pixels_to_model(8, center) / [hit[:plane_scale], 1e-6].max
      lo = bb.min
      hi = bb.max
      xs = [lo.x - pad, hi.x + pad]
      ys = [lo.y - pad, hi.y + pad]
      zs = [lo.z - pad, hi.z + pad]
      corners = (0..7).map { |i| hit[:tr] * Geom::Point3d.new(xs[i & 1], ys[(i >> 1) & 1], zs[(i >> 2) & 1]) }
      lines = []
      (0..7).each do |i|
        [1, 2, 4].each do |bit|
          j = i | bit
          lines.push(corners[i], corners[j]) if j > i
        end
      end
      view.drawing_color = Sketchup::Color.new(0, 200, 100)
      view.line_width = 2
      view.line_stipple = '-'
      view.draw(GL_LINES, lines)
      view.line_stipple = ''
    end

    # Penanda snap: hanya titik pada sudut / titik tengah yang jadi tujuan (tanpa menyorot group atau face lain)
    def draw_snap(view)
      return unless @snap && @drag

      pt = @snap[:point]
      view.draw_points([pt], 14, 2, Sketchup::Color.new(255, 255, 255))
      view.draw_points([pt], 9, 2, Sketchup::Color.new(0, 200, 100))
    rescue StandardError => e
      puts "[Boosok Trowel] draw_snap: #{e.class}: #{e.message}"
    end

    def hud_lines
      sl = BoosokTools::Trowel
      if @drag && @typed
        [sl.loc('trowel_hud_typed', 'Ketik jarak lain + Enter untuk mengubah | Klik atau Enter kosong untuk selesai'), sl.loc('trowel_hud_typed_esc', 'Esc: selesai')]
      elsif @drag && @drag[:kind] != :edge
        [sl.loc('trowel_hud_drag_pp', 'Gerakkan mouse atau ketik jarak + Enter | Klik tepi face = Offset | Klik untuk menerapkan'),
         sl.loc('trowel_hud_esc', 'Esc: batal')]
      elsif @drag && !@drag[:all]
        [sl.loc('trowel_hud_drag_edge', 'Garis offset: arahkan ke face mana pun (boleh group lain) | Gerakkan mouse atau ketik jarak + Enter | Klik untuk menerapkan'),
         sl.loc('trowel_hud_esc_offset', 'Esc: batal Offset')]
      elsif @drag
        [sl.loc('trowel_hud_drag_offset', 'Offset ke dalam / luar: gerakkan mouse atau ketik jarak + Enter | Klik lalu lanjut Push/Pull'),
         sl.loc('trowel_hud_esc_offset', 'Esc: batal Offset')]
      elsif @hover
        [sl.loc(mode == 'offset' ? 'trowel_hud_hover_offset' : 'trowel_hud_hover_pp', 'Klik untuk mulai'),
         newgroup? ? sl.loc('trowel_hud_new', 'Hasil: group baru') : sl.loc('trowel_hud_in', 'Hasil: langsung di dalam group')]
      elsif newgroup?
        [sl.loc('trowel_hud_find_new', 'Arahkan ke face (Push/Pull), boleh di dalam group, lalu klik'), sl.loc('trowel_hud_esc', 'Esc: batal')]
      else
        [sl.loc('trowel_hud_find', 'Arahkan ke face (Push/Pull) atau edge (Offset), boleh di dalam group, lalu klik'), sl.loc('trowel_hud_esc', 'Esc: batal')]
      end
    end

    def draw(view)
      if @erase_hover && !@drag
        sl = BoosokTools::Trowel
        lines = if @erase_hover[:ok]
                  ["#{sl.loc('trowel_hud_erase', 'Shift + klik: hapus edge ini (face yang bersebelahan menyatu)')} [#{@erase_hover[:edges].size}]", sl.loc('trowel_hud_esc', 'Esc: batal')]
                else
                  [sl.loc('trowel_hud_erase_no', 'Edge sudut / tepi bentuk tidak bisa dihapus (merusak group)'), sl.loc('trowel_hud_esc', 'Esc: batal')]
                end
        BoosokTools::Slice.draw_hud(view, sl.loc('trowel_hud_title_erase', 'TROWEL — HAPUS EDGE'), lines)
        view.drawing_color = @erase_hover[:ok] ? Sketchup::Color.new(230, 40, 40) : Sketchup::Color.new(150, 150, 150)
        view.line_width = 5
        pts = @erase_hover[:edges].select(&:valid?).flat_map { |e| [@erase_hover[:tr] * e.start.position, @erase_hover[:tr] * e.end.position] }
        view.draw(GL_LINES, pts) unless pts.empty?
        return
      end

      title = if !(@drag || @hover)
                BoosokTools::Trowel.loc('trowel_hud_title', 'TROWEL')
              elsif mode == 'offset'
                BoosokTools::Trowel.loc('trowel_hud_title_offset', 'TROWEL — OFFSET')
              else
                BoosokTools::Trowel.loc('trowel_hud_title_pp', 'TROWEL — PUSH/PULL')
              end
      BoosokTools::Slice.draw_hud(view, title, hud_lines)
      hit = @drag || @hover
      return unless hit

      draw_group_box(view, hit)
      draw_snap(view)
      draw_dims(view)
      draw_pushpull_dim(view)
      draw_fill_preview(view)
      draw_offset_preview(view)
      draw_rim_hot(view)
      return if @drag

      if hit[:kind] == :edge
        draw_edge(view, hit, Sketchup::Color.new(0, 200, 100)) if hit[:edge].valid?
      elsif hit[:face].valid?
        draw_face(view, hit, Sketchup::Color.new(0, 230, 118, 70), Sketchup::Color.new(0, 200, 100))
      end
    rescue StandardError => e
      puts "[Boosok Trowel] draw: #{e.class}: #{e.message}"
    end
  end

  # ── Dialog ────────────────────────────────────────────────────────────────

  def self.loc(key, fallback)
    defined?(BoosokTools::Locale) ? BoosokTools::Locale.t(key, fallback) : fallback
  end

  def self.report(ok, err, _hit)
    dlg = @dialog
    return unless dlg

    # Hanya kesalahan yang diberi tahu; keberhasilan cukup terlihat di model
    dlg.execute_script("showToast(#{err.to_s.to_json}, 'error');") unless ok
  end

  def self.send_init_data(dialog)
    return unless dialog

    dialog.execute_script("if (typeof init === 'function') init(#{options.to_json});")
  end

  def self.start_tool(opts)
    model = Sketchup.active_model
    return unless model

    @tool = TrowelTool.new(opts)
    model.select_tool(@tool)
  end

  def self.attach_callbacks(dialog)
    return unless dialog
    return if @dialog.equal?(dialog) # sudah terdaftar di dialog ini (hindari handler bertumpuk)
    @dialog = dialog

    dialog.add_action_callback("trowel_options") do |_ctx, json|
      opts = save_options(JSON.parse(json.to_s)) rescue options
      @tool.options = opts if @tool
    end

    dialog.add_action_callback("trowel_start") do |_ctx, json|
      opts = save_options(JSON.parse(json.to_s)) rescue options
      start_tool(opts)
    end
  end
end

file_loaded(__FILE__)
