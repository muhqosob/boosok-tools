module TheReplacer
  @@dialog = nil
  @@last_pos = nil
  @@old_items = []

  def self.run
    model = Sketchup.active_model
    
    # Kosongkan array lama dan jangan beri error di awal agar UI selalu bisa terbuka
    @@old_items = []

    if @@dialog && @@dialog.visible?
      begin
        pos = @@dialog.get_position
        @@last_pos = pos if pos.is_a?(Array) && pos.length == 2
      rescue
      end
      @@dialog.close
    end
    
    # --- KONFIGURASI DIALOG FIX (Dinaikkan ukurannya agar lebih lega) ---
    @@dialog = UI::HtmlDialog.new(
      {
        :dialog_title => "The Replacer",
        :scrollable => false,
        :resizable => false,
        :width => 360,
        :height => 390,
        :style => UI::HtmlDialog::STYLE_DIALOG
      }
    )

    @@dialog.set_file(File.join(__dir__, 'replacer.html'))

    if @@last_pos.is_a?(Array) && @@last_pos.length == 2
      @@dialog.set_position(@@last_pos[0], @@last_pos[1])
    else
      @@dialog.center if @@dialog.respond_to?(:center)
    end

    @@dialog.set_on_closed {
      begin
        pos = @@dialog.get_position
        @@last_pos = pos if pos.is_a?(Array) && pos.length == 2
      rescue
      end
    }

    @@dialog.add_action_callback("close_dialog") do |action_context|
      @@dialog.close if @@dialog && @@dialog.visible?
    end

    # --- CALLBACK 1: CEK ITEM LAMA SAAT KLIK NEXT ---
    @@dialog.add_action_callback("check_old_items") do |action_context|
      model = Sketchup.active_model
      sel = model.selection
      @@old_items = sel.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }

      if @@old_items.empty?
        @@dialog.execute_script("showToast('Pilih minimal 1 Grup/Komponen Lama terlebih dahulu di layar!');")
      else
        model.selection.clear
        @@dialog.execute_script("showStep(2);")
      end
    end

    # --- CALLBACK 2: MULAI KEMBALI (RESET & UNSELECT) ---
    @@dialog.add_action_callback("restart_process") do |action_context|
      @@old_items = []
      Sketchup.active_model.selection.clear
      @@dialog.execute_script("showStep(1);")
    end

    # --- CALLBACK 3: PROSES PENGGANTIAN & PENSKALAAN ---
    @@dialog.add_action_callback("proses_replace") do |action_context|
      model = Sketchup.active_model
      new_sel = model.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }

      if new_sel.length != 1
        @@dialog.execute_script("showToast('Pastikan Anda memilih tepat 1 Item Baru sebagai pengganti!');")
        @@dialog.execute_script("resetExecButton();")
        next
      end

      item_baru = new_sel[0]

      if @@old_items.include?(item_baru)
        @@dialog.execute_script("showToast('Item baru tidak boleh sama dengan item lama yang tadi dipilih!');")
        @@dialog.execute_script("resetExecButton();")
        next
      end

      # Item lama bisa sudah terhapus / di-undo sejak klik Next
      @@old_items.reject!(&:deleted?)
      if @@old_items.empty?
        @@dialog.execute_script("showToast('Item lama sudah tidak ada (terhapus/di-undo). Ulangi dari Langkah 1.'); resetExecButton(); showStep(1);")
        next
      end

      model.start_operation("The Replacer Wizard", true)
      begin

        definition_baru = item_baru.definition
        dicts_baru = item_baru.attribute_dictionaries

        get_dimension_inch = lambda do |ent, attr_name, axis_idx|
          base_inch = 0.0
          if ent.is_a?(Sketchup::ComponentInstance) && ent.definition.attribute_dictionaries && ent.definition.attribute_dictionaries["dynamic_attributes"]
            dict = "dynamic_attributes"
            base_inch = ent.definition.get_attribute(dict, "_#{attr_name}_nominal").to_f
            base_inch = ent.definition.get_attribute(dict, attr_name).to_f if base_inch == 0
            base_inch = ent.get_attribute(dict, "_#{attr_name}_nominal").to_f if base_inch == 0
            base_inch = ent.get_attribute(dict, attr_name).to_f if base_inch == 0
          end

          if base_inch == 0
            def_bb = ent.definition.bounds rescue ent.bounds
            base_inch = case axis_idx
                        when 0 then def_bb.width
                        when 1 then def_bb.depth
                        when 2 then def_bb.height
                        end
          end

          tr = ent.transformation
          current_scale = case axis_idx
                          when 0 then tr.xaxis.length
                          when 1 then tr.yaxis.length
                          when 2 then tr.zaxis.length
                          end
          return base_inch * current_scale
        end

        @@old_items.each do |item_lama|
          nama_lama = item_lama.name
          transformasi_lama = item_lama.transformation
          context_lama = item_lama.parent.entities
          tag_lama = item_lama.layer 

          target_inch_x = get_dimension_inch.call(item_lama, "lenx", 0)
          target_inch_y = get_dimension_inch.call(item_lama, "leny", 1)

          new_instance = context_lama.add_instance(definition_baru, transformasi_lama)
          new_instance.layer = tag_lama
          new_instance.name = nama_lama unless nama_lama.empty?
        
          if dicts_baru
            dicts_baru.each do |dict|
              dict.each_pair do |key, val|
                new_instance.set_attribute(dict.name, key, val)
              end
            end
          end

          base_inch_x = get_dimension_inch.call(new_instance, "lenx", 0)
          base_inch_y = get_dimension_inch.call(new_instance, "leny", 1)

          if base_inch_x > 0.001 && base_inch_y > 0.001 && target_inch_x > 0.001 && target_inch_y > 0.001
            scale_x = target_inch_x / base_inch_x
            scale_y = target_inch_y / base_inch_y
            scale_z = 1.0

            bb_baru = new_instance.bounds
            center_point = bb_baru.center

            scaling_transform = Geom::Transformation.scaling(center_point, scale_x, scale_y, scale_z)
            new_instance.transform!(scaling_transform)

            if new_instance.is_a?(Sketchup::ComponentInstance) && new_instance.definition.attribute_dictionaries && new_instance.definition.attribute_dictionaries["dynamic_attributes"]
              if defined?($dc_observers) && $dc_observers
                dco = $dc_observers.get_latest_class
                dco.redraw_with_undo(new_instance) if dco.respond_to?(:redraw_with_undo)
              end
            end
          end
        
          item_lama.erase!
        end

        model.commit_operation
      rescue => e
        model.abort_operation
        @@dialog.execute_script("resetExecButton();")
        @@dialog.execute_script("showToast(#{("Gagal: " + e.message).to_json});")
        next
      end

      model.selection.clear

      @@dialog.execute_script("resetExecButton();")
      @@dialog.execute_script("showSuccessStep('Sukses mengganti & menyesuaikan ukuran #{@@old_items.length} objek.');")
    end

    @@dialog.show
  end
end