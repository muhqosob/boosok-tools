# Minimal test harness for BoosokTools::SelectTool5D
# Mocks SketchUp API to run unit tests in standard Ruby / Docker

module Sketchup
  COPY_MODIFIER_MASK = 1
  CONSTRAIN_MODIFIER_MASK = 2
  COPY_MODIFIER_KEY = 17

  class << self
    attr_accessor :status_text
  end

  class Color
    def initialize(*args); end
  end

  class Edge
    def valid?; true; end
    def vertices; []; end
    def typename; "Edge"; end
    def layer; nil; end
  end

  class Face
    def valid?; true; end
    def outer_loop
      Struct.new(:vertices).new([])
    end
    def typename; "Face"; end
    def layer; nil; end
  end

  class MockBounds
    def corner(_i)
      Geom::Point3d.new(0, 0, 0)
    end
  end

  class Group
    attr_accessor :entityID, :name, :layer, :is_valid, :is_locked
    def initialize(id, name = "Group")
      @entityID = id
      @name = name
      @layer = Struct.new(:name).new("Layer0")
      @is_valid = true
      @is_locked = false
    end
    def valid?; @is_valid; end
    def locked?; @is_locked; end
    def typename; "Group"; end
    def bounds
      MockBounds.new
    end
  end

  class ComponentInstance < Group
    def typename; "ComponentInstance"; end
    def definition
      Struct.new(:name, :bounds).new(@name, bounds)
    end
  end

  class InstancePath
    attr_reader :path
    def initialize(path)
      @path = path
    end
    def valid?; true; end
    def transformation
      Geom::Transformation.new
    end
  end

  class Selection
    attr_reader :items
    def initialize
      @items = []
    end
    def count
      @items.length
    end
    def clear
      @items.clear
    end
    def add(item)
      @items << item
    end
    def toggle(item)
      if @items.include?(item)
        @items.delete(item)
      else
        @items << item
      end
    end
  end

  class Model
    attr_accessor :selection, :active_path, :entities
    def initialize
      @selection = Selection.new
      @active_path = []
      @entities = []
    end
    def active_view
      @view ||= View.new
    end
    def valid?; true; end
  end

  class PickHelper
    attr_accessor :picked_paths
    def initialize
      @picked_paths = []
    end
    def do_pick(_x, _y); end
    def count
      @picked_paths.length
    end
    def path_at(idx)
      @picked_paths[idx]
    end
  end

  class View
    attr_accessor :pick_helper, :invalidated, :should_raise_on_draw
    def initialize
      @pick_helper = PickHelper.new
      @invalidated = false
      @should_raise_on_draw = false
    end
    def invalidate
      @invalidated = true
    end
    def vpwidth; 1920; end
    def vpheight; 1080; end
    def draw_text(*args)
      raise "Simulated Draw Error" if @should_raise_on_draw
    end
    def drawing_color=(*args); end
    def line_width=(*args); end
    def line_stipple=(*args); end
    def draw(*args)
      raise "Simulated Draw Error" if @should_raise_on_draw
    end
    def draw2d(*args)
      raise "Simulated Draw Error" if @should_raise_on_draw
    end
  end

  def self.active_model
    @active_model ||= Model.new
  end
end

module Geom
  class Point3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0)
      @x, @y, @z = x, y, z
    end
    def transform(_t); self; end
  end

  class Transformation
    def initialize; end
  end
end

module UI
  def self.menu(*args)
    Struct.new(:add_item).new(->(&_b) {})
  end
  def self.messagebox(*args); end
end

def file_loaded?(*args); false; end
def file_loaded(*args); true; end

GL_LINES = 1
GL_LINE_LOOP = 2
GL_POLYGON = 3
COPY_MODIFIER_MASK = 1
CONSTRAIN_MODIFIER_MASK = 2
COPY_MODIFIER_KEY = 17

module BoosokTools
  module SelectTool5D; end
end

# Load the modular tool files
base_dir = File.expand_path('../src/boosok_tools/custom_select', __dir__)
require File.join(base_dir, 'core_tool')
require File.join(base_dir, 'mouse_handler')
require File.join(base_dir, 'select_handler')
require File.join(base_dir, 'draw_handler')
require File.join(base_dir, 'ui_info_handler')

puts "=== STARTING COMPREHENSIVE CUSTOM SELECT TESTS ==="

tool = BoosokTools::SelectTool5D::CoreTool.new
view = Sketchup.active_model.active_view
model = Sketchup.active_model

# -------------------------------------------------------------
# BAGIAN 1: PENGUJIAN LOGIKA PERSISTENSI TINGKAT KEDALAMAN (NESTED LVL 1)
# -------------------------------------------------------------
group_root   = Sketchup::Group.new(1, "RootGroup")
sub_comp     = Sketchup::ComponentInstance.new(2, "SubComponent_Lvl1")
sub_group_l2 = Sketchup::Group.new(3, "SubGroup_Lvl2")
face1        = Sketchup::Face.new
face2        = Sketchup::Face.new

path_a = [group_root, sub_comp, sub_group_l2, face1]
path_b = [group_root, sub_comp, sub_group_l2, face2]

# Test 1: Inisialisasi awal target_depth harus 0
raise "Test 1 Failed: target_depth awal bukan 0" unless tool.target_depth == 0
raise "Test 1 Failed: effective_depth awal bukan 0" unless tool.effective_depth == 0
puts "✓ Test 1 Passed: Initial depth is 0"

# Test 2: Hover pada path_a, lalu scroll wheel dengan CTRL down untuk memilih Nested Level 1
view.pick_helper.picked_paths = [path_a]
tool.onMouseMove(0, 100, 100, view)
raise "Test 2 Failed: hover_path tidak terpasang" unless tool.hover_path == path_a

tool.onKeyDown(17, 1, 0, view)
tool.onMouseWheel(Sketchup::COPY_MODIFIER_MASK, -120, 100, 100, view)
raise "Test 2 Failed: target_depth harus 1 setelah scroll down" unless tool.target_depth == 1
raise "Test 2 Failed: effective_depth harus 1" unless tool.effective_depth == 1
puts "✓ Test 2 Passed: Scrolled to Nested Level 1 (target_depth = 1)"

# Test 3: Kursor mouse bergeser ke face2 (pointer reset / hover_path ganti)
# target_depth HARUS TETAP 1 (tidak boleh reset ke 0!)
view.pick_helper.picked_paths = [path_b]
tool.onMouseMove(0, 105, 105, view)
raise "Test 3 Failed: hover_path tidak terupdate ke path_b" unless tool.hover_path == path_b
raise "Test 3 FAILED: target_depth TER-RESET! Harusnya tetap 1, didapat: #{tool.target_depth}" unless tool.target_depth == 1
raise "Test 3 FAILED: effective_depth harus tetap 1, didapat: #{tool.effective_depth}" unless tool.effective_depth == 1
puts "✓ Test 3 Passed: Mouse move maintains Nested Level 1 across leaf face changes!"

# Test 4: Mouse bergeser ke objek lain yang juga memiliki nested hierarchy
group_root_2 = Sketchup::Group.new(4, "RootGroup_2")
sub_comp_2   = Sketchup::ComponentInstance.new(5, "SubComp2_Lvl1")
face3        = Sketchup::Face.new
path_c       = [group_root_2, sub_comp_2, face3]

view.pick_helper.picked_paths = [path_c]
tool.onMouseMove(0, 200, 200, view)
raise "Test 4 FAILED: target_depth ter-reset saat geser ke objek lain!" unless tool.target_depth == 1
raise "Test 4 FAILED: effective_depth harus 1 untuk path_c" unless tool.effective_depth == 1
puts "✓ Test 4 Passed: Mouse move to another nested object retains Level 1!"

# Test 5: Mouse bergeser ke objek dengan 1 level saja (outermost only)
standalone_face = Sketchup::Face.new
path_single     = [standalone_face]

view.pick_helper.picked_paths = [path_single]
tool.onMouseMove(0, 300, 300, view)
raise "Test 5 FAILED: target_depth tidak boleh hilang walau objek 1 level!" unless tool.target_depth == 1
raise "Test 5 FAILED: effective_depth harus ter-clamp ke 0 untuk single entity!" unless tool.effective_depth == 0
puts "✓ Test 5 Passed: Single-level entity clamps effective_depth to 0 without clearing target_depth!"

# Test 6: Mouse kembali ke objek nested (path_c), effective_depth otomatis kembali ke 1
view.pick_helper.picked_paths = [path_c]
tool.onMouseMove(0, 205, 205, view)
raise "Test 6 FAILED: target_depth bukan 1!" unless tool.target_depth == 1
raise "Test 6 FAILED: effective_depth harus kembali ke 1!" unless tool.effective_depth == 1
puts "✓ Test 6 Passed: Hovering back to nested object restores Level 1 automatically!"

# Test 7: Klik seleksi pada Nested Level 1
model.selection.clear
tool.onLButtonDown(0, 205, 205, view)
selected_items = model.selection.items
raise "Test 7 FAILED: Seleksi kosong!" if selected_items.empty?
selected_ip = selected_items.first
raise "Test 7 FAILED: Item yang diseleksi harus InstancePath!" unless selected_ip.is_a?(Sketchup::InstancePath)
raise "Test 7 FAILED: InstancePath harus memiliki panjang 2 (Level 0 dan Level 1)!" unless selected_ip.path.length == 2
raise "Test 7 FAILED: Target seleksi harus sub_comp_2!" unless selected_ip.path.last == sub_comp_2
puts "✓ Test 7 Passed: Selection correctly selected Nested Level 1 component without opening root!"

# Test 8: Mouse geser setelah seleksi dilakukan, level harus tetap 1
view.pick_helper.picked_paths = [path_a]
tool.onMouseMove(0, 110, 110, view)
raise "Test 8 FAILED: target_depth ter-reset setelah klik seleksi!" unless tool.target_depth == 1
raise "Test 8 FAILED: effective_depth harus 1!" unless tool.effective_depth == 1
puts "✓ Test 8 Passed: Moving mouse after selection still maintains Nested Level 1!"

# Test 9: DrawHandler menggambar tanpa error
tool.draw(view)
puts "✓ Test 9 Passed: DrawHandler successfully executes without errors!"

# Test 10: Tombol ESC mereset target_depth kembali ke 0
tool.onKeyDown(27, 1, 0, view)
raise "Test 10 FAILED: ESC harus mereset target_depth ke 0!" unless tool.target_depth == 0
raise "Test 10 FAILED: effective_depth harus 0 setelah ESC!" unless tool.effective_depth == 0
puts "✓ Test 10 Passed: ESC key successfully resets target depth to Level 0!"

# -------------------------------------------------------------
# BAGIAN 2: STATE MANAGEMENT & DATA INTEGRITY
# -------------------------------------------------------------
# Test 11: Validasi entitas yang terhapus (deleted / invalid) dari hover_path
invalid_group = Sketchup::Group.new(99, "DeletedGroup")
invalid_group.is_valid = false # Menyimulasikan entitas terhapus
tool.hover_path = [invalid_group]
valid_paths = tool.valid_hover_path
raise "Test 11 FAILED: valid_hover_path harus mengabaikan entitas invalid!" unless valid_paths.empty?
raise "Test 11 FAILED: effective_depth harus 0 saat semua entitas invalid!" unless tool.effective_depth == 0
puts "✓ Test 11 Passed: State management safely handles and filters invalid/deleted entities!"

# Test 12: reset_state! membersihkan seluruh variabel state
tool.cursor_x = 50
tool.cursor_y = 50
tool.ctrl_pressed = true
tool.reset_state!
raise "Test 12 FAILED: reset_state! gagal mereset hover_path" unless tool.hover_path.empty?
raise "Test 12 FAILED: reset_state! gagal mereset cursor koordinat" unless tool.cursor_x.nil? && tool.cursor_y.nil?
raise "Test 12 FAILED: reset_state! gagal mereset ctrl_pressed" if tool.ctrl_pressed
puts "✓ Test 12 Passed: State management reset_state! cleanly purges tool state!"

# -------------------------------------------------------------
# BAGIAN 3: EMPTY STATE HANDLING
# -------------------------------------------------------------
# Test 13: Empty model pada activate
model.entities = []
tool.activate
raise "Test 13 FAILED: Status text tidak mengindikasikan model kosong!" unless Sketchup.status_text.include?("Model kosong")
puts "✓ Test 13 Passed: Empty model state properly detected and informed via status text!"

# Test 14: Kursor pada ruang kosong (empty space / sky)
model.entities = [group_root]
view.pick_helper.picked_paths = []
tool.onMouseMove(0, 500, 500, view)
raise "Test 14 FAILED: hover_path harus kosong saat kursor di area kosong" unless tool.hover_path.empty?
raise "Test 14 FAILED: Status text tidak memandu user saat ruang kosong" unless Sketchup.status_text.include?("Arahkan")
puts "✓ Test 14 Passed: Hovering over empty space gracefully enters empty state with guidance!"

# Test 15: Scroll wheel di area kosong tidak error dan memandu user
Sketchup.status_text = ""
tool.onMouseWheel(Sketchup::COPY_MODIFIER_MASK, -120, 500, 500, view)
raise "Test 15 FAILED: Scroll di area kosong harus memberi panduan status" unless Sketchup.status_text.include?("Arahkan")
puts "✓ Test 15 Passed: Scroll on empty space gives clear guidance without unexpected state change!"

# Test 16: Klik di area kosong membersihkan seleksi (empty space click)
model.selection.add(sub_comp_2)
raise "Test 16 FAILED: Setup seleksi gagal" if model.selection.count == 0
tool.onLButtonDown(0, 500, 500, view) # flags 0 (tanpa ctrl/shift)
raise "Test 16 FAILED: Klik ruang kosong harus membersihkan seleksi!" unless model.selection.count == 0
raise "Test 16 FAILED: Status text harus mengindikasikan seleksi dibersihkan" unless Sketchup.status_text.include?("dibersihkan")
puts "✓ Test 16 Passed: Clicking empty space clears selection with feedback!"

# -------------------------------------------------------------
# BAGIAN 4: FALLBACK ON ERROR
# -------------------------------------------------------------
# Test 17: Fallback on Error saat Viewport Draw mengalami exception
view.should_raise_on_draw = true
begin
  tool.draw(view) # Tidak boleh melempar exception keluar!
  puts "✓ Test 17 Passed: DrawHandler catches exceptions without freezing SketchUp viewport!"
ensure
  view.should_raise_on_draw = false
end

# Test 18: Fallback on Error pada objek terkunci (Locked Entity)
locked_group = Sketchup::Group.new(77, "LockedGroup")
locked_group.is_locked = true
view.pick_helper.picked_paths = [[locked_group]]
tool.onMouseMove(0, 150, 150, view)
tool.onLButtonDown(0, 150, 150, view)
raise "Test 18 FAILED: Status text harus memperingatkan bahwa objek terkunci! Didapat: #{Sketchup.status_text}" unless Sketchup.status_text.downcase.include?("terkunci")
puts "✓ Test 18 Passed: Locked entity is safely handled and user is alerted!"

puts "\n======================================================="
puts "ALL 18 TESTS PASSED SUCCESSFULLY IN DOCKER CONTAINER! 🎉"
puts "======================================================="
