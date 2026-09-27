require 'sketchup'
require 'json'

module TheSelectorPlugin
  class << self
    def run_selector
      # Satu dialog saja. Buka ulang supaya daftar tag ikut ter-refresh.
      @dialog.close if @dialog && @dialog.visible?

      model = Sketchup.active_model
      all_tags = model.layers.map { |layer| layer.name }.sort

      last_x = Sketchup.read_default("TheSelectorPlugin", "dialog_left", 300).to_i
      last_y = Sketchup.read_default("TheSelectorPlugin", "dialog_top", 300).to_i
      last_x = 300 if last_x < 50
      last_y = 300 if last_y < 50

      saved_keys_str = Sketchup.read_default("TheSelectorPlugin", "attr_keys_v2", "a_posisi").to_s
      saved_keys = saved_keys_str.empty? ? ["a_posisi"] : saved_keys_str.split("|")

      # Dibuat fixed (resizable: false) dengan tinggi default pas (Fit In)
      dialog = @dialog = UI::HtmlDialog.new(
        {
          :dialog_title => "The Selector",
          :scrollable => false,
          :resizable => false,
          :width => 390,
          :height => 470, # tinggi form tanpa filter atribut (lihat H_BASE di selector.html)
          :style => UI::HtmlDialog::STYLE_DIALOG
        }
      )

      dialog.set_position(last_x, last_y)

      html_path = File.join(File.dirname(__FILE__), 'html', 'selector.html')
      dialog.set_file(html_path)

      dialog.add_action_callback("closeDialog") do |action_context|
        dialog.close
      end

      # Fungsi otomatis memperbesar/memperkecil jendela dari HTML
      dialog.add_action_callback("resize_dialog") do |action_context, height|
        dialog.set_size(390, height.to_i)
      end

      dialog.add_action_callback("save_position") do |action_context, pos_json|
        pos = JSON.parse(pos_json) rescue nil
        if pos && pos["left"].to_i > 10 && pos["top"].to_i > 10
          Sketchup.write_default("TheSelectorPlugin", "dialog_left", pos["left"].to_i)
          Sketchup.write_default("TheSelectorPlugin", "dialog_top", pos["top"].to_i)
        end
      end

      dialog.add_action_callback("save_new_key") do |action_context, new_key|
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

      dialog.add_action_callback("delete_key") do |action_context, key_to_delete|
        key_to_delete = key_to_delete.to_s.strip.downcase
        str = Sketchup.read_default("TheSelectorPlugin", "attr_keys_v2", "a_posisi").to_s
        keys = str.empty? ? ["a_posisi"] : str.split("|")
        keys.delete(key_to_delete)
        keys = ["a_posisi"] if keys.empty?
        Sketchup.write_default("TheSelectorPlugin", "attr_keys_v2", keys.join("|"))
      end

      dialog.add_action_callback("perform_selection") do |action_context, json_data|
        begin
          data = JSON.parse(json_data) rescue {}
          if data.empty?
            dialog.execute_script("resetSubmitButton();")
            next
          end

          if data["left"] && data["top"] && data["left"].to_i > 10 && data["top"].to_i > 10
            Sketchup.write_default("TheSelectorPlugin", "dialog_left", data["left"].to_i)
            Sketchup.write_default("TheSelectorPlugin", "dialog_top", data["top"].to_i)
          end

          tag_utama = data["tag_utama"].to_s.strip
          tag_kedua = data["tag_kedua"].to_s.strip
          search_type = data["search_type"]
          target_keyword = data["keyword"].to_s.strip.downcase
          use_attribute = data["use_attr"]
          target_attr_key = data["attr_key"].to_s.strip.downcase
          target_attr_val = data["attr_val"].to_s.strip.downcase

          model = Sketchup.active_model # dialog tetap terbuka, model aktif bisa sudah ganti (Mac)
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

      dialog.add_action_callback("get_init_data") do |action_context|
        init_data = {
          tags: all_tags,
          keys: saved_keys
        }
        dialog.execute_script("initUIData(#{init_data.to_json});")
      end

      dialog.show
    end
  end
end