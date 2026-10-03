require 'sketchup'
require 'json'
Sketchup.require 'boosok_tools/ruby/titlebar'

module BoosokTools::TheSelectorPlugin
  @dialog = nil
  @cached_tags = []
  @update_timer = nil
  @poll_timer = nil
  @layers_observer = nil
  @model_observer = nil
  @app_observer = nil
  @observed_model = nil
  @callbacks_registered = false
  @dialog_registered_id = nil

  class LayersObserver < Sketchup::LayersObserver
    def onLayerAdded(*args)
      BoosokTools::TheSelectorPlugin.schedule_sync rescue nil
    end

    def onLayerRemoved(*args)
      BoosokTools::TheSelectorPlugin.schedule_sync rescue nil
    end

    def onLayerChanged(*args)
      BoosokTools::TheSelectorPlugin.schedule_sync rescue nil
    end

    def onLayerFolderAdded(*args)
      BoosokTools::TheSelectorPlugin.schedule_sync rescue nil
    end

    def onLayerFolderRemoved(*args)
      BoosokTools::TheSelectorPlugin.schedule_sync rescue nil
    end

    def onLayerFolderChanged(*args)
      BoosokTools::TheSelectorPlugin.schedule_sync rescue nil
    end
  end

  class ModelObserver < Sketchup::ModelObserver
    def onTransactionCommit(*args)
      BoosokTools::TheSelectorPlugin.schedule_sync rescue nil
    end

    def onTransactionUndo(*args)
      BoosokTools::TheSelectorPlugin.schedule_sync rescue nil
    end

    def onTransactionRedo(*args)
      BoosokTools::TheSelectorPlugin.schedule_sync rescue nil
    end
  end

  class AppObserver < Sketchup::AppObserver
    def onActivateModel(model)
      BoosokTools::TheSelectorPlugin.attach_to_model(model) rescue nil
    end

    def onNewModel(model)
      BoosokTools::TheSelectorPlugin.attach_to_model(model) rescue nil
    end

    def onOpenModel(model)
      BoosokTools::TheSelectorPlugin.attach_to_model(model) rescue nil
    end
  end

  def self.start_monitor_timer
    stop_monitor_timer
    @poll_timer = UI.start_timer(0.4, true) do
      begin
        dlg = @dialog || (defined?(BoosokTools) && BoosokTools.dialog)
        next unless dlg && dlg.visible?
        next if defined?(BoosokTools::Hub) && BoosokTools::Hub.current_tool != 'selector'

        model = Sketchup.active_model
        next unless model && model.valid?

        current_tags = model.layers.map(&:name).sort
        if current_tags != @cached_tags
          sync_tags
        end
      rescue => e
      end
    end
  end

  def self.stop_monitor_timer
    if @poll_timer
      UI.stop_timer(@poll_timer) rescue nil
      @poll_timer = nil
    end
  end

  def self.schedule_sync
    dlg = @dialog || (defined?(BoosokTools) && BoosokTools.dialog)
    return unless dlg && dlg.visible?
    return if defined?(BoosokTools::Hub) && BoosokTools::Hub.current_tool != 'selector'

    UI.stop_timer(@update_timer) if @update_timer
    @update_timer = UI.start_timer(0.08, false) do
      @update_timer = nil
      sync_tags
    end
  end

  def self.sync_tags
    dlg = @dialog || (defined?(BoosokTools) && BoosokTools.dialog)
    return unless dlg && dlg.visible?
    return if defined?(BoosokTools::Hub) && BoosokTools::Hub.current_tool != 'selector'

    current_model = Sketchup.active_model
    @cached_tags = current_model ? current_model.layers.map(&:name).sort : []
    dlg.execute_script("if (typeof updateTags === 'function') updateTags(#{@cached_tags.to_json}); else if (typeof initUIData === 'function') initUIData({ tags: #{@cached_tags.to_json} });")
  end

  def self.attach_to_model(model)
    return unless model && model.valid?

    detach_model_observers
    @observed_model = model

    @layers_observer ||= LayersObserver.new
    @model_observer  ||= ModelObserver.new

    begin
      model.layers.add_observer(@layers_observer)
    rescue => e
    end

    begin
      model.add_observer(@model_observer)
    rescue => e
    end

    start_monitor_timer
    schedule_sync
  end

  def self.detach_model_observers
    if @observed_model && @observed_model.valid?
      begin
        @observed_model.layers.remove_observer(@layers_observer) if @layers_observer
      rescue => e
      end
      begin
        @observed_model.remove_observer(@model_observer) if @model_observer
      rescue => e
      end
    end
    @observed_model = nil
  end

  def self.detach_all_observers
    stop_monitor_timer
    UI.stop_timer(@update_timer) if @update_timer
    @update_timer = nil

    detach_model_observers
    if @app_observer
      begin
        Sketchup.remove_observer(@app_observer)
      rescue => e
      end
      @app_observer = nil
    end
  end

  def self.run_selector
    Sketchup.require 'boosok_tools/hub' unless defined?(BoosokTools::Hub)
    BoosokTools::Hub.open_or_show('selector')
  end

  def self.send_init_data(dialog)
    return unless dialog
    model = Sketchup.active_model
    @cached_tags = model ? model.layers.map(&:name).sort : []
    saved_keys_str = Sketchup.read_default("TheSelectorPlugin", "attr_keys_v2", "a_posisi").to_s
    saved_keys = saved_keys_str.empty? ? ["a_posisi"] : saved_keys_str.split("|")
    init_data = {
      tags: @cached_tags,
      keys: saved_keys
    }
    dialog.execute_script("if (typeof initUIData === 'function') initUIData(#{init_data.to_json});")
  end

  def self.attach_callbacks(dialog)
    return unless dialog
    @dialog = dialog

    model = Sketchup.active_model
    @cached_tags = model ? model.layers.map(&:name).sort : []

    @app_observer ||= AppObserver.new
    begin
      Sketchup.add_observer(@app_observer)
    rescue => e
    end

    attach_to_model(model) if model

    if @callbacks_registered && @dialog_registered_id == dialog.object_id
      send_init_data(dialog)
      return
    end

    @dialog_registered_id = dialog.object_id
    @callbacks_registered = true

    dialog.add_action_callback("get_init_data") do |_ctx|
      send_init_data(dialog)
    end

    dialog.add_action_callback("save_new_key") do |_ctx, new_key|
      new_key = new_key.to_s.strip.downcase
      unless new_key.empty?
        str = Sketchup.read_default("TheSelectorPlugin", "attr_keys_v2", "a_posisi").to_s
        keys = str.empty? ? ["a_posisi"] : str.split("|")
        unless keys.include?(new_key)
          keys << new_key
          Sketchup.write_default("TheSelectorPlugin", "attr_keys_v2", keys.join("|"))
        end
      end
    end

    dialog.add_action_callback("delete_key") do |_ctx, key_to_delete|
      key_to_delete = key_to_delete.to_s.strip.downcase
      str = Sketchup.read_default("TheSelectorPlugin", "attr_keys_v2", "a_posisi").to_s
      keys = str.empty? ? ["a_posisi"] : str.split("|")
      keys.delete(key_to_delete)
      keys = ["a_posisi"] if keys.empty?
      Sketchup.write_default("TheSelectorPlugin", "attr_keys_v2", keys.join("|"))
    end

    dialog.add_action_callback("perform_selection") do |_ctx, json_data|
      execute_selection(dialog, json_data)
    end
  end

  def self.execute_selection(dialog, json_data)
      data = JSON.parse(json_data) rescue {}
      if data.empty?
        dialog.execute_script("resetSubmitButton();")
        return
      end

      if data["left"] && data["top"] && data["left"].to_i > 10 && data["top"].to_i > 10
        BoosokTools.save_position(data["left"].to_i, data["top"].to_i)
      end

      tag_utama = data["tag_utama"].to_s.strip
      tag_kedua = data["tag_kedua"].to_s.strip
      search_type = data["search_type"]
      target_keyword = data["keyword"].to_s.strip.downcase
      use_attribute = data["use_attr"]
      target_attr_key = data["attr_key"].to_s.strip.downcase
      target_attr_val = data["attr_val"].to_s.strip.downcase
      include_geo = data["include_geo"] != false

      model = Sketchup.active_model
      no_model_msg = defined?(BoosokTools::Locale) ? BoosokTools::Locale.t('sel_no_model', 'Tidak ada model yang aktif.') : 'Tidak ada model yang aktif.'
      return dialog.execute_script("resetSubmitButton(); showToast(#{no_model_msg.to_json});") unless model

      selection = model.selection
      selection.clear
      matching_entities = []
      search_entities = model.active_entities
      all_tags = "(Semua Tag / Abaikan)"
      # Edge/face hanya ikut dicari kalau tag utama BUKAN "semua tag" dan kata kunci nama kosong
      # (edge/face tidak punya nama). Kalau tag utama = semua tag, cukup group/component.
      # Hanya edge/face yang diberi tag sendiri (bukan Untagged) yang dipilih, supaya geometri polos tidak ikut.
      geo_enabled = include_geo && target_keyword.empty? && tag_utama != all_tags

      geo_tag_counts = Hash.new(0) # diagnosa: tag milik edge/face yang ditemukan saat menelusuri

      find_entities = lambda do |entities, current_parent_tag = nil|
        entities.each do |ent|
          if geo_enabled && (ent.is_a?(Sketchup::Edge) || ent.is_a?(Sketchup::Face))
            next if %w[Untagged Layer0].include?(ent.layer.name)
            ent_tag = ent.layer.name.strip
            geo_tag_counts[ent_tag] += 1

            match_tag_utama = (tag_utama == all_tags) || ent_tag.downcase == tag_utama.downcase ||
                              (current_parent_tag && current_parent_tag.downcase == tag_utama.downcase)
            match_tag_kedua = (tag_kedua == all_tags) || (ent_tag.downcase == tag_kedua.downcase)
            next unless match_tag_utama && match_tag_kedua

            if use_attribute
              next if target_attr_key.empty?
              attr_ok = (ent.attribute_dictionaries || []).any? do |dict|
                key = dict.keys.find { |k| k.to_s.downcase == target_attr_key }
                key && (target_attr_val.empty? || dict[key].to_s.strip.downcase == target_attr_val)
              end
              next unless attr_ok
            end

            matching_entities << ent
          elsif ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
            ent_tag = ent.layer.name.strip

            active_parent_tag = current_parent_tag
            if tag_utama == "(Semua Tag / Abaikan)" || ent_tag.downcase == tag_utama.downcase
              active_parent_tag = ent_tag
            end

            match_tag_utama = true
            if tag_utama != "(Semua Tag / Abaikan)"
              is_self_tag = (ent_tag.downcase == tag_utama.downcase)
              is_inside_parent = (active_parent_tag && active_parent_tag.downcase == tag_utama.downcase)
              match_tag_utama = is_self_tag || is_inside_parent
            end

            match_tag_kedua = (tag_kedua == "(Semua Tag / Abaikan)") || (ent_tag.downcase == tag_kedua.downcase)

            current_name = (search_type == "Instance Name") ? ent.name.strip.downcase : ent.definition.name.strip.downcase
            match_name = target_keyword.empty? || (current_name == target_keyword)

            match_attr = true
            if use_attribute
              match_attr = false
              unless target_attr_key.empty?
                dictionaries = ent.attribute_dictionaries.to_a + (ent.definition.attribute_dictionaries ? ent.definition.attribute_dictionaries.to_a : [])
                dictionaries.each do |dict|
                  next if dict.nil?
                  if dict.keys.any? { |k| k.to_s.downcase == target_attr_key }
                    val = dict[target_attr_key] || dict[dict.keys.find { |k| k.to_s.downcase == target_attr_key }]
                    if target_attr_val.empty? || val.to_s.strip.downcase == target_attr_val
                      match_attr = true
                      break
                    end
                  end
                end
              end
            end

            if match_tag_kedua && match_tag_utama && match_name && match_attr
              matching_entities << ent
            end

            inner = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
            find_entities.call(inner, active_parent_tag)
          end
        end
      end

      find_entities.call(search_entities, nil)

      if matching_entities.any?
        selection.add(matching_entities)
        found_msg = defined?(BoosokTools::Locale) ? BoosokTools::Locale.t('sel_found', 'Sukses! Ditemukan dan menyeleksi <b>%{count}</b> objek.') : 'Sukses! Ditemukan dan menyeleksi <b>%{count}</b> objek.'
        pesan = found_msg.gsub('%{count}', matching_entities.size.to_s)
        dialog.execute_script("showSuccessStep(#{pesan.to_json});")
      else
        not_found_msg = defined?(BoosokTools::Locale) ? BoosokTools::Locale.t('sel_not_found_msg', 'Tidak ditemukan objek dengan kriteria tersebut.') : 'Tidak ditemukan objek dengan kriteria tersebut.'
        puts "[Selector] Tidak ditemukan. tag_utama=#{tag_utama.inspect} tag_kedua=#{tag_kedua.inspect} geo=#{geo_enabled} edge/face bertag terlihat: #{geo_tag_counts.inspect}"
        dialog.execute_script("resetSubmitButton();")
        dialog.execute_script("showToast(#{not_found_msg.to_json});")
      end
    rescue => e
      dialog.execute_script("resetSubmitButton();")
      dialog.execute_script("showToast(#{("Gagal: " + e.message).to_json});")
    end
  end