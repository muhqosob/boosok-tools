require_relative 'test_helper'

load File.join(PLUGIN, 'ruby', 'paid', 'void.rb')

class VoidTest < Minitest::Test
  include Build

  V = BoosokTools::Void

  def setup
    Sketchup.reset_model!
    @model = Sketchup.active_model
    V.void_material(@model) # di SketchUp asli material ini dibuat saat void pertama ditandai (gerbang void_possible?)
    V.instance_variable_set(:@gated, false)
  end

  def stats
    V.new_stats
  end

  def role_of(ent)
    ent.get_attribute('BoosokTools', 'void_role')
  end

  # ── Primitif geometri ───────────────────────────────────────────────────

  def test_overlap_requires_volume_not_just_touching
    a = Geom::BoundingBox.from([0, 0, 0], [10, 10, 10])
    assert V.overlap?(a, Geom::BoundingBox.from([5, 5, 5], [15, 15, 15]))
    refute V.overlap?(a, Geom::BoundingBox.from([10, 0, 0], [20, 10, 10])), 'sentuh sisi tidak dihitung'
    refute V.overlap?(a, Geom::BoundingBox.from([50, 50, 50], [60, 60, 60]))
  end

  def test_inside_has_tolerance
    assert V.inside?([0, 0, 0], [10, 10, 10], [0, 0, 0], [10, 10, 10])
    assert V.inside?([-0.0005, 0, 0], [10, 10, 10], [0, 0, 0], [10, 10, 10])
    refute V.inside?([-1, 0, 0], [10, 10, 10], [0, 0, 0], [10, 10, 10])
  end

  def test_world_bounds_applies_translation_and_scale
    box = Geom::BoundingBox.from([0, 0, 0], [10, 10, 10])
    moved = V.world_bounds(box, tx(100, 0, 0))
    assert_equal [100, 0, 0], moved.min.to_a
    assert_equal [110, 10, 10], moved.max.to_a
    scaled = V.world_bounds(box, Geom::Transformation.scaling(2))
    assert_equal [20, 20, 20], scaled.max.to_a
  end

  def test_solid_uses_definition_manifold
    g = solid_box
    assert V.solid?(g)
    g.definition.solid = false
    refute V.solid?(g)
  end

  # ── Penanda ─────────────────────────────────────────────────────────────

  def test_mark_and_unmark_round_trip
    g = solid_box
    @model.active_entities << g
    assert V.mark(@model, g, true)
    outer = @model.active_entities.first
    assert V.void?(outer), 'pembungkus yang jadi void'
    refute V.void?(g), 'group asli hanya bentuk pemotong'
    refute V.mark(@model, outer, true), 'void ganda ditolak'
    assert V.mark(@model, outer, false)
    refute V.void?(g)
    refute V.mark(@model, g, false), 'unmark pada non-void ditolak'
  end

  def test_mark_rejects_result_and_source
    g = mark_role(solid_box, 'result')
    refute V.mark(@model, g, true)
  end

  # ── nested_has_state? ───────────────────────────────────────────────────

  def test_nested_has_state_finds_direct_child_state
    parent = plain([mark_role(solid_box, 'source')])
    assert V.nested_has_state?(parent, 0)
  end

  def test_nested_has_state_respects_depth
    deep = plain([plain([plain([mark_role(solid_box, 'result')])])]) # state ada di level ke-3
    refute V.nested_has_state?(deep, 0)
    refute V.nested_has_state?(deep, 1)
    assert V.nested_has_state?(deep, 2)
    assert V.nested_has_state?(deep, 3)
  end

  def test_nested_has_state_false_when_clean_or_negative_depth
    refute V.nested_has_state?(plain([solid_box]), 3)
    refute V.nested_has_state?(plain([mark_role(solid_box, 'source')]), -1)
  end

  # ── bake_inner ──────────────────────────────────────────────────────────

  def test_bake_inner_erases_sources_and_unlinks_results
    src = mark_role(solid_box, 'source')
    res = mark_role(solid_box, 'result')
    parent = plain([src, res])
    assert_equal 1, V.bake_inner(parent, 3)
    refute src.valid?
    assert res.valid?
    assert_nil role_of(res)
    assert_nil res.get_attribute('BoosokTools', 'void_link')
  end

  def test_bake_inner_recurses_up_to_depth
    res = mark_role(solid_box, 'result')
    outer = plain([plain([res])])
    assert_equal 0, V.bake_inner(outer, 0), 'depth 0 tidak masuk ke anak'
    assert_equal 'result', role_of(res)
    assert_equal 1, V.bake_inner(outer, 1)
    assert_nil role_of(res)
  end

  def test_bake_inner_skips_void_children
    v = void_box([0, 0, 0], [1, 1, 1])
    inner_res = mark_role(solid_box, 'result')
    v.entities << inner_res
    assert_equal 0, V.bake_inner(plain([v]), 3)
    assert_equal 'result', role_of(inner_res), 'isi void tidak boleh disentuh'
  end

  def test_bake_top_level_and_nested
    src = mark_role(solid_box, 'source')
    res = mark_role(solid_box, 'result', 'A')
    nested_src = mark_role(solid_box, 'source', 'B')
    nested_res = mark_role(solid_box, 'result', 'B')
    [src, res, plain([plain([nested_src, nested_res])])].each { |e| @model.active_entities << e }

    assert_equal 2, V.bake(@model)
    refute src.valid?
    refute nested_src.valid?
    assert_nil role_of(res)
    assert_nil role_of(nested_res)
  end

  def test_duplicate_keeps_group_material_and_tag
    wall = solid_box
    wall.material = @model.materials.add('Dulux')
    wall.layer = @model.layers.add('I. PARTITION')
    @model.active_entities << wall

    copy = V.duplicate(@model.active_entities, wall)
    assert_equal wall.material, copy.material
    assert_equal wall.layer, copy.layer
  end

  # ── pindah scene: scene memunculkan lagi source yang tersembunyi ────────

  def test_rehide_sources_hides_visible_top_level_and_nested_sources
    top = mark_role(solid_box, 'source', 'A')
    inner = mark_role(solid_box, 'source', 'B')
    inner_res = mark_role(solid_box, 'result', 'B')
    parent = plain([plain([inner, inner_res])])
    plain_wall = solid_box
    [top, parent, plain_wall].each { |e| @model.active_entities << e }

    assert_equal 2, V.rehide_sources(@model)
    assert top.hidden?
    assert inner.hidden?
    refute inner_res.hidden?, 'hasil berlubang tetap terlihat'
    refute plain_wall.hidden?
  end

  def test_rehide_sources_ignores_already_hidden
    src = mark_role(solid_box, 'source')
    src.hidden = true
    @model.active_entities << src
    assert_equal 0, V.rehide_sources(@model)
  end

  def test_fix_after_scene_change_commits_only_when_something_was_shown
    src = mark_role(solid_box, 'source')
    @model.active_entities << src
    V.fix_after_scene_change(@model)
    assert src.hidden?
    assert_equal [[:start, 'Sembunyikan Source Void'], [:commit]], @model.operations

    @model.operations.clear
    V.fix_after_scene_change(@model)
    assert_equal [[:start, 'Sembunyikan Source Void'], [:abort]], @model.operations, 'tidak ada perubahan = tidak ada langkah undo'
  end

  # ── rebuild_nonsolid_children: overlap harus dihitung di ruang WORLD ────
  # cut_child di-stub supaya yang diuji hanya keputusan "child ini kena void atau tidak".

  def cut_calls_for(parent, voids)
    calls = []
    recorder = lambda do |_ents, child, local_voids, _stats|
      calls << [child, local_voids.map(&:first)]
      nil
    end
    V.stub(:cut_child, recorder) do
      V.rebuild_nonsolid_children(@model, parent, voids, stats, 3)
    end
    calls
  end

  def test_nonsolid_child_cut_when_parent_at_origin
    child = solid_box([0, 0, 0], [10, 10, 10])
    parent = plain([child])
    @model.active_entities << parent
    v = void_box([2, 2, 2], [8, 8, 8])
    refute_empty cut_calls_for(parent, [v])
  end

  def test_nonsolid_child_cut_when_parent_is_translated
    # Parent digeser 100 di X: child ada di world X 100..110, void di world X 102..108.
    child = solid_box([0, 0, 0], [10, 10, 10])
    parent = plain([child], at: [100, 0, 0])
    @model.active_entities << parent
    v = void_box([102, 2, 2], [108, 8, 8])
    calls = cut_calls_for(parent, [v])
    assert_equal 1, calls.size, 'void yang jelas menimpa child harus memicu pemotongan walau parent digeser'
  end

  def test_nonsolid_child_not_cut_when_void_far_away
    child = solid_box([0, 0, 0], [10, 10, 10])
    parent = plain([child], at: [100, 0, 0])
    @model.active_entities << parent
    v = void_box([500, 0, 0], [510, 10, 10])
    assert_empty cut_calls_for(parent, [v])
  end

  def test_nonsolid_child_not_cut_when_void_only_overlaps_at_wrong_place
    # Void di world X 2..8 (posisi child JIKA parent tidak digeser). Parent di X=100 → tidak boleh kena.
    child = solid_box([0, 0, 0], [10, 10, 10])
    parent = plain([child], at: [100, 0, 0])
    @model.active_entities << parent
    v = void_box([2, 2, 2], [8, 8, 8])
    assert_empty cut_calls_for(parent, [v])
  end

  def test_child_with_own_translation_inside_translated_parent
    # Child digeser 20 di X di dalam parent (parent di X=100): child di world X 120..130.
    child = solid_box([0, 0, 0], [10, 10, 10], at: [20, 0, 0])
    parent = plain([child], at: [100, 0, 0])
    @model.active_entities << parent
    hit = void_box([122, 2, 2], [128, 8, 8])
    miss = void_box([102, 2, 2], [108, 8, 8])
    assert_equal 1, cut_calls_for(parent, [hit]).size
    assert_empty cut_calls_for(parent, [miss])
  end

  def test_two_level_nesting_with_translations
    # Parent X=100 > grup non-solid X=50 > child solid lokal 0..10  => world X 150..160.
    child = solid_box([0, 0, 0], [10, 10, 10])
    middle = plain([child], at: [50, 0, 0])
    parent = plain([middle], at: [100, 0, 0])
    @model.active_entities << parent
    v = void_box([152, 2, 2], [158, 8, 8])
    assert_equal 1, cut_calls_for(parent, [v]).size
  end

  def test_nesting_with_scaled_parent
    child = solid_box([0, 0, 0], [10, 10, 10])
    inner = plain([child], at: [10, 0, 0])
    outer = Sketchup::Group.new(tx: Geom::Transformation.scaling(2), solid: false, kids: [inner])
    @model.active_entities << outer
    # child di ruang outer: X 10..20  → world X 20..40
    hit = void_box([25, 5, 5], [35, 15, 15])
    miss = void_box([2, 2, 2], [8, 8, 8])
    assert_equal 1, cut_calls_for(outer, [hit]).size
    assert_empty cut_calls_for(outer, [miss])
  end

  def test_depth_limit_stops_recursion
    child = solid_box([0, 0, 0], [10, 10, 10])
    top = plain([plain([plain([plain([child])])])]) # child ada 3 level di bawah top
    @model.active_entities << top
    v = void_box([2, 2, 2], [8, 8, 8])
    assert_equal 1, cut_calls_for(top, [v]).size

    too_deep = plain([plain([plain([plain([plain([solid_box])])])])]) # 4 level di bawah
    @model.active_entities << too_deep
    assert_empty cut_calls_for(too_deep, [v])
  end

  def test_stale_nested_state_is_cleaned_when_void_moves_away
    src = mark_role(solid_box, 'source')
    src.hidden = true
    res = mark_role(solid_box, 'result')
    middle = plain([src, res])
    parent = plain([middle], at: [100, 0, 0])
    @model.active_entities << parent
    far = void_box([900, 0, 0], [910, 10, 10])

    V.rebuild_nonsolid_children(@model, parent, [far], stats, 3)
    refute res.valid?, 'hasil lama dibuang'
    refute src.hidden?, 'source dimunculkan lagi'
    assert_nil role_of(src)
  end

  def test_hidden_children_are_not_recursed
    hidden_group = plain([solid_box])
    hidden_group.hidden = true
    parent = plain([hidden_group])
    @model.active_entities << parent
    v = void_box([2, 2, 2], [8, 8, 8])
    assert_empty cut_calls_for(parent, [v])
  end

  # ── Target yang dipotong harus unik; "berubah" dinilai dari volume ───────

  # Pemotong palsu: mencatat apakah target masih dipakai bersama saat subtract, lalu (opsional) mengurangi volume.
  class SpyCutter < Sketchup::Group
    class << self
      attr_accessor :log, :reduce
    end

    def subtract(cur)
      (self.class.log ||= []) << { shared: cur.definition.instances.size > 1 }
      cur.volume -= 100.0 if self.class.reduce
      cur
    end
  end

  def spy(reduce: false)
    SpyCutter.log = []
    SpyCutter.reduce = reduce
    SpyCutter.new
  end

  def shared_target(kind)
    base = kind == :component ? plain_component : solid_box
    klass = kind == :component ? Sketchup::ComponentInstance : Sketchup::Group
    twin = klass.new(tx: tx(50, 0, 0), box: [[0, 0, 0], [10, 10, 10]], definition: base.definition)
    [base, twin].each { |e| @model.active_entities << e }
    [base, twin]
  end

  %i[component group].each do |kind|
    define_method("test_cut_child_makes_shared_#{kind}_unique_before_subtract") do
      target, twin = shared_target(kind)
      v = void_box([2, 2, 2], [8, 8, 8])
      @model.active_entities << v
      V.stub(:cutter_from_into, spy) { V.cut_child(@model.active_entities, target, [[v, tx]], stats) }
      assert_equal [{ shared: false }], SpyCutter.log, 'saat dipotong, target tidak boleh lagi berbagi definisi'
      refute_same target.definition, twin.definition
      assert_equal 1, twin.definition.instances.size
    end

    define_method("test_cut_copy_never_cuts_the_shared_original_of_#{kind}") do
      target, twin = shared_target(kind)
      v = void_box([2, 2, 2], [8, 8, 8])
      @model.active_entities << v
      shared_before = target.definition
      V.stub(:cutter_from, spy) { V.cut_copy(@model.active_entities, target, [v], stats) }
      assert_equal [{ shared: false }], SpyCutter.log
      assert_same shared_before, target.definition, 'target asli tetap memakai definisinya'
      assert_same shared_before, twin.definition
    end
  end

  def test_cut_child_reports_change_only_when_volume_changes
    v = void_box([2, 2, 2], [8, 8, 8])
    untouched = solid_box
    cut = solid_box
    [v, untouched, cut].each { |e| @model.active_entities << e }

    V.stub(:cutter_from_into, spy(reduce: false)) do
      changed = V.cut_child(@model.active_entities, untouched, [[v, tx]], stats).last
      assert_equal false, changed, 'bounding box kena tapi volume sama: BUKAN lubang'
    end
    V.stub(:cutter_from_into, spy(reduce: true)) do
      assert_equal true, V.cut_child(@model.active_entities, cut, [[v, tx]], stats).last
    end
  end

  # ── Dinding non-solid kembar (definisi dipakai bersama): jangan saling mempengaruhi ──

  # Dua dinding hasil copy: SATU definisi (berisi satu child solid), diletakkan di X=0 dan X=100.
  def twin_walls
    wall_a = plain([solid_box([0, 0, 0], [10, 10, 10])])
    wall_b = Sketchup::Group.new(tx: tx(100, 0, 0), solid: false, definition: wall_a.definition)
    [wall_a, wall_b].each { |w| @model.active_entities << w }
    [wall_a, wall_b]
  end

  def roles_inside(wall)
    wall.definition.entities.map { |e| role_of(e) }
  end

  def fake_cut_child
    ->(_ents, child, _local_voids, _stats) { [child, true] }
  end

  def test_shared_nonsolid_parent_is_made_unique_before_its_contents_change
    wall_a, wall_b = twin_walls
    assert V.shared_definition?(wall_a)
    v = void_box([2, 2, 2], [8, 8, 8]) # hanya menimpa dinding A
    @model.active_entities << v

    V.stub(:cut_child, fake_cut_child) do
      V.rebuild_nonsolid_children(@model, wall_a, [v], stats, 3)
    end

    refute_same wall_a.definition, wall_b.definition, 'dinding A harus punya definisi sendiri'
    assert_includes roles_inside(wall_a), 'source'
    assert_includes roles_inside(wall_a), 'result'
    assert_equal [nil], roles_inside(wall_b), 'dinding kembar tidak boleh ikut berubah'
  end

  def test_nonsolid_parent_untouched_by_voids_stays_shared
    wall_a, wall_b = twin_walls
    far = void_box([900, 0, 0], [910, 10, 10])
    @model.active_entities << far
    V.stub(:cut_child, fake_cut_child) { V.rebuild_nonsolid_children(@model, wall_a, [far], stats, 3) }
    assert_same wall_a.definition, wall_b.definition, 'tidak ada yang diubah, jadi tidak perlu dijadikan unik'
  end

  def test_rebuild_with_twin_walls_gives_each_wall_its_own_hole
    wall_a, wall_b = twin_walls
    va = void_box([2, 2, 2], [8, 8, 8])
    vb = void_box([102, 2, 2], [108, 8, 8])
    [va, vb].each { |v| @model.active_entities << v }

    V.stub(:cut_child, fake_cut_child) { V.rebuild(@model, stats) }

    refute_same wall_a.definition, wall_b.definition
    [wall_a, wall_b].each do |w|
      assert_equal %w[result source], roles_inside(w).compact.sort, 'tiap dinding punya pasangan source/result sendiri'
    end
  end

  def test_moving_one_twin_wall_away_closes_only_its_own_hole
    wall_a, wall_b = twin_walls
    va = void_box([2, 2, 2], [8, 8, 8])
    vb = void_box([102, 2, 2], [108, 8, 8])
    [va, vb].each { |v| @model.active_entities << v }

    V.stub(:cut_child, fake_cut_child) do
      V.rebuild(@model, stats)
      wall_a.transformation = tx(500, 0, 0) # dinding A digeser menjauh dari void, void tidak ikut
      V.rebuild(@model, stats)
    end

    assert_equal [nil], roles_inside(wall_a).uniq, 'lubang dinding A tertutup'
    assert_equal 1, wall_a.definition.entities.count, 'tidak ada sisa source/result di dinding A'
    assert_equal %w[result source], roles_inside(wall_b).compact.sort, 'lubang dinding B TETAP ada'
  end

  def test_cancel_one_void_keeps_twin_wall_hole
    wall_a, wall_b = twin_walls
    va = void_box([2, 2, 2], [8, 8, 8])
    vb = void_box([102, 2, 2], [108, 8, 8])
    [va, vb].each { |v| @model.active_entities << v }

    V.stub(:cut_child, fake_cut_child) do
      V.rebuild(@model, stats)
      V.cancel_holes(@model, [va])
    end

    assert_equal [nil], roles_inside(wall_a).uniq, 'lubang dinding A ditutup'
    assert_equal %w[result source], roles_inside(wall_b).compact.sort, 'lubang dinding B tetap ada'
  end

  # ── Void di dalam group bersarang (group "new" > group "revisi" > void + dinding) ──

  # NEW (X=100) > REVISI (X=50) > [dinding solid 0..10, void 2..8]  → di world: dinding X 150..160, void X 152..158.
  def nested_scene
    wall = solid_box([0, 0, 0], [10, 10, 10])
    inner_void = void_box([2, 2, 2], [8, 8, 8])
    revisi = plain([wall, inner_void], at: [50, 0, 0])
    new_group = plain([revisi], at: [100, 0, 0])
    @model.active_entities << new_group
    [new_group, revisi, wall, inner_void]
  end

  def pair_roles(group)
    group.definition.entities.map { |e| role_of(e) }.compact.sort
  end

  def test_nested_void_refs_have_world_transform_and_box
    _new, _revisi, _wall, inner_void = nested_scene
    top_void = void_box([900, 0, 0], [910, 10, 10])
    @model.active_entities << top_void

    refs = V.nested_void_refs(@model.active_entities)
    assert_equal 1, refs.size, 'void level atas tidak ikut (sudah ada di daftar void biasa)'
    assert_same inner_void, refs.first.ent
    assert_equal [152.0, 2.0, 2.0], refs.first.box.min.to_a
    assert_equal [158.0, 8.0, 8.0], refs.first.box.max.to_a
    assert_equal [150.0, 0.0, 0.0], refs.first.tx.origin.to_a
  end

  def test_hot_reload_with_an_older_voidref_struct_still_works
    # Simulasi plugin lama (VoidRef 3 field) yang di-reload dengan kode baru (4 field).
    V.send(:remove_const, :VoidRef)
    V.const_set(:VoidRef, Struct.new(:ent, :tx, :box))
    load File.join(PLUGIN, 'ruby', 'paid', 'void.rb')

    assert_includes V::VoidRef.members, :owner
    nested_scene
    refs = V.nested_void_refs(@model.active_entities)
    assert_equal 1, refs.size
    refute_nil refs.first.owner
  end

  def test_nested_void_refs_skip_inactive_hidden_and_dynamic
    _new, _revisi, _wall, inner_void = nested_scene
    V.set_voids_active(@model, [inner_void], false)
    assert_empty V.nested_void_refs(@model.active_entities), 'void nonaktif dilewati'
  end

  def test_nested_void_cuts_its_wall_when_rebuilding_from_the_outer_level
    _new, revisi, wall, inner_void = nested_scene
    V.stub(:cut_child, fake_cut_child) { V.rebuild(@model, stats) }
    assert_equal %w[result source], pair_roles(revisi), 'dinding di dalam revisi dilubangi void di dalam revisi'
    assert_nil role_of(inner_void), 'void bersarang tidak boleh dipotong'
    refute inner_void.hidden?
    refute_nil wall
  end

  def test_moving_an_outer_void_keeps_holes_made_by_nested_voids
    _new, revisi, _wall, inner_void = nested_scene
    outer = void_box([2, 2, 2], [8, 8, 8]) # void level atas, jauh dari group bersarang
    outer.transformation = tx(900, 0, 0)
    @model.active_entities << outer

    V.stub(:cut_child, fake_cut_child) do
      V.rebuild(@model, stats)
      assert_equal %w[result source], pair_roles(revisi)

      outer.transformation = tx(1500, 0, 0) # user menggeser void level atas
      V.rebuild(@model, stats)
    end

    assert_equal %w[result source], pair_roles(revisi), 'lubang milik void bersarang tidak boleh ikut tertutup'
    refute_nil inner_void
  end

  def test_top_level_void_overlapping_a_nested_void_never_cuts_it
    _new, _revisi, _wall, inner_void = nested_scene
    outer = void_box([150, 0, 0], [160, 10, 10]) # menimpa area void bersarang
    @model.active_entities << outer
    V.stub(:cut_child, fake_cut_child) { V.rebuild(@model, stats) }
    assert_nil role_of(inner_void)
    refute inner_void.hidden?
  end

  # Dua "versi" bangunan yang bertumpuk di posisi yang sama; hanya versi A yang punya void di dalamnya.
  def stacked_versions
    wall_a = solid_box([0, 0, 0], [10, 10, 10])
    void_a = void_box([2, 2, 2], [8, 8, 8])
    version_a = plain([wall_a, void_a])
    wall_b = solid_box([0, 0, 0], [10, 10, 10])
    version_b = plain([wall_b])
    [version_a, version_b].each { |v| @model.active_entities << v }
    [version_a, version_b, wall_a, wall_b, void_a]
  end

  def test_nested_void_only_cuts_inside_its_own_group_not_a_stacked_copy
    version_a, version_b, = stacked_versions
    V.stub(:cut_child, fake_cut_child) { V.rebuild(@model, stats) }
    assert_equal %w[result source], pair_roles(version_a), 'dinding di group pemilik void dilubangi'
    assert_empty pair_roles(version_b), 'dinding di versi lain yang menempati posisi sama TIDAK boleh ikut berlubang'
  end

  def test_nested_void_reaches_grandchildren_of_its_owner
    wall = solid_box([0, 0, 0], [10, 10, 10])
    partition = plain([wall])
    inner_void = void_box([2, 2, 2], [8, 8, 8])
    owner = plain([partition, inner_void])
    @model.active_entities << owner
    V.stub(:cut_child, fake_cut_child) { V.rebuild(@model, stats) }
    assert_equal %w[result source], pair_roles(partition), 'dinding cucu dari group pemilik void ikut dilubangi'
  end

  def test_top_level_void_still_cuts_walls_in_every_group
    wall_a = solid_box([0, 0, 0], [10, 10, 10])
    wall_b = solid_box([0, 0, 0], [10, 10, 10])
    group_a = plain([wall_a])
    group_b = plain([wall_b])
    top = void_box([2, 2, 2], [8, 8, 8])
    [group_a, group_b, top].each { |e| @model.active_entities << e }
    V.stub(:cut_child, fake_cut_child) { V.rebuild(@model, stats) }
    assert_equal %w[result source], pair_roles(group_a)
    assert_equal %w[result source], pair_roles(group_b)
  end

  def test_existing_hole_of_nested_void_is_not_rebuilt_by_unrelated_stacked_copy
    version_a, version_b, = stacked_versions
    V.stub(:cut_child, fake_cut_child) do
      V.rebuild(@model, stats)
      V.rebuild(@model, stats) # rebuild kedua (mis. live): hasil tetap, versi B tetap utuh
    end
    assert_equal %w[result source], pair_roles(version_a)
    assert_empty pair_roles(version_b)
  end

  def test_deactivated_nested_void_closes_its_hole
    _new, revisi, _wall, inner_void = nested_scene
    V.stub(:cut_child, fake_cut_child) do
      V.rebuild(@model, stats)
      assert_equal %w[result source], pair_roles(revisi)
      V.set_voids_active(@model, [inner_void], false)
      V.rebuild(@model, stats)
    end
    assert_empty pair_roles(revisi), 'void bersarang dinonaktifkan → lubangnya tertutup'
  end

  # ── Sisa versi lama: dynamic component yang sudah terlanjur dipotong dipulihkan ──

  def test_dynamic_component_left_as_source_by_old_version_is_restored
    dc = dynamic_component
    mark_role(dc, 'source', 'OLD')
    dc.hidden = true
    res = mark_role(solid_box, 'result', 'OLD')
    v = void_box([2, 2, 2], [8, 8, 8])
    [dc, res, v].each { |e| @model.active_entities << e }

    with_fake_cuts { V.rebuild(@model, stats) }
    refute dc.hidden?, 'dynamic component tampil lagi'
    assert_nil role_of(dc)
    refute res.valid?, 'hasil berlubang dibuang'
  end

  def test_nested_dynamic_component_left_as_source_is_restored
    dc = dynamic_component
    mark_role(dc, 'source', 'OLD')
    dc.hidden = true
    res = mark_role(solid_box, 'result', 'OLD')
    parent = plain([dc, res])
    @model.active_entities << parent
    v = void_box([2, 2, 2], [8, 8, 8])
    @model.active_entities << v

    V.rebuild_nonsolid_children(@model, parent, [v], stats, 3)
    refute dc.hidden?
    assert_nil role_of(dc)
    refute res.valid?
  end

  # ── Dynamic component: TIDAK BOLEH dilubangi ────────────────────────────

  # on: :instance → kamus dynamic_attributes di instance; :definition → di definisi (kasus umum DC asli).
  def dynamic_component(min = [0, 0, 0], max = [10, 10, 10], at: [0, 0, 0], solid: true, kids: [], on: :definition)
    inst = Sketchup::ComponentInstance.new(tx: tx(*at), box: (kids.empty? ? [min, max] : nil), solid: solid, kids: kids)
    if on == :instance
      inst.set_attribute('dynamic_attributes', 'lenx', 10)
    else
      inst.definition.set_attribute('dynamic_attributes', 'lenx', 10)
    end
    inst
  end

  def plain_component(min = [0, 0, 0], max = [10, 10, 10], at: [0, 0, 0])
    Sketchup::ComponentInstance.new(tx: tx(*at), box: [min, max])
  end

  def test_dynamic_detects_dictionary_on_instance_or_definition
    assert V.dynamic?(dynamic_component(on: :instance))
    assert V.dynamic?(dynamic_component(on: :definition))
  end

  def test_dynamic_is_false_for_plain_component_and_group
    refute V.dynamic?(plain_component)
    refute V.dynamic?(solid_box)
    refute V.dynamic?(nil)
  end

  def test_top_level_dynamic_component_is_never_cut
    dc = dynamic_component
    normal = plain_component([0, 0, 0], [10, 10, 10])
    v = void_box([2, 2, 2], [8, 8, 8])
    [dc, normal, v].each { |e| @model.active_entities << e }

    cut_targets = []
    st = stats
    V.stub(:cut_copy, ->(_ents, base, _voids, _stats) { cut_targets << base; nil }) do
      V.rebuild(@model, st)
    end

    assert_includes cut_targets, normal, 'component biasa tetap dilubangi'
    refute_includes cut_targets, dc, 'dynamic component tidak boleh disentuh'
    assert_equal 1, st[:dynamic]
    refute dc.hidden?
    assert_nil role_of(dc)
  end

  def test_dynamic_component_on_instance_dictionary_is_also_skipped
    dc = dynamic_component(on: :instance)
    v = void_box([2, 2, 2], [8, 8, 8])
    [dc, v].each { |e| @model.active_entities << e }
    cut_targets = []
    V.stub(:cut_copy, ->(_e, base, _v, _s) { cut_targets << base; nil }) { V.rebuild(@model, stats) }
    assert_empty cut_targets
  end

  def test_dynamic_component_far_from_void_is_not_counted
    dc = dynamic_component(at: [500, 0, 0])
    v = void_box([2, 2, 2], [8, 8, 8])
    [dc, v].each { |e| @model.active_entities << e }
    st = stats
    V.rebuild(@model, st)
    assert_equal 0, st[:dynamic]
  end

  def test_nonsolid_dynamic_component_contents_are_not_cut
    inner = solid_box
    dc = dynamic_component(solid: false, kids: [inner])
    v = void_box([2, 2, 2], [8, 8, 8])
    [dc, v].each { |e| @model.active_entities << e }
    cut = []
    st = stats
    V.stub(:cut_child, ->(_p, child, _lv, _s) { cut << child; nil }) { V.rebuild(@model, st) }
    assert_empty cut, 'isi dynamic component tidak boleh dipotong'
    assert_equal 1, st[:dynamic]
  end

  def test_dynamic_child_inside_nonsolid_group_is_skipped_but_siblings_are_cut
    dc = dynamic_component([0, 0, 0], [10, 10, 10])
    normal = solid_box([0, 0, 0], [10, 10, 10])
    parent = plain([dc, normal])
    @model.active_entities << parent
    v = void_box([2, 2, 2], [8, 8, 8])
    cut = []
    st = stats
    V.stub(:cut_child, ->(_p, child, _lv, _s) { cut << child; nil }) do
      V.rebuild_nonsolid_children(@model, parent, [v], st, 3)
    end
    assert_equal [normal], cut
    assert_equal 1, st[:dynamic]
  end

  def test_dynamic_nested_deep_inside_groups_is_skipped
    dc = dynamic_component
    parent = plain([plain([plain([dc])])], at: [100, 0, 0])
    @model.active_entities << parent
    v = void_box([102, 2, 2], [108, 8, 8])
    cut = []
    st = stats
    V.stub(:cut_child, ->(_p, child, _lv, _s) { cut << child; nil }) do
      V.rebuild_nonsolid_children(@model, parent, [v], st, 3)
    end
    assert_empty cut
    assert_equal 1, st[:dynamic]
  end

  def test_new_stats_has_dynamic_counter
    assert_equal 0, V.new_stats[:dynamic]
  end

  # ── Void hasil copy harus unik ───────────────────────────────────────────

  # Dua instance memakai SATU definisi berisi satu face (seperti hasil copy dengan Move+Ctrl).
  def shared_pair(kind)
    face = Sketchup::Face.new
    first = kind == :component ? plain_component([0, 0, 0], [10, 10, 10]) : solid_box
    first.definition.entities << face
    twin = (kind == :component ? Sketchup::ComponentInstance : Sketchup::Group)
           .new(tx: tx(50, 0, 0), box: [[0, 0, 0], [10, 10, 10]], definition: first.definition)
    [first, twin].each { |e| @model.active_entities << e }
    [first, twin]
  end

  def face_layer_names(ent)
    ent.definition.entities.select { |e| e.is_a?(Sketchup::Face) }.map { |f| f.layer.name }
  end

  %i[component group].each do |kind|
define_method("test_mark_of_shared_#{kind}_does_not_touch_the_other") do
  a, b = shared_pair(kind)
  V.mark(@model, a, true)
  refute V.void?(b)
  assert_equal ['Layer0'], face_layer_names(b), 'salinan lain tidak boleh ikut ditandai'
  assert_equal ['Layer0'], face_layer_names(a), 'isi group tidak diubah, hanya dibungkus'
  outer = @model.active_entities.find { |e| V.void?(e) && e != b }
  assert_equal 1, V.cutter_shapes(V.entities_of(outer)).size
end

    define_method("test_unmark_of_one_copied_#{kind}_void_does_not_touch_the_other") do
      a, b = shared_pair(kind)
      # Void yang SUDAH ditandai lalu di-copy: definisi bersama, isinya bertag #void_hidden, atribut ikut tersalin.
      hidden = V.void_hidden_layer(@model)
      a.definition.entities.each { |e| e.layer = hidden }
      [a, b].each do |v|
        v.set_attribute('BoosokTools', 'void', true)
        v.set_attribute('BoosokTools', 'void_orig_material', '')
      end
      assert V.shared_definition?(a)
      V.mark(@model, a, false)
      refute V.void?(a)
      assert V.void?(b), 'void salinan tetap void'
      assert_equal ['Layer0'], face_layer_names(a), 'isi void yang dibatalkan kembali Untagged'
      assert_equal ['#void_hidden'], face_layer_names(b), 'isi void salinan tidak boleh ikut dikembalikan'
    end

    define_method("test_rebuild_makes_copied_#{kind}_void_unique") do
      a, b = shared_pair(kind)
      [a, b].each { |v| v.set_attribute('BoosokTools', 'void', true) }
      V.rebuild(@model, stats)
      refute_same a.definition, b.definition
    end
  end

# ── Group yang dijadikan void: group(Untagged) > group(#void_hidden) > face & edge ──

def test_mark_tags_selected_group_and_wraps_it_in_untagged_void_group
  g = solid_box
  g.definition.entities << Sketchup::Face.new
  g.layer = @model.layers.add('I. PARTITION')
  @model.active_entities << g
  assert V.mark(@model, g, true)

  outers = @model.active_entities.to_a
  assert_equal 1, outers.size
  outer = outers.first
  refute_same g, outer
  assert V.void?(outer)
  assert_equal 'Layer0', outer.layer.name
  assert_same V.void_material(@model), outer.material
  assert_equal [g], V.cutter_shapes(outer.entities), 'group asli ada di dalam pembungkus'
  assert_equal '#void_hidden', g.layer.name
  assert_same V.void_material(@model), g.material
  assert_equal 1, g.definition.entities.count, 'face tetap polos di dalam group asli'
end

def test_unmark_restores_original_group_tag_and_material_and_removes_wrapper
  g = solid_box
  g.definition.entities << Sketchup::Face.new
  g.layer = @model.layers.add('I. PARTITION')
  g.material = @model.materials.add('Beton')
  @model.active_entities << g
  V.mark(@model, g, true)
  outer = @model.active_entities.first
  assert V.mark(@model, outer, false)

  assert_equal [g], @model.active_entities.to_a
  refute V.void?(g)
  assert_equal 'I. PARTITION', g.layer.name
  assert_equal 'Beton', g.material.name
  assert_nil g.get_attribute('BoosokTools', 'void_cutter')
end

def test_mark_ignores_group_that_is_already_void
  v = solid_box
  v.set_attribute('BoosokTools', 'void', true)
  @model.active_entities << v
  refute V.mark(@model, v, true)
  assert_equal [v], @model.active_entities.to_a
end

def test_unmark_of_legacy_void_with_tagged_plain_faces_untags_them
  v = solid_box
  face = Sketchup::Face.new
  face.layer = V.void_hidden_layer(@model)
  v.definition.entities << face
  v.set_attribute('BoosokTools', 'void', true)
  @model.active_entities << v
  assert V.mark(@model, v, false)
  assert_equal 'Layer0', face.layer.name
end

  def test_ensure_unique_is_noop_for_unshared_void_and_dynamic_component
    v = solid_box
    assert_same v, V.ensure_unique(v)
    assert_equal 0, v.make_unique_calls

    dc = dynamic_component
    twin = Sketchup::ComponentInstance.new(definition: dc.definition)
    assert_same dc, V.ensure_unique(dc)
    assert V.shared_definition?(dc), 'dynamic component tidak boleh disentuh'
    refute_nil twin
  end

  def test_ensure_unique_survives_errors
    a, = shared_pair(:group)
    a.define_singleton_method(:make_unique) { raise 'boom' }
    assert_same a, V.ensure_unique(a)
  end

  # ── Batalkan Lubang: hanya void terpilih ─────────────────────────────────

  # cut_copy palsu: salinan target "terpotong" kalau ada void yang overlap (cukup untuk menguji siapa-memotong-apa).
  def fake_cut_copy
    lambda do |ents, base, voids, _stats|
      cur = V.duplicate(ents, base)
      hit = voids.any? { |v| v.valid? && cur.valid? && V.overlap?(cur.bounds, v.bounds) }
      [cur, hit]
    end
  end

  def with_fake_cuts(&block)
    V.stub(:cut_copy, fake_cut_copy, &block)
  end

  def two_walls
    w1 = solid_box([0, 0, 0], [10, 10, 10])
    w2 = solid_box([0, 0, 0], [10, 10, 10], at: [100, 0, 0])
    v1 = void_box([2, 2, 2], [8, 8, 8])
    v2 = void_box([102, 2, 2], [108, 8, 8])
    [w1, w2, v1, v2].each { |e| @model.active_entities << e }
    [w1, w2, v1, v2]
  end

  def holes(model = @model)
    V.count_results(model.active_entities)
  end

  # ── Material hasil lubang harus sama dengan target asli ───────────────────

  def face_with(material = nil, back = nil)
    f = Sketchup::Face.new
    f.material = material
    f.back_material = back
    f
  end

  def test_restore_look_removes_void_material_but_keeps_all_original_materials
    brick = Sketchup::Material.new('Bata')
    paint = Sketchup::Material.new('Cat')
    void_mat = V.void_material(@model)
    base = plain([])
    [face_with(brick), face_with(paint)].each { |f| base.definition.entities << f }
    result = plain([])
    result.material = void_mat # dibawa dari pemotong
    kept1 = face_with(brick)
    kept2 = face_with(paint)
    hole_wall = face_with(void_mat, void_mat) # face lubang yang mewarisi material pemotong
    [kept1, kept2, hole_wall].each { |f| result.definition.entities << f }

    V.restore_look(result, base)

    assert_nil result.material, 'target asli tanpa material group: hasil juga tanpa'
    assert_same brick, kept1.material
    assert_same paint, kept2.material, 'target dengan lebih dari satu material: semuanya tetap'
    assert_nil hole_wall.material, 'material void tidak boleh tersisa di face lubang'
    assert_nil hole_wall.back_material
  end

  # Face fake dengan geometri minimal: bounds, luas, dan tetangga lewat edge.
  def shaped_face(min, max, area: 1.0, material: nil, neighbours: [])
    f = face_with(material)
    f.define_singleton_method(:bounds) { Geom::BoundingBox.from(min, max) }
    f.define_singleton_method(:area) { area }
    edge = Struct.new(:faces).new(neighbours)
    f.define_singleton_method(:edges) { [edge] }
    f
  end

  def test_hole_faces_take_the_material_of_the_adjacent_wall_face
    brick = Sketchup::Material.new('Bata')
    paint = Sketchup::Material.new('Cat')
    base = plain([])
    base.material = nil
    [shaped_face([0, 0, 0], [100, 1, 100], area: 100.0, material: brick),
     shaped_face([0, 5, 0], [100, 6, 100], area: 40.0, material: paint)].each { |f| base.definition.entities << f }

    front = shaped_face([0, 0, 0], [100, 1, 100], area: 90.0, material: brick)
    back = shaped_face([0, 5, 0], [100, 6, 100], area: 30.0, material: paint)
    hole_a = shaped_face([40, 0, 40], [60, 5, 40], area: 5.0, neighbours: [front, back])
    hole_b = shaped_face([40, 0, 40], [60, 5, 60], area: 5.0, neighbours: [back])
    result = plain([])
    [front, back, hole_a, hole_b].each { |f| result.definition.entities << f }

    V.restore_look(result, base, [Geom::BoundingBox.from([40, -1, 40], [60, 7, 60])])

    assert_same brick, hole_a.material, 'bersebelahan dengan face terbesar (bata)'
    assert_same paint, hole_b.material
    assert_same brick, front.material, 'material dinding asli tidak berubah'
    assert_same paint, back.material
  end

  def test_hole_faces_without_neighbours_use_the_dominant_material
    brick = Sketchup::Material.new('Bata')
    paint = Sketchup::Material.new('Cat')
    base = plain([])
    [shaped_face([0, 0, 0], [1, 1, 1], area: 100.0, material: brick),
     shaped_face([0, 0, 0], [1, 1, 1], area: 20.0, material: paint)].each { |f| base.definition.entities << f }
    hole = shaped_face([40, 0, 40], [60, 5, 40], area: 5.0)
    result = plain([])
    result.definition.entities << hole

    V.restore_look(result, base, [Geom::BoundingBox.from([40, -1, 40], [60, 7, 60])])

    assert_same brick, hole.material
  end

  def test_restore_look_uses_the_group_material_for_hole_faces
    wood = Sketchup::Material.new('Kayu')
    base = plain([])
    base.material = wood
    result = plain([])
    hole_wall = face_with(V.void_material(@model))
    result.definition.entities << hole_wall

    V.restore_look(result, base)

    assert_same wood, result.material
    assert_same wood, hole_wall.material
  end

  def test_cutter_copy_does_not_carry_the_void_material
    v = void_box([2, 2, 2], [8, 8, 8])
    v.material = V.void_material(@model)
    @model.active_entities << v
    cutter = V.cutter_from(@model.active_entities, v)
    assert_nil cutter.material
  end

  def test_incremental_rebuild_only_recuts_sources_whose_input_changed
    _w1, _w2, v1, _v2 = two_walls
    calls = 0
    base = fake_cut_copy
    counting = ->(*args) { calls += 1; base.call(*args) }
    V.stub(:cut_copy, counting) do
      V.rebuild(@model, stats)
      assert_equal 2, calls, 'rebuild penuh memotong semua'

      V.instance_variable_set(:@incremental, true)
      calls = 0
      V.rebuild(@model, stats)
      assert_equal 0, calls, 'tidak ada yang berubah: tidak ada pemotongan ulang'

      v1.transformation = tx(1, 0, 0)
      V.rebuild(@model, stats)
      assert_equal 1, calls, 'hanya dinding yang disentuh void yang digeser yang dipotong ulang'
      assert_equal 2, holes

      V.instance_variable_set(:@incremental, false)
      calls = 0
      V.rebuild(@model, stats)
      assert_equal 2, calls, 'tombol manual (Refresh/Terapkan) selalu memotong ulang semua'
    end
  ensure
    V.instance_variable_set(:@incremental, false)
  end

  def test_cancel_holes_only_closes_the_selected_void
    w1, w2, v1, v2 = two_walls
    with_fake_cuts do
      V.rebuild(@model, stats)
      assert_equal 2, holes
      assert_equal 'source', role_of(w1)
      assert_equal 'source', role_of(w2)

      res = V.cancel_holes(@model, [v1])
      assert_equal({ count: 1, voids: 1, total: 1 }, res)
      assert_equal 1, holes, 'lubang void lain harus tetap ada'
      refute w1.hidden?, 'dinding 1 pulih utuh'
      assert_nil role_of(w1)
      assert w2.hidden?, 'dinding 2 masih berlubang (source tersembunyi)'
      assert_equal 'source', role_of(w2)
    end
    assert V.void?(v1) && V.void_off?(v1)
    refute V.void_off?(v2)
  end

  def test_cancel_holes_without_selection_cancels_every_void
    _w1, _w2, v1, v2 = two_walls
    with_fake_cuts do
      V.rebuild(@model, stats)
      res = V.cancel_holes(@model, [])
      assert_equal 2, res[:count]
      assert_equal 2, res[:voids]
      assert_equal 0, holes
    end
    assert V.void_off?(v1) && V.void_off?(v2)
  end

  def test_cancelled_void_stays_off_across_live_rebuilds
    w1, _w2, v1, _v2 = two_walls
    with_fake_cuts do
      V.rebuild(@model, stats)
      V.cancel_holes(@model, [v1])
      st = stats
      V.rebuild(@model, st) # mis. live memicu rebuild karena void lain digeser
      assert_equal 1, st[:off]
      refute w1.hidden?, 'dinding 1 tidak boleh dilubangi lagi oleh void yang dibatalkan'
      assert_equal 1, holes
    end
  end

  def test_cancel_keeps_hole_made_by_another_void_on_same_wall
    wall = solid_box([0, 0, 0], [20, 10, 10])
    va = void_box([2, 2, 2], [6, 8, 8])
    vb = void_box([12, 2, 2], [16, 8, 8])
    [wall, va, vb].each { |e| @model.active_entities << e }
    with_fake_cuts do
      V.rebuild(@model, stats)
      V.cancel_holes(@model, [va])
      assert wall.hidden?, 'dinding masih dilubangi void B'
      assert_equal 1, holes
    end
  end

  def test_apply_reactivates_selected_void_only
    w1, w2, v1, v2 = two_walls
    with_fake_cuts do
      V.rebuild(@model, stats)
      V.cancel_holes(@model, [])
      V.run_rebuild(@model, 'Terapkan Void', false) { V.set_voids_active(@model, [v1], true) }
      refute V.void_off?(v1)
      assert V.void_off?(v2)
      assert w1.hidden?, 'dinding 1 dilubangi lagi'
      refute w2.hidden?, 'dinding 2 tetap utuh'
    end
  end

  def test_off_void_gets_grey_material_and_active_gets_red_back
    v = void_box([0, 0, 0], [5, 5, 5])
    @model.active_entities << v
    V.set_voids_active(@model, [v], false)
    assert_equal 'Boosok Void (Off)', v.material.name
    assert_equal 0, V.set_voids_active(@model, [v], false), 'sudah nonaktif: tidak dihitung'
    assert_equal 1, V.set_voids_active(@model, [v], true)
    assert_equal 'Boosok Void', v.material.name
    refute V.void_off?(v)
  end

  def test_unmark_clears_off_flag
    g = solid_box
    @model.active_entities << g
    V.mark(@model, g, true)
    V.set_voids_active(@model, [g], false)
    V.mark(@model, g, false)
    assert_nil g.get_attribute('BoosokTools', 'void_off')
  end

  def test_cancel_holes_with_no_voids_reports_total_zero
    @model.active_entities << solid_box
    assert_equal({ count: 0, voids: 0, total: 0 }, V.cancel_holes(@model, []))
  end

  def test_cancel_callback_uses_selection_and_reports_json
    _w1, _w2, v1, _v2 = two_walls
    with_fake_cuts do
      V.rebuild(@model, stats)
      @model.selection.add(v1)
      dlg = attach
      dlg.fire('void_reset_cuts')
      assert_includes dlg.scripts.last, 'onCutsReset({"count":1,"voids":1,"total":1})'
    end
  end

  def test_cancel_callback_reports_exception_as_json_string
    @model.active_entities << void_box([0, 0, 0], [5, 5, 5])
    dlg = attach
    V.stub(:cancel_holes, ->(*) { raise 'pesan "aneh"' }) { dlg.fire('void_reset_cuts') }
    assert_includes dlg.scripts.last, 'Gagal membatalkan lubang: pesan \"aneh\"'
  end

  # ── Dinding digeser, void tidak terbawa → lubang menutup ─────────────────

  def test_hole_of_child_closes_when_void_no_longer_touches_that_child_only
    # Parent besar berisi dinding A (0..10) dan B (50..60); void hanya menyentuh B. A punya lubang basi.
    src_a = mark_role(solid_box([0, 0, 0], [10, 10, 10]), 'source', 'A')
    src_a.hidden = true
    res_a = mark_role(solid_box([0, 0, 0], [10, 10, 10]), 'result', 'A')
    b = solid_box([50, 0, 0], [60, 10, 10])
    parent = plain([src_a, res_a, b], at: [100, 0, 0])
    @model.active_entities << parent
    v = void_box([152, 2, 2], [158, 8, 8]) # world X 152..158 → hanya B

    cut = []
    V.stub(:cut_child, ->(_p, child, _lv, _s) { cut << child; nil }) do
      V.rebuild_nonsolid_children(@model, parent, [v], stats, 3)
    end
    refute res_a.valid?, 'hasil lama A dibuang'
    refute src_a.hidden?, 'A pulih utuh walau parent masih tertimpa void'
    assert_nil role_of(src_a)
    assert_equal 1, cut.size, 'hanya B yang dipotong'
  end

  def test_nonsolid_parent_with_hole_is_watched_and_move_changes_signature
    result = mark_role(solid_box, 'result')
    parent = plain([mark_role(solid_box, 'source'), result])
    clean = plain([solid_box])
    [parent, clean].each { |e| @model.active_entities << e }

    V.rescan(@model)
    assert_includes V.watched_ids(@model), parent.persistent_id
    refute_includes V.watched_ids(@model), clean.persistent_id, 'group tanpa lubang tidak perlu dipantau'

    before = V.signature(@model)
    parent.transformation = tx(300, 0, 0)
    refute_equal before, V.signature(@model)
  end

  def test_moving_nonsolid_parent_with_hole_triggers_live_recut
    parent = plain([mark_role(solid_box, 'source'), mark_role(solid_box, 'result')])
    @model.active_entities << parent
    V.rescan(@model)

    recut = false
    V.stub(:schedule_recut, -> { recut = true }) do
      V.on_commit(@model)
      refute recut, 'belum ada yang berubah'
      parent.transformation = tx(300, 0, 0)
      V.on_commit(@model)
    end
    assert recut
  end

  # ── Dinding digeser MASUK ke void aktif → lubang dibuat otomatis (live) ──

  def commit_triggers_recut?
    recut = false
    V.stub(:schedule_recut, -> { recut = true }) { V.on_commit(@model) }
    recut
  end

  def test_moving_a_plain_wall_into_an_active_void_triggers_live_recut
    wall = solid_box([0, 0, 0], [10, 10, 10], at: [500, 0, 0])
    v = void_box([2, 2, 2], [8, 8, 8])
    [wall, v].each { |e| @model.active_entities << e }
    V.rescan(@model)
    refute commit_triggers_recut?, 'dinding jauh dari void: tidak ada yang berubah'

    wall.transformation = tx(0, 0, 0) # digeser masuk ke void
    assert commit_triggers_recut?, 'dinding menyentuh void aktif → harus memicu pelubangan otomatis'
  end

  def test_wall_moved_into_void_actually_gets_a_hole_after_the_recut
    wall = solid_box([0, 0, 0], [10, 10, 10], at: [500, 0, 0])
    v = void_box([2, 2, 2], [8, 8, 8])
    [wall, v].each { |e| @model.active_entities << e }
    with_fake_cuts do
      V.rebuild(@model, stats)
      assert_equal 0, holes
      wall.transformation = tx(0, 0, 0)
      V.rebuild(@model, stats) # yang dijalankan schedule_recut
    end
    assert_equal 1, holes
    assert wall.hidden?, 'dinding asli jadi source tersembunyi, hasil berlubang tampil'
  end

  def test_pasting_a_wall_onto_an_active_void_triggers_live_recut
    v = void_box([2, 2, 2], [8, 8, 8])
    @model.active_entities << v
    V.rescan(@model)
    refute commit_triggers_recut?
    @model.active_entities << solid_box([0, 0, 0], [10, 10, 10])
    assert commit_triggers_recut?
  end

  # ── Navigasi konteks tidak boleh memindai ────────────────────────────────

  def test_path_change_only_marks_stale_and_does_not_scan
    @model.active_entities << void_box([2, 2, 2], [8, 8, 8])
    V.rescan(@model)
    scans = 0
    V.stub(:scan_top, ->(_m) { scans += 1; [[], 0] }) do
      V.mark_stale(@model)
      assert_equal 0, scans, 'buka/tutup group tidak boleh memindai'
      V.refresh_if_stale(@model)
      assert_equal 1, scans, 'baseline diambil lazy sebelum transaksi berikutnya'
      V.refresh_if_stale(@model)
      assert_equal 1, scans, 'sudah segar: tidak memindai lagi'
    end
  end

  def test_model_without_any_void_is_never_scanned
    Sketchup.reset_model!
    model = Sketchup.active_model # tanpa material/tag Void
    model.active_entities << solid_box([0, 0, 0], [10, 10, 10])
    scans = 0
    V.stub(:scan_top, ->(_m) { scans += 1; [[], 0] }) do
      V.stub(:signature, ->(_m) { scans += 1; [] }) do
        V.rescan(model)
        V.on_commit(model)
      end
    end
    assert_equal 0, scans
  end

  # ── Cache bendera & signature terpangkas (skala project besar) ───────────

  def test_subtree_flags_are_cached_and_reused_across_scans
    building, = nested_building
    reads = 0
    kids = building.definition.entities
    kids.define_singleton_method(:each) { |&b| reads += 1; super(&b) }
    V.invalidate_scan_cache
    2.times { V.watched_ids(@model) }
    assert_equal 1, reads, 'isi group hanya ditelusuri sekali, scan berikutnya memakai cache'
  end

  def test_flags_are_dropped_when_group_content_changes
    parent = plain([solid_box])
    @model.active_entities << parent
    V.invalidate_scan_cache
    refute_includes V.watched_ids(@model), parent.persistent_id

    parent.definition.entities << void_box([2, 2, 2], [8, 8, 8])
    assert_includes V.watched_ids(@model), parent.persistent_id, 'void baru di dalam group harus ketahuan tanpa invalidasi manual'
  end

  def test_signature_ignores_nested_walls_far_from_every_void
    far = solid_box([0, 0, 0], [10, 10, 10], at: [900, 0, 0])
    building, _wall, = nested_building
    building.definition.entities << far
    V.rescan(@model)
    before = V.signature(@model)
    far.transformation = tx(950, 0, 0)
    assert_equal before, V.signature(@model), 'dinding jauh dari void tidak memengaruhi lubang'
    far.transformation = tx(0, 0, 0)
    refute_equal before, V.signature(@model), 'dinding yang bergeser masuk ke area void harus terdeteksi'
  end

  def test_touching_an_inactive_void_does_not_trigger_recut
    wall = solid_box([0, 0, 0], [10, 10, 10], at: [500, 0, 0])
    v = void_box([2, 2, 2], [8, 8, 8])
    [wall, v].each { |e| @model.active_entities << e }
    V.set_voids_active(@model, [v], false)
    V.rescan(@model)
    wall.transformation = tx(0, 0, 0)
    refute commit_triggers_recut?, 'void nonaktif tidak melubangi, jadi tidak perlu rebuild'
  end

  def test_moving_walls_without_any_void_costs_nothing
    @model.active_entities << solid_box
    assert_empty V.touching_signature(@model)
  end

  def test_dynamic_component_touching_a_void_is_not_watched
    dc = dynamic_component
    v = void_box([2, 2, 2], [8, 8, 8])
    [dc, v].each { |e| @model.active_entities << e }
    assert_empty V.touching_signature(@model)
  end

  def test_signature_is_stable_after_a_rebuild
    wall = solid_box([0, 0, 0], [10, 10, 10])
    v = void_box([2, 2, 2], [8, 8, 8])
    [wall, v].each { |e| @model.active_entities << e }
    with_fake_cuts { V.run_rebuild(@model, 'Update Void', true) }
    recut = false
    V.stub(:schedule_recut, -> { recut = true }) { V.on_commit(@model) }
    refute recut, 'setelah rebuild tidak boleh memicu rebuild lagi (hindari loop)'
  end

  def test_moving_top_level_result_away_from_void_closes_hole
    wall = solid_box([0, 0, 0], [10, 10, 10])
    v = void_box([2, 2, 2], [8, 8, 8])
    [wall, v].each { |e| @model.active_entities << e }
    with_fake_cuts do
      V.rebuild(@model, stats)
      result = @model.active_entities.find { |e| role_of(e) == 'result' }
      result.transformation = tx(500, 0, 0) # user menggeser dinding, void tidak ikut
      V.rebuild(@model, stats)
    end
    refute wall.hidden?, 'dinding pulih utuh'
    assert_equal 0, holes
    assert_equal [500.0, 0.0, 0.0], wall.transformation.origin.to_a, 'dan ikut pindah ke posisi baru'
  end

  # ── Move pada anak bersarang (group di dalam group) ─────────────────────

  def nested_building(wall_at: [0, 0, 0], void_at: [0, 0, 0])
    wall = solid_box([0, 0, 0], [10, 10, 10], at: wall_at)
    v = void_box([2, 2, 2], [8, 8, 8], at: void_at)
    building = plain([wall, v], at: [0, 0, 0])
    @model.active_entities << building
    [building, wall, v]
  end

  def test_group_with_nested_active_void_is_watched
    building, = nested_building
    assert_includes V.watched_ids(@model), building.persistent_id
  end

  def test_moving_a_nested_void_changes_signature_and_triggers_recut
    _building, _wall, v = nested_building
    V.rescan(@model)
    refute commit_triggers_recut?, 'belum ada yang digeser'

    v.transformation = tx(300, 0, 0)
    assert commit_triggers_recut?, 'void di dalam group digeser → lubang harus diperbarui'
  end

  def test_moving_a_nested_wall_triggers_recut
    _building, wall, = nested_building(wall_at: [500, 0, 0])
    V.rescan(@model)
    refute commit_triggers_recut?

    wall.transformation = tx(0, 0, 0) # dinding bersarang digeser masuk ke void bersarang
    assert commit_triggers_recut?
  end

  def test_nested_wall_moved_into_top_level_void_triggers_recut
    wall = solid_box([0, 0, 0], [10, 10, 10], at: [500, 0, 0])
    group = plain([wall])
    v = void_box([2, 2, 2], [8, 8, 8])
    [group, v].each { |e| @model.active_entities << e }
    V.rescan(@model)
    refute commit_triggers_recut?

    wall.transformation = tx(0, 0, 0)
    assert commit_triggers_recut?, 'group tanpa lubang yang menyentuh void aktif: gerakan anaknya harus terdeteksi'
  end

  def test_nested_signature_is_stable_without_moves
    nested_building
    V.rescan(@model)
    refute commit_triggers_recut?
  end

  def test_moving_nested_result_away_closes_hole_and_source_follows
    wall = solid_box([0, 0, 0], [10, 10, 10])
    v = void_box([102, 2, 2], [108, 8, 8])
    parent = plain([wall], at: [100, 0, 0])
    [parent, v].each { |e| @model.active_entities << e }

    V.stub(:cut_child, fake_cut_child) do
      V.rebuild(@model, stats)
      result = parent.definition.entities.find { |e| role_of(e) == 'result' }
      refute_nil result, 'dinding di dalam group sudah berlubang'
      result.transformation = tx(500, 0, 0) # user menggeser dinding di dalam group, void tidak ikut
      V.rebuild(@model, stats)
    end

    kids = parent.definition.entities.to_a
    assert_equal [nil], kids.map { |e| role_of(e) }.uniq, 'lubang tertutup, tidak ada sisa source/result'
    assert_equal 1, kids.size
    assert_equal [500.0, 0.0, 0.0], kids.first.transformation.origin.to_a, 'dinding tetap di posisi baru'
  end

  # ── Callback dialog ─────────────────────────────────────────────────────

  class FakeDialog
    attr_reader :callbacks, :scripts

    def initialize
      @callbacks = {}
      @scripts = []
    end

    def add_action_callback(name, &blk)
      @callbacks[name] = blk
    end

    def execute_script(js)
      @scripts << js
    end

    def visible?
      false
    end

    def fire(name, *args)
      @callbacks.fetch(name).call(self, *args)
    end
  end

  def attach
    V.release_dialog
    dlg = FakeDialog.new
    V.attach_callbacks(dlg)
    dlg
  end

  def test_callbacks_registered_for_every_html_action
    dlg = attach
    html = File.read(File.join(PLUGIN, 'html', 'void.html'))
    called = html.scan(/call\('(void_\w+)'/).flatten.uniq
    refute_empty called
    called.each { |name| assert dlg.callbacks.key?(name), "void.html memanggil #{name} tapi Ruby tidak mendaftarkannya" }
  end

  def test_reset_cuts_callback_without_model_shows_error
    Sketchup.model = nil
    dlg = attach
    dlg.fire('void_reset_cuts')
    assert_match(/showToast\('Tidak ada model yang aktif\.', 'error'\)/, dlg.scripts.last)
  end

  def test_refresh_callback_without_voids_returns_stats
    @model.active_entities << solid_box
    dlg = attach
    dlg.fire('void_refresh')
    st = JSON.parse(dlg.scripts.last[/onRefreshed\((.*)\);/, 1])
    assert_equal 0, st['voids']
    assert_equal 0, st['cut']
    assert_equal 0, st['failed']
  end

  def test_refresh_callback_opens_named_operation
    dlg = attach
    dlg.fire('void_refresh')
    assert_equal [:start, 'Refresh Void'], @model.operations.first
  end
end
