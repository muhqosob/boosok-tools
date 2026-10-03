require 'sketchup'
Sketchup.require 'boosok_tools/ruby/locale' unless defined?(BoosokTools::Locale)

module BoosokTools
  module SelectTool
    # Daftar eksplisit (bukan Dir['*.rb']): di paket terenkripsi filenya .rbe sehingga glob tidak ketemu.
    # Handler cuma saling pakai saat tool dibuat, jadi urutan muat tidak berpengaruh.
    # Tanpa `unless defined?`: konstanta harus diganti saat hot-reload, kalau tidak handler baru tidak ikut dimuat.
    remove_const(:HANDLERS) if defined?(HANDLERS)
    HANDLERS = %w[core_tool draw_handler mouse_handler select_handler area_handler ui_info_handler].freeze

    # Nama tipe entity ("Group", "Face", ...). Pengganti Entity#typename yang lambat.
    def self.type_name(entity)
      entity.class.name.to_s.split('::').last || 'Entity'
    end

    def self.load_handlers
      HANDLERS.each { |h| BoosokTools.load_module("ruby/paid/select_tool/#{h}") }
    end

    def self.reload!
      load_handlers
      activate_tool
      puts "[Select Tool] Berhasil me-reload semua file dan mengaktifkan tool baru!"
    end

    def self.activate_tool
      if defined?(BoosokTools::License) && !BoosokTools::License.can_use?
        # Cukup notifikasi "terkunci" (tanpa popup aktivasi)
        BoosokTools::Hub.notify_locked rescue nil
        return
      end

      # Handler sudah dimuat di bawah (saat file ini di-load); jangan parse ulang tiap aktivasi
      load_handlers unless defined?(BoosokTools::SelectTool::CoreTool)
      model = Sketchup.active_model
      unless model && model.valid?
        UI.messagebox("Tidak ada model aktif yang terbuka di SketchUp.") rescue nil
        return
      end

      tool = BoosokTools::SelectTool::CoreTool.new
      model.select_tool(tool)
    rescue => e
      UI.messagebox("Gagal mengaktifkan Select Tool: #{e.message}") rescue nil
    end

    def self.run
      Sketchup.require 'boosok_tools/hub' unless defined?(BoosokTools::Hub)
      BoosokTools::Hub.open_or_show('custom_select')
    end

    # Muat semua handler di dalam folder select_tool
    load_handlers
  end
end

file_loaded(__FILE__)
