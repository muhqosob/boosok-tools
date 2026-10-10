# Tiruan minimal SketchUp API supaya logika murni (Void, dsb.) bisa diuji di Ruby biasa, tanpa SketchUp.
# Hanya yang dipakai test; BUKAN emulasi lengkap. Konvensi penting yang ditiru dari SketchUp asli:
#   * Drawingelement#bounds ada di ruang koordinat PARENT (sudah termasuk transformation entity itu sendiri).
#   * Membaca/menulis entity yang sudah di-erase melempar error ("reference to deleted Entity").
require 'matrix'

module Geom
  class Point3d
    attr_reader :x, :y, :z

    def initialize(x = 0, y = 0, z = 0)
      @x = x.to_f
      @y = y.to_f
      @z = z.to_f
    end

    def to_a
      [x, y, z]
    end

    def transform(tx)
      tx.apply(self)
    end
  end

  class Transformation
    attr_reader :matrix

    # Menerima Matrix, atau array 16 elemen kolom-mayor (seperti Geom::Transformation.new(array) di SketchUp).
    def initialize(matrix = Matrix.identity(4))
      matrix = Matrix.columns(matrix.each_slice(4).to_a) if matrix.is_a?(Array)
      @matrix = matrix
    end

    def self.translation(x, y, z)
      new(Matrix[[1, 0, 0, x], [0, 1, 0, y], [0, 0, 1, z], [0, 0, 0, 1]].map(&:to_f))
    end

    def self.scaling(sx, sy = sx, sz = sx)
      new(Matrix[[sx, 0, 0, 0], [0, sy, 0, 0], [0, 0, sz, 0], [0, 0, 0, 1]].map(&:to_f))
    end

    def *(other)
      Transformation.new(matrix * other.matrix)
    end

    def inverse
      Transformation.new(matrix.inverse)
    end

    def apply(pt)
      v = matrix * Vector[pt.x, pt.y, pt.z, 1.0]
      Point3d.new(v[0], v[1], v[2])
    end

    def origin
      apply(Point3d.new(0, 0, 0))
    end

    def to_a
      matrix.transpose.to_a.flatten # kolom-mayor, seperti SketchUp
    end
  end

  class BoundingBox
    attr_reader :min, :max

    def initialize
      @min = nil
      @max = nil
    end

    def add(pt)
      if empty?
        @min = Point3d.new(*pt.to_a)
        @max = Point3d.new(*pt.to_a)
      else
        @min = Point3d.new(*[@min.to_a, pt.to_a].transpose.map(&:min))
        @max = Point3d.new(*[@max.to_a, pt.to_a].transpose.map(&:max))
      end
      self
    end

    def empty?
      @min.nil?
    end

    def width;  extent(0); end
    def height; extent(1); end
    def depth;  extent(2); end

    def intersect(other)
      out = BoundingBox.new
      return out if empty? || other.empty?

      lo = [min.to_a, other.min.to_a].transpose.map(&:max)
      hi = [max.to_a, other.max.to_a].transpose.map(&:min)
      return out if lo.zip(hi).any? { |l, h| l > h }

      out.add(Point3d.new(*lo)).add(Point3d.new(*hi))
    end

    def self.from(min, max)
      new.add(Point3d.new(*min)).add(Point3d.new(*max))
    end

    private

    def extent(i)
      empty? ? 0.0 : max.to_a[i] - min.to_a[i]
    end
  end
end

module Sketchup
  class DeletedEntityError < StandardError; end

  class Color
    def initialize(*); end
  end

  class AppObserver; end
  class ModelObserver; end
  class ViewObserver; end

  class Entities
    include Enumerable
    attr_reader :owner

    def initialize(owner = nil)
      @items = []
      @owner = owner
    end

    def each(&block)
      @items.dup.each(&block)
    end

    def <<(ent)
      ent.parent = self
      @items << ent
      ent
    end

    def length
      @items.length
    end

    def delete(ent)
      @items.delete(ent)
    end

    # Entities#add_group(entities): entitas yang diberikan dipindahkan ke dalam group baru.
    def add_group(*ents)
      group = self << Group.new
      ents.flatten.each do |e|
        delete(e)
        group.definition.entities << e
      end
      group
    end

    def add_instance(defn, tx)
      inst = ComponentInstance.new(tx: tx, definition: defn)
      self << inst
    end

    # Entities#transform_entities: transformasi dikalikan di depan (dalam ruang entities ini).
    def transform_entities(delta, list)
      Array(list).each { |e| e.transformation = delta * e.transformation }
    end

    def erase_entities(list)
      Array(list).each(&:erase!)
    end
  end

  class Layer
    attr_accessor :name, :visible

    def initialize(name)
      @name = name
      @visible = true
    end
  end

  class Layers
    include Enumerable

    def initialize
      @list = [Layer.new('Layer0')]
    end

    def each(&block)
      @list.each(&block)
    end

    def [](key)
      key.is_a?(Integer) ? @list[key] : @list.find { |l| l.name == key }
    end

    def add(name)
      @list << Layer.new(name)
      @list.last
    end
  end

  class Entity
    attr_accessor :parent
    attr_reader :persistent_id

    @@next_id = 0

    def initialize
      @attrs = Hash.new { |h, k| h[k] = {} }
      @valid = true
      @@next_id += 1
      @persistent_id = @@next_id
    end

    def valid?
      @valid
    end

    def erase!
      guard!
      @valid = false
      parent.delete(self) if parent
      true
    end

    def get_attribute(dict, key, default = nil)
      guard!
      @attrs[dict].fetch(key, default)
    end

    def set_attribute(dict, key, value)
      guard!
      @attrs[dict][key] = value
    end

    def delete_attribute(dict, key = nil)
      guard!
      key ? @attrs[dict].delete(key) : @attrs.delete(dict)
    end

    def attribute_dictionaries
      nil
    end

    # Klon terpisah untuk menyalin isi definisi saat make_unique (atribut ikut tersalin).
    def fake_clone
      copy = self.class.new
      copy.layer = layer if respond_to?(:layer)
      @attrs.each { |dict, kv| kv.each { |k, v| copy.set_attribute(dict, k, v) } }
      copy
    end

    def attribute_dictionary(name)
      guard!
      @attrs.key?(name) && !@attrs[name].empty? ? @attrs[name] : nil
    end

    protected

    def guard!
      raise DeletedEntityError, 'reference to deleted Entity' unless @valid
    end
  end

  class Drawingelement < Entity
    attr_writer :hidden
    attr_accessor :material, :name
    attr_writer :layer

    def initialize
      super
      @hidden = false
      @name = ''
      @layer = nil
    end

    def layer
      guard!
      @layer ||= Sketchup.active_model.layers[0]
    end

    def hidden?
      guard!
      @hidden
    end
  end

  class Face < Drawingelement
    attr_accessor :back_material
  end
  class Edge < Drawingelement; end

  # Definisi dipakai bersama oleh Group/ComponentInstance. `solid` menggantikan ComponentDefinition#manifold?.
  class FakeDefinition
    attr_reader :entities, :instances
    attr_accessor :solid, :box

    def initialize(solid)
      @entities = Entities.new(self)
      @solid = solid
      @attrs = {}
      @instances = []
    end

    # Salinan definisi (isi dikloning sederhana: hanya atribut + solid; cukup untuk uji keunikan).
    def unshared_copy
      d = FakeDefinition.new(solid)
      d.box = box
      @attrs.each { |k, v| d.instance_variable_get(:@attrs)[k] = v.dup }
      entities.each { |e| d.entities << e.fake_clone }
      d
    end

    def set_attribute(dict, key, value)
      (@attrs[dict] ||= {})[key] = value
    end

    def attribute_dictionary(name)
      @attrs[name] && !@attrs[name].empty? ? @attrs[name] : nil
    end

    def manifold?
      @solid
    end
  end

  # Dasar Group & ComponentInstance. `box` = [min, max] di ruang lokal (isi), dipakai kalau tak punya anak.
  class Container < Drawingelement
    attr_accessor :transformation, :volume
    attr_reader :definition, :make_unique_calls

    def initialize(tx: Geom::Transformation.new, box: nil, solid: true, kids: [], definition: nil)
      super()
      @transformation = tx
      @box = box
      @definition = definition || FakeDefinition.new(solid)
      @definition.instances << self
      @definition.box ||= box
      @make_unique_calls = 0
      @volume = 1000.0
      kids.each { |k| @definition.entities << k }
    end

    # Group#make_unique / ComponentInstance#make_unique: definisi baru kalau dipakai bersama; mengembalikan self.
    def make_unique
      guard!
      @make_unique_calls += 1
      if @definition.instances.size > 1
        @definition.instances.delete(self)
        @definition = @definition.unshared_copy
        @definition.instances << self
      end
      self
    end

    def fake_clone
      copy = self.class.new(tx: @transformation, box: @box, solid: definition.solid)
      copy.definition.box = definition.box
      copy.layer = layer
      copy.hidden = @hidden
      copy.name = name
      @attrs.each { |dict, kv| kv.each { |k, v| copy.set_attribute(dict, k, v) } }
      definition.entities.each { |e| copy.definition.entities << e.fake_clone }
      copy
    end

    def bounds
      guard!
      inner = inner_box
      out = Geom::BoundingBox.new
      return out if inner.empty?

      corners(inner).each { |pt| out.add(pt.transform(@transformation)) }
      out
    end

    def hidden?
      guard!
      @hidden
    end

    private

    def inner_box
      box = @box || definition.box
      return Geom::BoundingBox.from(*box) if box

      acc = Geom::BoundingBox.new
      definition.entities.each do |e|
        next unless e.respond_to?(:bounds)

        b = e.bounds
        acc.add(b.min).add(b.max) unless b.empty?
      end
      acc
    end

    def corners(box)
      lo = box.min.to_a
      hi = box.max.to_a
      [lo[0], hi[0]].product([lo[1], hi[1]], [lo[2], hi[2]]).map { |x, y, z| Geom::Point3d.new(x, y, z) }
    end
  end

  class Group < Container
    def entities
      definition.entities
    end

    # Group#explode: isi dipindahkan ke entities induk, group dihapus.
    def explode
      guard!
      items = definition.entities.to_a
      items.each do |e|
        definition.entities.delete(e)
        parent << e
      end
      erase!
      items
    end

    # Group#copy: salinan terpisah (definisi sendiri) di entities yang sama.
    def copy
      guard!
      dup_group = Group.new(tx: transformation, box: @box, solid: definition.solid)
      parent << dup_group if parent # seperti SketchUp asli: tag dan material level-group tidak ikut tersalin
      dup_group
    end
  end

  class ComponentInstance < Container
  end

  class Material
    attr_accessor :name, :color, :alpha

    def initialize(name)
      @name = name
    end
  end

  class Materials
    def initialize
      @list = {}
    end

    def [](name)
      @list[name]
    end

    def add(name)
      @list[name] = Material.new(name)
    end
  end

  class Selection
    include Enumerable

    def initialize
      @items = []
    end

    def each(&block)
      @items.each(&block)
    end

    def clear
      @items.clear
    end

    def add(*ents)
      @items.concat(ents.flatten)
    end
  end

  class View
    attr_reader :model

    def initialize(model)
      @model = model
    end

    def add_observer(*); end
    def remove_observer(*); end
  end

  class Pages
    attr_accessor :selected_page
  end

  class Model
    attr_reader :active_entities, :layers, :materials, :operations, :selection

    def initialize
      @selection = Selection.new
      @active_entities = Entities.new
      @layers = Layers.new
      @materials = Materials.new
      @operations = []
      @attrs = {}
    end

    def valid?
      true
    end

    def active_path
      nil
    end

    def start_operation(name, *)
      @operations << [:start, name]
    end

    def commit_operation
      @operations << [:commit]
    end

    def abort_operation
      @operations << [:abort]
    end

    def add_observer(*); end
    def remove_observer(*); end

    def entities
      active_entities
    end

    def active_view
      @active_view ||= View.new(self)
    end

    def pages
      @pages ||= Pages.new
    end

    def get_attribute(dict, key, default = nil)
      (@attrs[dict] || {}).fetch(key, default)
    end

    def set_attribute(dict, key, value)
      (@attrs[dict] ||= {})[key] = value
    end

    def find_entity_by_persistent_id(pid)
      active_entities.find { |e| e.persistent_id == pid }
    end
  end

  @model = Model.new

  class << self
    attr_accessor :model

    def active_model
      @model
    end

    def reset_model!
      @model = Model.new
    end

    def require(_path)
      true
    end

    def add_observer(*); end
    def remove_observer(*); end
  end
end

module UI
  def self.start_timer(*)
    1
  end

  def self.stop_timer(*); end
end

module BoosokTools; end

def file_loaded(_file); end
