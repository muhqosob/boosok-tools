require 'sketchup'
require 'json'
load File.join(__dir__, 'titlebar.rb')

module TheSelectorPlugin
  class << self
    def run_selector
      require_relative 'hub' unless defined?(BoosokTools::Hub)
      BoosokTools::Hub.open_or_show('selector')
    end

    def send_init_data(dialog)
      return unless dialog
      model = Sketchup.active_model
      all_tags = model ? model.layers.map(&:name).sort : []
      saved_keys_str = Sketchup.read_default("TheSelectorPlugin", "attr_keys_v2", "a_posisi").to_s
      saved_keys = saved_keys_str.empty? ? ["a_posisi"] : saved_keys_str.split("|")
      init_data = {
        tags: all_tags,
        keys: saved_keys
      }
      dialog.execute_script("if (typeof initUIData === 'function') initUIData(#{init_data.to_json});")
    end

    def attach_callbacks(dialog)
      return unless dialog

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

    def execute_selection(dialog, json_data)
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

      model = Sketchup.active_model
      return dialog.execute_script("resetSubmitButton(); showToast('Tidak ada model yang aktif.');") unless model

      selection = model.selection
      selection.clear
      matching_entities = []
      search_entities = model.active_entities

      find_entities = lambda do |entities, current_parent_tag = nil|
        entities.each do |ent|
          if ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
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
        pesan = "Sukses! Ditemukan dan menyeleksi <b>#{matching_entities.size}</b> objek."
        dialog.execute_script("showSuccessStep('#{pesan}');")
      else
        dialog.execute_script("resetSubmitButton();")
        dialog.execute_script("showToast('Tidak ditemukan objek dengan kriteria tersebut.');")
      end
    rescue => e
      dialog.execute_script("resetSubmitButton();")
      dialog.execute_script("showToast(#{("Gagal: " + e.message).to_json});")
    end
  end
end