require 'sketchup'
require 'json'

module BoosokTools
  unless file_loaded?(__FILE__)
    load File.join(__dir__, 'titlebar.rb')
    BoosokTools.init_session_file
    require_relative 'locale'
    # Buat js/strings.js dari locales/*.json sebelum dialog mana pun dimuat
    BoosokTools::Locale.export_js
    require_relative 'updater'
    require_relative 'shortcut_sync'
    require_relative 'license'
    require_relative 'hub'
    require_relative 'the_custom_select'

    BoosokTools::ShortcutSync.init

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

    # Mode developer (hanya aktif kalau file .dev_mode ada di folder plugin)
    require_relative 'dev_reload'
    if BoosokTools::Dev.enabled?
      register_cmd.call('Reload Plugin (Dev)') { BoosokTools::Dev.reload_all }
      BoosokTools::Dev.start
    end

    # Preload file tool sebentar setelah startup supaya buka Hub pertama kali tetap cepat
    UI.start_timer(1.5, false) { BoosokTools::Hub.preload_tools rescue nil }

    # Cek otomatis saat SketchUp dibuka, dialog cuma muncul kalau ada update
    Updater.check

    file_loaded(__FILE__)
  end
end
