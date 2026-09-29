module BoosokTools::SelectTool5D
  class DrawHandler
    def initialize(tool)
      @tool = tool
    end

    def draw(view)
      return unless view && view.respond_to?(:vpwidth)

      draw_hud_instructions(view)
      draw_target_highlight(view)
      draw_floating_hierarchy_card(view)
    rescue => e
      warn "[5D Select Tool] Draw error: #{e.message}" if $DEBUG
    end

    private

    def draw_hud_instructions(view)
      center_x = view.vpwidth / 2
      bottom_y = view.vpheight - 60

      path = @tool.respond_to?(:valid_hover_path) ? @tool.valid_hover_path : @tool.hover_path
      is_hovering = path && !path.empty?

      # Judul
      view.draw_text(Geom::Point3d.new(center_x - 45, bottom_y, 0), "SELECT TOOL", 
                     color: Sketchup::Color.new(20, 100, 160), font: "Arial", size: 11, bold: true)

      # Subtitle 1 (Dynamic Empty State vs Hovering State)
      sub1 = if is_hovering
               "Klik untuk seleksi Level #{@tool.effective_depth} | Tahan klik & seret untuk geser"
             else
               "Arahkan kursor ke objek untuk inspeksi hierarki | Klik untuk seleksi"
             end
      view.draw_text(Geom::Point3d.new(center_x - 145, bottom_y + 16, 0), sub1, 
                     color: Sketchup::Color.new(80, 80, 80), font: "Arial", size: 10)

      # Subtitle 2 (Presistensi Level Indikator)
      sub2 = if @tool.target_depth > 0
               "[Level #{@tool.target_depth} Terpilih] | (Tahan) CTRL + Scroll: Ubah Level | ESC: Reset Level 0"
             else
               "(Tahan) CTRL + Scroll middle wheel: Ganti nested level | ESC: Reset Level 0"
             end
      view.draw_text(Geom::Point3d.new(center_x - 200, bottom_y + 32, 0), sub2, 
                     color: Sketchup::Color.new(140, 140, 140), font: "Arial", size: 9)
    rescue => e
      # Safe fallback: abaikan error teks instruksi
    end

    def draw_target_highlight(view)
      path = @tool.respond_to?(:valid_hover_path) ? @tool.valid_hover_path : @tool.hover_path
      return if path.nil? || path.empty?

      depth = @tool.effective_depth
      return if depth >= path.length

      target_entity = path[depth]
      return unless target_entity && target_entity.respond_to?(:valid?) && target_entity.valid?

      # Warna Pink / Magenta khas 5D Select Tool
      color_outline = Sketchup::Color.new(233, 30, 99)       # #e91e63
      color_fill    = Sketchup::Color.new(245, 175, 215, 60) # Soft pink transparan

      if target_entity.is_a?(Sketchup::Edge)
        parent_tr = parent_world_transform(path, depth)
        draw_edge_highlight(view, target_entity, parent_tr)

      elsif target_entity.is_a?(Sketchup::Face)
        parent_tr = parent_world_transform(path, depth)
        draw_face_highlight(view, target_entity, parent_tr, color_fill, color_outline)

      elsif target_entity.respond_to?(:definition) || target_entity.respond_to?(:bounds)
        corners = get_world_corners_for_container(path, depth)
        draw_bounding_box_highlight(view, corners, color_fill, color_outline) if corners
      end
    rescue => e
      warn "[5D Select Tool] Error during draw_target_highlight: #{e.message}" if $DEBUG
    end

    # Menghitung transformasi kumulatif dunia untuk container (Group / ComponentInstance)
    # dari root model sampai ke container pada index depth (inklusif)
    def container_world_transform(path, depth)
      tr = Geom::Transformation.new
      (0..depth).each do |i|
        ent = path[i]
        if ent && ent.respond_to?(:transformation) && ent.transformation
          tr = tr * ent.transformation
        end
      end
      tr
    rescue
      Geom::Transformation.new
    end

    # Menghitung transformasi kumulatif dunia untuk parent container dari suatu entitas (Face / Edge)
    # dari root model sampai ke index depth - 1
    def parent_world_transform(path, depth)
      tr = Geom::Transformation.new
      (0...depth).each do |i|
        ent = path[i]
        if ent && ent.respond_to?(:transformation) && ent.transformation
          tr = tr * ent.transformation
        end
      end
      tr
    rescue
      Geom::Transformation.new
    end

    # Menghitung 8 titik sudut bounding box dalam koordinat dunia (world coordinates)
    # untuk Group atau ComponentInstance di level kedalaman apapun
    def get_world_corners_for_container(path, depth)
      target_entity = path[depth]
      return nil unless target_entity

      # 1. Coba ambil local bounding box yang belum tertransformasi
      local_bb = nil
      if target_entity.respond_to?(:local_bounds) && target_entity.local_bounds
        local_bb = target_entity.local_bounds
      elsif target_entity.respond_to?(:definition) && target_entity.definition && target_entity.definition.respond_to?(:bounds)
        local_bb = target_entity.definition.bounds
      end

      if local_bb
        # Transformasikan seluruh sudut local_bb menggunakan world transform instance ini
        tr = container_world_transform(path, depth)
        return (0..7).map { |i| local_bb.corner(i).transform(tr) }
      end

      # 2. Fallback: target_entity.bounds (koordinat relatif terhadap parent container)
      if target_entity.respond_to?(:bounds) && target_entity.bounds
        parent_tr = parent_world_transform(path, depth)
        return (0..7).map { |i| target_entity.bounds.corner(i).transform(parent_tr) }
      end

      nil
    rescue
      nil
    end

    # Menggambar highlight bounding box 3D untuk Group / Component
    def draw_bounding_box_highlight(view, corners, color_fill, color_outline)
      return unless corners && corners.length == 8

      # 6 bidang bounding box untuk fill transparan
      faces = [
        [corners[0], corners[1], corners[3], corners[2]], # Bawah
        [corners[4], corners[5], corners[7], corners[6]], # Atas
        [corners[0], corners[1], corners[5], corners[4]], # Depan
        [corners[1], corners[3], corners[7], corners[5]], # Kanan
        [corners[3], corners[2], corners[6], corners[7]], # Belakang
        [corners[2], corners[0], corners[4], corners[6]]  # Kiri
      ]

      # 1. Fill transparan setiap sisi bounding box
      view.drawing_color = color_fill
      faces.each do |quad_pts|
        view.draw(GL_POLYGON, quad_pts)
      end

      # 2. Garis tepi bounding box (wireframe pink solid tebal)
      view.drawing_color = color_outline
      view.line_width = 2.5
      view.line_stipple = ""

      points = [
        corners[0], corners[1], corners[1], corners[3],
        corners[3], corners[2], corners[2], corners[0],
        corners[4], corners[5], corners[5], corners[7],
        corners[7], corners[6], corners[6], corners[4],
        corners[0], corners[4], corners[1], corners[5],
        corners[2], corners[6], corners[3], corners[7]
      ]
      view.draw(GL_LINES, points)
    rescue => e
      warn "[5D Select Tool] Error drawing bbox highlight: #{e.message}" if $DEBUG
    end

    # Menggambar highlight untuk Face dengan triangulasi dan offset anti Z-fighting
    def draw_face_highlight(view, face, world_tr, color_fill, color_outline)
      return unless face && face.respond_to?(:valid?) && face.valid?

      # Vektor offset ke arah kamera/mata pengamat agar tidak terjadi z-fighting dengan bidang SketchUp
      cam_eye = view.camera.eye rescue nil
      normal = (face.normal.transform(world_tr).normalize rescue nil)

      offset_vec = Geom::Vector3d.new(0, 0, 0)
      if normal && normal.respond_to?(:valid?) && normal.valid?
        if cam_eye
          sample_pt = (face.vertices.first.position.transform(world_tr) rescue Geom::Point3d.new(0, 0, 0))
          view_dir = cam_eye - sample_pt
          normal.reverse! if (view_dir % normal) < 0 rescue nil
        end
        offset_vec = normal
        offset_vec.length = 0.02 rescue nil # offset ~0.5 mm ke arah kamera
      end

      # 1. Fill Permukaan Menggunakan Triangulasi (PolygonMesh) agar mendukung bidang concave / lubang
      mesh_pts = []
      begin
        mesh = face.mesh
        if mesh && mesh.respond_to?(:count_polygons) && mesh.count_polygons > 0
          (1..mesh.count_polygons).each do |i|
            pts = mesh.polygon_points_at(i)
            pts.each do |pt|
              mesh_pts << (pt.transform(world_tr) + offset_vec)
            end
          end
        end
      rescue
        mesh_pts = []
      end

      # Fallback jika mesh gagal atau kosong: gunakan outer_loop
      if mesh_pts.empty? && face.respond_to?(:outer_loop) && face.outer_loop
        outer_pts = face.outer_loop.vertices.map { |v| (v.position.transform(world_tr) + offset_vec) }
        view.drawing_color = color_fill
        view.draw(GL_POLYGON, outer_pts)
      elsif !mesh_pts.empty?
        view.drawing_color = color_fill
        view.draw(GL_TRIANGLES, mesh_pts)
      end

      # 2. Garis Tepi (Edges & Loops) Tebal dan Tegas Berwarna Pink Solid
      view.drawing_color = color_outline
      view.line_width = 3
      view.line_stipple = ""

      loops = face.respond_to?(:loops) ? face.loops : [face.outer_loop]
      loops.each do |lp|
        next unless lp && lp.respond_to?(:vertices)
        loop_pts = lp.vertices.map { |v| (v.position.transform(world_tr) + offset_vec) }
        view.draw(GL_LINE_LOOP, loop_pts)
      end
    rescue => e
      warn "[5D Select Tool] Error drawing face highlight: #{e.message}" if $DEBUG
    end

    # Menggambar highlight garis Edge tebal orange
    def draw_edge_highlight(view, edge, world_tr)
      pts = edge.vertices.map { |v| v.position.transform(world_tr) }
      view.drawing_color = Sketchup::Color.new(255, 153, 0)
      view.line_width = 4
      view.line_stipple = ""
      view.draw(GL_LINES, pts)
    rescue => e
      warn "[5D Select Tool] Error drawing edge highlight: #{e.message}" if $DEBUG
    end

    # Menggambar Card Info Hirarki Mengambang di Viewport Persis Seperti Gambar
    def draw_floating_hierarchy_card(view)
      path = @tool.respond_to?(:valid_hover_path) ? @tool.valid_hover_path : @tool.hover_path
      return if path.nil? || path.empty?
      return unless @tool.cursor_x && @tool.cursor_y

      # Ekstrak data hierarki dari hover_path
      rows = path.each_with_index.map do |entity, idx|
        next unless entity && entity.respond_to?(:valid?) && entity.valid?
        type = entity.typename rescue "Entity"
        name = if entity.respond_to?(:name) && !entity.name.empty?
                 entity.name
               elsif entity.is_a?(Sketchup::Group)
                 "Group##{entity.entityID rescue ''}"
               elsif entity.respond_to?(:definition) && !entity.definition.name.empty?
                 entity.definition.name
               else
                 type
               end
        tag = (entity.respond_to?(:layer) && entity.layer && !entity.layer.name.empty?) ? entity.layer.name : "Untagged"
        icon = if entity.is_a?(Sketchup::ComponentInstance)
                 :component
               elsif entity.is_a?(Sketchup::Group)
                 :group
               elsif entity.is_a?(Sketchup::Face)
                 :face
               elsif entity.is_a?(Sketchup::Edge)
                 :edge
               else
                 :default
               end
        { level: idx, name: name, tag: tag, icon: icon }
      end.compact

      return if rows.empty?

      row_h = 32
      pad = 5
      card_w = 175
      card_h = pad * 2 + rows.length * row_h
      active_lvl = @tool.effective_depth

      # Posisi badge lingkaran dekat kursor (di bawah-kanan ujung panah kursor)
      badge_r = 11.0
      badge_cx = @tool.cursor_x + 20
      badge_cy = @tool.cursor_y + 16

      # Kartu diposisikan di sebelah kanan badge, dengan baris aktif sejajar vertikal dengan badge
      card_x = badge_cx + badge_r + 8
      card_y = badge_cy - (pad + active_lvl * row_h + row_h / 2)

      # Mencegah kartu keluar dari viewport layar
      if card_x + card_w > view.vpwidth - 15
        card_x = @tool.cursor_x - card_w - 25
      end
      card_y = [[card_y, 10].max, view.vpheight - card_h - 60].min

      # 1. Bayangan kartu (Drop shadow)
      view.drawing_color = Sketchup::Color.new(0, 0, 0, 22)
      draw_rounded_rect(view, card_x + 2, card_y + 2, card_w, card_h, 7, fill: true)

      # 2. Background kartu putih lembut
      view.drawing_color = Sketchup::Color.new(246, 248, 252)
      draw_rounded_rect(view, card_x, card_y, card_w, card_h, 7, fill: true)

      # 3. Border kartu
      view.drawing_color = Sketchup::Color.new(210, 220, 230)
      view.line_width = 1
      view.line_stipple = ""
      draw_rounded_rect(view, card_x, card_y, card_w, card_h, 7, fill: false)

      # 4. Badge Lingkaran Kursor
      draw_cursor_circle(view, badge_cx, badge_cy, badge_r, active_lvl)

      # 5. Gambar Setiap Baris Hierarki
      rows.each_with_index do |item, idx|
        ry = card_y + pad + idx * row_h
        rw = card_w - pad * 2
        rh = row_h - 2
        is_active = (idx == active_lvl)

        if is_active
          # Baris aktif: Biru Solid (#0088cc)
          view.drawing_color = Sketchup::Color.new(0, 136, 204)
          draw_rounded_rect(view, card_x + pad, ry, rw, rh, 5, fill: true)

          # Panah segitiga biru yang menyambungkan baris aktif ke badge kursor
          tri_pts = [
            Geom::Point3d.new(card_x - 5, ry + rh / 2, 0),
            Geom::Point3d.new(card_x + pad, ry + rh / 2 - 5, 0),
            Geom::Point3d.new(card_x + pad, ry + rh / 2 + 5, 0)
          ]
          view.drawing_color = Sketchup::Color.new(0, 136, 204)
          view.draw2d(GL_POLYGON, tri_pts)

          title_color = Sketchup::Color.new(255, 255, 255)
          tag_color   = Sketchup::Color.new(230, 245, 255)
        else
          title_color = Sketchup::Color.new(30, 41, 59)
          tag_color   = Sketchup::Color.new(100, 116, 139)
        end

        # Badge nomor level di dalam baris
        r_badge_cx = card_x + pad + 13
        r_badge_cy = ry + rh / 2
        r_badge_r  = 8.5
        r_badge_pts = (0...16).map do |i|
          a = i * 2 * Math::PI / 16
          Geom::Point3d.new(r_badge_cx + r_badge_r * Math.cos(a), r_badge_cy + r_badge_r * Math.sin(a), 0)
        end

        if is_active
          view.drawing_color = Sketchup::Color.new(41, 182, 246) # Cyan cerah
        elsif idx == 0
          view.drawing_color = Sketchup::Color.new(100, 133, 194)
        elsif idx == 1
          view.drawing_color = Sketchup::Color.new(2, 136, 209)
        elsif idx == 2
          view.drawing_color = Sketchup::Color.new(38, 166, 154)
        else
          view.drawing_color = Sketchup::Color.new(239, 108, 0)
        end
        view.draw2d(GL_POLYGON, r_badge_pts)

        # Angka di dalam badge baris
        num_str = idx.to_s
        nx_off = num_str.length > 1 ? -5 : -3
        view.draw_text(Geom::Point3d.new(r_badge_cx + nx_off, r_badge_cy - 6, 0), num_str, 
                       color: Sketchup::Color.new(255, 255, 255), size: 8, bold: true, font: "Arial")

        # Teks Nama & Tag
        tx = card_x + pad + 27
        disp_name = item[:name].length > 17 ? "#{item[:name][0...15]}.." : item[:name]
        disp_tag  = item[:tag].length > 20 ? "#{item[:tag][0...18]}.." : item[:tag]
        view.draw_text(Geom::Point3d.new(tx, ry + 2, 0), disp_name, color: title_color, size: 9, bold: true, font: "Arial")
        view.draw_text(Geom::Point3d.new(tx, ry + 15, 0), disp_tag, color: tag_color, size: 8, bold: false, font: "Arial")

        # Ikon di sisi kanan baris
        icon_cx = card_x + card_w - pad - 14
        icon_cy = ry + rh / 2
        icon_color = is_active ? Sketchup::Color.new(255, 255, 255) : Sketchup::Color.new(120, 140, 160)
        draw_row_icon(view, item[:icon], icon_cx, icon_cy, icon_color)
      end
    end

    def draw_cursor_circle(view, cx, cy, r, active_lvl)
      segments = 24
      badge_pts = (0...segments).map do |i|
        a = i * 2 * Math::PI / segments
        Geom::Point3d.new(cx + r * Math.cos(a), cy + r * Math.sin(a), 0)
      end

      if active_lvl == 0
        # Level 0: Lingkaran putih dengan border tipis (seperti gambar-1)
        view.drawing_color = Sketchup::Color.new(255, 255, 255)
        view.draw2d(GL_POLYGON, badge_pts)
        view.drawing_color = Sketchup::Color.new(80, 90, 100)
        view.line_width = 1.2
        view.line_stipple = ""
        view.draw2d(GL_LINE_LOOP, badge_pts)
        num_color = Sketchup::Color.new(30, 40, 50)
      else
        # Level 1+: Lingkaran Pink Magenta cerah (#e91e63) (seperti gambar-2, 3, 4)
        view.drawing_color = Sketchup::Color.new(233, 30, 99)
        view.draw2d(GL_POLYGON, badge_pts)
        view.drawing_color = Sketchup::Color.new(255, 255, 255, 220)
        view.line_width = 1.2
        view.line_stipple = ""
        view.draw2d(GL_LINE_LOOP, badge_pts)
        num_color = Sketchup::Color.new(255, 255, 255)
      end

      text = active_lvl.to_s
      x_off = text.length > 1 ? -6 : -4
      view.draw_text(Geom::Point3d.new(cx + x_off, cy - 7, 0), text, color: num_color, size: 9, bold: true, font: "Arial")
    end

    def draw_rounded_rect(view, x, y, w, h, r, fill: true)
      pts = []
      segments = 6
      # Top-Right
      (0..segments).each do |i|
        a = -Math::PI / 2 + i * (Math::PI / 2) / segments
        pts << Geom::Point3d.new(x + w - r + r * Math.cos(a), y + r + r * Math.sin(a), 0)
      end
      # Bottom-Right
      (0..segments).each do |i|
        a = 0 + i * (Math::PI / 2) / segments
        pts << Geom::Point3d.new(x + w - r + r * Math.cos(a), y + h - r + r * Math.sin(a), 0)
      end
      # Bottom-Left
      (0..segments).each do |i|
        a = Math::PI / 2 + i * (Math::PI / 2) / segments
        pts << Geom::Point3d.new(x + r + r * Math.cos(a), y + h - r + r * Math.sin(a), 0)
      end
      # Top-Left
      (0..segments).each do |i|
        a = Math::PI + i * (Math::PI / 2) / segments
        pts << Geom::Point3d.new(x + r + r * Math.cos(a), y + r + r * Math.sin(a), 0)
      end

      if fill
        view.draw2d(GL_POLYGON, pts)
      else
        view.draw2d(GL_LINE_LOOP, pts)
      end
    end

    def draw_row_icon(view, icon_type, cx, cy, color)
      view.drawing_color = color
      view.line_width = 1.4
      view.line_stipple = ""

      case icon_type
      when :component # 3D cube
        s = 6.0
        pts = [
          Geom::Point3d.new(cx - s, cy - s + 3, 0), Geom::Point3d.new(cx, cy - s - 1, 0),
          Geom::Point3d.new(cx, cy - s - 1, 0), Geom::Point3d.new(cx + s, cy - s + 3, 0),
          Geom::Point3d.new(cx + s, cy - s + 3, 0), Geom::Point3d.new(cx, cy + 1, 0),
          Geom::Point3d.new(cx, cy + 1, 0), Geom::Point3d.new(cx - s, cy - s + 3, 0),

          Geom::Point3d.new(cx - s, cy - s + 3, 0), Geom::Point3d.new(cx - s, cy + s - 1, 0),
          Geom::Point3d.new(cx, cy + 1, 0), Geom::Point3d.new(cx, cy + s + 3, 0),
          Geom::Point3d.new(cx + s, cy - s + 3, 0), Geom::Point3d.new(cx + s, cy + s - 1, 0),

          Geom::Point3d.new(cx - s, cy + s - 1, 0), Geom::Point3d.new(cx, cy + s + 3, 0),
          Geom::Point3d.new(cx, cy + s + 3, 0), Geom::Point3d.new(cx + s, cy + s - 1, 0)
        ]
        view.draw2d(GL_LINES, pts)

      when :group # Box dengan corner brackets
        s = 6.0
        box_pts = [
          Geom::Point3d.new(cx - s + 2, cy - s + 2, 0), Geom::Point3d.new(cx + s - 2, cy - s + 2, 0),
          Geom::Point3d.new(cx + s - 2, cy + s - 2, 0), Geom::Point3d.new(cx - s + 2, cy + s - 2, 0)
        ]
        view.draw2d(GL_LINE_LOOP, box_pts)

        brackets = [
          Geom::Point3d.new(cx - s, cy - s + 3, 0), Geom::Point3d.new(cx - s, cy - s, 0),
          Geom::Point3d.new(cx - s, cy - s, 0), Geom::Point3d.new(cx - s + 3, cy - s, 0),

          Geom::Point3d.new(cx + s - 3, cy - s, 0), Geom::Point3d.new(cx + s, cy - s, 0),
          Geom::Point3d.new(cx + s, cy - s, 0), Geom::Point3d.new(cx + s, cy - s + 3, 0),

          Geom::Point3d.new(cx - s, cy + s - 3, 0), Geom::Point3d.new(cx - s, cy + s, 0),
          Geom::Point3d.new(cx - s, cy + s, 0), Geom::Point3d.new(cx - s + 3, cy + s, 0),

          Geom::Point3d.new(cx + s - 3, cy + s, 0), Geom::Point3d.new(cx + s, cy + s, 0),
          Geom::Point3d.new(cx + s, cy + s, 0), Geom::Point3d.new(cx + s, cy + s - 3, 0)
        ]
        view.draw2d(GL_LINES, brackets)

      when :face # Tilted parallelogram
        s = 6.0
        pts = [
          Geom::Point3d.new(cx - s + 3, cy - s + 1, 0),
          Geom::Point3d.new(cx + s, cy - s + 1, 0),
          Geom::Point3d.new(cx + s - 3, cy + s - 1, 0),
          Geom::Point3d.new(cx - s, cy + s - 1, 0)
        ]
        view.draw2d(GL_LINE_LOOP, pts)

      when :edge # Line with endpoints
        s = 6.0
        view.draw2d(GL_LINES, [Geom::Point3d.new(cx - s + 1, cy + s - 1, 0), Geom::Point3d.new(cx + s - 1, cy - s + 1, 0)])
        p1 = (0...8).map { |i| Geom::Point3d.new(cx - s + 1 + 1.5 * Math.cos(i*Math::PI/4), cy + s - 1 + 1.5 * Math.sin(i*Math::PI/4), 0) }
        p2 = (0...8).map { |i| Geom::Point3d.new(cx + s - 1 + 1.5 * Math.cos(i*Math::PI/4), cy - s + 1 + 1.5 * Math.sin(i*Math::PI/4), 0) }
        view.draw2d(GL_POLYGON, p1)
        view.draw2d(GL_POLYGON, p2)

      else
        s = 5.0
        pts = [
          Geom::Point3d.new(cx - s, cy - s, 0), Geom::Point3d.new(cx + s, cy - s, 0),
          Geom::Point3d.new(cx + s, cy + s, 0), Geom::Point3d.new(cx - s, cy + s, 0)
        ]
        view.draw2d(GL_LINE_LOOP, pts)
      end
    end
  end
end
