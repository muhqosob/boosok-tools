Sketchup.require 'boosok_tools/ruby/titlebar'

module BoosokTools::TheReplacer
  @old_items  ||= []
  @cache      ||= []
  @timer      ||= nil
  @dialog        ||= nil

  # Observer hanya menandai "selection berubah"; penyaringan dilakukan timer, dan hanya kalau berubah.
  class SelectionDirtyObserver < Sketchup::SelectionObserver
    def onSelectionBulkChange(*);  BoosokTools::TheReplacer.mark_dirty; end
    def onSelectionAdded(*);       BoosokTools::TheReplacer.mark_dirty; end
    def onSelectionRemoved(*);     BoosokTools::TheReplacer.mark_dirty; end
    def onSelectionCleared(*);     BoosokTools::TheReplacer.mark_dirty; end
  end

  def self.mark_dirty
    @sel_dirty = true
  end

  # Dipanggil Hub saat dialog ditutup supaya callback didaftarkan lagi di dialog berikutnya
  def self.release_dialog
    @dialog = nil
  end

  # --- Timer sticky cache ------------------------------------------
  # Dulu: tiap 200ms seluruh selection di-to_a + filter walau tidak berubah → model berat jadi lag.
  # Sekarang: timer tetap 200ms (menggabungkan banyak event jadi 1), tapi kerja hanya kalau dirty.
  def self.start_cache_timer
    stop_cache_timer
    @sel_dirty = true
    attach_selection_observer(Sketchup.active_model)
    @timer = UI.start_timer(0.2, true) do
      begin
        model = Sketchup.active_model
        next unless model
        attach_selection_observer(model) if model != @observed_model
        next unless @sel_dirty && @old_items.empty?
        @sel_dirty = false
        current = model.selection.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        # Sticky: jangan timpa cache valid dengan selection kosong
        if !current.empty? || @cache.empty?
          @cache = current
        end
      rescue; end
    end
  end

  def self.attach_selection_observer(model)
    detach_selection_observer
    return unless model
    @sel_observer ||= SelectionDirtyObserver.new
    model.selection.add_observer(@sel_observer)
    @observed_model = model
    @sel_dirty = true
  rescue
  end

  def self.detach_selection_observer
    if @observed_model && @sel_observer
      (@observed_model.selection.remove_observer(@sel_observer) if @observed_model.valid?) rescue nil
    end
    @observed_model = nil
  end

  def self.stop_cache_timer
    if @timer
      UI.stop_timer(@timer) rescue nil
      @timer = nil
    end
    detach_selection_observer
  end

  # Mode "ukuran ikut item baru": ambil posisi (origin) & rotasi dari transformasi item lama,
  # tapi skalanya dari transformasi item baru. Arah sumbu dinormalisasi supaya skala item lama
  # tidak ikut terbawa; kalau item lama ter-mirror, orientasi mirror-nya tetap dipertahankan.
  def self.follow_new_transform(tr_lama, tr_baru)
    xa = tr_lama.xaxis.normalize
    ya = tr_lama.yaxis.normalize
    za = tr_lama.zaxis.normalize
    base = Geom::Transformation.axes(tr_lama.origin, xa, ya, za)
    base * Geom::Transformation.scaling(tr_baru.xaxis.length, tr_baru.yaxis.length, tr_baru.zaxis.length)
  rescue
    tr_lama
  end

  # Bounds lokal entitas dalam definition/entity space (sebelum transformation scale)
  # Digunakan untuk menghitung rasio skala yang benar di ruang lokal.
  # Di SketchUp:
  # - width  = sumbu X lokal (LenX)
  # - height = sumbu Y lokal (LenY)
  # - depth  = sumbu Z lokal (LenZ)
  def self.local_def_bounds(entity)
    defn = if entity.respond_to?(:definition)
             entity.definition
           elsif entity.respond_to?(:entities)
             entity.entities.parent rescue nil
           else
             nil
           end

    if defn && defn.respond_to?(:bounds) && defn.bounds.valid?
      defn.bounds
    elsif entity.respond_to?(:bounds)
      entity.bounds
    else
      Geom::BoundingBox.new
    end
  end
  # -----------------------------------------------------------------

  def self.run
    Sketchup.require 'boosok_tools/hub' unless defined?(BoosokTools::Hub)
    BoosokTools::Hub.open_or_show('replacer')
  end

  def self.attach_callbacks(dialog)
    return unless dialog
    start_cache_timer
    # Callback cukup didaftarkan sekali per dialog; add_action_callback dengan nama sama
    # akan bertumpuk (handler jalan 2-3x). Timer di atas tetap dinyalakan tiap tool dibuka.
    return if @dialog.equal?(dialog)
    @dialog = dialog

    # "activate_select_tool"/"deactivate_select_tool" didaftarkan sekali oleh Hub.

    # --- CALLBACK 1: CEK ITEM LAMA ---
    dialog.add_action_callback("check_old_items") do |_action_context|
      model = Sketchup.active_model
      live = model ? model.selection.to_a.select { |e|
        e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      } : []
      picked = live.empty? ? @cache : live

      if picked.empty?
        dialog.execute_script("showToast('Pilih minimal 1 Grup/Komponen Lama terlebih dahulu di layar!');")
      else
        @old_items = picked.dup
        stop_cache_timer
        @cache = []
        model.selection.clear if model
        dialog.execute_script("showStep(2);")
      end
    end

    # --- CALLBACK 2: RESTART ---
    restart_cb = lambda do |_action_context|
      @old_items = []
      @cache     = []
      model = Sketchup.active_model
      model.selection.clear if model
      start_cache_timer
      dialog.execute_script("showStep(1);")
    end
    dialog.add_action_callback("replacer_restart_process", &restart_cb)

    # --- CALLBACK 3: PROSES PENGGANTIAN & PENSKALAAN ---
    # size_mode: 'old' (default) = ukuran ikut item lama, 'new' = ukuran ikut item baru
    replace_cb = lambda do |_action_context, size_mode = 'old'|
      follow_new = (size_mode.to_s == 'new')
      model = Sketchup.active_model
      if model.nil?
        dialog.execute_script("resetExecButton(); showToast('Tidak ada model aktif.');")
        next
      end

      new_sel = model.selection.to_a.select { |e|
        e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      }

      if new_sel.length != 1
        dialog.execute_script("showToast('Pastikan Anda memilih tepat 1 Item Baru sebagai pengganti!');")
        dialog.execute_script("resetExecButton();")
        next
      end

      item_baru = new_sel[0]

      if @old_items.empty?
        dialog.execute_script("showToast('Item Lama belum dipilih. Ulangi dari Langkah 1.'); resetExecButton(); showStep(1);")
        start_cache_timer
        next
      end

      # Filter item lama yang masih valid
      @old_items.select! { |e| e && e.valid? }
      if @old_items.empty?
        dialog.execute_script("showToast('Item Lama sudah tidak ada (terhapus/di-undo). Ulangi dari Langkah 1.'); resetExecButton(); showStep(1);")
        start_cache_timer
        next
      end

      if @old_items.include?(item_baru)
        dialog.execute_script("showToast('Item baru tidak boleh sama dengan item lama!');")
        dialog.execute_script("resetExecButton();")
        next
      end

      begin
        model.start_operation("Group Replacer", true)

        definition_baru = item_baru.respond_to?(:definition) ? item_baru.definition : item_baru.entities.parent
        dicts_baru      = item_baru.attribute_dictionaries
        transformasi_baru = item_baru.transformation

        replaced = 0

        @old_items.each do |item_lama|
          begin
            next unless item_lama && item_lama.valid?

            nama_lama         = item_lama.name
            transformasi_lama = item_lama.transformation
            context_lama      = item_lama.parent.entities
            tag_lama          = item_lama.layer

            # 1. Tambahkan instance baru dengan transformasi lama (posisi, rotasi, titik axes 100% sama).
            #    Mode 'new': posisi & rotasi item lama, tapi skala dari item baru.
            spawn_tr = follow_new ? follow_new_transform(transformasi_lama, transformasi_baru) : transformasi_lama
            new_instance = context_lama.add_instance(definition_baru, spawn_tr)
            new_instance.layer = tag_lama
            new_instance.name  = nama_lama unless nama_lama.empty?

            if dicts_baru
              dicts_baru.each do |dict|
                dict.each_pair { |k, v| new_instance.set_attribute(dict.name, k, v) }
              end
            end

            unless follow_new
            # 2. Hitung rasio penskalaan agar ukuran bounding LenX, LenY, LenZ mengikuti item lama
            old_lb = local_def_bounds(item_lama)
            new_lb = local_def_bounds(new_instance)

            old_w = old_lb.width.to_f
            old_h = old_lb.height.to_f
            old_d = old_lb.depth.to_f

            new_w = new_lb.width.to_f
            new_h = new_lb.height.to_f
            new_d = new_lb.depth.to_f

            sx = (new_w > 0.0001 && old_w > 0.0001) ? (old_w / new_w) : 1.0
            sy = (new_h > 0.0001 && old_h > 0.0001) ? (old_h / new_h) : 1.0
            sz = (new_d > 0.0001 && old_d > 0.0001) ? (old_d / new_d) : 1.0

            # 3. Terapkan skala non-uniform di ruang lokal objek
            # Memakai transformasi lokal bawaan SketchUp: titik axes (origin) TIDAK AKAN BERGESER!
            scale_tr = Geom::Transformation.scaling(sx, sy, sz)
            new_instance.transformation = new_instance.transformation * scale_tr

            # 4. Sinkronisasi attribute Dynamic Component bila ada
            if new_instance.is_a?(Sketchup::ComponentInstance) &&
               new_instance.definition.attribute_dictionaries &&
               new_instance.definition.attribute_dictionaries["dynamic_attributes"]
              target_len_x = old_w * transformasi_lama.xaxis.length.to_f
              target_len_y = old_h * transformasi_lama.yaxis.length.to_f
              target_len_z = old_d * transformasi_lama.zaxis.length.to_f
              new_instance.set_attribute("dynamic_attributes", "lenx", target_len_x)
              new_instance.set_attribute("dynamic_attributes", "leny", target_len_y)
              new_instance.set_attribute("dynamic_attributes", "lenz", target_len_z)
              new_instance.set_attribute("dynamic_attributes", "_lenx_nominal", target_len_x)
              new_instance.set_attribute("dynamic_attributes", "_leny_nominal", target_len_y)
              new_instance.set_attribute("dynamic_attributes", "_lenz_nominal", target_len_z)
            end
            end # unless follow_new

            item_lama.erase!
            replaced += 1
          rescue => item_err
            puts "[TheReplacer] Gagal ganti item: #{item_err.message}\n#{item_err.backtrace.first(3).join("\n") rescue ''}"
          end
        end

        model.commit_operation
        model.selection.clear

        @old_items = []
        dialog.execute_script("resetExecButton();")
        done_msg = follow_new ? "Sukses mengganti #{replaced} objek (ukuran ikut item baru)." :
                                "Sukses mengganti & menyesuaikan ukuran #{replaced} objek."
        dialog.execute_script("showSuccessStep(#{done_msg.to_json});")

      rescue => e
        model.abort_operation rescue nil
        dialog.execute_script("resetExecButton();")
        dialog.execute_script("showToast(#{("Gagal: " + e.message).to_json});")
      end
    end
    dialog.add_action_callback("proses_replace", &replace_cb)
    dialog.add_action_callback("replace", &replace_cb)
  end
end