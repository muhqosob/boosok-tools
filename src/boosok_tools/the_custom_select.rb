require 'sketchup'
require_relative 'locale' unless defined?(BoosokTools::Locale)

module BoosokTools
  module SelectTool5D
    PATH ||= File.join(__dir__, 'custom_select')

    def self.reload!
      Dir[File.join(PATH, '*.rb')].each { |f| load f }
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
      Dir[File.join(PATH, '*.rb')].each { |f| load f } unless defined?(BoosokTools::SelectTool5D::CoreTool)
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
      require_relative 'hub' unless defined?(BoosokTools::Hub)
      BoosokTools::Hub.open_or_show('custom_select')
    end

    # Muat semua handler di dalam folder custom_select
    Dir[File.join(PATH, '*.rb')].each { |f| load f }
  end
end

# Alias untuk kompatibilitas ke belakang (backwards compatibility)
module CustomTools
  SelectTool5D = BoosokTools::SelectTool5D unless defined?(SelectTool5D)
end

file_loaded(__FILE__)
