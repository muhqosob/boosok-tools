require 'sketchup'

module BoosokTools
  module SelectTool5D
    PATH ||= File.join(__dir__, 'custom_select')

    def self.reload!
      Dir[File.join(PATH, '*.rb')].each { |f| load f }
      activate_tool
      puts "[5D Select Tool] Berhasil me-reload semua file dan mengaktifkan tool baru!"
    end

    def self.activate_tool
      Dir[File.join(PATH, '*.rb')].each { |f| load f }
      model = Sketchup.active_model
      unless model && model.valid?
        UI.messagebox("Tidak ada model aktif yang terbuka di SketchUp.") rescue nil
        return
      end

      tool = CoreTool.new
      model.select_tool(tool)
    rescue => e
      UI.messagebox("Gagal mengaktifkan 5D Select Tool: #{e.message}") rescue nil
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

unless file_loaded?(__FILE__)
  menu = UI.menu('Plugins')
  menu.add_item('5D Select Tool (Modular)') {
    BoosokTools::SelectTool5D.activate_tool
  }
  file_loaded(__FILE__)
end
