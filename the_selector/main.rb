require 'sketchup'
require 'json'

module TheSelectorPlugin
  class << self
    def run_selector
      model = Sketchup.active_model
      all_tags = model.layers.map { |layer| layer.name }.sort

      # Ambil posisi terakhir dialog
      last_x = Sketchup.read_default("TheSelectorPlugin", "dialog_left", 300).to_i
      last_y = Sketchup.read_default("TheSelectorPlugin", "dialog_top", 300).to_i
      last_x = 300 if last_x < 50
      last_y = 300 if last_y < 50

      # Ambil daftar riwayat Key Atribut (Format String Anti-gagal)
      saved_keys_str = Sketchup.read_default("TheSelectorPlugin", "attr_keys_v2", "a_posisi").to_s
      saved_keys = saved_keys_str.empty? ? ["a_posisi"] : saved_keys_str.split("|")

      dialog = UI::HtmlDialog.new(
        {
          :dialog_title => "The Selector",
          :scrollable => false,
          :resizable => false,
          :width => 400,
          :height => 500,
          :style => UI::HtmlDialog::STYLE_DIALOG
        }
      )

      dialog.set_position(last_x, last_y)

      html_path = File.join(File.dirname(__FILE__), 'dialog.html')
      dialog.set_file(html_path)

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

      dialog.add_action_callback("resize_dialog") do |action_context, height|
        dialog.set_size(400, height.to_i)
      end

      dialog.add_action_callback("perform_selection") do |action_context, json_data|
        dialog.close

        data = JSON.parse(json_data) rescue {}
        next if data.empty?

        if data["left"] && data["top"] && data["left"].to_i > 10 && data["top"].to_i > 10
          Sketchup.write_default("TheSelectorPlugin", "dialog_left", data["left"].to_i)
          Sketchup.write_default("TheSelectorPlugin", "dialog_top", data["top"].to_i)
        end

        tag_utama = data["tag_utama"]   # Contoh: Level 1 (Parent Group)
        tag_kedua = data["tag_kedua"]   # Contoh: Beam (Objek di dalamnya)
        search_type = data["search_type"]
        target_keyword = data["keyword"].strip.downcase
        use_attribute = data["use_attr"]
        target_attr_key = data["attr_key"].strip.downcase
        target_attr_val = data["attr_val"].strip.downcase

        selection = model.selection
        selection.clear
        matching_entities = []
        search_entities = model.active_entities

        # Lambda helper untuk mengecek parent tag (diubah namanya tanpa tanda ?)
        has_parent_tag = lambda do |entity, target_tag|
          parent = entity.parent
          while parent.is_a?(Sketchup::ComponentDefinition)
            instances = parent.instances
            found_in_parent = instances.any? { |inst|
              inst.layer.name.strip.downcase == target_tag.downcase || 
              (inst.parent.respond_to?(:instances) && inst.parent != model && has_parent_tag.call(inst, target_tag))
            }
            return true if found_in_parent
            
            if parent.respond_to?(:model) && parent.entity && parent.entity.respond_to?(:parent)
              parent = parent.entity.parent
            else
              break
            end
          end
          false
        end

find_entities = lambda do |entities, current_parent_tag = nil|
          entities.each do |ent|
            if ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
              
              ent_tag = ent.layer.name.strip
              
              # Perbarui parent tag aktif jika grup/komponen ini cocok dengan tag utama
              active_parent_tag = current_parent_tag
              if tag_utama == "(Semua Tag / Abaikan)" || ent_tag.downcase == tag_utama.downcase
                active_parent_tag = ent_tag
              end

              # 1. Validasi Tag Utama (Parent harus sesuai tag utama)
              match_tag_utama = true
              if tag_utama != "(Semua Tag / Abaikan)"
                is_self_tag = (ent_tag.downcase == tag_utama.downcase)
                is_inside_parent = (active_parent_tag && active_parent_tag.downcase == tag_utama.downcase)
                match_tag_utama = is_self_tag || is_inside_parent
              end

              # 2. Validasi Tag Kedua (Sub-Tag Objek di dalamnya, misal: beam)
              match_tag_kedua = (tag_kedua == "(Semua Tag / Abaikan)") || (ent_tag.downcase == tag_kedua.downcase)

              # 3. Validasi Nama
              current_name = (search_type == "Instance Name") ? ent.name.strip.downcase : ent.definition.name.strip.downcase
              match_name = target_keyword.empty? || (current_name == target_keyword)
              
              # 4. Validasi Atribut Custom
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

              # Jika objek berada di dalam hierarki tag utama DAN memenuhi tag kedua, nama, serta atributnya
              if match_tag_kedua && match_tag_utama && match_name && match_attr
                matching_entities << ent
              end
              
              # Masuk ke dalam nested entities secara rekursif dengan meneruskan parent tag yang sedang aktif
              inner = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
              find_entities.call(inner, active_parent_tag)
            end
          end
        end

        find_entities.call(search_entities, nil)

        if matching_entities.any?
          selection.add(matching_entities)
          UI.messagebox("Sukses! Ditemukan dan diseleksi #{matching_entities.size} objek.")
        else
          UI.messagebox("Tidak ditemukan objek dengan kriteria tersebut.")
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