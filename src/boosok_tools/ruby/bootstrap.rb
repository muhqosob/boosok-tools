require 'sketchup'
require 'json'

module BoosokTools
  unless file_loaded?(__FILE__)
    Sketchup.require 'boosok_tools/ruby/titlebar'
    BoosokTools.init_session_file
    Sketchup.require 'boosok_tools/ruby/locale'
    # Buat js/strings.js dari locales/*.json sebelum dialog mana pun dimuat
    BoosokTools::Locale.export_js
    Sketchup.require 'boosok_tools/updater'
    Sketchup.require 'boosok_tools/license'
    Sketchup.require 'boosok_tools/flags'
    Sketchup.require 'boosok_tools/hub'
    Sketchup.require 'boosok_tools/ruby/paid/select_tool'

    # File lama sebelum dipindah ke ruby/free dan ruby/paid: hapus supaya tidak ada salinan ganda (hanya kalau
    # lokasi baru sudah ada, dan gagal pun tidak masalah).
    if File.directory?(File.join(BoosokTools::SUPPORT_DIR, 'ruby', 'free'))
      begin
        require 'fileutils'
        %w[cleangroup purge replacer reset selector deep_properties hideon_scene select_tool slice void
           untagnpaint locale shortcut_sync titlebar bootstrap].each do |name|
          %w[rb rbe].each do |ext|
            old = File.join(BoosokTools::SUPPORT_DIR, "#{name}.#{ext}")
            File.delete(old) if File.exist?(old)
          end
        end
        old_dir = File.join(BoosokTools::SUPPORT_DIR, 'select_tool')
        FileUtils.rm_rf(old_dir) if File.directory?(old_dir)
      rescue StandardError
        nil
      end
    end

    # Fitur Hotkey di Hub dihapus: shortcut diatur lewat SketchUp (Preferences > Shortcuts). Bersihkan sisa lama:
    # file modul & .dat dari versi sebelumnya, serta data hotkey tersimpan (dulu ditulis ulang ke preferensi
    # SketchUp tiap SketchUp ditutup, sehingga bisa menimpa pengaturan shortcut bawaan).
    begin
      %w[rb rbe].each do |ext|
        stale = File.join(BoosokTools::SUPPORT_DIR, 'ruby', "shortcut_sync.#{ext}")
        File.delete(stale) if File.exist?(stale)
      end
      stale_dat = File.join(BoosokTools::SUPPORT_DIR, 'BoosokTools_Shortcuts.dat')
      File.delete(stale_dat) if File.exist?(stale_dat)
      Sketchup.write_default('BoosokTools', 'saved_hotkeys', '')
    rescue StandardError
      nil
    end

    # ── Menu Extensions utama: submenu Boosok Tools ──
    ext_menu   = UI.menu('Extensions')
    tools_menu = ext_menu.add_submenu('Boosok Tools')

    # Helper lambda (closure) agar bisa akses tools_menu sebagai local variable
    register_cmd = lambda do |label, &block|
      cmd = UI::Command.new(label) { block.call }
      tools_menu.add_item(cmd)
      cmd
    end

    register_cmd.call('Buka Hub')      { BoosokTools::Hub.show }
    register_cmd.call('Selector')      { BoosokTools::Hub.open_or_show('selector') }
    register_cmd.call('Select Tools')  { BoosokTools::Hub.open_or_show('custom_select') }
    register_cmd.call('Replacer')      { BoosokTools::Hub.open_or_show('replacer') }
    register_cmd.call('Cleaner')       { BoosokTools::Hub.open_or_show('clean') }
    register_cmd.call('Reset Scale')   { BoosokTools::Hub.open_or_show('reset') }
    register_cmd.call('Hide Scene')    { BoosokTools::Hub.open_or_show('scene') }
    register_cmd.call('Untag')         { BoosokTools::Hub.open_or_show('untag') }
    register_cmd.call('Deep Props')    { BoosokTools::Hub.open_or_show('deep') }
    register_cmd.call('Purge')         { BoosokTools::Hub.open_or_show('purge') }
    register_cmd.call('Void')          { BoosokTools::Hub.open_or_show('void') }
    register_cmd.call('Slice')         { BoosokTools::Hub.open_or_show('slice') }
    register_cmd.call('Trowel')        { BoosokTools::Hub.open_or_show('trowel') }
    register_cmd.call('RAB')           { BoosokTools::Hub.open_or_show('rab') } unless BoosokTools::Hub.tool_hidden?('rab')

    # Mode developer (hanya aktif kalau file .dev_mode ada di folder plugin)
    Sketchup.require 'boosok_tools/dev_reload'
    if BoosokTools::Dev.enabled?
      register_cmd.call('Reload Plugin (Dev)') { BoosokTools::Dev.reload_all }
      BoosokTools::Dev.start
    end

    # Preload file tool sebentar setelah startup supaya buka Hub pertama kali tetap cepat
    UI.start_timer(1.5, false) { BoosokTools::Hub.preload_tools rescue nil }

    # Cek otomatis saat SketchUp dibuka, dialog cuma muncul kalau ada update
    Updater.check
    # Cek lisensi ke server di momen yang sama (butuh internet, offline dilewati diam-diam): key yang dicabut baru
    # berlaku di sini, selain itu lisensi yang sudah aktif tetap jalan offline tanpa batas waktu.
    # Ditunda: verifikasi token memuat OpenSSL, jangan memperlambat startup SketchUp.
    UI.start_timer(5, false) { License.maybe_refresh rescue nil }
    # Kill-switch fitur dari server: cek saat startup lalu tiap 5 menit; tool yang dimatikan tidak bisa dibuka
    Flags.start { BoosokTools::Hub.flags_changed rescue nil }

    # ── Helpers Make Unique (dipakai context menu + bisa dipanggil internal) ──
    # Untuk ComponentInstance: pakai make_unique bawaan SketchUp API.
    # Untuk Group: tidak ada make_unique di API, jadi kita buat definisi baru secara manual
    # (copy semua entities ke group baru, lalu hapus group lama) jika definisinya dipakai >1 instance.
    # Mengembalikan entity hasil (bisa beda pointer jika group di-replace), atau nil jika gagal.
    make_entity_unique = lambda do |ent|
      return nil unless ent.respond_to?(:valid?) && ent.valid?

      if ent.is_a?(Sketchup::ComponentInstance)
        ent.make_unique
        return ent
      end

      # Group: cek apakah definisinya masih dipakai oleh >1 instance
      return ent unless ent.is_a?(Sketchup::Group)

      begin
        defn = ent.entities.parent   # ComponentDefinition di balik group ini
        return ent if defn.instances.length <= 1  # sudah unique

        # Buat group baru di entities yang sama dengan group asli
        parent_ents = ent.parent.is_a?(Sketchup::Entities) ? ent.parent : ent.parent.entities
        new_grp = parent_ents.add_group
        new_grp.transformation = ent.transformation
        new_grp.layer          = ent.layer
        new_grp.name           = ent.name
        new_grp.material       = ent.material if ent.material

        # Salin semua attribute dictionaries (kecuali internal SketchUp)
        (ent.attribute_dictionaries || []).each do |dict|
          dict.each_pair { |k, v| new_grp.set_attribute(dict.name, k, v) }
        end

        # Salin semua entity (face, edge, group, component) dari definisi lama
        # ke group baru menggunakan add_faces/add_line (untuk geometri dasar)
        # dan entities.add_group/add_instance untuk nested containers.
        copy_entities = lambda do |src_ents, dst_ents|
          # Salin face terlebih dahulu
          src_ents.each do |e|
            next unless e.valid?
            case e
            when Sketchup::Face
              pts = e.outer_loop.vertices.map(&:position)
              begin
                new_face = dst_ents.add_face(pts)
                new_face.material      = e.material      if e.material
                new_face.back_material = e.back_material if e.back_material
              rescue StandardError
                nil
              end
            end
          end
          # Salin edge yang belum punya face (standalone edges)
          src_ents.each do |e|
            next unless e.valid?
            next unless e.is_a?(Sketchup::Edge)
            next if e.faces.any?(&:valid?)
            begin
              dst_ents.add_line(e.start.position, e.end.position)
            rescue StandardError
              nil
            end
          end
          # Salin nested groups & components
          src_ents.each do |e|
            next unless e.valid?
            if e.is_a?(Sketchup::Group)
              ng = dst_ents.add_group
              ng.transformation = e.transformation
              ng.layer          = e.layer
              ng.name           = e.name
              ng.material       = e.material if e.material
              (e.attribute_dictionaries || []).each { |d| d.each_pair { |k, v| ng.set_attribute(d.name, k, v) } }
              copy_entities.call(e.entities, ng.entities)
            elsif e.is_a?(Sketchup::ComponentInstance)
              ni = dst_ents.add_instance(e.definition, e.transformation)
              ni.layer    = e.layer
              ni.name     = e.name
              ni.material = e.material if e.material
              (e.attribute_dictionaries || []).each { |d| d.each_pair { |k, v| ni.set_attribute(d.name, k, v) } }
            end
          end
        end

        copy_entities.call(defn.entities, new_grp.entities)
        ent.erase!
        new_grp
      rescue => ex
        puts "[Boosok] make_group_unique gagal: #{ex.class}: #{ex.message}"
        ent  # kembalikan entity asli jika gagal
      end
    end

    # Rekursif: jadikan unique ent + semua nested containers-nya
    make_entity_unique_recursive = lambda do |ent|
      return 0 unless ent.respond_to?(:valid?) && ent.valid?

      result = make_entity_unique.call(ent)
      n = 1

      # Masuk ke dalam entities untuk proses nested containers
      target = result || ent
      return n unless target.respond_to?(:valid?) && target.valid?

      inner_ents = target.is_a?(Sketchup::Group) ? target.entities :
                   (target.is_a?(Sketchup::ComponentInstance) ? target.definition.entities : nil)
      return n unless inner_ents

      inner_ents.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }.each do |child|
        n += make_entity_unique_recursive.call(child)
      end
      n
    end

    # ── Context menu klik kanan: satu submenu "Boosok Tools >" ───────────────
    # Muncul saat ada group/component di seleksi. Berisi sub-menu terstruktur.
    UI.add_context_menu_handler do |menu|
      model = Sketchup.active_model
      next unless model

      sel = model.selection.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      next if sel.empty?

      menu.add_separator
      bt_menu = menu.add_submenu('Boosok Tools')

      # ── Reset Scale ────────────────────────────────────────────────────────
      bt_menu.add_item('Reset Scale') do
        begin
          if BoosokTools::Hub.tool_disabled?('reset')
            UI.messagebox(BoosokTools::Hub.disabled_message('reset'), MB_OK)
            next
          end
          BoosokTools.load_module('ruby/free/reset')
          result = BoosokTools::TheResetScale.reset_selection('preserve', false)
          if result.is_a?(Integer)
            UI.messagebox("Skala #{result} objek di-reset (ukuran tetap dipertahankan).", MB_OK)
          else
            UI.messagebox(result.to_s, MB_OK)
          end
        rescue => e
          UI.messagebox("Reset gagal: #{e.message}", MB_OK)
        end
      end

      # ── Make Unique Group ─────────────────────────────────────────────────
      mu_menu = bt_menu.add_submenu('Make Unique Group')

      mu_menu.add_item('Hanya yang dipilih') do
        begin
          model.start_operation('Make Unique', true)
          count = 0
          sel.each do |e|
            next unless e.valid?
            res = make_entity_unique.call(e)
            count += 1 if res
          end
          model.commit_operation
          UI.messagebox("#{count} group/component dijadikan unique.", MB_OK)
        rescue => e
          model.abort_operation rescue nil
          UI.messagebox("Make Unique gagal: #{e.message}", MB_OK)
        end
      end

      mu_menu.add_item('Rekursif (termasuk isi)') do
        begin
          model.start_operation('Make Unique Rekursif', true)
          count = sel.sum { |e| make_entity_unique_recursive.call(e) }
          model.commit_operation
          UI.messagebox("#{count} group/component dijadikan unique (rekursif).", MB_OK)
        rescue => e
          model.abort_operation rescue nil
          UI.messagebox("Make Unique rekursif gagal: #{e.message}", MB_OK)
        end
      end
    end

    file_loaded(__FILE__)
  end
end
