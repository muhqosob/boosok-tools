module MyTools
  module HideGroupHelper

    def self.hide_selected
      model = Sketchup.active_model
      targets = model.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }

      if targets.empty?
        UI.messagebox("Pilih minimal 1 Grup/Komponen terlebih dahulu.")
        return
      end

      model.start_operation("Hide Group", true)
      targets.each { |e| e.hidden = true }
      model.selection.clear
      model.commit_operation
    end

    # Termasuk grup/komponen yang bersarang di dalam grup lain
    def self.unhide_all
      model = Sketchup.active_model
      count = 0

      model.start_operation("Unhide All Groups", true)
      model.definitions.each do |d|
        d.instances.each do |e|
          next unless e.hidden?
          e.hidden = false
          count += 1
        end
      end
      model.commit_operation

      UI.messagebox("#{count} grup/komponen ditampilkan kembali.")
    end

  end
end
