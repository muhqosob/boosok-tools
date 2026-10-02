require 'sketchup'
require 'json'

module DeepProperties
  @dialog = nil
  @callbacks_registered = false
  @dialog_registered_id = nil
  @scan_context = nil   # Entity yang di-scan (apapun: Edge, Face, Group, ComponentInstance)

  # ── Helpers ─────────────────────────────────────────────────────────────────

  # Normalisasi nama tag: Layer0 diganti menjadi Untagged
  def self.display_tag_name(raw_name)
    name = raw_name.to_s.strip
    (name == 'Layer0' || name.empty?) ? 'Untagged' : name
  end

  # Mencari layer di SketchUp (menangani Untagged <-> Layer0)
  def self.find_layer(model, tag_name)
    return nil unless model && model.layers
    if tag_name == 'Untagged'
      model.layers['Untagged'] || model.layers['Layer0'] || model.layers.find { |l| l.name == 'Layer0' }
    else
      model.layers[tag_name] || (tag_name == 'Layer0' ? model.layers['Untagged'] : nil)
    end
  end

  # Warna hex dari layer/tag
  def self.color_hex(layer)
    return '#cccccc' unless layer.respond_to?(:color)
    c = layer.color
    '#%02x%02x%02x' % [c.red, c.green, c.blue] rescue '#cccccc'
  end

  # Kumpulkan semua entitas rekursif dari entities tertentu
  def self.collect_all_entities(entities_list, &block)
    return unless entities_list
    entities_list.each do |ent|
      next unless ent.respond_to?(:valid?) && ent.valid?
      block.call(ent)
      inner = if ent.is_a?(Sketchup::Group)
                ent.entities
              elsif ent.is_a?(Sketchup::ComponentInstance)
                ent.definition.entities
              end rescue nil
      collect_all_entities(inner, &block) if inner
    end
  end

  # Dapatkan entitas yang di-scan berdasarkan objek yang dipilih (Edge, Face, Group, Component)
  def self.scan_root_entities(model)
    sel = model.selection.to_a
    if sel.empty?
      @scan_context = []
      return [[], nil, 'Pilih objek terlebih dahulu di SketchUp (Edge, Face, Group, atau Component).']
    end

    @scan_context = sel

    ctx_name = if sel.size == 1
                 ent = sel[0]
                 if ent.is_a?(Sketchup::ComponentInstance)
                   cname = ent.name.to_s.strip
                   cname.empty? ? ent.definition.name : "#{ent.definition.name} (#{cname})"
                 elsif ent.is_a?(Sketchup::Group)
                   gname = ent.name.to_s.strip
                   gname.empty? ? 'Group' : gname
                 elsif ent.is_a?(Sketchup::Edge)
                   '1 Edge'
                 elsif ent.is_a?(Sketchup::Face)
                   '1 Face'
                 else
                   ent.class.name.split('::').last rescue '1 Objek'
                 end
               else
                 "#{sel.size} Objek Terseleksi"
               end rescue 'Objek Terseleksi'

    [sel, ctx_name, nil]
  end

  # ── Hitung isi secara rekursif dengan memo per definisi ─────────────────────
  # Isi sebuah definisi cukup dihitung sekali lalu dijumlahkan ke tiap instance-nya.
  # Hasil sama dengan menelusuri setiap instance, tapi komponen yang dipakai ribuan kali
  # tidak ditelusuri ribuan kali.
  def self.add_counts(into, from)
    from.each do |tag, c|
      d = (into[tag] ||= { edges: 0, faces: 0, groups: 0, components: 0 })
      d[:edges] += c[:edges]
      d[:faces] += c[:faces]
      d[:groups] += c[:groups]
      d[:components] += c[:components]
    end
  end

  def self.count_entity(ent, counts, memo)
    return unless ent.respond_to?(:valid?) && ent.valid?
    raw_tag = ent.layer.name rescue 'Layer0'
    c = (counts[display_tag_name(raw_tag)] ||= { edges: 0, faces: 0, groups: 0, components: 0 })
    if ent.is_a?(Sketchup::Edge)
      c[:edges] += 1
    elsif ent.is_a?(Sketchup::Face)
      c[:faces] += 1
    elsif ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
      c[ent.is_a?(Sketchup::Group) ? :groups : :components] += 1
      defn = ent.definition rescue nil
      add_counts(counts, definition_counts(defn, memo)) if defn
    end
  end

  def self.definition_counts(defn, memo)
    key = defn.entityID
    return memo[key] if memo.key?(key)
    memo[key] = {} # cegah rekursi tak berujung
    h = {}
    defn.entities.each { |e| count_entity(e, h, memo) }
    memo[key] = h
  rescue
    {}
  end

  # ── Scan Tags ───────────────────────────────────────────────────────────────
  def self.scan_tags(model)
    root_list, ctx_name, err = scan_root_entities(model)
    if err
      return {
        error: err,
        tags: [],
        ctx_name: nil,
        total_ents: 0
      }
    end

    # Peta tag_name => { edges: N, faces: N, groups: N, components: N }
    counts = {}
    memo = {}
    root_list.each { |ent| count_entity(ent, counts, memo) }

    # Hanya menampilkan tag yang ada isinya di objek terpilih
    result = counts.keys.sort_by { |n| n.downcase }.map do |tag_name|
      c = counts[tag_name]
      total = c[:edges] + c[:faces] + c[:groups] + c[:components]
      next if total == 0

      layer = find_layer(model, tag_name)
      visible = layer.respond_to?(:visible?) ? layer.visible? : true

      {
        name:       tag_name,
        color:      color_hex(layer),
        visible:    visible,
        edges:      c[:edges],
        faces:      c[:faces],
        groups:     c[:groups],
        components: c[:components],
        total:      total
      }
    end.compact

    {
      tags:       result,
      ctx_name:   ctx_name,
      total_ents: counts.values.map { |c| c[:edges] + c[:faces] + c[:groups] + c[:components] }.inject(0, :+) || 0
    }
  end

  # ── Toggle Visibility Tag ───────────────────────────────────────────────────
  def self.toggle_tag_visibility(model, tag_name, visible)
    layer = find_layer(model, tag_name)
    return [false, "Tag '#{tag_name}' tidak ditemukan."] unless layer

    # Cegah menyembunyikan tag yang sedang aktif di SketchUp
    if !visible && layer == model.active_layer
      msg = (tag_name == 'Untagged' || layer.name == 'Layer0') ?
              "Tag 'Untagged' sedang aktif sehingga tidak bisa disembunyikan. Ubah tag aktif di SketchUp terlebih dahulu." :
              "Tag '#{tag_name}' sedang aktif sehingga tidak bisa disembunyikan. Ubah tag aktif di SketchUp terlebih dahulu."
      return [false, msg]
    end

    model.start_operation('Toggle Tag Visibility', true)
    layer.visible = visible
    model.commit_operation
    [true, nil]
  rescue => e
    model.abort_operation rescue nil
    [false, "Gagal mengubah visibilitas tag: #{e.message}"]
  end

  # ── Seleksi Subtipe Spesifik (Edge, Face, Group, Component) ─────────────────
  def self.select_by_tag_and_subtype(model, tag_name, subtype)
    return 0 unless @scan_context && !@scan_context.empty?

    sel = model.selection
    sel.clear
    matched = []
    target_tag = tag_name.to_s.downcase

    single_container = (@scan_context.size == 1 && (@scan_context[0].is_a?(Sketchup::Group) || @scan_context[0].is_a?(Sketchup::ComponentInstance))) ? @scan_context[0] : nil

    collect_all_entities(@scan_context) do |ent|
      next unless ent.respond_to?(:valid?) && ent.valid?
      raw_tag = ent.layer.name rescue 'Layer0'
      ent_tag = display_tag_name(raw_tag).downcase
      next unless ent_tag == target_tag

      case subtype.to_s.downcase
      when 'edge'
        matched << ent if ent.is_a?(Sketchup::Edge)
      when 'face'
        matched << ent if ent.is_a?(Sketchup::Face)
      when 'group'
        matched << ent if ent.is_a?(Sketchup::Group)
      when 'component'
        matched << ent if ent.is_a?(Sketchup::ComponentInstance)
      end
    end

    return 0 if matched.empty?

    begin
      if single_container && matched.all? { |e| e.parent == (single_container.is_a?(Sketchup::Group) ? single_container.entities.parent : single_container.definition) }
        begin
          model.active_path = [single_container] rescue nil
        rescue
        end
      end
      sel.add(matched)
    rescue
      sel.add(@scan_context) if sel.empty?
    end

    matched.size
  rescue
    0
  end

  # ── Seleksi Entitas Berdasarkan Tag & Tipe dari Checkbox ────────────────────
  def self.select_by_tags(model, tag_names, types)
    return 0 unless @scan_context && !@scan_context.empty?

    sel = model.selection
    sel.clear
    matched = []
    type_arr = types.map { |t| t.to_s.downcase }
    tag_set = tag_names.map { |t| t.to_s.downcase }

    single_container = (@scan_context.size == 1 && (@scan_context[0].is_a?(Sketchup::Group) || @scan_context[0].is_a?(Sketchup::ComponentInstance))) ? @scan_context[0] : nil

    collect_all_entities(@scan_context) do |ent|
      next unless ent.respond_to?(:valid?) && ent.valid?
      raw_tag = ent.layer.name rescue 'Layer0'
      ent_tag = display_tag_name(raw_tag).downcase
      next unless tag_set.include?(ent_tag)

      if type_arr.include?('edge') && ent.is_a?(Sketchup::Edge)
        matched << ent
      elsif type_arr.include?('face') && ent.is_a?(Sketchup::Face)
        matched << ent
      elsif type_arr.include?('group') && ent.is_a?(Sketchup::Group)
        matched << ent
      elsif type_arr.include?('component') && ent.is_a?(Sketchup::ComponentInstance)
        matched << ent
      end
    end

    return 0 if matched.empty?

    begin
      if single_container && matched.all? { |e| e.parent == (single_container.is_a?(Sketchup::Group) ? single_container.entities.parent : single_container.definition) }
        begin
          model.active_path = [single_container] rescue nil
        rescue
        end
      end
      sel.add(matched)
    rescue
      sel.add(@scan_context) if sel.empty?
    end

    matched.size
  rescue => e
    0
  end

  # ── Dialog ─────────────────────────────────────────────────────────────────
  def self.run
    dlg = BoosokTools.dialog
    return unless dlg && dlg.visible?
    attach_callbacks(dlg)
    send_init_data(dlg)
  end

  def self.send_init_data(dialog = nil, from_scan = false)
    dlg = dialog || @dialog || (defined?(BoosokTools) && BoosokTools.dialog)
    return unless dlg && dlg.visible?
    model = Sketchup.active_model
    return unless model

    begin
      data = scan_tags(model)
      dlg.execute_script("if (typeof initData === 'function') initData(#{data.to_json}, #{from_scan ? 'true' : 'false'});")
    rescue => e
      dlg.execute_script("showToast(#{("Gagal scan: " + e.message).to_json}, 'error');")
    end
  end

  def self.attach_callbacks(dialog)
    dlg = dialog || @dialog || (defined?(BoosokTools) && BoosokTools.dialog)
    return unless dlg

    if @callbacks_registered && @dialog_registered_id == dlg.object_id
      return
    end
    @callbacks_registered = true
    @dialog_registered_id = dlg.object_id

    # Saat halaman deep_properties.html siap
    dlg.add_action_callback('dp_ready') do |_ctx|
      send_init_data(dlg, false)
    end

    # Scan tags ulang (dipanggil saat user klik tombol Scan Objek)
    dlg.add_action_callback('dp_scan') do |_ctx|
      model = Sketchup.active_model
      next unless model
      begin
        data = scan_tags(model)
        dlg.execute_script("if (typeof initData === 'function') initData(#{data.to_json}, true);")
      rescue => e
        dlg.execute_script("showToast(#{("Gagal scan: " + e.message).to_json}, 'error');")
      end
    end

    # Toggle visibilitas tag
    dlg.add_action_callback('dp_toggle_vis') do |_ctx, tag_name, visible|
      model = Sketchup.active_model
      next unless model
      target_visible = (visible == 'true' || visible == true)
      ok, err_msg = toggle_tag_visibility(model, tag_name, target_visible)

      safe_tag = tag_name.to_s.gsub("'", "\\\\'")
      if ok
        dlg.execute_script("if(typeof updateEyeIcon === 'function') updateEyeIcon('#{safe_tag}', #{target_visible});")
      else
        dlg.execute_script("if(typeof updateEyeIcon === 'function') updateEyeIcon('#{safe_tag}', #{!target_visible});")
        err_js = err_msg ? err_msg.to_json : "'Gagal menyembunyikan tag. Pastikan bukan tag aktif.'"
        dlg.execute_script("if(typeof showToast === 'function') showToast(#{err_js}, 'error');")
      end
    end

    # Seleksi subtipe dari klik sub-row di tree
    dlg.add_action_callback('dp_select_subtype') do |_ctx, tag_name, subtype|
      model = Sketchup.active_model
      next unless model
      n = select_by_tag_and_subtype(model, tag_name, subtype)
      type_labels = { 'edge' => 'Edge', 'face' => 'Face', 'group' => 'Group', 'component' => 'Component' }
      label = type_labels[subtype.to_s.downcase] || subtype
      if n > 0
        dlg.execute_script("showToast(#{("Terseleksi #{n} #{label} pada tag '#{tag_name}'.").to_json}, 'success');")
      else
        dlg.execute_script("showToast(#{("Tidak ada #{label} yang ditemukan pada tag '#{tag_name}'.").to_json}, 'error');")
      end
    end

    # Seleksi entitas berdasarkan tag dan tipe terpilih dari footer button
    dlg.add_action_callback('dp_select') do |_ctx, json_str|
      model = Sketchup.active_model
      next unless model
      begin
        params = JSON.parse(json_str)
        tag_names = params['tags']  || []
        types     = params['types'] || ['edge', 'face', 'group', 'component']
        n = select_by_tags(model, tag_names, types)
        if n > 0
          dlg.execute_script("showToast(#{("Terseleksi " + n.to_s + " entitas.").to_json}, 'success');")
        else
          dlg.execute_script("showToast('Tidak ada entitas yang cocok.', 'error');")
        end
      rescue => e
        dlg.execute_script("showToast(#{("Gagal: " + e.message).to_json}, 'error');")
      end
    end
  end
end
