require 'sketchup'

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
        UI.messagebox("Masa uji coba (trial 7 hari) Boosok Tools telah habis.\nSemua tool terkunci.\n\nSilakan buka Hub dan aktifkan lisensi Anda.") rescue nil
        BoosokTools::Hub.show rescue nil
        return
      end

      Dir[File.join(PATH, '*.rb')].each { |f| load f }
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
