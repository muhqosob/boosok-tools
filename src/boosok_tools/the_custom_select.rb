require 'sketchup'
Sketchup.require 'boosok_tools/locale' unless defined?(BoosokTools::Locale)

module BoosokTools
  module SelectTool5D
    # Daftar eksplisit (bukan Dir['*.rb']): di paket terenkripsi filenya .rbe sehingga glob tidak ketemu.
    # Handler cuma saling pakai saat tool dibuat, jadi urutan muat tidak berpengaruh.
    HANDLERS = %w[core_tool draw_handler mouse_handler select_handler ui_info_handler].freeze unless defined?(HANDLERS)

    def self.load_handlers
      HANDLERS.each { |h| BoosokTools.load_module("custom_select/#{h}") }
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
      load_handlers unless defined?(BoosokTools::SelectTool5D::CoreTool)
      model = Sketchup.active_model
      unless model && model.valid?
        UI.messagebox("Tidak ada model aktif yang terbuka di SketchUp.") rescue nil
        return
      end

      tool = BoosokTools::SelectTool5D::CoreTool.new
      model.select_tool(tool)
    rescue => e
      UI.messagebox("Gagal mengaktifkan Select Tool: #{e.message}") rescue nil
    end

    def self.run
      Sketchup.require 'boosok_tools/hub' unless defined?(BoosokTools::Hub)
      BoosokTools::Hub.open_or_show('custom_select')
    end

    # Muat semua handler di dalam folder custom_select
    load_handlers
  end
end

# Alias untuk kompatibilitas ke belakang (backwards compatibility)
module CustomTools
  SelectTool5D = BoosokTools::SelectTool5D unless defined?(SelectTool5D)
end

file_loaded(__FILE__)
