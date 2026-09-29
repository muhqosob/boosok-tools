require 'sketchup.rb'

module CustomTools
  module SelectTool5D
    PATH ||= File.dirname(__FILE__)
    
    def self.reload!
      Dir[File.join(PATH, 'custom_select', '*.rb')].each { |f| load f }
      Sketchup.active_model.select_tool(CoreTool.new)
      puts "[5D Select Tool] Berhasil me-reload semua file dan mengaktifkan tool baru!"
    end

    # Gunakan load agar perubahan kode selalu langsung aktif tanpa restart SketchUp
    Dir[File.join(PATH, 'custom_select', '*.rb')].each { |f| load f }

    unless file_loaded?(__FILE__)
      menu = UI.menu('Plugins')
      menu.add_item('5D Select Tool (Modular)') {
        Sketchup.active_model.select_tool(CoreTool.new)
      }
      file_loaded(__FILE__)
    end
  end
end