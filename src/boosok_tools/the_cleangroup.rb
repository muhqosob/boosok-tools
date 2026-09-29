load File.join(__dir__, 'titlebar.rb')

module ConvertToCleanGroup
  # --- FUNGSI INTI ---

  def self.purge_attributes(entity)
    if entity.respond_to?(:attribute_dictionaries) && entity.attribute_dictionaries
      entity.attribute_dictionaries.to_a.each do |d|
        begin
          entity.delete_attribute(d.name)
        rescue
          # Abaikan dictionary internal sistem
        end
      end
    end
  end

  def self.remove_target_completely(container_entities)
    container_entities.to_a.each do |child|
      if child.is_a?(Sketchup::ComponentInstance)
        defn = child.definition
        remove_target_completely(defn.entities)
        
        defn_name = defn.name.to_s.strip
        if defn_name == "2d__Line" || defn_name.include?("2d__Line")
          child.erase! rescue nil
        end
      elsif child.is_a?(Sketchup::Group)
        remove_target_completely(child.entities)
        
        grp_name = child.name.to_s.strip
        if grp_name == "2d__Line" || grp_name.include?("2d__Line")
          child.erase! rescue nil
        end
      end
    end
  end

  def self.convert_remaining_to_groups(container_entities)
    instances = container_entities.grep(Sketchup::ComponentInstance)
    
    instances.each do |inst|
      next unless inst.valid?

      tr = inst.transformation
      defn = inst.definition
      
      original_layer = inst.layer 
      
      purge_attributes(defn)
      convert_remaining_to_groups(defn.entities)
      
      inner_ents = defn.entities.to_a
      unless inner_ents.empty?
        new_group = container_entities.add_group
        new_group.transformation = tr
        
        new_group.layer = original_layer if original_layer
        
        temp_sub = new_group.entities.add_instance(defn, Geom::Transformation.new)
        temp_sub.explode if temp_sub
        
        purge_attributes(new_group)
        inst.erase!
      end
    end

    groups = container_entities.grep(Sketchup::Group)
    groups.each do |grp|
      next unless grp.valid?
      purge_attributes(grp)
      convert_remaining_to_groups(grp.entities)
    end
  end

  # --- UI & DIALOG ---

  $cleangroup_dlg ||= nil

  def self.run
    require_relative 'hub' unless defined?(BoosokTools::Hub)
    BoosokTools::Hub.open_or_show('clean')
  end

  def self.attach_callbacks(dialog)
    return unless dialog
    if $cleangroup_dlg.equal?(dialog)
      return
    end
    $cleangroup_dlg = dialog

    # --- CALLBACK: MULAI KEMBALI ---
    restart_cb = lambda do |_action_context|
      Sketchup.active_model.selection.clear if Sketchup.active_model
      dialog.execute_script("showStep(1); resetExecButton();")
    end
    dialog.add_action_callback("restart_process", &restart_cb)
    dialog.add_action_callback("clean_restart_process", &restart_cb)

    # --- CALLBACK: PROSES EKSEKUSI ---
    dialog.add_action_callback("proses_clean_group") do |_action_context|
      execute_clean(dialog)
    end
  end

  def self.execute_clean(dialog)
    model = Sketchup.active_model
    return dialog.execute_script("resetExecButton(); showToast('Tidak ada model aktif.');") unless model

    sel = model.selection.to_a
    
    # Validasi Cepat di Awal
    if sel.length != 1
      dialog.execute_script("showToast('Silakan pilih tepat 1 objek di layar!'); resetExecButton();")
      return
    elsif !sel[0].is_a?(Sketchup::ComponentInstance)
      dialog.execute_script("showToast('Error: Objek yang dipilih BUKAN Component!'); resetExecButton();")
      return
    end

    item = sel[0]
    main_layer = item.layer

    model.start_operation("Group Cleaner", true)
    begin
      # 1. Jadikan unik agar instans lain aman
      item = item.make_unique

      tr = item.transformation
      parent_ents = item.parent.entities
      source_defn = item.definition

      # 2. Hapus 2d__Line di source_defn
      remove_target_completely(source_defn.entities)
      purge_attributes(source_defn)

      # 3. Buat Group Master
      master_group = parent_ents.add_group
      master_group.transformation = tr
      master_group.layer = main_layer if main_layer

      # 4. Masukkan isi ke dalam master group
      temp_inst = master_group.entities.add_instance(source_defn, Geom::Transformation.new)
      temp_inst.explode if temp_inst

      # 5. Hapus komponen asli
      item.erase!

      # 6. Ubah seluruh struktur di dalamnya menjadi grup dan bersihkan atribut
      purge_attributes(master_group)
      convert_remaining_to_groups(master_group.entities)

      model.commit_operation
    rescue => e
      model.abort_operation
      dialog.execute_script("resetExecButton();")
      dialog.execute_script("showToast(#{("Gagal: " + e.message).to_json});")
      return
    end
    model.selection.clear

    dialog.execute_script("resetExecButton();")
    dialog.execute_script("showSuccessStep('Selesai! Komponen berhasil dibersihkan menjadi Grup murni.');")
  end
end