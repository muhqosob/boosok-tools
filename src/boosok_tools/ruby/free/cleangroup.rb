Sketchup.require 'boosok_tools/ruby/titlebar'

module BoosokTools::ConvertToCleanGroup
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

  # Dipanggil Hub saat dialog ditutup supaya callback didaftarkan lagi di dialog berikutnya
  def self.release_dialog
    @dialog = nil
  end

  def self.run
    Sketchup.require 'boosok_tools/hub' unless defined?(BoosokTools::Hub)
    BoosokTools::Hub.open_or_show('clean')
  end

  def self.attach_callbacks(dialog)
    return unless dialog
    return if @dialog.equal?(dialog) # sudah terdaftar di dialog ini (hindari handler bertumpuk)
    @dialog = dialog

    # --- CALLBACK: MULAI KEMBALI ---
    restart_cb = lambda do |_action_context|
      Sketchup.active_model.selection.clear if Sketchup.active_model
      dialog.execute_script("showStep(1); resetExecButton();")
    end
    dialog.add_action_callback("clean_restart_process", &restart_cb)

    # --- CALLBACK: PROSES EKSEKUSI ---
    clean_cb = lambda do |_action_context|
      execute_clean(dialog)
    end
    dialog.add_action_callback("proses_clean_group", &clean_cb)
    dialog.add_action_callback("clean_group", &clean_cb)
  end

  def self.execute_clean(dialog)
    model = Sketchup.active_model
    return dialog.execute_script("resetExecButton(); showToast('Tidak ada model aktif.');") unless model

    sel = model.selection.to_a.select { |e| e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group) }

    if sel.empty?
      dialog.execute_script("showToast('Silakan pilih minimal 1 group atau component di layar!'); resetExecButton();")
      return
    end

    cleaned = 0
    model.start_operation("Group Cleaner", true)
    begin
      sel.each do |item|
        next unless item.valid?

        main_layer = item.layer
        parent_ents = item.parent.is_a?(Sketchup::Entities) ? item.parent : item.parent.entities

        if item.is_a?(Sketchup::ComponentInstance)
          # Jadikan unik agar instans lain aman
          item.make_unique # mengubah instance di tempat; nilai kembaliannya tidak dipakai
          tr = item.transformation
          source_defn = item.definition

          # Hapus 2d__Line di source_defn
          remove_target_completely(source_defn.entities)
          purge_attributes(source_defn)

          # Buat Group Master
          master_group = parent_ents.add_group
          master_group.transformation = tr
          master_group.layer = main_layer if main_layer

          # Masukkan isi ke dalam master group
          temp_inst = master_group.entities.add_instance(source_defn, Geom::Transformation.new)
          temp_inst.explode if temp_inst

          # Hapus komponen asli
          item.erase!

          # Ubah seluruh struktur di dalamnya menjadi grup dan bersihkan atribut
          purge_attributes(master_group)
          convert_remaining_to_groups(master_group.entities)
        else
          # Group: langsung bersihkan tanpa perlu explode/rebuild
          remove_target_completely(item.entities)
          purge_attributes(item)
          convert_remaining_to_groups(item.entities)
        end

        cleaned += 1
      end
      model.commit_operation
    rescue => e
      model.abort_operation
      dialog.execute_script("resetExecButton();")
      dialog.execute_script("showToast(#{("Gagal: " + e.message).to_json});")
      return
    end
    model.selection.clear

    dialog.execute_script("resetExecButton();")
    dialog.execute_script("showSuccessStep(#{("Selesai! #{cleaned} objek berhasil dibersihkan menjadi Grup murni.").to_json});")
  end
end