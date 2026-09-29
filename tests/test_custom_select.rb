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
    attr_accessor :vertices
    def initialize(v1 = nil, v2 = nil)
      @vertices = [
        v1 || Struct.new(:position).new(Geom::Point3d.new(0, 0, 0)),
        v2 || Struct.new(:position).new(Geom::Point3d.new(10, 0, 0))
      ]
    end
    def valid?; true; end
    def typename; "Edge"; end
    def layer; nil; end
  end

  class PolygonMesh
    attr_accessor :points
    def initialize(pts = [])
      @points = pts
    end
    def count_polygons
      @points.empty? ? 0 : 1
    end
    def polygon_points_at(_idx)
      @points
    end
  end

  class Face
    attr_accessor :vertices, :normal, :loops
    def initialize(pts = nil)
      @pts = pts || [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0), Geom::Point3d.new(10, 10, 0), Geom::Point3d.new(0, 10, 0)]
      @vertices = @pts.map { |p| Struct.new(:position).new(p) }
      @normal = Geom::Vector3d.new(0, 0, 1)
      @loops = [Struct.new(:vertices).new(@vertices)]
    end
    def valid?; true; end
    def outer_loop
      @loops.first
    end
    def mesh
      PolygonMesh.new(@pts)
    end
    def typename; "Face"; end
    def layer; nil; end
  end

  class MockBounds
    def initialize(min_x = 0, min_y = 0, min_z = 0, max_x = 10, max_y = 10, max_z = 10)
      @min = [min_x, min_y, min_z]
      @max = [max_x, max_y, max_z]
    end
    def corner(i)
      x = (i & 1 == 0) ? @min[0] : @max[0]
      y = (i & 2 == 0) ? @min[1] : @max[1]
      z = (i & 4 == 0) ? @min[2] : @max[2]
      Geom::Point3d.new(x, y, z)
    end
  end

  class Group
    attr_accessor :entityID, :name, :layer, :is_valid, :is_locked, :transformation
    def initialize(id, name = "Group", tx = 0, ty = 0, tz = 0)
      @entityID = id
      @name = name
      @layer = Struct.new(:name).new("Layer0")
      @is_valid = true
      @is_locked = false
      @transformation = Geom::Transformation.new(tx, ty, tz)
    end
    def valid?; @is_valid; end
    def locked?; @is_locked; end
    def typename; "Group"; end
    def bounds
      MockBounds.new
    end
    def local_bounds
      bounds
    end
    def definition
      Struct.new(:name, :bounds).new(@name, bounds)
    end
  end

  class ComponentInstance < Group
    def typename; "ComponentInstance"; end
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
    attr_accessor :pick_helper, :invalidated, :should_raise_on_draw, :draw_calls
    def initialize
      @pick_helper = PickHelper.new
      @invalidated = false
      @should_raise_on_draw = false
      @draw_calls = []
    end
    def invalidate
      @invalidated = true
    end
    def vpwidth; 1920; end
    def vpheight; 1080; end
    def camera
      Struct.new(:eye).new(Geom::Point3d.new(0, 0, 500))
    end
    def draw_text(*args)
      raise "Simulated Draw Error" if @should_raise_on_draw
    end
    def drawing_color=(c); @color = c; end
    def line_width=(w); @width = w; end
    def line_stipple=(s); @stipple = s; end
    def draw(mode, pts)
      raise "Simulated Draw Error" if @should_raise_on_draw
      @draw_calls << { mode: mode, points: pts, color: @color, width: @width }
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
    def transform(t)
      return self unless t
      Geom::Point3d.new(@x + t.x, @y + t.y, @z + t.z)
    end
    def +(other)
      if other.is_a?(Geom::Vector3d) || other.is_a?(Geom::Point3d)
        Geom::Point3d.new(@x + other.x, @y + other.y, @z + other.z)
      else
        self
      end
    end
    def -(other)
      Geom::Vector3d.new(@x - other.x, @y - other.y, @z - other.z)
    end
  end

  class Vector3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0)
      @x, @y, @z = x, y, z
    end
    def normalize; self; end
    def length=(val); end
    def reverse!; self; end
    def %(other); 1; end
    def valid?; true; end
    def transform(_t); self; end
  end

  class Transformation
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0)
      @x, @y, @z = x, y, z
    end
    def *(other)
      return self unless other
      Geom::Transformation.new(@x + other.x, @y + other.y, @z + other.z)
    end
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
GL_TRIANGLES = 4
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

# -------------------------------------------------------------
# BAGIAN 5: NESTED HIGHLIGHT AT DEPTH 0, 1, 2, 3 (The Core Fix)
# -------------------------------------------------------------
# Setup nested hierarchy with real transformations:
# RootGroup (at [100, 0, 0])
#   └── SubGroup_L1 (at [20, 0, 0] relative to L0)
#         └── SubComp_L2 (at [0, 30, 0] relative to L1)
#               ├── NestedFace_L3
#               └── NestedEdge_L3
g_l0 = Sketchup::Group.new(101, "Root_L0", 100, 0, 0)
g_l1 = Sketchup::Group.new(102, "Sub_L1", 20, 0, 0)
c_l2 = Sketchup::ComponentInstance.new(103, "Comp_L2", 0, 30, 0)
f_l3 = Sketchup::Face.new
e_l3 = Sketchup::Edge.new

full_nested_path = [g_l0, g_l1, c_l2, f_l3]

# Test 19: Container World Transformation kumulatif
draw_h = tool.instance_variable_get(:@draw_handler)
tr_l0 = draw_h.send(:container_world_transform, full_nested_path, 0)
raise "Test 19 FAILED: tr_l0 x harus 100, didapat: #{tr_l0.x}" unless tr_l0.x == 100

tr_l1 = draw_h.send(:container_world_transform, full_nested_path, 1)
raise "Test 19 FAILED: tr_l1 x harus 120, didapat: #{tr_l1.x}" unless tr_l1.x == 120

tr_l2 = draw_h.send(:container_world_transform, full_nested_path, 2)
raise "Test 19 FAILED: tr_l2 harus [120, 30, 0], didapat: [#{tr_l2.x}, #{tr_l2.y}, #{tr_l2.z}]" unless tr_l2.x == 120 && tr_l2.y == 30
puts "✓ Test 19 Passed: container_world_transform correctly accumulates translations across depth 0, 1, and 2!"

# Test 20: Parent World Transformation untuk Face/Edge
ptr_l3 = draw_h.send(:parent_world_transform, full_nested_path, 3)
raise "Test 20 FAILED: ptr_l3 harus sama dengan tr_l2 (parent container transform)" unless ptr_l3.x == 120 && ptr_l3.y == 30
puts "✓ Test 20 Passed: parent_world_transform correctly retrieves parent container transform for leaf entities!"

# Test 21: Bounding Box World Corners untuk Nested Group Level 1
corners_l1 = draw_h.send(:get_world_corners_for_container, full_nested_path, 1)
raise "Test 21 FAILED: corners_l1 kosong atau panjangnya bukan 8" unless corners_l1 && corners_l1.length == 8
raise "Test 21 FAILED: Sudut pertama harus memiliki offset x = 120 (100 + 20), didapat: #{corners_l1[0].x}" unless corners_l1[0].x == 120
puts "✓ Test 21 Passed: Nested Level 1 Group world bounding box corners calculated accurately in world space!"

# Test 22: Bounding Box World Corners untuk Nested Component Level 2
corners_l2 = draw_h.send(:get_world_corners_for_container, full_nested_path, 2)
raise "Test 22 FAILED: corners_l2 kosong" unless corners_l2 && corners_l2.length == 8
raise "Test 22 FAILED: Sudut L2 harus memiliki x=120, y=30, didapat x=#{corners_l2[0].x}, y=#{corners_l2[0].y}" unless corners_l2[0].x == 120 && corners_l2[0].y == 30
puts "✓ Test 22 Passed: Nested Level 2 Component world bounding box corners calculated accurately across 3 nested levels!"

# Test 23: Viewport Draw Highlight pada Nested Level 1 (Group Highlight)
tool.hover_path = full_nested_path
tool.target_depth = 1
view.draw_calls.clear
tool.draw(view)
# Verifikasi bahwa draw dipanggil untuk bounding box
has_polygon = view.draw_calls.any? { |c| c[:mode] == GL_POLYGON }
has_lines = view.draw_calls.any? { |c| c[:mode] == GL_LINES }
raise "Test 23 FAILED: DrawHandler tidak menggambar polygon fill untuk Level 1 Group!" unless has_polygon
raise "Test 23 FAILED: DrawHandler tidak menggambar lines wireframe untuk Level 1 Group!" unless has_lines
puts "✓ Test 23 Passed: DrawHandler successfully highlights Nested Level 1 Group with fill and wireframe!"

# Test 24: Viewport Draw Highlight pada Nested Level 2 (Component Highlight)
tool.target_depth = 2
view.draw_calls.clear
tool.draw(view)
has_polygon_l2 = view.draw_calls.any? { |c| c[:mode] == GL_POLYGON }
has_lines_l2 = view.draw_calls.any? { |c| c[:mode] == GL_LINES }
raise "Test 24 FAILED: DrawHandler tidak menggambar highlight untuk Level 2 Component!" unless has_polygon_l2 && has_lines_l2
puts "✓ Test 24 Passed: DrawHandler successfully highlights Nested Level 2 Component!"

# Test 25: Viewport Draw Highlight pada Nested Face (Level 3 Face)
tool.target_depth = 3
view.draw_calls.clear
tool.draw(view)
has_triangles = view.draw_calls.any? { |c| c[:mode] == GL_TRIANGLES }
has_line_loop = view.draw_calls.any? { |c| c[:mode] == GL_LINE_LOOP }
raise "Test 25 FAILED: Face highlight tidak menggambar GL_TRIANGLES untuk fill anti z-fighting!" unless has_triangles
raise "Test 25 FAILED: Face highlight tidak menggambar GL_LINE_LOOP untuk border outline!" unless has_line_loop
puts "✓ Test 25 Passed: DrawHandler successfully highlights Nested Face using GL_TRIANGLES & GL_LINE_LOOP!"

# Test 26: Viewport Draw Highlight pada Nested Edge
full_edge_path = [g_l0, g_l1, c_l2, e_l3]
tool.hover_path = full_edge_path
tool.target_depth = 3
view.draw_calls.clear
tool.draw(view)
has_edge_lines = view.draw_calls.any? { |c| c[:mode] == GL_LINES && c[:width] == 4 }
raise "Test 26 FAILED: Edge highlight tidak menggambar garis tebal orange (line_width 4)!" unless has_edge_lines
puts "✓ Test 26 Passed: DrawHandler successfully highlights Nested Edge with width 4!"

puts "\n======================================================="
puts "ALL 26 TESTS PASSED SUCCESSFULLY IN DOCKER CONTAINER! 🎉"
puts "======================================================="
