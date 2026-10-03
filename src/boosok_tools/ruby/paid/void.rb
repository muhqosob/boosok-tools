require 'sketchup'
require 'json'
Sketchup.require 'boosok_tools/ruby/titlebar'

# Group void: group/component yang ditandai "void" dipakai sebagai pemotong. "Terapkan Void" melubangi setiap
# group/component SOLID lain (di konteks edit yang sama) yang bertabrakan dengan void.
#
# Non-destruktif: target asli (utuh) disimpan tersembunyi sebagai "sumber", dan yang terlihat adalah "hasil"
# yang berlubang. Saat void digeser (mode live), hasil dibangun ulang dari sumber sehingga lubang ikut bergeser.
# Void sendiri tidak pernah dipotong: yang dipakai memotong hanyalah salinannya.
#
# Group/component void boleh berisi group/component lain (mis. pintu): isi itu ikut bergerak bersama void tetapi
# TIDAK ikut memotong. Yang memotong hanya geometri polos (bentuk lubang) milik void itu sendiri.
module BoosokTools::Void
  DICT = 'BoosokTools'.freeze unless defined?(DICT)
  KEY = 'void'.freeze unless defined?(KEY)
  ORIG_MATERIAL = 'void_orig_material'.freeze unless defined?(ORIG_MATERIAL)
  ROLE = 'void_role'.freeze unless defined?(ROLE)   # 'source' (utuh, tersembunyi) / 'result' (berlubang)
  LINK = 'void_link'.freeze unless defined?(LINK)   # id yang memasangkan sumber dengan hasilnya
  TX = 'void_tx'.freeze unless defined?(TX)         # transformasi hasil saat dibuat (deteksi hasil digeser user)
  SETTINGS = 'BoosokTools_Void'.freeze unless defined?(SETTINGS)
  MATERIAL_NAME = 'Boosok Void'.freeze unless defined?(MATERIAL_NAME)
  UNTAGGED_NAMES = %w[Untagged Layer0].freeze unless defined?(UNTAGGED_NAMES)
  EPS = 0.001 unless defined?(EPS) # inci; toleransi bounding box
  RECUT_DELAY = 0.25 unless defined?(RECUT_DELAY)

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

  # Tandai / lepas tanda void. Material asli disimpan di atribut lalu dipulihkan saat tanda dilepas.
  def self.mark(model, ent, on)
    if on
      return false if void?(ent) || role(ent)

      ent.set_attribute(DICT, ORIG_MATERIAL, ent.material ? ent.material.name : '')
      ent.set_attribute(DICT, KEY, true)
      ent.material = void_material(model)
    else
      return false unless void?(ent)

      orig = ent.get_attribute(DICT, ORIG_MATERIAL, '').to_s
      ent.material = orig.empty? ? nil : model.materials[orig]
      ent.delete_attribute(DICT, KEY)
      ent.delete_attribute(DICT, ORIG_MATERIAL)
    end
    true
  end

  def self.void_count(model)
    model.active_entities.count { |e| void?(e) }
  end

  # ── Operasi solid ─────────────────────────────────────────────────────────

  def self.solid?(ent)
    ent.definition.manifold?
  rescue StandardError
    false
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

  def self.untagged_layer(model)
    model.layers.find { |l| UNTAGGED_NAMES.include?(l.name) } || model.layers[0]
  end

  # Salinan void yang hanya berisi bentuk pemotongnya (isi group/component dibuang dari salinan).
  # Salinan dan semua face/edge-nya diberi tag Untagged: face lubang yang terbentuk mewarisi tag pemotong,
  # jadi tag void yang tersembunyi tidak boleh ikut terbawa (bisa membuat face dinding lubang tidak terlihat).
  def self.cutter_from(entities, void_src)
    cutter = duplicate(entities, void_src)
    cutter.make_unique if cutter.is_a?(Sketchup::ComponentInstance) # jangan ubah definition milik void asli
    inner = entities_of(cutter)
    kids = inner.select { |e| container?(e) }
    inner.erase_entities(kids) unless kids.empty?
    untagged = untagged_layer(Sketchup.active_model)
    cutter.layer = untagged
    inner.each { |e| e.layer = untagged if e.is_a?(Sketchup::Drawingelement) }
    cutter
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

  def self.duplicate(entities, ent)
    copy = ent.is_a?(Sketchup::Group) ? ent.copy : entities.add_instance(ent.definition, ent.transformation)
    copy.hidden = false
    copy
  end

  def self.copy_properties(src, dst)
    dst.name = src.name
    dst.layer = src.layer
    dst.material = src.material if src.material
    (src.attribute_dictionaries || []).each do |dict|
      dict.each_pair do |k, v|
        next if dict.name == DICT && [ROLE, LINK, TX].include?(k)

        dst.set_attribute(dict.name, k, v)
      end
    end
  end

  def self.erase_if_valid(ent)
    ent.erase! if ent && ent.valid?
  end

  def self.clear_roles(ent)
    [ROLE, LINK, TX].each { |k| ent.delete_attribute(DICT, k) }
  end

  # Satu pemotongan: `cur` dikurangi `void`. Hasil: [grup hasil, berubah?] atau nil kalau gagal.
  # Perilaku Group#subtract di SketchUp: receiver.subtract(x) = x - receiver (sama dengan tool Subtract di UI),
  # jadi salinan void jadi receiver agar yang berlubang adalah `cur`. Receiver/argumen bisa terhapus oleh operasi.
  def self.cut_step(entities, cur, void_src)
    cutter = cutter_from(entities, void_src)
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
    cur = duplicate(entities, base)
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
    end
    [cur, changed]
  end

  def self.finalize_result(result, base, link)
    copy_properties(base, result)
    result.set_attribute(DICT, ROLE, 'result')
    result.set_attribute(DICT, LINK, link)
    result.set_attribute(DICT, TX, result.transformation.to_a)
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
    entities.transform_entities(delta, [source])
  end

  def self.rebuild_source(entities, source, old_result, voids, stats, out)
    # Hasil sudah dihapus user → sumber tersembunyi ikut dihapus (jangan hidup lagi)
    return erase_if_valid(source) unless old_result

    done = cut_copy(entities, source, voids, stats)
    return unless done # gagal: biarkan hasil lama

    cur, changed = done
    if changed
      finalize_result(cur, source, link_of(source))
      erase_if_valid(old_result)
      out << cur
    else
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
    all = entities.select { |e| container?(e) }
    voids = all.select { |e| void?(e) }.select do |v|
      ok = solid_shape?(entities, v)
      stats[:bad_voids] += 1 unless ok
      ok
    end
    stats[:voids] = voids.size
    sources = all.select { |e| role(e) == 'source' }
    results = all.select { |e| role(e) == 'result' }
    # Hasil yang di-copy user membawa id pasangan yang sama: yang tertua dianggap asli, salinannya jadi group biasa
    results.group_by { |r| link_of(r) }.each_value do |same|
      next if same.size < 2

      keep = same.min_by(&:persistent_id)
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
    all.each do |t|
      next if !t.valid? || void?(t) || role(t) || t.hidden?
      next unless voids.any? { |v| overlap?(t.bounds, v.bounds) }

      unless solid?(t)
        skipped[t.entityID] = true
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
      finalize_result(cur, t, link)
      t.set_attribute(DICT, ROLE, 'source')
      t.set_attribute(DICT, LINK, link)
      t.hidden = true
      out << cur
    end
    stats[:skipped] = skipped.size
    out.select(&:valid?)
  end

  def self.new_stats
    { voids: 0, cut: 0, skipped: 0, failed: 0, bad_voids: 0 }
  end

  # Jalankan rebuild sebagai satu operasi. transparent: menyatu dengan langkah Undo sebelumnya (dipakai live).
  def self.run_rebuild(model, name, transparent)
    stats = new_stats
    @busy = true
    model.start_operation(name, true, false, transparent)
    begin
      results = rebuild(model, stats)
      stats[:cut] = results.size
      model.commit_operation
      [stats, results]
    rescue => e
      model.abort_operation
      raise e
    end
  ensure
    @busy = false
    rescan(model)
  end

  # Finalisasi: hapus semua sumber tersembunyi, hasil jadi group biasa (void tidak lagi mengendalikannya).
  def self.bake(model)
    entities = model.active_entities
    all = entities.select { |e| container?(e) }
    count = 0
    @busy = true
    model.start_operation('Finalisasi Void', true)
    begin
      all.select { |e| role(e) == 'source' }.each(&:erase!)
      all.select { |e| role(e) == 'result' }.each do |r|
        clear_roles(r)
        count += 1
      end
      model.commit_operation
    rescue => e
      model.abort_operation
      raise e
    end
    count
  ensure
    @busy = false
    rescan(model)
  end

  # ── Mode live: pantau void ────────────────────────────────────────────────

  def self.context_key(model)
    (model.active_path || []).map(&:persistent_id)
  end

  def self.watched_ids(model)
    model.active_entities.select { |e| container?(e) && (void?(e) || role(e)) }.map(&:persistent_id)
  end

  def self.signature(model)
    (@watch || []).map do |pid|
      e = model.find_entity_by_persistent_id(pid)
      next [pid, :gone] unless e && e.valid?

      if void?(e)
        [pid, e.transformation.to_a.map { |x| x.round(4) }, e.bounds.min.to_a.map { |x| x.round(3) }, e.bounds.max.to_a.map { |x| x.round(3) }]
      elsif role(e) == 'result'
        rec = e.get_attribute(DICT, TX)
        [pid, rec && same_tx?(e.transformation.to_a, rec) ? 0 : 1]
      else
        [pid, :src]
      end
    end
  end

  def self.rescan(model)
    return unless model && model.valid?

    refresh_dialog_count(model, true) unless @busy
    @watch = watched_ids(model)
    @ctx = context_key(model)
    @sig = signature(model)
    @ent_len = model.active_entities.length
    @void_n = void_count(model)
  rescue StandardError => e
    puts "[Boosok Void] rescan: #{e.message}"
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

    if context_key(model) != @ctx
      rescan(model)
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

  def self.schedule_recut
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

  class VoidModelObserver < Sketchup::ModelObserver
    def onTransactionCommit(model)
      BoosokTools::Void.on_commit(model)
    rescue StandardError
      nil
    end

    def onTransactionUndo(model)
      BoosokTools::Void.rescan(model)
    rescue StandardError
      nil
    end

    def onTransactionRedo(model)
      BoosokTools::Void.rescan(model)
    rescue StandardError
      nil
    end

    def onActivePathChanged(model)
      BoosokTools::Void.rescan(model)
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
    @model_observer ||= VoidModelObserver.new
    model.add_observer(@model_observer)
    @observed_model = model
    rescan(model)
  end

  def self.detach_model_observer
    @observed_model.remove_observer(@model_observer) if @observed_model && @observed_model.valid? && @model_observer
  rescue StandardError
    nil
  ensure
    @observed_model = nil
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
        stats, results = run_rebuild(model, 'Terapkan Void', false)
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
