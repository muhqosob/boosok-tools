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

    file_loaded(__FILE__)
  end
end
