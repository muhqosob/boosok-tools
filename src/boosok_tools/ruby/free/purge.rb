require 'sketchup'
require 'json'
Sketchup.require 'boosok_tools/ruby/titlebar'

module BoosokTools::Purge
  UNTAGGED_NAMES = %w[Untagged Layer0].freeze unless defined?(UNTAGGED_NAMES)

  # Dipanggil Hub saat dialog ditutup supaya callback didaftarkan lagi di dialog berikutnya
  def self.release_dialog
    @dialog = nil
  end

  def self.run
    Sketchup.require 'boosok_tools/hub' unless defined?(BoosokTools::Hub)
    BoosokTools::Hub.open_or_show('purge')
  end

  # ── Pemindaian ────────────────────────────────────────────────────────────

  # Component definition yang tidak terjangkau dari entitas root model (termasuk yang cuma dipakai
  # oleh component lain yang juga tidak terpakai). Definition group/image/internal tidak ikut.
  def self.unused_definitions(model)
    reachable = {}
    queue = []
    enqueue = lambda do |entities|
      entities.each do |ent|
        next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)

        defn = ent.definition
        next if reachable[defn.name]

        reachable[defn.name] = true
        queue << defn
      end
    end

    enqueue.call(model.entities) # rubocop:disable SketchupSuggestions/ModelEntities -- harus mulai dari root model
    enqueue.call(queue.shift.entities) until queue.empty?

    model.definitions.reject do |d|
      reachable[d.name] || d.image? || d.group? || d.internal?
    end
  end

  # Kumpulkan material & tag yang dipakai oleh semua entitas di model (root + semua definition).
  def self.used_materials_and_tags(model)
    mats = {}
    tags = {}
    scan = lambda do |entities|
      entities.each do |ent|
        next unless ent.is_a?(Sketchup::Drawingelement)

        # Kunci pakai nama (unik per model) karena wrapper Ruby bukan jaminan objek yang sama
        mats[ent.material.name] = true if ent.material
        mats[ent.back_material.name] = true if ent.is_a?(Sketchup::Face) && ent.back_material
        tags[ent.layer.name] = true
      end
    end

    scan.call(model.entities) # rubocop:disable SketchupSuggestions/ModelEntities -- harus mulai dari root model
    model.definitions.each { |d| scan.call(d.entities) unless d.image? }
    [mats, tags]
  end

  def self.unused_materials(model, used_mats = nil)
    used_mats ||= used_materials_and_tags(model)[0]
    model.materials.reject { |m| used_mats[m.name] }
  end

  # Tag yang tidak dipakai entitas mana pun. Tag "Untagged" dan tag aktif tidak pernah ikut.
  def self.unused_tags(model, used_tags = nil)
    used_tags ||= used_materials_and_tags(model)[1]
    model.layers.reject do |l|
      used_tags[l.name] || UNTAGGED_NAMES.include?(l.name) || l == model.active_layer
    end
  end

  def self.color_hex(color)
    return nil unless color

    format('#%02x%02x%02x', color.red, color.green, color.blue)
  rescue StandardError
    nil
  end

  def self.capture(model)
    used_mats, used_tags = used_materials_and_tags(model)
    {
      components: unused_definitions(model).map { |d| { n: d.name } }.sort_by { |h| h[:n].downcase },
      materials: unused_materials(model, used_mats).map { |m| { n: m.name, c: color_hex(m.color) } }.sort_by { |h| h[:n].downcase },
      tags: unused_tags(model, used_tags).map { |l| { n: l.name, c: color_hex(l.color) } }.sort_by { |h| h[:n].downcase }
    }
  end

  # ── Penghapusan ───────────────────────────────────────────────────────────

  # Hapus yang namanya ada di `wanted` (nil = semua yang tidak terpakai). Daftar "tidak terpakai" selalu
  # dihitung ulang di sini, jadi hasil capture lama tidak bisa menghapus sesuatu yang sudah terpakai lagi.
  def self.purge(model, wanted = nil)
    removed = { components: 0, materials: 0, tags: 0 }
    pick = lambda do |key, list|
      names = wanted && wanted[key].to_a.map(&:to_s)
      names ? list.select { |x| names.include?(x.name) } : list
    end

    pick.call('components', unused_definitions(model)).each do |d|
      removed[:components] += 1 if safe_remove { model.definitions.remove(d) }
    end
    # Material & tag dihitung setelah component dihapus supaya yang cuma dipakai component itu ikut terdeteksi
    used_mats, used_tags = used_materials_and_tags(model)
    pick.call('materials', unused_materials(model, used_mats)).each do |m|
      removed[:materials] += 1 if safe_remove { model.materials.remove(m) }
    end
    pick.call('tags', unused_tags(model, used_tags)).each do |l|
      removed[:tags] += 1 if safe_remove { model.layers.remove(l) }
    end
    removed
  end

  def self.safe_remove
    yield
    true
  rescue StandardError
    false
  end

  def self.execute_purge(dialog, wanted)
    model = Sketchup.active_model
    unless model
      dialog.execute_script("resetPurgeButtons(); showToast('Tidak ada model yang aktif.', 'error');")
      return
    end

    model.start_operation('Purge Unused', true)
    begin
      removed = purge(model, wanted)
      model.commit_operation
      payload = { removed: removed, data: capture(model) }
      dialog.execute_script("onPurged(#{payload.to_json});")
    rescue => e
      model.abort_operation
      dialog.execute_script("resetPurgeButtons(); showToast(#{("Gagal purge: " + e.message).to_json}, 'error');")
    end
  end

  # ── Callback dialog ───────────────────────────────────────────────────────

  def self.attach_callbacks(dialog)
    return unless dialog
    return if @dialog.equal?(dialog) # sudah terdaftar di dialog ini (hindari handler bertumpuk)
    @dialog = dialog

    dialog.add_action_callback("purge_capture") do |_ctx|
      model = Sketchup.active_model
      if model
        dialog.execute_script("onCaptured(#{capture(model).to_json});")
      else
        dialog.execute_script("resetPurgeButtons(); showToast('Tidak ada model yang aktif.', 'error');")
      end
    end

    dialog.add_action_callback("purge_selected") do |_ctx, json_data|
      wanted = JSON.parse(json_data.to_s) rescue {}
      execute_purge(dialog, wanted)
    end

    dialog.add_action_callback("purge_all") do |_ctx|
      execute_purge(dialog, nil)
    end
  end
end

file_loaded(__FILE__)
