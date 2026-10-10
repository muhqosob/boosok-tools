require 'sketchup'
require 'json'
require 'digest/md5'
Sketchup.require 'boosok_tools/ruby/titlebar'

# Group void: group/component yang ditandai "void" dipakai sebagai pemotong. "Terapkan Void" melubangi setiap
# group/component SOLID lain (di konteks edit yang sama) yang bertabrakan dengan void.
#
# Non-destruktif: target asli (utuh) disimpan tersembunyi sebagai "sumber", dan yang terlihat adalah "hasil"
# yang berlubang. Saat void digeser (mode live), hasil dibangun ulang dari sumber sehingga lubang ikut bergeser.
# Void sendiri tidak pernah dipotong: yang dipakai memotong hanyalah salinannya.
#
# Group/component void boleh berisi group/component lain (mis. pintu): isi itu ikut bergerak bersama void tetapi
# TIDAK ikut memotong. Yang memotong hanya geometri polos (bentuk lubang) milik void itu sendiri, atau, kalau di
# dalam void ada group/component ber-tag #void_hidden, hanya geometri polos di dalam group/component itu.
module BoosokTools::Void
  DICT = 'BoosokTools'.freeze unless defined?(DICT)
  KEY = 'void'.freeze unless defined?(KEY)
  ORIG_MATERIAL = 'void_orig_material'.freeze unless defined?(ORIG_MATERIAL)
  ROLE = 'void_role'.freeze unless defined?(ROLE)   # 'source' (utuh, tersembunyi) / 'result' (berlubang)
  LINK = 'void_link'.freeze unless defined?(LINK)   # id yang memasangkan sumber dengan hasilnya
  TX = 'void_tx'.freeze unless defined?(TX)         # transformasi hasil saat dibuat (deteksi hasil digeser user)
  FP = 'void_fp'.freeze unless defined?(FP)         # sidik jari input pemotongan hasil (lewati hasil yang tidak berubah)
  CHILD_LAYER = 'void_child_layer'.freeze unless defined?(CHILD_LAYER) # nama layer child asli (untuk non-solid parent)
  VOID_HIDDEN_TAG = '#void_hidden'.freeze unless defined?(VOID_HIDDEN_TAG) # tag untuk face/edge di dalam void
  ORIG_LAYER = 'void_orig_layer'.freeze unless defined?(ORIG_LAYER) # nama tag asli group yang dijadikan void
  CUTTER = 'void_cutter'.freeze unless defined?(CUTTER) # true = group asli user yang dijadikan bentuk pemotong (di dalam pembungkus void)
  OFF = 'void_off'.freeze unless defined?(OFF)    # true = void dinonaktifkan ("Batalkan Lubang"): tidak melubangi apa pun
  OFF_MATERIAL_NAME = 'Boosok Void (Off)'.freeze unless defined?(OFF_MATERIAL_NAME)
  DYNAMIC_DICT = 'dynamic_attributes'.freeze unless defined?(DYNAMIC_DICT)
  SETTINGS = 'BoosokTools_Void'.freeze unless defined?(SETTINGS)
  MATERIAL_NAME = 'Boosok Void'.freeze unless defined?(MATERIAL_NAME)
  UNTAGGED_NAMES = %w[Untagged Layer0].freeze unless defined?(UNTAGGED_NAMES)
  EPS = 0.001 unless defined?(EPS) # inci; toleransi bounding box
  RECUT_DELAY = 0.08 unless defined?(RECUT_DELAY)

  # Dipanggil Hub saat dialog ditutup supaya callback didaftarkan lagi di dialog berikutnya
  def self.release_dialog
    @dialog = nil
  end

  def self.run
    Sketchup.require 'boosok_tools/hub' unless defined?(BoosokTools::Hub)
    BoosokTools::Hub.open_or_show('void')
  end

  # ── Penanda ───────────────────────────────────────────────────────────────

  def self.container?(ent)
    ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
  end

  def self.void?(ent)
    container?(ent) && ent.get_attribute(DICT, KEY, false) == true
  end

  # Log diagnostik ke Ruby Console. Hanya aktif kalau mode dev (.dev_mode) menyala.
  def self.dev_log?
    defined?(BoosokTools::Dev) && BoosokTools::Dev.enabled?
  end

  # Pesan boleh berupa blok supaya string (dan panggilan API di dalamnya, mis. dinfo) tidak dihitung kalau log mati.
  def self.dlog(msg = nil)
    puts "[Boosok Void] #{msg || yield}" if dev_log?
  end

  # Bounding box ringkas untuk log: [xmin,ymin,zmin]..[xmax,ymax,zmax] dibulatkan 0.1.
  def self.dbox(box)
    return 'kosong' if box.nil? || box.empty?

    "[#{box.min.to_a.map { |x| x.round(1) }.join(',')}]..[#{box.max.to_a.map { |x| x.round(1) }.join(',')}]"
  rescue StandardError
    '?'
  end

  # Ringkasan satu entity untuk log: kelas, id, nama definisi, dan berapa instance yang memakai definisinya.
  def self.dinfo(ent)
    return 'nil' unless ent
    return "#{ent.class.name.split('::').last}(terhapus)" unless ent.valid?

    d = ent.definition
    "#{ent.class.name.split('::').last}##{ent.persistent_id} def=#{d.name.inspect}(#{d.instances.size}x) role=#{role(ent).inspect}"
  rescue StandardError
    ent.class.name.to_s
  end

  def self.void_off?(ent)
    void?(ent) && ent.get_attribute(DICT, OFF, false) == true
  end

  # Definisi dipakai bersama instance lain (mis. void di-copy dengan Move+Ctrl).
  def self.shared_definition?(ent)
    ent.definition.instances.size > 1
  rescue StandardError
    false
  end

  # Setiap void harus unik: kalau definisinya dipakai bersama hasil copy, mengubah satu void (tag isi, unmark)
  # ikut mengubah semua salinannya. Mengembalikan entity hasil (bisa objek baru), atau `ent` kalau tidak perlu/gagal.
  # Dynamic component tidak disentuh.
  def self.ensure_unique(ent)
    return ent unless container?(ent) && ent.valid? && !dynamic?(ent) && shared_definition?(ent)

    before = dinfo(ent)
    res = ent.make_unique
    out = container?(res) && res.valid? ? res : ent
    dlog { "make_unique: #{before} -> #{dinfo(out)}#{out.equal?(ent) ? '' : ' (objek BARU)'}" }
    out
  rescue StandardError => e
    puts "[Boosok Void] make_unique gagal: #{e.class}: #{e.message}"
    ent
  end

  # Dynamic Component = ComponentInstance yang punya kamus 'dynamic_attributes' (di instance atau definisinya).
  # Void TIDAK BOLEH melubangi / mengubah dynamic component (dan isinya): selalu dilewati.
  def self.dynamic?(ent)
    return false unless ent.is_a?(Sketchup::ComponentInstance)
    return true unless ent.attribute_dictionary(DYNAMIC_DICT).nil?

    defn = ent.definition
    memo = @scan_memo && @scan_memo[:dyn]
    return memo[defn] if memo&.key?(defn)

    res = !defn.attribute_dictionary(DYNAMIC_DICT).nil?
    memo[defn] = res if memo
    res
  rescue StandardError
    false
  end

  def self.role(ent)
    ent.get_attribute(DICT, ROLE)
  end

  def self.link_of(ent)
    ent.get_attribute(DICT, LINK)
  end

  def self.live?(model)
    model.get_attribute(SETTINGS, 'live', true) != false
  end

  def self.void_material(model)
    mat = model.materials[MATERIAL_NAME]
    return mat if mat

    mat = model.materials.add(MATERIAL_NAME)
    mat.color = Sketchup::Color.new(220, 38, 38)
    mat.alpha = 0.35
    mat
  end

  # Material abu-abu untuk void yang dinonaktifkan (terlihat beda dari void aktif yang merah).
  def self.void_off_material(model)
    mat = model.materials[OFF_MATERIAL_NAME]
    return mat if mat

    mat = model.materials.add(OFF_MATERIAL_NAME)
    mat.color = Sketchup::Color.new(120, 120, 120)
    mat.alpha = 0.35
    mat
  end

  # Aktifkan / nonaktifkan void. Void nonaktif tetap void (marker, tag isi), tapi tidak melubangi apa pun.
  # Dipanggil di dalam operasi. Mengembalikan jumlah void yang statusnya benar-benar berubah.
  def self.set_voids_active(model, voids, active)
    voids.count do |v|
      next false unless void?(v) && v.valid? && (void_off?(v) == active)

      if active
        v.delete_attribute(DICT, OFF)
        v.material = void_material(model)
      else
        v.set_attribute(DICT, OFF, true)
        v.material = void_off_material(model)
      end
      true
    end
  end

  # Ambil atau buat tag '#void_hidden' untuk face/edge di dalam void.
  # Tag ini dibuat dengan visible=false agar geometri void tidak terlihat di viewport.
  def self.void_hidden_layer(model)
    layer = model.layers[VOID_HIDDEN_TAG]
    return layer if layer

    layer = model.layers.add(VOID_HIDDEN_TAG)
    layer.visible = false
    layer
  end

  # Tandai / lepas tanda void.
  # Saat ditandai: group yang dipilih diberi tag '#void_hidden' + material void (jadi bentuk pemotong, lihat
  # cutter_shapes) lalu dibungkus group baru ber-tag Untagged. Group pembungkus itulah void-nya:
  #   group(Untagged, void) > group(#void_hidden, material void) > face & edge
  # Tag dan material asli group disimpan di atribut group yang dipilih.
  # Saat dilepas: tag dan material asli dipulihkan, group pembungkus di-explode.
  def self.mark(model, ent, on)
    invalidate_scan_cache
    if on
      return false if void?(ent) || role(ent)

      wrap_as_void(model, ent)
    else
      return false unless void?(ent)

      unwrap_void(model, ent)
    end
    true
  end

  # Entities tempat ent berada (Group#parent bisa berupa Model / ComponentDefinition).
  def self.parent_entities(ent)
    parent = ent.parent
    parent.respond_to?(:entities) ? parent.entities : parent
  end

  def self.wrap_as_void(model, ent)
    orig_material = ent.material ? ent.material.name : ''
    orig_layer = ent.layer ? ent.layer.name : ''
    outer = parent_entities(ent).add_group(ent)
    # add_group bisa membuat ulang entity di dalam group baru, jadi group yang dipilih dicari lagi dari sana.
    inner = entities_of(outer).find { |e| container?(e) }
    return unless inner

    inner.set_attribute(DICT, CUTTER, true)
    inner.set_attribute(DICT, ORIG_MATERIAL, orig_material)
    inner.set_attribute(DICT, ORIG_LAYER, orig_layer)
    inner.layer = void_hidden_layer(model)
    inner.material = void_material(model)
    outer.layer = untagged_layer(model)
    outer.set_attribute(DICT, KEY, true)
    outer.set_attribute(DICT, ORIG_MATERIAL, '')
    outer.material = void_material(model)
    model.selection.clear
    model.selection.add(outer)
  end

  def self.unwrap_void(model, ent)
    ent = ensure_unique(ent) # tag isi dikembalikan: jangan ikut mengubah void salinan lain
    inner = entities_of(ent)
    untagged = untagged_layer(model)
    cutters = cutter_shapes(inner).select { |s| s.get_attribute(DICT, CUTTER, false) }
    original = cutters.find { |s| s.get_attribute(DICT, ORIG_LAYER, nil) }

    if original
      restore_original(model, original)
      ent.material = nil # material void tidak boleh menular ke group asli saat pembungkus di-explode
      ent.layer = untagged
      freed = ent.explode
      model.selection.clear
      model.selection.add(freed.select { |e| container?(e) })
    else
      orig = ent.get_attribute(DICT, ORIG_MATERIAL, '').to_s
      ent.material = orig.empty? ? nil : model.materials[orig]
      ent.delete_attribute(DICT, KEY)
      ent.delete_attribute(DICT, OFF)
      ent.delete_attribute(DICT, ORIG_MATERIAL)
      # Void versi lama: group pembungkus isi di-explode dan face/edge polos ber-tag #void_hidden dikembalikan.
      cutters.each do |s|
        s.material = nil
        s.layer = untagged
        s.explode
      end
      inner.each do |e|
        e.layer = untagged if e.is_a?(Sketchup::Drawingelement) && !container?(e) && e.layer.name == VOID_HIDDEN_TAG
      end
    end
  end

  # Kembalikan tag dan material group yang dulu dipilih user (dibuang dari atributnya).
  def self.restore_original(model, shape)
    layer_name = shape.get_attribute(DICT, ORIG_LAYER, '').to_s
    shape.layer = model.layers[layer_name] || untagged_layer(model)
    orig = shape.get_attribute(DICT, ORIG_MATERIAL, '').to_s
    shape.material = orig.empty? ? nil : model.materials[orig]
    [CUTTER, ORIG_MATERIAL, ORIG_LAYER].each { |k| shape.delete_attribute(DICT, k) }
  end

  def self.void_count(model)
    model.active_entities.count { |e| void?(e) }
  end

  # ── Operasi solid ─────────────────────────────────────────────────────────

  # ComponentDefinition#manifold? baru ada di SketchUp 2026.2; versi lama memakai Group/ComponentInstance#manifold?
  # (di 2026.2 dideprekasi). Tanpa respond_to?, NoMethodError di SketchUp <= 2026.1 ditelan rescue dan semua
  # group dianggap bukan solid, sehingga Slice / Void / Trowel diam-diam gagal.
  def self.solid?(ent)
    defn = ent.definition
    memo = @scan_memo && @scan_memo[:solid]
    return memo[defn] if memo&.key?(defn)

    res = defn.respond_to?(:manifold?) ? defn.manifold? : ent.manifold?
    memo[defn] = res if memo
    res
  rescue StandardError
    false
  end

  # Pemindaian live (rescan / signature) menelusuri ribuan group, dan banyak di antaranya instance dari definisi yang
  # sama (isi identik). Selama blok ini hasil per definisi dipakai ulang. Hanya untuk membaca (model tidak boleh
  # berubah di dalam blok), makanya tidak dipakai oleh rebuild yang mengubah model.
  def self.with_scan_memo
    prev = @scan_memo
    unless prev
      sync_scan_flags
      @scan_memo = { solid: {}.compare_by_identity, dyn: {}.compare_by_identity }
    end
    yield
  ensure
    @scan_memo = prev
  end

  # ── Cache bendera per definisi (bertahan antar scan) ───────────────────────
  # Pertanyaan yang diulang tiap navigasi/edit: "apakah di dalam group ini ada void / source / result?". Jawabannya
  # hanya berubah kalau isi pohon group itu berubah, jadi dihitung sekali per definisi lalu dipakai ulang. Dengan ini
  # scan hanya menelusuri jalur menuju void, bukan seluruh isi project. Nilai = [ada_void, ada_role, jumlah_entitas].
  # Bendera sengaja konservatif (void tersembunyi/nonaktif tetap dihitung): salah-positif cuma menambah yang dipantau.
  def self.scan_flags
    @scan_flags ||= {}.compare_by_identity
  end

  # Dipanggil setelah operasi yang mengubah penanda void/role (tandai, rebuild, finalisasi, undo/redo, ganti model).
  def self.invalidate_scan_cache
    @scan_flags = nil
  end

  def self.subtree_flags(ent)
    defn = ent.definition
    hit = scan_flags[defn]
    return hit if hit

    has_void = has_role = false
    ents = entities_of(ent)
    ents.each do |c|
      next unless container?(c)

      if void?(c)
        has_void = true
      elsif role(c)
        has_role = true
      elsif !dynamic?(c) && !solid?(c)
        v, r = subtree_flags(c)
        has_void ||= v
        has_role ||= r
      end
    end
    scan_flags[defn] = [has_void, has_role, ents.length]
  end

  # Buang entri yang isinya berubah sejak dihitung (jumlah entitas beda / definisi sudah hilang), beserta semua
  # definisi yang memuatnya, karena bendera leluhur ikut berubah. Entri lain tetap berlaku.
  def self.sync_scan_flags
    flags = @scan_flags
    return if flags.nil? || flags.empty?

    flags.keys.each do |d|
      next unless flags.key?(d)

      drop_flag_chain(flags, d) unless defn_valid?(d) && d.entities.length == flags[d][2]
    end
  rescue StandardError
    @scan_flags = nil
  end

  def self.defn_valid?(defn)
    !defn.respond_to?(:valid?) || defn.valid?
  end

  def self.drop_flag_chain(flags, defn)
    seen = {}.compare_by_identity
    stack = [defn]
    until stack.empty?
      d = stack.pop
      next if seen[d]

      seen[d] = true
      flags.delete(d)
      next unless defn_valid?(d)

      d.instances.each do |inst|
        par = inst.parent
        par = par.owner if par.is_a?(Sketchup::Entities)
        stack << par if par.respond_to?(:instances)
      end
    end
  end

  def self.volume_of(ent)
    ent.volume
  rescue StandardError
    nil
  end

  def self.same_tx?(a, b)
    a.size == b.size && a.zip(b).all? { |x, y| (x - y).abs < 1e-6 }
  end

  # Tumpang tindih bounding box dengan volume > 0 (sentuhan sisi/titik saja tidak dihitung)
  def self.overlap?(box_a, box_b)
    inter = box_a.intersect(box_b)
    return false if inter.empty?

    inter.width > EPS && inter.height > EPS && inter.depth > EPS
  end

  def self.inside?(inner_min, inner_max, outer_min, outer_max)
    (0..2).all? { |i| inner_min[i] >= outer_min[i] - EPS && inner_max[i] <= outer_max[i] + EPS }
  end

  def self.entities_of(ent)
    ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
  end

  # Group/component di dalam void (mis. pintu) — bukan bagian pemotong.
  def self.nested(ent)
    entities_of(ent).select { |e| container?(e) }
  end

  # Pulihkan layer entity dari atribut CHILD_LAYER yang tersimpan (dipakai saat src di-unhide).
  # Fallback ke entity.layer jika atribut tidak ada (source dibuat sebelum fix ini).
  def self.restore_layer_from_attr(ent, model)
    saved = ent.get_attribute(DICT, CHILD_LAYER)
    if saved && !saved.empty?
      layer = model.layers[saved]
      ent.layer = layer if layer
    end
  rescue StandardError
    nil
  end

  # Helper: konversi bounds entity (dalam ruang lokal parent) ke world-space BoundingBox.
  def self.world_bounds(local_box, parent_tx)
    box = Geom::BoundingBox.new
    min = local_box.min
    max = local_box.max
    [
      min,
      max,
      Geom::Point3d.new(min.x, min.y, max.z),
      Geom::Point3d.new(min.x, max.y, min.z),
      Geom::Point3d.new(max.x, min.y, min.z),
      Geom::Point3d.new(max.x, max.y, min.z),
      Geom::Point3d.new(min.x, max.y, max.z),
      Geom::Point3d.new(max.x, min.y, max.z)
    ].each { |pt| box.add(pt.transform(parent_tx)) }
    box
  end

  # Void yang berada di dalam group lain (bersarang). `ent` = void aslinya, `tx` = transformasi void itu ke world,
  # `box` = bounding box-nya di world. Void level atas dipakai apa adanya (entity), jadi semua kode yang membaca
  # posisi void memakai vbox / vtx / vent supaya keduanya diperlakukan sama.
  # Dibuat ulang setiap file dimuat: saat hot-reload, Struct lama dengan jumlah field berbeda akan memicu
  # "struct size differs" kalau dipertahankan lewat `unless defined?`.
  send(:remove_const, :VoidRef) if const_defined?(:VoidRef, false)
  VoidRef = Struct.new(:ent, :tx, :box, :owner)

  def self.vbox(v)
    v.is_a?(VoidRef) ? v.box : v.bounds
  end

  def self.vtx(v)
    v.is_a?(VoidRef) ? v.tx : v.transformation
  end

  def self.vent(v)
    v.is_a?(VoidRef) ? v.ent : v
  end

  NESTED_VOID_DEPTH = 4 unless defined?(NESTED_VOID_DEPTH)

  # Cakupan void: void level atas berlaku untuk semua isi konteks edit. Void di dalam sebuah group hanya melubangi
  # isi group pemiliknya (anak-anaknya dan turunannya), BUKAN group lain yang kebetulan menempati posisi yang sama
  # (mis. versi/revisi lain dari bangunan yang sama). `chain` = parent yang sedang diproses + semua leluhurnya.
  def self.void_applies?(v, chain)
    !v.is_a?(VoidRef) || chain.any? { |c| c.equal?(v.owner) }
  end

  # Kumpulkan void aktif yang ada DI DALAM group lain (mis. group "new" > group "revisi" > void). Lubang yang dibuat
  # void-void itu harus tetap terjaga saat rebuild dijalankan dari level yang lebih luar: void level atas
  # tidak boleh dianggap satu-satunya void, kalau tidak lubang milik void bersarang ikut ditutup.
  # `top` = true untuk entities level atas (void di sana sudah ada di daftar void biasa, jadi dilewati).
  # prune: true hanya menelusuri group yang menurut cache bendera memang memuat void (dipakai pemindai live).
  def self.nested_void_refs(ents, outer_tx = Geom::Transformation.new, depth = NESTED_VOID_DEPTH, top = true, out = [], owner = nil, prune = false)
    ents.each do |e|
      next unless container?(e) && e.valid? && !e.hidden? && !role(e) && !dynamic?(e)

      if void?(e)
        next if top || void_off?(e)

        out << VoidRef.new(e, outer_tx * e.transformation, world_bounds(e.bounds, outer_tx), owner)
      elsif depth > 0 && (!prune || subtree_flags(e)[0]) && !solid?(e)
        nested_void_refs(entities_of(e), outer_tx * e.transformation, depth - 1, false, out, e, prune)
      end
    end
    out
  end

  # Potong child menggunakan list [void_src, local_tx]. Mengembalikan [result, changed?] atau nil jika gagal.
  # Semua entity harus berada di dalam parent_entities.
  # Target dijadikan unik dulu (Group maupun Component) supaya definisi yang dipakai group/component lain
  # tidak ikut terpotong. Entity hasil make_unique bisa berupa objek baru, jadi selalu pakai nilai kembaliannya.
  def self.cut_child(parent_entities, child, local_voids, stats)
    cur = ensure_unique(child)
    changed = false
    local_voids.each do |void_src, local_tx|
      next unless cur.valid? && vent(void_src).valid?

      cutter = cutter_from_into(parent_entities, vent(void_src), local_tx)
      before = volume_of(cur)
      bmin = cur.bounds.min.to_a
      bmax = cur.bounds.max.to_a
      result = cutter.subtract(cur)
      erase_if_valid(cutter) unless result.equal?(cutter)
      erase_if_valid(cur) unless result.equal?(cur)
      unless result && inside?(result.bounds.min.to_a, result.bounds.max.to_a, bmin, bmax)
        erase_if_valid(result)
        stats[:failed] += 1
        return nil
      end
      # Hanya bounding box yang bersinggungan belum berarti ada lubang: volume harus benar-benar berubah
      after = volume_of(result)
      changed ||= !(before && after && (after - before).abs <= (before.abs * 1e-6) + 1e-9)
      cur = result
    end
    [cur, changed]
  end

  # Untuk group non-solid: kelola pemotongan child solid di dalamnya secara rekursif (maks depth=3),
  # non-destruktif. Child asli disimpan sebagai source (tersembunyi di dalam parent), hasil berlubang
  # sebagai result. Saat void digeser, result dibangun ulang dari source — identik dengan mekanisme solid group.
  # world_tx = transformasi ruang DALAM parent ke world (top-level: parent.transformation).
  # KUNCI: bounds sebuah entity sudah berada di ruang pemiliknya, jadi bounds child dikonversi dengan world_tx
  # (BUKAN dikali transformation child lagi). Hanya untuk rekursi world_tx diperbarui: world_tx * child.transformation.
  def self.rebuild_nonsolid_children(model, parent, voids, stats, depth = 3, world_tx = nil, ancestors = [])
    world_tx      ||= parent.transformation          # top-level: ruang dalam parent → world
    chain           = ancestors + [parent]
    world_tx_inv    = world_tx.inverse

    # World-bounds parent: bounds-nya ada di ruang pemilik parent = world_tx * parent.transformation.inverse
    parent_world_box = world_bounds(parent.bounds, world_tx * parent.transformation.inverse)

    # Void yang overlap dengan parent (world-space), lalu konversi ke ruang lokal parent
    local_voids = voids.select { |v| void_applies?(v, chain) && overlap?(parent_world_box, vbox(v)) }.map do |v|
      [v, world_tx_inv * vtx(v)]
    end

    # Isi parent (child, source, result) hidup di DEFINISI parent. Kalau definisi itu dipakai bersama group lain
    # (dinding hasil copy), mengubah isinya mengubah semua kembarannya. Jadi parent dijadikan unik dulu, sebelum
    # isinya disentuh. Harus sebelum mengambil `parent_entities`: isi definisi baru adalah objek-objek baru.
    if (local_voids.any? || nested_has_state?(parent, depth)) && shared_definition?(parent)
      parent = ensure_unique(parent)
      chain[-1] = parent
    end
    dlog { "nonsolid #{dinfo(parent)} box=#{dbox(parent_world_box)} void_overlap=#{local_voids.size} depth=#{depth}" }
    parent_entities = entities_of(parent)

    child_all     = parent_entities.select { |e| container?(e) }
    child_sources = child_all.select { |e| role(e) == 'source' }
    child_results = child_all.select { |e| role(e) == 'result' }
    by_link       = child_results.each_with_object({}) { |r, h| h[link_of(r)] = r }

    # ── 1. Rebuild pasangan source/result yang sudah ada ──────────────────────
    child_sources.each do |src|
      next unless src.valid?

      old_result = by_link[link_of(src)]
      if dynamic?(src) # sisa versi lama: dynamic component dipulihkan, tidak dipotong lagi
        restore_source(src, old_result, model)
        next
      end
      # Hasil yang digeser user (Move) di dalam parent → sumbernya ikut digeser, sama seperti hasil level atas.
      sync_moved(parent_entities, src, old_result) if old_result&.valid?
      # Hanya void yang masih menyentuh child INI yang dihitung: kalau parent/child digeser dan void tidak
      # terbawa, lubangnya tertutup walau void masih menyentuh bagian lain dari parent.
      src_box = world_bounds(src.bounds, world_tx)
      src_voids = local_voids.select { |v, _| overlap?(src_box, vbox(v)) }

      if src_voids.empty?
        # Void sudah tidak overlap child ini: kembalikan child asli
        dlog { "  child source #{dinfo(src)} box=#{dbox(src_box)}: tidak kena void lagi -> DIPULIHKAN" }
        erase_if_valid(old_result)
        restore_layer_from_attr(src, Sketchup.active_model)
        src.hidden = false
        clear_roles(src)
        next
      end

      fp = cut_fp(src, src_voids)
      if @incremental && old_result&.valid? && old_result.get_attribute(DICT, FP) == fp
        dlog { "  child source #{dinfo(src)}: input tidak berubah -> dilewati" }
        next
      end

      # Buat ulang hasil dari source
      begin
        fresh = duplicate(parent_entities, src)
        fresh.hidden = false
        done = cut_child(parent_entities, fresh, src_voids, stats)
        dlog { "  child source #{dinfo(src)} box=#{dbox(src_box)}: dibangun ulang dengan #{src_voids.size} void -> #{done ? "berubah=#{done.last}" : 'GAGAL'}" }
        if done
          new_result, changed = done
          if changed
            erase_if_valid(old_result)
            # Pulihkan layer dari atribut yang disimpan di source (lebih reliable dari src.layer)
            saved_layer_name = src.get_attribute(DICT, CHILD_LAYER)
            if saved_layer_name
              restored_layer = Sketchup.active_model.layers[saved_layer_name]
              new_result.layer = restored_layer || untagged_layer(Sketchup.active_model)
            else
              new_result.layer = src.layer
            end
            saved_name = src.get_attribute(DICT, 'void_child_name')
            new_result.name = saved_name if saved_name && !saved_name.empty?
            restore_look(new_result, src, src_voids.map { |v, _| world_bounds(vbox(v), world_tx_inv) })
            new_result.set_attribute(DICT, ROLE, 'result')
            new_result.set_attribute(DICT, LINK, link_of(src))
            new_result.set_attribute(DICT, TX, new_result.transformation.to_a)
            new_result.set_attribute(DICT, FP, fp)
          else
            # Void tidak lagi memotong source ini: pulihkan
            erase_if_valid(new_result)
            erase_if_valid(old_result)
            restore_layer_from_attr(src, Sketchup.active_model)
            src.hidden = false
            clear_roles(src)
          end
        else
          # Gagal: buang fresh copy, biarkan old_result tetap
          erase_if_valid(fresh) if fresh&.valid?
        end
      rescue => e
        puts "[Boosok Void] rebuild child gagal: #{e.class}: #{e.message}"
        stats[:failed] += 1
      end
    end

    # ── 2. Rekursi ke child non-solid (selama masih ada kedalaman tersisa) ────
    # Bounds child ada di ruang dalam parent (world_tx); ruang dalam child sendiri = world_tx * child.transformation.
    if depth > 0
      nonsolid_plain = child_all.select do |e|
        e.valid? && !e.hidden? && !role(e) && !void?(e) && !dynamic?(e) && !solid?(e)
      end

      nonsolid_plain.each do |ns_child|
        child_world_tx  = world_tx * ns_child.transformation
        child_world_box = world_bounds(ns_child.bounds, world_tx)
        next unless voids.any? { |v| overlap?(child_world_box, vbox(v)) }

        rebuild_nonsolid_children(model, ns_child, voids, stats, depth - 1, child_world_tx, chain)
      end

      # Child non-solid yang sudah punya state: proses agar state dibersihkan saat void menjauh
      nonsolid_plain.each do |ns_child|
        next unless nested_has_state?(ns_child, depth)

        child_world_tx  = world_tx * ns_child.transformation
        child_world_box = world_bounds(ns_child.bounds, world_tx)
        next if voids.any? { |v| overlap?(child_world_box, vbox(v)) } # sudah diproses di atas

        rebuild_nonsolid_children(model, ns_child, voids, stats, depth - 1, child_world_tx, chain)
      end
    end

    return if local_voids.empty?

    # ── 3. Child solid baru (belum punya role) ────────────────────────────────
    fresh_children = parent_entities.select { |e| container?(e) && !e.hidden? && !role(e) && !void?(e) } # void bukan target
    fresh_children.each do |child|
      next unless child.valid?

      child_world_box = world_bounds(child.bounds, world_tx)
      matching = local_voids.select { |v, _| overlap?(child_world_box, vbox(v)) }
      next if matching.empty?

      if dynamic?(child) # dynamic component tidak boleh dilubangi
        stats[:dynamic] += 1
        next
      end
      next unless solid?(child)

      begin
        # Simpan layer & nama child asli sebelum apapun (subtract akan mengkonsumsi child)
        orig_layer = child.layer
        orig_name  = child.name

        # Simpan source (salinan tersembunyi dari child asli)
        src = duplicate(parent_entities, child)
        link = new_link
        src.hidden = true
        src.set_attribute(DICT, ROLE, 'source')
        src.set_attribute(DICT, LINK, link)
        # Simpan layer & nama sebagai atribut di source agar reliable saat rebuild live
        src.set_attribute(DICT, CHILD_LAYER, orig_layer.name)
        src.set_attribute(DICT, 'void_child_name', orig_name) unless orig_name.to_s.empty?

        child_desc = dinfo(child)
        done = cut_child(parent_entities, child, matching, stats)
        dlog { "  child #{child_desc}: dipotong #{matching.size} void -> #{done ? "berubah=#{done.last}" : 'GAGAL'}" }
        if done
          result, changed = done
          if changed
            result.layer = orig_layer
            result.name  = orig_name unless orig_name.to_s.empty?
            restore_look(result, src, matching.map { |v, _| world_bounds(vbox(v), world_tx_inv) })
            result.set_attribute(DICT, ROLE, 'result')
            result.set_attribute(DICT, LINK, link)
            result.set_attribute(DICT, TX, result.transformation.to_a)
          else
            # Tidak benar-benar terpotong: bersihkan source, child tetap
            erase_if_valid(src)
            clear_roles(result) if result&.valid?
          end
        else
          # Gagal: hapus source yang terlanjur dibuat
          erase_if_valid(src)
        end
      rescue => e
        puts "[Boosok Void] potong child gagal: #{e.class}: #{e.message}"
        stats[:failed] += 1
      end
    end
  end

  def self.untagged_layer(model)
    model.layers.find { |l| UNTAGGED_NAMES.include?(l.name) } || model.layers[0]
  end

  # Group/component di dalam void yang ber-tag #void_hidden = bentuk pemotong eksplisit. Kalau ada, hanya
  # merekalah yang memotong; geometri polos void dan group lain (mis. pintu) diabaikan.
  def self.cutter_shapes(entities)
    entities.select { |e| container?(e) && e.valid? && e.layer.name == VOID_HIDDEN_TAG }
  end

  # Buang semua yang bukan bentuk pemotong dari salinan void. Kalau ada bentuk pemotong eksplisit (group
  # ber-tag #void_hidden), geometri polos dan group lain dibuang lalu bentuk itu di-explode jadi geometri polos.
  # Kalau tidak ada, perilaku lama: hanya geometri polos void yang dipakai, group/component di dalamnya dibuang.
  # Salinan dan semua face/edge-nya diberi tag Untagged: face lubang yang terbentuk mewarisi tag pemotong,
  # jadi tag void yang tersembunyi tidak boleh ikut terbawa (bisa membuat face dinding lubang tidak terlihat).
  def self.strip_cutter(cutter)
    inner = entities_of(cutter)
    shapes = cutter_shapes(inner)
    unless shapes.empty?
      drop = inner.select { |e| e.is_a?(Sketchup::Edge) || container?(e) } - shapes
      inner.erase_entities(drop) unless drop.empty?
      shapes.each do |s|
        next unless s.valid?

        s.material = nil # material void tidak boleh menular ke face pemotong / lubang
        s.explode
      end
    end
    kids = inner.select { |e| container?(e) }
    inner.erase_entities(kids) unless kids.empty?
    orient_faces_outward(inner)
    untagged = untagged_layer(Sketchup.active_model)
    cutter.layer = untagged
    inner.each { |e| e.layer = untagged if e.is_a?(Sketchup::Drawingelement) }
    cutter
  end

  # Pemotong yang normal face-nya menghadap ke dalam membuat dinding lubang hasil subtract terbalik.
  # Volume bertanda (1/3 * sum luas * (titik . normal)) negatif = normal menghadap ke dalam → balik semua face.
  def self.orient_faces_outward(entities)
    faces = entities.grep(Sketchup::Face)
    return if faces.empty?

    signed = faces.sum { |f| f.area * (f.vertices[0].position.to_a.zip(f.normal.to_a).sum { |p, n| p * n }) }
    faces.each(&:reverse!) if signed < 0
  rescue StandardError => e
    puts "[Boosok Void] orient cutter gagal: #{e.class}: #{e.message}"
  end

  # Salinan void yang hanya berisi bentuk pemotongnya (lihat strip_cutter).
  def self.cutter_from(entities, void_src)
    cutter = duplicate(entities, void_src)
    cutter.material = nil # material void (merah) tidak boleh terbawa ke face lubang atau group hasil
    cutter.make_unique if cutter.is_a?(Sketchup::ComponentInstance) # jangan ubah definition milik void asli
    strip_cutter(cutter)
  end

  # Bentuk pemotong void (tanpa isi group/component-nya) harus solid.
  def self.solid_shape?(entities, void_src)
    return solid?(void_src) if nested(void_src).empty?

    cutter = cutter_from(entities, void_src)
    ok = solid?(cutter)
    erase_if_valid(cutter)
    ok
  rescue StandardError
    false
  end

  # Group#copy dan add_instance tidak membawa tag dan material level-group (terbukti dari log: tag asli
  # "I. PARTITION" jadi Layer0 di salinan), padahal boolean mengubah material level-group jadi material face. Tanpa
  # ini salinan source kehilangan warnanya dan restore_look memulihkan ke "tanpa material".
  def self.duplicate(entities, ent)
    copy = ent.is_a?(Sketchup::Group) ? ent.copy : entities.add_instance(ent.definition, ent.transformation)
    copy.hidden = false
    copy.layer = ent.layer if ent.layer && copy.layer != ent.layer
    copy.material = ent.material if ent.material && copy.material != ent.material
    copy
  end

  # Duplikasi group/component ke dalam entities LAIN (mis. ke dalam parent_entities).
  # Untuk group: salin semua face/edge dari definition ke group baru di target entities.
  # Untuk component: add_instance ke target entities dengan transformasi yang sudah diberikan.
  def self.duplicate_into(target_entities, ent, new_tx = nil)
    tx = new_tx || ent.transformation
    if ent.is_a?(Sketchup::ComponentInstance)
      copy = target_entities.add_instance(ent.definition, tx)
      copy.make_unique
    else
      # Group: buat group baru di target, lalu isi dengan konten definition void
      copy = target_entities.add_group
      copy.transformation = tx
      src = ent.definition.entities
      shapes = cutter_shapes(src)
      if shapes.empty?
        copy_plain_geometry(src, copy.entities)
      else
        # Bentuk pemotong eksplisit: hanya geometri polos di dalamnya (dengan transformasinya) yang disalin
        shapes.each { |s| copy_plain_geometry(entities_of(s), copy.entities, s.transformation) }
      end
    end
    copy.hidden = false
    copy
  end

  # Salin face/edge polos (tanpa group/component) dari src ke dst, titiknya ditransformasi dengan tx.
  def self.copy_plain_geometry(src, dst, tx = Geom::Transformation.new)
    src.each do |e|
      case e
      when Sketchup::Face
        begin
          new_face = dst.add_face(e.outer_loop.vertices.map { |v| v.position.transform(tx) })
          # Arah face dari urutan titik bisa terbalik (mis. tx mencerminkan geometri): samakan dengan normal aslinya
          new_face.reverse! if new_face.normal.dot(e.normal.transform(tx)) < 0
          new_face.material = e.material if e.material # copy material face jika ada
        rescue StandardError
          nil
        end
      when Sketchup::Edge
        begin
          dst.add_line(e.start.position.transform(tx), e.end.position.transform(tx))
        rescue StandardError
          nil
        end
      end
    end
  end

  # Versi cutter_from yang membuat salinan pemotong di dalam target_entities (bukan entities void).
  def self.cutter_from_into(target_entities, void_src, local_tx)
    strip_cutter(duplicate_into(target_entities, void_src, local_tx))
  end

  def self.copy_properties(src, dst)
    dst.name = src.name
    dst.layer = src.layer
    dst.material = src.material if src.material
    (src.attribute_dictionaries || []).each do |dict|
      dict.each_pair do |k, v|
        next if dict.name == DICT && [ROLE, LINK, TX, FP].include?(k)

        dst.set_attribute(dict.name, k, v)
      end
    end
  end

  def self.erase_if_valid(ent)
    ent.erase! if ent && ent.valid?
  end

  def self.clear_roles(ent)
    [ROLE, LINK, TX, FP].each { |k| ent.delete_attribute(DICT, k) }
  end

  # Satu pemotongan: `cur` dikurangi `void`. Hasil: [grup hasil, berubah?] atau nil kalau gagal.
  # Perilaku Group#subtract di SketchUp: receiver.subtract(x) = x - receiver (sama dengan tool Subtract di UI),
  # jadi salinan void jadi receiver agar yang berlubang adalah `cur`. Receiver/argumen bisa terhapus oleh operasi.
  # make_unique dipanggil sebelum subtract agar definisi component yang shared tidak ikut dimodifikasi.
  def self.cut_step(entities, cur, void_src)
    cutter = cutter_from(entities, void_src)
    cur = ensure_unique(cur) # definisi bersama group/component lain tidak boleh ikut terpotong
    before = volume_of(cur)
    bmin = cur.bounds.min.to_a
    bmax = cur.bounds.max.to_a
    result = cutter.subtract(cur)
    erase_if_valid(cutter) unless result.equal?(cutter)
    erase_if_valid(cur) unless result.equal?(cur)
    # Pengaman arah: hasil yang benar tidak pernah keluar dari bounding box semula. Kalau keluar, operasinya
    # terbalik → buang hasil dan anggap gagal (target asli tidak disentuh oleh pemanggil).
    unless result && inside?(result.bounds.min.to_a, result.bounds.max.to_a, bmin, bmax)
      erase_if_valid(result)
      return nil
    end

    after = volume_of(result)
    changed = !(before && after && (after - before).abs <= (before.abs * 1e-6) + 1e-9)
    [result, changed]
  end

  # Salinan `base` yang sudah dipotong semua `voids`. Hasil: [salinan, berubah?] atau nil kalau ada yang gagal.
  def self.cut_copy(entities, base, voids, stats)
    dlog { "cut_copy base=#{dinfo(base)} voids=#{voids.size}" }
    cur = ensure_unique(duplicate(entities, base))
    dlog { "  salinan: #{dinfo(cur)}" }
    changed = false
    voids.each do |v|
      next unless v.valid? && cur.valid? && overlap?(cur.bounds, v.bounds)

      step = cut_step(entities, cur, v)
      if step.nil?
        stats[:failed] += 1
        return nil
      end
      cur, did = step
      changed ||= did
      dlog { "  dipotong void #{dinfo(v)} berubah=#{did}" }
    end
    dlog { "  hasil: berubah=#{changed}" }
    [cur, changed]
  end

  # Penampilan hasil harus sama dengan target asli. Boolean bisa membawa material pemotong ke group hasil atau ke
  # face lubang. Material group dikembalikan ke milik target (termasuk "tanpa material"), dan face yang membawa
  # material yang tidak dipakai target sama sekali dikembalikan ke material group target (atau default). Material
  # face milik target (termasuk kalau lebih dari satu) tidak disentuh.
  # Ringkasan material satu container untuk log: material group + jumlah face per material (depan/belakang).
  def self.look_summary(ent)
    faces = entities_of(ent).select { |f| f.is_a?(Sketchup::Face) }
    front = faces.group_by { |f| f.material&.name }.transform_values(&:size)
    back = faces.group_by { |f| f.back_material&.name }.transform_values(&:size)
    textured = faces.count { |f| f.material&.texture || f.back_material&.texture }
    kids = entities_of(ent).select { |c| container?(c) }
    kid_mats = kids.map { |c| c.material&.name }.compact.tally
    "group=#{ent.material&.name.inspect} tag=#{ent.layer&.name.inspect} depan=#{front} belakang=#{back} " \
      "bertekstur=#{textured} anak=#{kids.size}#{kid_mats.empty? ? '' : " material_anak=#{kid_mats}"}"
  end

  def self.restore_look(result, base, hole_boxes = nil)
    unless result&.valid? && base&.valid?
      dlog { "restore_look dilewati: result valid=#{result&.valid?.inspect} base valid=#{base&.valid?.inspect}" }
      return
    end

    dlog { "restore_look: target  #{look_summary(base)}" }
    dlog { "restore_look: hasil sebelum #{look_summary(result)} kotak_void=#{hole_boxes ? hole_boxes.size : 'nil'}" }
    result.material = base.material
    allowed = [base.material]
    entities_of(base).each do |f|
      allowed << f.material << f.back_material if f.is_a?(Sketchup::Face)
    end
    allowed = allowed.compact.map(&:name) # dibandingkan lewat nama: nama material unik di dalam model
    fallback = base.material
    faces = entities_of(result).select { |f| f.is_a?(Sketchup::Face) }
    faces.each do |f|
      f.material = fallback if f.material && !allowed.include?(f.material.name)
      f.back_material = fallback if f.back_material && !allowed.include?(f.back_material.name)
    end
    painted = hole_boxes && !hole_boxes.empty? ? paint_hole_faces(faces, base, result, hole_boxes) : 0
    dlog { "restore_look: hasil sesudah #{look_summary(result)} face_lubang_dicat=#{painted}" }
  rescue StandardError => e
    puts "[Boosok Void] pulihkan material gagal: #{e.class}: #{e.message} @ #{e.backtrace&.first}"
  end

  # Face dinding lubang berasal dari pemotong, jadi tidak membawa material dinding. Face itu dikenali karena seluruhnya
  # berada di dalam kotak void, lalu dicat dengan material face dinding terbesar yang bersebelahan dengannya (lewat
  # edge). Kalau tidak ada yang bersebelahan, dipakai material dominan (menurut luas) milik target asli.
  # `hole_boxes` = bounding box void di ruang tempat `result` berada.
  def self.paint_hole_faces(faces, base, result, hole_boxes)
    inv = result.transformation.inverse
    local = hole_boxes.map { |b| world_bounds(b, inv) }
    hole = faces.select do |f|
      fb = f.bounds
      local.any? { |lb| inside?(fb.min.to_a, fb.max.to_a, lb.min.to_a, lb.max.to_a) }
    end
    return 0 if hole.empty?

    hole_ids = hole.map(&:persistent_id)
    dominant = nil
    dominant_set = false
    hole.each do |f|
      neighbours = f.edges.flat_map(&:faces).uniq.reject { |g| hole_ids.include?(g.persistent_id) }
      src = neighbours.max_by(&:area)
      mat = if src
              src.material || base.material
            else
              unless dominant_set
                dominant = dominant_material(base)
                dominant_set = true
              end
              dominant
            end
      f.material = mat
    end
    hole.size
  end

  # Material yang paling banyak dipakai (menurut luas face) di target asli; face tanpa material dihitung sebagai
  # material group-nya.
  def self.dominant_material(base)
    area = Hash.new(0.0)
    mats = {}
    entities_of(base).each do |f|
      next unless f.is_a?(Sketchup::Face)

      m = f.material || base.material
      key = m ? m.name : nil
      mats[key] = m
      area[key] += f.area
    end
    best = area.max_by { |_, a| a }
    best ? mats[best.first] : base.material
  end

  def self.finalize_result(result, base, link, fp = nil, hole_boxes = nil)
    copy_properties(base, result)
    restore_look(result, base, hole_boxes)
    result.set_attribute(DICT, ROLE, 'result')
    result.set_attribute(DICT, LINK, link)
    result.set_attribute(DICT, TX, result.transformation.to_a)
    result.set_attribute(DICT, FP, fp) if fp
  end

  # Sidik jari seluruh input satu pemotongan: posisi/ukuran sumber + void yang menyentuhnya (posisi dan ukuran).
  # `pairs` = [[void, transformasi void di ruang sumber]]. Kalau sama dengan yang tersimpan di hasil, memotong ulang
  # pasti menghasilkan bentuk yang sama, jadi mode live melewatinya. Hanya void yang menyentuh sumber ikut dihitung,
  # jadi menggeser satu void tidak membangun ulang dinding lain. Tombol manual (Terapkan/Refresh) tetap memotong semua.
  def self.cut_fp(src, pairs)
    rnd = ->(a) { a.to_a.map { |x| x.round(4) } }
    parts = [rnd.call(src.transformation), rnd.call(src.bounds.min), rnd.call(src.bounds.max)]
    pairs.map { |v, tx| [vent(v).persistent_id, rnd.call(tx), rnd.call(vbox(v).min), rnd.call(vbox(v).max)] }
         .sort_by(&:first).each { |x| parts << x }
    Digest::MD5.hexdigest(parts.inspect)
  end

  def self.new_link
    "#{Time.now.to_f}-#{rand(1_000_000)}"
  end

  # Hasil yang digeser user → sumbernya ikut digeser dengan selisih yang sama, lalu hasil dibangun ulang.
  def self.sync_moved(entities, source, result)
    rec = result.get_attribute(DICT, TX)
    return unless rec

    now = result.transformation.to_a
    return if same_tx?(now, rec)

    delta = result.transformation * Geom::Transformation.new(rec).inverse
    dlog { "sync_moved: hasil #{dinfo(result)} digeser -> source #{dinfo(source)} ikut digeser" }
    entities.transform_entities(delta, [source])
  end

  # Kembalikan target asli: hasil dibuang, source ditampilkan lagi dan tidak lagi dikendalikan void.
  def self.restore_source(src, result, model = Sketchup.active_model)
    erase_if_valid(result)
    restore_layer_from_attr(src, model)
    src.hidden = false
    clear_roles(src)
  end

  # Kembalikan target ke kondisi utuh sementara (dipakai Slice): hasil berlubang diganti sumbernya, group non-solid
  # dibersihkan dari pasangan sumber/hasil di dalamnya (rekursif). Void tetap aktif, jadi rebuild berikutnya
  # melubangi lagi bagian yang tersisa. Hasil: [daftar target pengganti (urutan sama), jumlah lubang yang dibatalkan].
  # Dipanggil di dalam operasi milik pemanggil.
  def self.restore_holes(entities, targets, depth = 3)
    count = 0
    mapped = targets.map do |t|
      next t unless t.valid?

      if role(t) == 'result'
        src = entities.find { |e| container?(e) && e.valid? && role(e) == 'source' && link_of(e) == link_of(t) }
        next t unless src

        sync_moved(entities, src, t)
        restore_source(src, t)
        count += 1
        src
      elsif !void?(t) && !role(t) && !dynamic?(t) && !solid?(t) && nested_has_state?(t, depth)
        t = ensure_unique(t) # definisi bersama group lain jangan ikut dibersihkan
        count += restore_inner(t, depth)
        t
      else
        t
      end
    end
    [mapped, count]
  end

  # Pulihkan semua pasangan sumber/hasil di dalam container `ent` sampai `depth` level.
  def self.restore_inner(ent, depth)
    count = 0
    inner = entities_of(ent)
    kids = inner.select { |e| container?(e) && e.valid? }
    results = kids.select { |e| role(e) == 'result' }.each_with_object({}) { |r, h| h[link_of(r)] = r }
    kids.select { |e| role(e) == 'source' }.each do |src|
      res = results[link_of(src)]
      next unless res&.valid? # hasilnya sudah dihapus user: sumber ini sisa, biarkan rebuild yang membersihkan

      sync_moved(inner, src, res)
      restore_source(src, res)
      count += 1
    end
    if depth.positive?
      kids.select { |e| e.valid? && !role(e) && !void?(e) && !dynamic?(e) && !solid?(e) && nested_has_state?(e, depth - 1) }.each do |kid|
        count += restore_inner(ensure_unique(kid), depth - 1)
      end
    end
    count
  end

  # Tahan pemantau mode live selama blok (perubahan di dalamnya dikerjakan pemanggil sendiri, termasuk rebuild),
  # lalu pindai ulang supaya tanda tangan model terbaru dipakai sebagai acuan.
  def self.hold_live
    prev = @busy
    @busy = true
    yield
  ensure
    @busy = prev
    invalidate_scan_cache
    rescan(Sketchup.active_model) unless prev
  end

  def self.rebuild_source(entities, source, old_result, voids, stats, out)
    # Sisa versi lama: dynamic component tidak boleh dilubangi, jadi kembalikan ke kondisi utuh
    return restore_source(source, old_result) if dynamic?(source)

    # Hasil sudah dihapus user → sumber tersembunyi ikut dihapus (jangan hidup lagi)
    unless old_result
      dlog { "rebuild_source: source #{dinfo(source)} TANPA hasil -> source DIHAPUS" }
      return erase_if_valid(source)
    end

    rel = voids.select { |v| v.valid? && overlap?(source.bounds, v.bounds) }
    fp = cut_fp(source, rel.map { |v| [v, v.transformation] })
    if @incremental && old_result.valid? && old_result.get_attribute(DICT, FP) == fp
      dlog { "rebuild_source: #{dinfo(source)} input tidak berubah -> dilewati" }
      return
    end

    done = cut_copy(entities, source, voids, stats)
    return unless done # gagal: biarkan hasil lama

    cur, changed = done
    if changed
      dlog { "rebuild_source: source #{dinfo(source)} -> hasil diganti #{dinfo(cur)}" }
      finalize_result(cur, source, link_of(source), fp, rel.map(&:bounds))
      erase_if_valid(old_result)
      out << cur
    else
      dlog { "rebuild_source: source #{dinfo(source)} tidak kena void lagi -> DIPULIHKAN, hasil #{dinfo(old_result)} dibuang" }
      # Sudah tidak bertabrakan (void digeser menjauh / dihapus / dilepas): kembalikan target asli
      erase_if_valid(cur)
      erase_if_valid(old_result)
      source.hidden = false
      clear_roles(source)
    end
  end

  # Inti: sinkronkan semua sumber/hasil dengan posisi void sekarang, lalu daftarkan target polos yang baru
  # bertabrakan. Hasil: array grup hasil yang dibuat.
  def self.rebuild(model, stats)
    entities = model.active_entities
    # Satu lintasan: tiap container dibaca atributnya sekali, lalu dipilah (void / source / result).
    all, all_voids, sources, results = classify_containers(entities)
    # Void hasil copy (definisi dipakai bersama) dijadikan unik dulu; entity bisa berganti objek, jadi pilih ulang.
    if all_voids.any? { |v| shared_definition?(v) }
      all_voids.each { |v| ensure_unique(v) if v.valid? && shared_definition?(v) }
      all, all_voids, sources, results = classify_containers(entities)
    end
    stats[:off] = all_voids.count { |v| void_off?(v) }
    voids = all_voids.reject { |v| void_off?(v) }.select do |v|
      ok = shape_ok?(entities, v)
      stats[:bad_voids] += 1 unless ok
      ok
    end
    stats[:voids] = voids.size
    dlog { "rebuild: void aktif=#{voids.size} nonaktif=#{stats[:off]} source=#{sources.size} hasil=#{results.size}" }
    voids.each { |v| dlog { "  void #{dinfo(v)} box=#{dbox(v.bounds)}" } } if dev_log?
    # Void yang ada di dalam group lain: lubangnya harus tetap terjaga dari level mana pun rebuild dijalankan
    nested_voids = with_scan_memo { nested_void_refs(entities, Geom::Transformation.new, NESTED_VOID_DEPTH, true, [], nil, true) }
    nested_voids.each { |v| dlog { "  void BERSARANG #{dinfo(v.ent)} box=#{dbox(v.box)}" } } if dev_log?
    cutters = voids + nested_voids
    # Hasil yang di-copy user membawa id pasangan yang sama: yang tertua dianggap asli, salinannya jadi group biasa
    results.group_by { |r| link_of(r) }.each_value do |same|
      next if same.size < 2

      keep = same.min_by(&:persistent_id)
      dlog { "link kembar #{same.size}x: pertahankan #{dinfo(keep)}, lepas #{(same - [keep]).size} salinan" }
      (same - [keep]).each { |dup| clear_roles(dup) }
    end
    results = results.select { |r| role(r) == 'result' }
    out = []

    # Pasangan dihitung sekali di awal: rebuild_source menghapus hasil lama, dan membaca atribut entity yang
    # sudah terhapus melempar "reference to deleted Entity".
    by_link = results.each_with_object({}) { |r, h| h[link_of(r)] = r }
    pairs = sources.map { |s| [s, by_link[link_of(s)]] }
    pairs.each { |s, r| sync_moved(entities, s, r) if r }
    pairs.each { |s, r| rebuild_source(entities, s, r, voids, stats, out) }

    skipped = {}
    # Non-solid top-level yang masih memiliki state (child source/result) — perlu diproses ulang
    # meski void tidak overlap lagi, supaya state dibersihkan secara rekursif (maks 3 level).
    nonsolid_with_state = with_scan_memo do
      all.select do |t|
        t.valid? && !void?(t) && !role(t) && !t.hidden? && !dynamic?(t) && subtree_flags(t)[1] && !solid?(t)
      end
    end
    nonsolid_with_state.each { |t| rebuild_nonsolid_children(model, t, cutters, stats, 3) }

    all.each do |t|
      next if !t.valid? || void?(t) || role(t) || t.hidden?

      # Bounding box dulu (murah): kebanyakan group jauh dari semua void, tidak perlu menghitung manifold-nya.
      next unless cutters.any? { |v| overlap?(t.bounds, vbox(v)) }

      is_solid = solid?(t)
      # Target solid level atas hanya dipotong void level atas. Group non-solid juga dipengaruhi void bersarang.
      next unless (is_solid ? voids : cutters).any? { |v| overlap?(t.bounds, vbox(v)) }

      if dynamic?(t) # dynamic component (dan isinya) tidak boleh dilubangi
        stats[:dynamic] += 1
        next
      end

      unless is_solid
        # Group non-solid: kelola children solid di dalamnya secara rekursif (maks 3 level)
        # Lewati jika sudah diproses di pass nonsolid_with_state di atas
        next if nonsolid_with_state.any? { |p| p.equal?(t) }

        rebuild_nonsolid_children(model, t, cutters, stats, 3)
        next
      end

      done = cut_copy(entities, t, voids, stats)
      next unless done

      cur, changed = done
      unless changed
        erase_if_valid(cur)
        next
      end

      link = new_link
      near = voids.select { |v| overlap?(t.bounds, v.bounds) }
      finalize_result(cur, t, link, cut_fp(t, near.map { |v| [v, v.transformation] }), near.map(&:bounds))
      t.set_attribute(DICT, ROLE, 'source')
      t.set_attribute(DICT, LINK, link)
      t.hidden = true
      out << cur
    end
    stats[:skipped] = skipped.size
    out.select(&:valid?)
  end

  # Pilah container satu lintasan: [semua, void, source, result].
  def self.classify_containers(entities)
    all = []
    voids = []
    sources = []
    results = []
    entities.each do |e|
      next unless container?(e)

      all << e
      if void?(e)
        voids << e
      else
        case role(e)
        when 'source' then sources << e
        when 'result' then results << e
        end
      end
    end
    [all, voids, sources, results]
  end

  # solid_shape? menduplikasi pemotong kalau void berisi group (pintu dll). Di mode live hasilnya diingat per void
  # selama posisi, ukuran, dan jumlah isinya sama, supaya void yang tidak disentuh tidak diperiksa ulang tiap update.
  def self.shape_ok?(entities, void_src)
    return solid_shape?(entities, void_src) unless @incremental

    key = [void_src.transformation.to_a.map { |x| x.round(4) }, void_src.bounds.min.to_a.map { |x| x.round(3) },
           void_src.bounds.max.to_a.map { |x| x.round(3) }, entities_of(void_src).length]
    hit = (@shape_ok ||= {})[void_src.persistent_id]
    return hit[1] if hit && hit[0] == key

    ok = solid_shape?(entities, void_src)
    @shape_ok[void_src.persistent_id] = [key, ok]
    ok
  end

  def self.new_stats
    { voids: 0, cut: 0, skipped: 0, failed: 0, bad_voids: 0, dynamic: 0, off: 0 }
  end

  # Jalankan rebuild sebagai satu operasi. transparent: menyatu dengan langkah Undo sebelumnya (dipakai live).
  # Blok (opsional) dijalankan di dalam operasi yang sama sebelum rebuild, jadi Undo cukup sekali.
  def self.run_rebuild(model, name, transparent)
    stats = new_stats
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @busy = true
    @incremental = transparent # live / lepas void: lewati hasil yang inputnya tidak berubah; tombol manual memotong ulang semua
    model.start_operation(name, true, false, transparent)
    begin
      yield if block_given?
      results = rebuild(model, stats)
      stats[:cut] = results.size
      model.commit_operation
      dlog { "run_rebuild '#{name}' #{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round}ms #{stats}" }
      [stats, results]
    rescue => e
      model.abort_operation
      raise e
    end
  ensure
    @busy = false
    @incremental = false
    # Cache bendera sengaja tidak dikosongkan: rebuild mengubah jumlah isi group yang disentuhnya (hasil/source
    # ditambah atau dibuang), dan sync_scan_flags membuang hanya entri itu. Mengosongkan semuanya membuat rescan
    # sesudah tiap update menelusuri ulang seluruh project.
    rescan(model)
  end

  # Helper rekursif: cek apakah container atau nested-nya (maks `depth` level) punya child berperan source/result.
  def self.nested_has_state?(ent, depth)
    return false if depth < 0

    entities_of(ent).any? do |e|
      next false unless container?(e)
      next true if role(e)

      depth > 0 && nested_has_state?(e, depth - 1)
    end
  rescue StandardError
    false
  end

  # Helper rekursif: bake (bersihkan source/result) di dalam sebuah container sampai `depth` level.
  def self.bake_inner(ent, depth)
    count = 0
    inner = entities_of(ent)
    inner.select { |e| container?(e) && role(e) == 'source' }.each(&:erase!)
    inner.select { |e| container?(e) && role(e) == 'result' }.each do |r|
      clear_roles(r)
      count += 1
    end
    if depth > 0
      inner.select { |e| container?(e) && !role(e) && !void?(e) }.each do |child|
        count += bake_inner(child, depth - 1)
      end
    end
    count
  rescue StandardError
    count
  end

  # Finalisasi: hapus semua sumber tersembunyi, hasil jadi group biasa (void tidak lagi mengendalikannya).
  # Juga bersihkan source/result di dalam parent group non-solid secara rekursif (maks 3 level).
  def self.bake(model)
    entities = model.active_entities
    all = entities.select { |e| container?(e) }
    count = 0
    @busy = true
    model.start_operation('Finalisasi Void', true)
    begin
      # Top-level source/result
      all.select { |e| role(e) == 'source' }.each(&:erase!)
      all = all.select(&:valid?) # entity yang sudah di-erase melempar error kalau dibaca
      all.select { |e| role(e) == 'result' }.each do |r|
        clear_roles(r)
        count += 1
      end
      # Source/result di dalam non-solid parent secara rekursif (maks 3 level)
      all.select { |e| !void?(e) && !role(e) && !solid?(e) }.each do |parent|
        count += bake_inner(parent, 3)
      end
      model.commit_operation
    rescue => e
      model.abort_operation
      raise e
    end
    count
  ensure
    @busy = false
    invalidate_scan_cache
    rescan(model)
  end

  # Jumlah hasil lubang (result) di entities ini, termasuk di dalam group non-solid sampai `depth` level.
  def self.count_results(ents, depth = 3)
    ents.sum do |e|
      next 0 unless container?(e) && e.valid?
      next 1 if role(e) == 'result'
      next 0 if void?(e) || dynamic?(e) || depth <= 0

      count_results(entities_of(e), depth - 1)
    end
  end

  # "Batalkan Lubang": nonaktifkan void terpilih (atau semua void kalau tidak ada yang dipilih), lalu bangun ulang
  # tanpa mereka sehingga target yang tadinya dilubangi pulih utuh. Void tetap ada sebagai marker (abu-abu) dan
  # tidak melubangi lagi sampai diaktifkan lewat "Terapkan Void". Void lain yang aktif tetap melubangi.
  # Mengembalikan { count: lubang yang ditutup, voids: void yang baru dinonaktifkan, total: void yang dituju }.
  def self.cancel_holes(model, picked = nil)
    all_voids = model.active_entities.select { |e| void?(e) }
    targets = picked.nil? || picked.empty? ? all_voids : picked.select { |e| void?(e) }
    return { count: 0, voids: 0, total: 0 } if targets.empty?

    before = count_results(model.active_entities)
    dlog { "cancel_holes: target=#{targets.map { |t| dinfo(t) }.join(', ')} hasil sebelum=#{before}" }
    turned_off = 0
    run_rebuild(model, 'Batalkan Lubang Void', false) { turned_off = set_voids_active(model, targets, false) }
    { count: [before - count_results(model.active_entities), 0].max, voids: turned_off, total: targets.size }
  end

  # ── Mode live: pantau void ────────────────────────────────────────────────

  def self.context_key(model)
    (model.active_path || []).map(&:persistent_id)
  end

  # Satu lintasan atas isi konteks aktif: [id yang dipantau, jumlah void]. Group biasa dilewati lewat cache bendera
  # (tanpa menelusuri isinya, tanpa menghitung manifold) kecuali di dalamnya memang ada void/source/result.
  def self.scan_top(model)
    ids = []
    voids = 0
    with_scan_memo do
      model.active_entities.each do |e|
        next unless container?(e)

        if void?(e)
          voids += 1
          ids << e.persistent_id
        elsif role(e) || nest_with_state?(e) || nest_with_voids?(e)
          ids << e.persistent_id
        end
      end
    end
    [ids, voids]
  end

  def self.watched_ids(model)
    scan_top(model).first
  end

  # Group non-solid yang di dalamnya ada void (bersarang): menggeser void itu (atau dinding di sekitarnya)
  # dengan Move harus memperbarui lubang, padahal transformasi group terluarnya tidak berubah.
  def self.nest_with_voids?(ent)
    !void?(ent) && !role(ent) && !dynamic?(ent) && subtree_flags(ent)[0] && !solid?(ent)
  rescue StandardError
    false
  end

  # Void aktif di ruang konteks aktif: yang level atas ditambah yang bersarang. Dipakai memangkas signature supaya
  # hanya cabang di sekitar void yang ditelusuri.
  def self.scan_void_boxes(model)
    ents = model.active_entities
    boxes = ents.select { |e| container?(e) && void?(e) && !void_off?(e) }.map(&:bounds)
    nested_void_refs(ents, Geom::Transformation.new, NESTED_VOID_DEPTH, true, [], nil, true).each { |r| boxes << r.box }
    boxes
  end

  # Transformasi (dibulatkan) group/component terlihat di dalam `ent`, sampai `depth` level. Dipakai untuk
  # mendeteksi Move pada anak bersarang (void, dinding, atau hasil berlubang) yang tidak mengubah transformasi
  # group terluar. Source tersembunyi dan dynamic component tidak ikut dipindai, supaya stabil setelah rebuild.
  # Dengan `boxes` (bbox void aktif di ruang konteks), hanya anak yang bersinggungan dengan salah satu void yang
  # dicatat dan ditelusuri lebih dalam: dinding yang jauh dari void tidak memengaruhi lubang, dan dinding yang
  # bergeser masuk/keluar area void tetap terdeteksi karena muncul/hilang dari daftar. `acc` = transformasi ruang
  # dalam `ent` ke ruang konteks.
  def self.deep_signature(ent, depth = NESTED_VOID_DEPTH, boxes = nil, acc = nil)
    return [] if depth < 0

    local = nil
    if boxes
      return [] if boxes.empty?

      acc ||= ent.transformation
      inv = acc.inverse
      local = boxes.map { |b| world_bounds(b, inv) }
    end
    entities_of(ent).each_with_object([]) do |e, out|
      next unless container?(e) && e.valid? && !e.hidden? && !dynamic?(e)
      next if local && local.none? { |lb| overlap?(e.bounds, lb) }

      out << [e.persistent_id, e.transformation.to_a.map { |x| x.round(4) }]
      out.concat(deep_signature(e, depth - 1, boxes, acc && acc * e.transformation)) if depth.positive? && !solid?(e)
    end
  rescue StandardError
    []
  end

  # Group non-solid yang di dalamnya ada lubang (source/result): kalau group ini digeser, lubangnya harus
  # dihitung ulang (ditutup kalau void tidak ikut terbawa). Group biasa tanpa state tidak perlu dipantau.
  def self.nest_with_state?(ent)
    !void?(ent) && !role(ent) && !dynamic?(ent) && subtree_flags(ent)[1] && !solid?(ent)
  rescue StandardError
    false
  end

  # Target polos (belum berlubang) yang saat ini menyentuh void aktif, beserta posisinya. Kalau dinding digeser
  # masuk ke area void (atau ditempel di sana), daftar ini berubah sehingga live mode melubanginya otomatis.
  # Dilewati kalau tidak ada void aktif, supaya model tanpa void tidak membayar biaya apa pun.
  def self.touching_signature(model, boxes = nil)
    ents = model.active_entities
    active = ents.select { |e| container?(e) && void?(e) && !void_off?(e) }
    return [] if active.empty?

    boxes ||= scan_void_boxes(model)
    ents.select { |e| container?(e) && !void?(e) && !role(e) && !e.hidden? && !dynamic?(e) }
        .select { |e| active.any? { |v| overlap?(e.bounds, v.bounds) } }
        .map { |e| [e.persistent_id, :touch, e.transformation.to_a.map { |x| x.round(4) }, solid?(e) ? [] : deep_signature(e, NESTED_VOID_DEPTH, boxes)] }
  end

  def self.signature(model)
    with_scan_memo do
      boxes = scan_void_boxes(model)
      watched_signature(model, boxes) + touching_signature(model, boxes)
    end
  end

  def self.watched_signature(model, boxes = nil)
    boxes ||= scan_void_boxes(model)
    (@watch || []).map do |pid|
      e = model.find_entity_by_persistent_id(pid)
      next [pid, :gone] unless e && e.valid?

      if void?(e)
        [pid, e.transformation.to_a.map { |x| x.round(4) }, e.bounds.min.to_a.map { |x| x.round(3) }, e.bounds.max.to_a.map { |x| x.round(3) }]
      elsif role(e) == 'result'
        rec = e.get_attribute(DICT, TX)
        [pid, rec && same_tx?(e.transformation.to_a, rec) ? 0 : 1]
      elsif role(e) == 'source'
        [pid, :src]
      else
        [pid, :nest, e.transformation.to_a.map { |x| x.round(4) }, deep_signature(e, NESTED_VOID_DEPTH, boxes)]
      end
    end
  end

  def self.rescan(model)
    return unless model && model.valid?

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    refresh_dialog_count(model, true) unless @busy
    @stale = false
    @ctx = context_key(model)
    if void_possible?(model)
      @watch, @void_n = scan_top(model)
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @sig = signature(model)
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      dlog { "  rescan: watched_ids #{((t1 - t0) * 1000).round}ms, signature #{((t2 - t1) * 1000).round}ms" }
      @ent_len = model.active_entities.length
    else
      @watch = []
      @sig = []
      @ent_len = @void_n = 0
    end
    dlog { "rescan #{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round}ms watch=#{@watch.size}" }
  rescue StandardError => e
    puts "[Boosok Void] rescan: #{e.message}"
  end

  # Gerbang murah: void menandai modelnya (material/tag Void dibuat saat pertama kali menandai). Model yang belum
  # pernah punya void tidak perlu dipindai sama sekali — baik saat rescan maupun tiap transaksi.
  def self.void_possible?(model)
    !!(model.materials[MATERIAL_NAME] || model.materials[OFF_MATERIAL_NAME] || model.layers[VOID_HIDDEN_TAG])
  end

  # Pindah konteks edit (buka/tutup group) dan undo/redo cuma menandai baseline kedaluwarsa. Rescan penuh memindai
  # seluruh isi konteks (rekursif sampai 4 level) sehingga di model besar terasa lag kalau dijalankan tiap navigasi.
  # Baseline baru diambil lazy, tepat sebelum transaksi berikutnya (lihat refresh_if_stale).
  def self.mark_stale(model)
    return if @busy

    @stale = true
    dlog { 'konteks/undo berubah: baseline ditandai kedaluwarsa' }
    refresh_dialog_count(model, true)
    schedule_idle_baseline
  end

  IDLE_BASELINE_DELAY = 0.8 unless defined?(IDLE_BASELINE_DELAY)

  # Ambil baseline saat user berhenti (bukan saat sedang pindah-pindah group). Navigasi beruntun cuma menunda timer,
  # jadi tidak ada pemindaian sia-sia. Kalau transaksi dimulai lebih dulu, refresh_if_stale sudah jalan di sana.
  def self.schedule_idle_baseline
    UI.stop_timer(@idle_timer) if @idle_timer
    @idle_timer = UI.start_timer(IDLE_BASELINE_DELAY, false) do
      @idle_timer = nil
      refresh_if_stale(Sketchup.active_model)
    end
  end

  def self.refresh_if_stale(model)
    return unless @stale && !@busy
    return unless model && model.valid? && live?(model) && licensed?

    rescan(model)
  end

  def self.licensed?
    !defined?(BoosokTools::License) || BoosokTools::License.can_use?
  end

  # Dorong jumlah void terbaru ke dialog yang sedang terbuka (copy/hapus/undo void tanpa buka ulang dialog).
  # Hanya memindai saat jumlah entitas berubah (atau force), dan hanya kalau dialog Void memang tampil.
  def self.refresh_dialog_count(model, force = false)
    dlg = @dialog
    return unless dlg && dlg.visible?
    return if defined?(BoosokTools::Hub) && BoosokTools::Hub.current_tool != 'void'

    n = model.active_entities.length
    return if !force && n == @dlg_len

    @dlg_len = n
    count = void_count(model)
    return if !force && count == @dlg_count

    @dlg_count = count
    dlg.execute_script("if (typeof onCount === 'function') onCount(#{count});")
  rescue StandardError
    nil
  end

  def self.on_commit(model)
    return if @busy

    refresh_dialog_count(model)
    return if @watch.nil?
    return unless live?(model) && licensed?

    unless void_possible?(model)
      @gated = true
      return
    end
    if @gated
      @gated = false
      rescan(model)
      return schedule_recut if @void_n.to_i.positive?

      return
    end

    # Baseline kedaluwarsa atau konteks sudah pindah (transaksi ini sendiri yang memindahkannya): jangan pindai di sini,
    # cukup tandai. Baru diambil saat jeda (schedule_idle_baseline) atau tepat sebelum transaksi berikutnya.
    if @stale || context_key(model) != @ctx
      @stale = true
      schedule_idle_baseline
      return
    end
    # Jumlah entitas berubah (mis. void di-copy): kalau jumlah void bertambah, terapkan otomatis.
    # Hanya dipindai kalau memang sudah ada void (hemat), dan hanya saat jumlah entitas berubah.
    n = model.active_entities.length
    if n != @ent_len
      @ent_len = n
      return schedule_recut if @void_n.to_i.positive? && void_count(model) != @void_n
    end
    return if signature(model) == @sig

    schedule_recut
  end

  # Pengaman: kalau live terus memicu rebuild beruntun (tanda tangan model tidak pernah stabil), hentikan supaya
  # SketchUp tidak terkunci mengerjakan rebuild terus-menerus. Edit manual berikutnya jalan normal lagi.
  RECUT_BURST = 3 unless defined?(RECUT_BURST)
  RECUT_BURST_WINDOW = 6.0 unless defined?(RECUT_BURST_WINDOW)

  def self.recut_loop?
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @recut_times = (@recut_times || []).select { |t| now - t < RECUT_BURST_WINDOW }
    @recut_times << now
    @recut_times.size > RECUT_BURST
  end

  def self.schedule_recut
    if recut_loop?
      puts '[Boosok Void] live: rebuild beruntun terdeteksi, update otomatis dilewati (jalankan Refresh Void kalau perlu).'
      @recut_times.clear
      return
    end

    UI.stop_timer(@timer) if @timer
    @timer = UI.start_timer(RECUT_DELAY, false) do
      @timer = nil
      model = Sketchup.active_model
      next unless model && model.valid? && !@busy

      begin
        run_rebuild(model, 'Update Void', true)
      rescue => e
        puts "[Boosok Void] update gagal: #{e.class}: #{e.message}"
      end
    end
  end

  # ── Pindah scene ──────────────────────────────────────────────────────────
  # Scene menyimpan daftar objek tersembunyi. Source (utuh, tersembunyi) dibuat SESUDAH scene disimpan, jadi tidak ada
  # di daftar itu: pindah scene memunculkannya lagi dan menutup lubang (hasil berlubang tertimpa source utuh).
  # Solusinya menyembunyikan lagi semua source setiap kali scene aktif berganti.
  SCENE_SETTLE_DELAY = 0.5 unless defined?(SCENE_SETTLE_DELAY)

  # Sembunyikan source yang terlihat di `ents` (dan di dalam group non-solid yang punya lubang, sampai `depth` level).
  # Hasil: jumlah source yang disembunyikan lagi.
  def self.rehide_in(ents, depth)
    ents.sum do |e|
      next 0 unless container?(e) && e.valid?

      if role(e) == 'source'
        next 0 if e.hidden?

        e.hidden = true
        1
      elsif depth.positive? && nest_with_state?(e)
        rehide_in(entities_of(e), depth - 1)
      else
        0
      end
    end
  end

  def self.rehide_sources(model)
    contexts = [model.entities, model.active_entities].uniq
    with_scan_memo { contexts.sum { |ents| rehide_in(ents, 3) } }
  end

  def self.scene_key(model)
    page = model.pages.selected_page
    page && [page.persistent_id, page.name]
  rescue StandardError
    nil
  end

  # Dipanggil tiap tampilan berubah (orbit, animasi transisi scene). Murah: hanya membandingkan scene terpilih.
  # Penyembunyian ditunda sampai tampilan tenang, karena transisi scene menerapkan status objek sepanjang animasinya.
  def self.check_scene_change(model)
    return if @busy || !model.valid?

    key = scene_key(model)
    pending = @scene_key != key
    @scene_key = key
    return unless pending || @scene_pending

    @scene_pending = true
    UI.stop_timer(@scene_timer) if @scene_timer
    @scene_timer = UI.start_timer(SCENE_SETTLE_DELAY, false) do
      @scene_timer = nil
      @scene_pending = false
      fix_after_scene_change(Sketchup.active_model)
    end
  end

  def self.fix_after_scene_change(model)
    return unless model && model.valid? && !@busy && void_possible?(model)

    hidden_count = nil
    @busy = true
    begin
      model.start_operation('Sembunyikan Source Void', true)
      hidden_count = rehide_sources(model)
      hidden_count.positive? ? model.commit_operation : model.abort_operation
    rescue StandardError => e
      model.abort_operation
      puts "[Boosok Void] sembunyikan source setelah pindah scene gagal: #{e.class}: #{e.message}"
    ensure
      @busy = false
    end
    dlog { "pindah scene: #{hidden_count.inspect} source disembunyikan lagi" }
  end

  class VoidViewObserver < Sketchup::ViewObserver
    def onViewChanged(view)
      BoosokTools::Void.check_scene_change(view.model)
    rescue StandardError
      nil
    end
  end

  class VoidModelObserver < Sketchup::ModelObserver
    def onTransactionCommit(model)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      BoosokTools::Void.on_commit(model)
      BoosokTools::Void.dlog("commit #{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round}ms")
    rescue StandardError
      nil
    end

    def onTransactionStart(model)
      BoosokTools::Void.refresh_if_stale(model)
    rescue StandardError
      nil
    end

    def onTransactionUndo(model)
      BoosokTools::Void.invalidate_scan_cache
      BoosokTools::Void.mark_stale(model)
    rescue StandardError
      nil
    end

    def onTransactionRedo(model)
      BoosokTools::Void.invalidate_scan_cache
      BoosokTools::Void.mark_stale(model)
    rescue StandardError
      nil
    end

    def onActivePathChanged(model)
      BoosokTools::Void.mark_stale(model)
    rescue StandardError
      nil
    end
  end

  class VoidAppObserver < Sketchup::AppObserver
    def onNewModel(model)
      BoosokTools::Void.attach_to_model(model)
    rescue StandardError
      nil
    end

    def onOpenModel(model)
      BoosokTools::Void.attach_to_model(model)
    rescue StandardError
      nil
    end

    def onActivateModel(model)
      BoosokTools::Void.attach_to_model(model)
    rescue StandardError
      nil
    end
  end

  def self.attach_to_model(model)
    return unless model && model.valid?

    detach_model_observer
    invalidate_scan_cache
    @model_observer ||= VoidModelObserver.new
    model.add_observer(@model_observer)
    @view_observer ||= VoidViewObserver.new
    @observed_view = model.active_view
    @observed_view.add_observer(@view_observer)
    @observed_model = model
    @scene_key = scene_key(model)
    rescan(model)
  end

  def self.detach_model_observer
    @observed_model.remove_observer(@model_observer) if @observed_model && @observed_model.valid? && @model_observer
    @observed_view.remove_observer(@view_observer) if @observed_view && @view_observer
  rescue StandardError
    nil
  ensure
    @observed_model = nil
    @observed_view = nil
  end

  # Dipanggil saat file ini dimuat (juga saat hot-reload: observer lama dilepas dulu supaya tidak dobel).
  def self.attach_observers
    detach_model_observer
    Sketchup.remove_observer(@app_observer) if @app_observer
    @app_observer = VoidAppObserver.new
    Sketchup.add_observer(@app_observer)
    attach_to_model(Sketchup.active_model)
  rescue StandardError => e
    puts "[Boosok Void] attach_observers: #{e.message}"
  end

  # ── Dialog ────────────────────────────────────────────────────────────────

  def self.send_init_data(dialog)
    return unless dialog

    model = Sketchup.active_model
    data = { voids: model ? void_count(model) : 0, live: model ? live?(model) : true }
    dialog.execute_script("if (typeof init === 'function') init(#{data.to_json});")
  end

  def self.attach_callbacks(dialog)
    return unless dialog
    return if @dialog.equal?(dialog) # sudah terdaftar di dialog ini (hindari handler bertumpuk)
    @dialog = dialog

    dialog.add_action_callback("void_mark") do |_ctx, on|
      model = Sketchup.active_model
      on = (on == true || on.to_s == 'true')
      picked = model ? model.selection.select { |e| container?(e) } : []
      if picked.empty?
        dialog.execute_script("resetVoidButtons(); showToast('Seleksi minimal 1 group/component dulu.', 'error');")
        next
      end

      begin
        model.start_operation(on ? 'Jadikan Void' : 'Batalkan Void', true)
        begin
          changed = picked.count { |e| mark(model, e, on) }
          model.commit_operation
        rescue => e
          model.abort_operation
          raise e
        end
        rescan(model)
        # Void dilepas: lubangnya harus hilang juga (hanya kalau mode live aktif; kalau tidak, lewat Terapkan Void)
        run_rebuild(model, 'Update Void', true) if !on && live?(model) && licensed? && changed.positive?
        payload = { changed: changed, on: on, voids: void_count(model) }
        dialog.execute_script("onMarked(#{payload.to_json});")
      rescue => e
        dialog.execute_script("resetVoidButtons(); showToast(#{("Gagal: " + e.message).to_json}, 'error');")
      end
    end

    dialog.add_action_callback("void_apply") do |_ctx|
      model = Sketchup.active_model
      unless model
        dialog.execute_script("resetVoidButtons(); showToast('Tidak ada model yang aktif.', 'error');")
        next
      end

      begin
        # Terapkan = aktifkan lagi void terpilih (atau semua void kalau tidak ada yang dipilih), lalu lubangi
        voids_now = model.active_entities.select { |e| void?(e) }
        picked = model.selection.select { |e| void?(e) }
        stats, results = run_rebuild(model, 'Terapkan Void', false) do
          set_voids_active(model, picked.empty? ? voids_now : picked, true)
        end
        model.selection.clear
        model.selection.add(results)
        dialog.execute_script("onApplied(#{stats.to_json});")
      rescue => e
        dialog.execute_script("resetVoidButtons(); showToast(#{("Gagal menerapkan void: " + e.message).to_json}, 'error');")
      end
    end

    dialog.add_action_callback("void_bake") do |_ctx|
      model = Sketchup.active_model
      begin
        count = model ? bake(model) : 0
        dialog.execute_script("onBaked(#{{ count: count }.to_json});")
      rescue => e
        dialog.execute_script("resetVoidButtons(); showToast(#{("Gagal finalisasi: " + e.message).to_json}, 'error');")
      end
    end

    dialog.add_action_callback("void_refresh") do |_ctx|
      model = Sketchup.active_model
      unless model
        dialog.execute_script("resetVoidButtons(); showToast('Tidak ada model yang aktif.', 'error');")
        next
      end
      begin
        stats, results = run_rebuild(model, 'Refresh Void', false)
        model.selection.clear
        model.selection.add(results)
        dialog.execute_script("onRefreshed(#{stats.to_json});")
      rescue => e
        dialog.execute_script("resetVoidButtons(); showToast(#{("Gagal refresh: " + e.message).to_json}, 'error');")
      end
    end

    dialog.add_action_callback("void_reset_cuts") do |_ctx|
      model = Sketchup.active_model
      unless model
        dialog.execute_script("resetVoidButtons(); showToast('Tidak ada model yang aktif.', 'error');")
        next
      end
      begin
        res = cancel_holes(model, model.selection.to_a)
        dialog.execute_script("onCutsReset(#{res.to_json});")
      rescue => e
        dialog.execute_script("resetVoidButtons(); showToast(#{("Gagal membatalkan lubang: " + e.message).to_json}, 'error');")
      end
    end

    dialog.add_action_callback("void_live") do |_ctx, on|
      model = Sketchup.active_model
      next unless model

      model.set_attribute(SETTINGS, 'live', on == true || on.to_s == 'true')
      rescan(model)
    end
  end
end

BoosokTools::Void.attach_observers

file_loaded(__FILE__)
