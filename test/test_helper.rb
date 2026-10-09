# Jalankan semua test:  ruby test/run_all.rb   (satu file: ruby test/void_test.rb)
$LOAD_PATH.unshift File.expand_path('support', __dir__) # 'require "sketchup"' diarahkan ke tiruan API
require 'minitest/autorun'
require 'minitest/mock'
require 'json'
require 'sketchup'

ROOT = File.expand_path('..', __dir__)
SRC = File.join(ROOT, 'src')
PLUGIN = File.join(SRC, 'boosok_tools')

# Bangun pohon entity tiruan dengan ringkas.
module Build
  include Sketchup

  def tx(x = 0, y = 0, z = 0)
    Geom::Transformation.translation(x, y, z)
  end

  # Group solid berbentuk kotak [min, max] di ruang lokal, dipasang dengan translasi (x, y, z).
  def solid_box(min = [0, 0, 0], max = [10, 10, 10], at: [0, 0, 0])
    Group.new(tx: tx(*at), box: [min, max], solid: true)
  end

  # Group non-solid berisi anak-anak.
  def plain(kids, at: [0, 0, 0])
    Group.new(tx: tx(*at), solid: false, kids: kids)
  end

  def void_box(min, max, at: [0, 0, 0])
    g = Group.new(tx: tx(*at), box: [min, max], solid: true)
    g.set_attribute('BoosokTools', 'void', true)
    g
  end

  def mark_role(ent, role, link = 'L1')
    ent.set_attribute('BoosokTools', 'void_role', role)
    ent.set_attribute('BoosokTools', 'void_link', link)
    ent
  end
end
