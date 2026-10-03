module BoosokTools::SelectTool
  # Seleksi area: tahan klik kiri lalu seret membentuk kotak (seperti Select bawaan SketchUp).
  #   Seret ke KANAN  → Window   : hanya yang seluruhnya berada di dalam kotak (garis kotak utuh)
  #   Seret ke KIRI   → Crossing : semua yang tersentuh kotak (garis kotak putus-putus)
  # Ctrl = tambah ke seleksi, Shift = toggle, tanpa modifier = ganti seleksi. Klik tanpa seret tetap seleksi level biasa.
  class AreaHandler
    DRAG_PX = 5 unless defined?(DRAG_PX) # geseran minimum (px) sebelum dianggap seret

    attr_reader :down_flags

    def initialize(tool)
      @tool = tool
      reset
    end

    def reset
      @start = nil
      @cur = nil
      @dragging = false
      @down_flags = 0
    end

    def pressed?
      !@start.nil?
    end

    def dragging?
      @dragging
    end

    def press(x, y, flags)
      @start = [x, y]
      @cur = [x, y]
      @dragging = false
      @down_flags = flags
    end

    # Hasil: true kalau sedang menyeret kotak
    def move(x, y)
      return false unless @start

      @cur = [x, y]
      @dragging = true if !@dragging && Math.hypot(x - @start[0], y - @start[1]) >= DRAG_PX
      @dragging
    end

    def window?
      @cur[0] >= @start[0]
    end

    def rect
      [[@start[0], @cur[0]].min, [@start[1], @cur[1]].min, [@start[0], @cur[0]].max, [@start[1], @cur[1]].max]
    end

    # ── Gambar kotak seleksi (koordinat layar) ──────────────────────────────

    def draw(view)
      return unless @dragging && @start

      x1, y1, x2, y2 = rect
      pts = [[x1, y1], [x2, y1], [x2, y2], [x1, y2]].map { |x, y| Geom::Point3d.new(x, y, 0) }
      color = window? ? Sketchup::Color.new(0, 120, 255) : Sketchup::Color.new(0, 190, 110)
      fill = Sketchup::Color.new(color.red, color.green, color.blue, 40)
      view.drawing_color = fill
      view.draw2d(GL_QUADS, pts)
      view.drawing_color = color
      view.line_width = 1
      view.line_stipple = window? ? '' : '-'
      view.draw2d(GL_LINE_LOOP, pts)
      view.line_stipple = ''
    rescue StandardError
      nil
    end

    # ── Seleksi ─────────────────────────────────────────────────────────────

    def select_area(view, flags)
      model = Sketchup.active_model
      return 0 unless model

      area = rect
      window = window?
      tr = model.edit_transform
      matched = model.active_entities.select do |e|
        e.is_a?(Sketchup::Drawingelement) && e.visible? && hit?(view, tr, e, area, window)
      end

      selection = model.selection
      ctrl = @tool.ctrl_pressed || (defined?(COPY_MODIFIER_MASK) && (flags & COPY_MODIFIER_MASK) == COPY_MODIFIER_MASK)
      shift = defined?(CONSTRAIN_MODIFIER_MASK) && (flags & CONSTRAIN_MODIFIER_MASK) == CONSTRAIN_MODIFIER_MASK
      selection.clear unless ctrl || shift
      if shift
        matched.each { |e| selection.toggle(e) }
      else
        selection.add(matched)
      end
      matched.size
    rescue StandardError => e
      warn "[Select Tool] Error select_area: #{e.message}" if $DEBUG
      0
    end

    private

    def screen_xy(view, tr, pt)
      sp = view.screen_coords(tr * pt)
      [sp.x, sp.y]
    end

    def inside?(pt, r)
      pt[0] >= r[0] && pt[0] <= r[2] && pt[1] >= r[1] && pt[1] <= r[3]
    end

    def hit?(view, tr, ent, r, window)
      case ent
      when Sketchup::Edge
        a = screen_xy(view, tr, ent.start.position)
        b = screen_xy(view, tr, ent.end.position)
        window ? (inside?(a, r) && inside?(b, r)) : segment_hits_rect?(a, b, r)
      when Sketchup::Face
        pts = ent.outer_loop.vertices.map { |v| screen_xy(view, tr, v.position) }
        window ? pts.all? { |p| inside?(p, r) } : polygon_hits_rect?(pts, r)
      else
        box_hits?(view, tr, ent, r, window)
      end
    end

    # Group/component/lainnya: kotak pembatasnya diproyeksikan ke layar
    def box_hits?(view, tr, ent, r, window)
      box = ent.bounds
      return false if box.empty?

      pts = (0..7).map { |i| screen_xy(view, tr, box.corner(i)) }
      xs = pts.map(&:first)
      ys = pts.map(&:last)
      er = [xs.min, ys.min, xs.max, ys.max]
      if window
        er[0] >= r[0] && er[1] >= r[1] && er[2] <= r[2] && er[3] <= r[3]
      else
        er[0] <= r[2] && er[2] >= r[0] && er[1] <= r[3] && er[3] >= r[1]
      end
    end

    # Liang–Barsky: apakah segmen a-b memotong / berada di dalam kotak r
    def segment_hits_rect?(a, b, r)
      dx = b[0] - a[0]
      dy = b[1] - a[1]
      t0 = 0.0
      t1 = 1.0
      [[-dx, a[0] - r[0]], [dx, r[2] - a[0]], [-dy, a[1] - r[1]], [dy, r[3] - a[1]]].each do |p, q|
        if p.zero?
          return false if q.negative?
        else
          t = q / p.to_f
          if p.negative?
            return false if t > t1

            t0 = t if t > t0
          else
            return false if t < t0

            t1 = t if t < t1
          end
        end
      end
      true
    end

    def polygon_hits_rect?(pts, r)
      return true if pts.any? { |p| inside?(p, r) }

      pts.each_with_index do |p, i|
        return true if segment_hits_rect?(p, pts[(i + 1) % pts.size], r)
      end
      # kotak seluruhnya di dalam face: salah satu sudutnya berada di dalam poligon
      point_in_polygon?([r[0], r[1]], pts)
    end

    def point_in_polygon?(pt, poly)
      inside = false
      j = poly.size - 1
      poly.each_with_index do |pi, i|
        pj = poly[j]
        if ((pi[1] > pt[1]) != (pj[1] > pt[1])) &&
           (pt[0] < ((pj[0] - pi[0]) * (pt[1] - pi[1]) / (pj[1] - pi[1])) + pi[0])
          inside = !inside
        end
        j = i
      end
      inside
    end
  end
end
