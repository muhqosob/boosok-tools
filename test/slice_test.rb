require_relative 'test_helper'

load File.join(PLUGIN, 'ruby', 'paid', 'void.rb')
load File.join(PLUGIN, 'ruby', 'paid', 'slice.rb')

# Uji penyaring ruang layar Slice (murni matematika 2D; View/BoundingBox ditiru secukupnya).
class SliceTest < Minitest::Test
  S = BoosokTools::Slice

  Pt = Struct.new(:x, :y, :z) do
    def -(other) = Vec.new(x - other.x, y - other.y, z - other.z)
  end
  Vec = Struct.new(:x, :y, :z) do
    def dot(other) = (x * other.x) + (y * other.y) + (z * other.z)
  end

  # Kamera paralel menghadap -Z: layar = (x, y) dunia
  class FakeView
    Cam = Struct.new(:eye, :direction) { def perspective? = false }

    def camera = Cam.new(Pt.new(0, 0, 100), Vec.new(0, 0, -1))

    def screen_coords(pt) = Pt.new(pt.x, pt.y, 0)
  end

  # Entity dengan kotak [min, max]; transformasi identitas
  class FakeBox
    Box = Struct.new(:min, :max) do
      def empty? = false
      def corner(i) = Pt.new(i[0].zero? ? min[0] : max[0], i[1].zero? ? min[1] : max[1], i[2].zero? ? min[2] : max[2])
    end

    def initialize(min, max) = @box = Box.new(min, max)
    def bounds = @box
  end

  class Ident
    def *(pt) = pt
  end

  # Garis vertikal x = 50 dari y=-1000 ke y=1000; area buang = sisi kiri (x < 50)
  def env
    poly = [[50.0, -1000.0], [50.0, 1000.0], [-1000.0, 1000.0], [-1000.0, -1000.0]]
    { view: FakeView.new, poly: poly }
  end

  def klass(min, max)
    S.region_class(env, FakeBox.new(min, max), Ident.new)
  end

  def test_region_class_detects_inside_outside_cross
    assert_equal :inside, klass([0, 0, 0], [20, 20, 5])
    assert_equal :outside, klass([80, 0, 0], [100, 20, 5])
    assert_equal :cross, klass([40, 0, 0], [60, 20, 5])
  end

  def test_region_class_is_conservative_near_the_line
    assert_equal :cross, klass([30, 0, 0], [50, 20, 5]), 'sisi menempel garis tidak boleh dianggap jelas'
    assert_equal :cross, klass([50.5, 0, 0], [70, 20, 5])
  end

  def test_convex_hull_drops_interior_points
    hull = S.convex_hull([[0, 0], [10, 0], [10, 10], [0, 10], [5, 5]])
    assert_equal 4, hull.size
    refute_includes hull, [5, 5]
  end

  def test_convex_hull_degenerate
    assert_equal 2, S.convex_hull([[0, 0], [5, 5], [10, 10]]).size
  end

  def test_signed_dist_sides
    assert_in_delta 5.0, S.signed_dist([0, 5], [0, 0], [10, 0]).abs, 1e-9
    refute_equal S.signed_dist([0, 5], [0, 0], [10, 0]).positive?, S.signed_dist([0, -5], [0, 0], [10, 0]).positive?
  end

  def test_near_segment_clamps_to_ends
    assert S.near_segment?([12.0, 0.0], [0.0, 0.0], [10.0, 0.0], 2.5)
    refute S.near_segment?([20.0, 0.0], [0.0, 0.0], [10.0, 0.0], 2.5)
    assert S.near_segment?([5.0, 1.0], [0.0, 0.0], [10.0, 0.0], 2.5)
  end
end

class SliceProgressTest < Minitest::Test
  S = BoosokTools::Slice

  def test_rounded_rect_stays_within_rect
    pts = S.rounded_rect(10.0, 20.0, 110.0, 40.0, 12)
    xs = pts.map(&:x)
    ys = pts.map(&:y)
    assert_operator xs.min, :>=, 10.0 - 1e-9
    assert_operator xs.max, :<=, 110.0 + 1e-9
    assert_operator ys.min, :>=, 20.0 - 1e-9
    assert_operator ys.max, :<=, 40.0 + 1e-9
  end

  def test_progress_fraction_and_percent
    pg = S::Progress.new(Object.new, 4, 'x')
    pg.instance_variable_set(:@last, Float::INFINITY) # tahan gambar ulang
    2.times { pg.tick }
    assert_equal 50, pg.percent
    pg.extend_total(4)
    assert_equal 25, pg.percent
    10.times { pg.tick }
    assert_equal 100, pg.percent
  end

  def test_themes_have_same_keys
    assert_equal S::PROGRESS_THEME[:light].keys, S::PROGRESS_THEME[:dark].keys
  end
end

# Penggabungan potongan garis potong (matematika vektor ditiru secukupnya)
class SliceMergeTest < Minitest::Test
  S = BoosokTools::Slice

  P = Struct.new(:x, :y, :z) do
    def -(other) = P.new(x - other.x, y - other.y, z - other.z)
    def dot(other) = (x * other.x) + (y * other.y) + (z * other.z)
    def cross(other) = P.new((y * other.z) - (z * other.y), (z * other.x) - (x * other.z), (x * other.y) - (y * other.x))
    def length = Math.sqrt(dot(self))
    def distance(other) = (self - other).length
  end

  def pt(x, y) = P.new(x.to_f, y.to_f, 0.0)

  def test_collinear_chain_becomes_single_line
    pieces = [[pt(50, 0), pt(50, 10)], [pt(50, 10), pt(50, 90)], [pt(50, 90), pt(50, 100)]]
    lines = S.merge_pieces(pieces)
    assert_equal 1, lines.size
    ys = lines.first.map(&:y).sort
    assert_equal [0.0, 100.0], ys
  end

  def test_bend_is_not_merged
    pieces = [[pt(0, 0), pt(10, 0)], [pt(10, 0), pt(10, 10)]]
    assert_equal 2, S.merge_pieces(pieces).size
  end

  def test_separate_chords_stay_separate
    pieces = [[pt(0, 0), pt(10, 0)], [pt(20, 0), pt(30, 0)]]
    assert_equal 2, S.merge_pieces(pieces).size
  end

  def test_overlapping_back_tracking_is_not_merged
    assert_nil S.join_lines([pt(0, 0), pt(10, 0)], [pt(10, 0), pt(5, 0)])
  end
end
