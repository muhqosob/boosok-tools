# frozen_string_literal: true
require 'sketchup'
require 'json'

module BoosokTools
  module ShortcutSync
    # Mapping tool ID ke menu path resmi di SketchUp dan path lama (legacy)
    TOOL_COMMANDS = {
      'hub'           => { label: 'Buka Hub',     path: 'Extensions/Boosok Tools/Buka Hub',     legacy: ['Extensions/Boosok Tools'] },
      'selector'      => { label: 'Selector',     path: 'Extensions/Boosok Tools/Selector',     legacy: ['Extensions/Boosok Tools/The Selector'] },
      'custom_select' => { label: 'Select Tools', path: 'Extensions/Boosok Tools/Select Tools', legacy: [] },
      'replacer'      => { label: 'Replacer',     path: 'Extensions/Boosok Tools/Replacer',     legacy: ['Extensions/Boosok Tools/The Replacer'] },
      'clean'         => { label: 'Cleaner',      path: 'Extensions/Boosok Tools/Cleaner',      legacy: ['Extensions/Boosok Tools/Convert to Clean Group'] },
      'reset'         => { label: 'Reset Scale',  path: 'Extensions/Boosok Tools/Reset Scale',  legacy: ['Extensions/Boosok Tools/Reset The Group Scale'] },
      'scene'         => { label: 'Hide Scene',   path: 'Extensions/Boosok Tools/Hide Scene',   legacy: ['Extensions/Boosok Tools/Hide on Scene Manager'] },
      'untag'         => { label: 'Untag',        path: 'Extensions/Boosok Tools/Untag',        legacy: ['Extensions/Boosok Tools/Untag and Paint'] },
      'deep'          => { label: 'Deep Props',   path: 'Extensions/Boosok Tools/Deep Props',   legacy: [] }
    }.freeze

    class << self
      # Inisialisasi: pasang AppObserver agar saat SketchUp ditutup, preferensi tidak tertimpa
      def init
        return if @initialized
        @initialized = true
        register_app_observer
        migrate_legacy_shortcuts rescue nil
      end

      # Path ke file SharedPreferences.json SketchUp
      def pref_file_path
        # SketchUp 2026 atau versi saat ini
        ver = Sketchup.version.to_i
        year = ver >= 2000 ? ver : (2000 + ver)
        primary = File.join(ENV['APPDATA'] || '', 'SketchUp', "SketchUp #{year}", 'SketchUp', 'SharedPreferences.json')
        return primary if File.exist?(primary)

        # Fallback cari di folder SketchUp apapun
        pattern = File.join(ENV['APPDATA'] || '', 'SketchUp', 'SketchUp *', 'SketchUp', 'SharedPreferences.json')
        Dir.glob(pattern).sort.last
      end

      # Konversi shortcut manusia (misal "Shift+T", "Ctrl+Shift+G") ke format SketchUp ("0 0 1 T", "1 0 1 G")
      def combo_to_skp(combo)
        return nil if combo.nil? || combo.to_s.strip.empty?
        parts = combo.to_s.split('+').map(&:strip)
        key = parts.pop
        return nil unless key

        ctrl  = parts.any? { |p| p.casecmp('ctrl').zero? || p.casecmp('control').zero? } ? 1 : 0
        alt   = parts.any? { |p| p.casecmp('alt').zero? } ? 1 : 0
        shift = parts.any? { |p| p.casecmp('shift').zero? } ? 1 : 0

        k = key.length == 1 ? key.upcase : key
        "#{ctrl} #{alt} #{shift} #{k}"
      end

      # Konversi format SketchUp ("0 0 1 T") ke format manusia ("Shift+T")
      def skp_to_combo(skp_str)
        tokens = skp_str.to_s.strip.split(/\s+/)
        return '' if tokens.size < 4
        ctrl  = tokens[0] == '1'
        alt   = tokens[1] == '1'
        shift = tokens[2] == '1'
        key   = tokens[3]
        res = []
        res << 'Ctrl' if ctrl
        res << 'Alt' if alt
        res << 'Shift' if shift
        res << key
        res.join('+')
      end

      # Ambil semua shortcut yang saat ini terdaftar (gabungan dari Sketchup.get_shortcuts & SharedPreferences.json)
      def get_all_shortcuts
        active = {}
        # 1. Dari API Sketchup.get_shortcuts (shortcut yang aktif di memori sesi saat ini)
        if Sketchup.respond_to?(:get_shortcuts)
          Sketchup.get_shortcuts.each do |line|
            combo, menu_path = line.split("\t", 2)
            next unless combo && menu_path
            active[menu_path.strip] = combo.strip
          end
        end

        # 2. Dari SharedPreferences.json (shortcut yang tersimpan di disk)
        from_file = read_shortcuts_from_file

        result = {}
        TOOL_COMMANDS.each do |id, info|
          all_paths = [info[:path]] + (info[:legacy] || [])
          # Cek aktif di memori dulu
          combo = all_paths.map { |p| active[p] }.compact.first
          # Fallback cek dari file
          combo ||= all_paths.map { |p| from_file[p] }.compact.first
          result[id] = combo || ''
        end
        result
      end

      # Baca shortcut langsung dari file SharedPreferences.json
      def read_shortcuts_from_file
        res = {}
        path = pref_file_path
        return res unless path && File.exist?(path)

        data = JSON.parse(File.read(path))
        settings = (data['Windows Only'] && data['Windows Only']['Settings']) || data['Settings'] || {}
        settings.each do |k, v|
          next unless k.start_with?('Shortcut_') && v.is_a?(String)
          tokens = v.strip.split(/\s+/)
          next if tokens.size < 5
          target_path = tokens[4..].join(' ')
          combo = skp_to_combo(tokens[0..3].join(' '))
          res[target_path] = combo
        end
        res
      rescue => e
        puts "[BoosokTools] read_shortcuts_from_file error: #{e.message}"
        res
      end

      # Simpan satu atau banyak shortcut ke SharedPreferences.json
      # hotkeys_hash: { 'selector' => 'Shift+T', 'replacer' => 'Shift+R', ... }
      def save_shortcuts_to_file(hotkeys_hash)
        path = pref_file_path
        return false unless path && File.exist?(path)

        data = JSON.parse(File.read(path))
        target_section = if data['Windows Only'] && data['Windows Only']['Settings']
                           data['Windows Only']['Settings']
                         else
                           data['Settings'] ||= {}
                         end

        # Kumpulkan semua shortcut yang bukan Boosok Tools
        preserved_shortcuts = []
        boosok_paths = TOOL_COMMANDS.values.flat_map { |v| [v[:path]] + (v[:legacy] || []) }

        target_section.each do |k, v|
          next unless k.start_with?('Shortcut_') && v.is_a?(String)
          tokens = v.strip.split(/\s+/)
          next if tokens.size < 5
          target_cmd = tokens[4..].join(' ')
          unless boosok_paths.include?(target_cmd)
            preserved_shortcuts << v
          end
        end

        # Tambahkan shortcut Boosok Tools yang aktif
        hotkeys_hash.each do |id, combo|
          next if combo.nil? || combo.to_s.strip.empty?
          info = TOOL_COMMANDS[id.to_s]
          next unless info
          skp_prefix = combo_to_skp(combo)
          next unless skp_prefix
          preserved_shortcuts << "#{skp_prefix} #{info[:path]}"
        end

        # Hapus semua Shortcut_* lama di section
        keys_to_del = target_section.keys.select { |k| k.start_with?('Shortcut_') }
        keys_to_del.each { |k| target_section.delete(k) }

        # Tulis ulang dengan indeks berurutan 1..N
        preserved_shortcuts.each_with_index do |sc_str, idx|
          target_section["Shortcut_#{idx + 1}"] = sc_str
        end
        target_section['Num_Shortcuts'] = preserved_shortcuts.size

        # Tulis kembali ke file secara aman
        File.write(path, JSON.pretty_generate(data))

        # Simpan juga ke cache default Boosok
        Sketchup.write_default('BoosokTools', 'saved_hotkeys', hotkeys_hash.to_json) rescue nil

        true
      rescue => e
        puts "[BoosokTools] save_shortcuts_to_file error: #{e.message}"
        false
      end

      # Migrasikan nama legacy jika masih ada di file
      def migrate_legacy_shortcuts
        path = pref_file_path
        return unless path && File.exist?(path)

        data = JSON.parse(File.read(path))
        target_section = (data['Windows Only'] && data['Windows Only']['Settings']) || data['Settings']
        return unless target_section

        changed = false
        target_section.each do |k, v|
          next unless k.start_with?('Shortcut_') && v.is_a?(String)
          TOOL_COMMANDS.each do |_id, info|
            (info[:legacy] || []).each do |old_path|
              if v.end_with?(" #{old_path}")
                target_section[k] = v.sub(" #{old_path}", " #{info[:path]}")
                changed = true
              end
            end
          end
        end

        File.write(path, JSON.pretty_generate(data)) if changed
      rescue => e
        puts "[BoosokTools] migrate_legacy_shortcuts error: #{e.message}"
      end

      # Buat file export .dat yang bisa di-import langsung di SketchUp Preferences > Shortcuts
      def generate_dat_file(hotkeys_hash = nil)
        hotkeys = hotkeys_hash || get_all_shortcuts
        valid_entries = []
        hotkeys.each do |id, combo|
          next if combo.nil? || combo.to_s.strip.empty?
          info = TOOL_COMMANDS[id.to_s]
          next unless info
          skp_prefix = combo_to_skp(combo)
          next unless skp_prefix
          valid_entries << "#{skp_prefix} #{info[:path]}"
        end

        lines = ["[Accelerator]", "Count=#{valid_entries.size}"] + valid_entries
        content = lines.join("\r\n") + "\r\n"

        # Simpan ke Desktop agar mudah dipilih saat klik Import...
        desktop_dir = File.join(ENV['USERPROFILE'] || ENV['HOME'] || '', 'Desktop')
        desktop_path = File.join(desktop_dir, 'BoosokTools_Shortcuts.dat')
        File.write(desktop_path, content) rescue nil

        # Simpan juga ke folder plugin
        target_dir = ::BoosokTools::SUPPORT_DIR
        dat_path = File.join(target_dir, 'BoosokTools_Shortcuts.dat')
        File.write(dat_path, content) rescue nil

        # Salin path ke clipboard Windows agar user bisa langsung paste (Ctrl+V) di dialog file
        begin
          IO.popen('clip', 'w') { |pipe| pipe.write(desktop_path) }
        rescue => e
          puts "[BoosokTools] clip error: #{e.message}"
        end

        desktop_path
      rescue => e
        puts "[BoosokTools] generate_dat_file error: #{e.message}"
        nil
      end

      # Otomatisasi sinkronisasi ke SketchUp Preferences:
      # 1. Simpan ke SharedPreferences.json
      # 2. Buat file .dat di Desktop & clipboard
      # 3. Buka jendela Preferences > Shortcuts jika diminta
      def apply_to_sketchup(hotkeys_hash)
        save_shortcuts_to_file(hotkeys_hash)
        desktop_path = generate_dat_file(hotkeys_hash)

        # Coba buka dialog Preferences SketchUp jika belum buka
        begin
          if UI.respond_to?(:show_preferences)
            UI.show_preferences('Shortcuts') rescue UI.show_preferences
          else
            Sketchup.send_action('showPreferences:') rescue Sketchup.send_action(21022) rescue nil
          end
        rescue => e
          puts "[BoosokTools] show_preferences error: #{e.message}"
        end

        desktop_path
      end

      private

      def register_app_observer
        return if @observer_registered
        obs = Class.new(Sketchup::AppObserver) do
          def onQuit
            # Saat SketchUp ditutup, pastikan shortcut BoosokTools tetap tersimpan di SharedPreferences.json
            saved = Sketchup.read_default('BoosokTools', 'saved_hotkeys', '') rescue ''
            if saved && !saved.empty?
              hash = JSON.parse(saved) rescue nil
              BoosokTools::ShortcutSync.save_shortcuts_to_file(hash) if hash
            end
          end
        end.new
        Sketchup.add_observer(obs)
        @observer_registered = true
      rescue => e
        puts "[BoosokTools] register_app_observer error: #{e.message}"
      end
    end
  end
end
