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
      warn "[Select Tool] Draw error: #{e.message}" if $DEBUG
    end

    private

    def draw_centered_text(view, y, text, size: 10, bold: false, color: nil)
      return if text.nil? || text.empty?

      # Estimasi lebar piksel karakter font Segoe UI
      char_w = case size
               when 12 then bold ? 8.2 : 7.0
               when 10 then bold ? 6.8 : 5.8
               when 9  then bold ? 6.0 : 5.0
               else 5.5
               end
      text_w = text.length * char_w
      x = (view.vpwidth - text_w) / 2.0 
      view.draw_text(Geom::Point3d.new(x, y, 0), text, color: color, font: "Segoe UI", size: size, bold: bold)
    end

    def draw_hud_instructions(view)
      bottom_y = view.vpheight - 70

      path = @tool.respond_to?(:valid_hover_path) ? @tool.valid_hover_path : @tool.hover_path
      is_hovering = path && !path.empty?

      # Judul Center Sempurna
      draw_centered_text(view, bottom_y, "SELECT TOOL", size: 12, bold: true, color: Sketchup::Color.new(24, 24, 27))

      # Subtitle 1 Center Sempurna
      sub1 = if is_hovering
               "Klik untuk seleksi Level | Tahan klik & seret untuk geser"
             else
               "ESC : Exit"
             end
      draw_centered_text(view, bottom_y + 18, sub1, size: 10, bold: false, color: Sketchup::Color.new(70, 70, 75))

      # Subtitle 2 Center Sempurna
      sub2 = if is_hovering
               "(Tahan) CTRL + Scroll: Untuk ubah kedalaman Level grup | ESC: Exit"
             end
      draw_centered_text(view, bottom_y + 35, sub2, size: 9, bold: false, color: Sketchup::Color.new(120, 120, 130))
    rescue
      # Safe fallback
    end

    def draw_target_highlight(view)
      path = @tool.respond_to?(:valid_hover_path) ? @tool.valid_hover_path : @tool.hover_path
      return if path.nil? || path.empty?

      depth = @tool.effective_depth
      return if depth >= path.length

      target_entity = path[depth]
      return unless target_entity && target_entity.respond_to?(:valid?) && target_entity.valid?

      # Skip jika kursor mengarah ke Axes
      return if defined?(Sketchup::Axes) && target_entity.is_a?(Sketchup::Axes)
      return if target_entity.respond_to?(:typename) && target_entity.typename.to_s.downcase.include?('axes')

      # Warna highlight tema Boosok Tools
      color_outline = Sketchup::Color.new(24, 24, 27)         # #18181b dark
      color_fill    = Sketchup::Color.new(24, 24, 27, 40)     # Dark transparan

      if target_entity.is_a?(Sketchup::Edge)
        parent_tr = parent_world_transform(path, depth)
        draw_edge_highlight(view, target_entity, parent_tr)

      elsif target_entity.is_a?(Sketchup::Face)
        parent_tr = parent_world_transform(path, depth)
        draw_face_highlight(view, target_entity, parent_tr, color_fill)

      elsif target_entity.respond_to?(:definition) || target_entity.respond_to?(:bounds)
        corners = get_world_corners_for_container(path, depth)
        draw_bounding_box_highlight(view, corners, color_fill, color_outline) if corners
      end
    rescue => e
      warn "[Select Tool] Error during draw_target_highlight: #{e.message}" if $DEBUG
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
      view.line_width = 3.5
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
      warn "[Select Tool] Error drawing bbox highlight: #{e.message}" if $DEBUG
    end

    # Menggambar highlight untuk Face: Hanya fill permukaan tanpa border outline (persis Gambar 3)
    def draw_face_highlight(view, face, world_tr, color_fill)
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

      # 1. Fill Permukaan Menggunakan Triangulasi (PolygonMesh)
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

      # Fill Permukaan Transparan Pink Bersih Tanpa Garis Tepi
      if mesh_pts.empty? && face.respond_to?(:outer_loop) && face.outer_loop
        outer_pts = face.outer_loop.vertices.map { |v| (v.position.transform(world_tr) + offset_vec) }
        view.drawing_color = color_fill
        view.draw(GL_POLYGON, outer_pts)
      elsif !mesh_pts.empty?
        view.drawing_color = color_fill
        view.draw(GL_TRIANGLES, mesh_pts)
      end
    rescue => e
      warn "[Select Tool] Error drawing face highlight: #{e.message}" if $DEBUG
    end

    # Menggambar highlight garis Edge tebal orange
    def draw_edge_highlight(view, edge, world_tr)
      pts = edge.vertices.map { |v| v.position.transform(world_tr) }
      view.drawing_color = Sketchup::Color.new(255, 153, 0)
      view.line_width = 5
      view.line_stipple = ""
      view.draw(GL_LINES, pts)
    rescue => e
      warn "[Select Tool] Error drawing edge highlight: #{e.message}" if $DEBUG
    end

    # Menggambar Card Info Hirarki Mengambang di Viewport Persis Seperti Gambar
    def draw_floating_hierarchy_card(view)
      path = @tool.respond_to?(:valid_hover_path) ? @tool.valid_hover_path : @tool.hover_path
      return if path.nil? || path.empty?
      return unless @tool.cursor_x && @tool.cursor_y

      # Skip jika kursor mengarah ke Axes (Sumbu Koordinat)
      return if path.any? { |e| (defined?(Sketchup::Axes) && e.is_a?(Sketchup::Axes)) || (e.respond_to?(:typename) && e.typename.to_s.downcase.include?('axes')) }

      # Ekstrak data hierarki dari hover_path
      rows = path.each_with_index.map do |entity, idx|
        next unless entity && entity.respond_to?(:valid?) && entity.valid?
        next if defined?(Sketchup::Axes) && entity.is_a?(Sketchup::Axes)
        next if entity.respond_to?(:typename) && entity.typename.to_s.downcase.include?('axes')

        type = entity.typename rescue "Entity"
        # Nama Group/Component dibuat berurutan dengan hashtag # dimulai dari 1 dan seterusnya per level
        name = if entity.respond_to?(:name) && !entity.name.empty?
                 entity.name
               elsif entity.is_a?(Sketchup::Group)
                 "Group##{idx + 1}"
               elsif entity.is_a?(Sketchup::ComponentInstance)
                 (entity.definition && !entity.definition.name.empty?) ? entity.definition.name : "Component##{idx + 1}"
               else
                 type
               end

        # Layer0 otomatis diubah menjadi "Untagged"
        raw_tag = (entity.respond_to?(:layer) && entity.layer && !entity.layer.name.empty?) ? entity.layer.name : "Untagged"
        tag = (raw_tag.nil? || raw_tag.empty? || raw_tag.casecmp("Layer0") == 0) ? "Untagged" : raw_tag

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

      row_h   = 36
      row_gap = 4
      pad     = 7
      card_w  = 186
      card_h  = pad * 2 + rows.length * row_h + (rows.length - 1) * row_gap
      active_lvl = @tool.effective_depth
      corner_r   = 8.0

      # 1. Posisi badge lingkaran presisi di bawah kursor (Persis Gambar 2, 3, 4):
      # Jarak lega dan nyaman di bawah panah mouse dan tanda plus, tidak tertindih atau mepet
      badge_r  = 11.5
      badge_cx = @tool.cursor_x + 6.5
      badge_cy = @tool.cursor_y + 35

      # 2. Deteksi Arah & Batas Layar (Viewport Safe Boundaries)
      margin_top    = 10
      margin_bottom = 5
      margin_left   = 10
      margin_right  = 15

      # Deteksi tema dark/light dari preferensi Boosok Tools
      theme_val = Sketchup.read_default("BoosokTools", "theme", "").to_s rescue ""
      is_dark = (theme_val == "dark")

      # Palet warna tema card
      if is_dark
        card_bg       = Sketchup::Color.new(30, 30, 34)      # --surface dark (#1e1e22)
        card_border   = Sketchup::Color.new(46, 46, 52)      # --line dark (#2e2e34)
        card_shadow   = Sketchup::Color.new(0, 0, 0, 60)
        row_active_bg = Sketchup::Color.new(244, 244, 246)   # terang saat dark mode
        row_active_title = Sketchup::Color.new(24, 24, 27)   # hitam untuk kontras
        row_active_tag   = Sketchup::Color.new(80, 80, 90)
        row_active_icon  = Sketchup::Color.new(24, 24, 27)
        row_inactive_bg  = Sketchup::Color.new(40, 40, 46)   # gray gelap
        row_inactive_border = Sketchup::Color.new(60, 60, 68)
        row_inactive_title  = Sketchup::Color.new(200, 200, 210) # teks terang
        row_inactive_tag    = Sketchup::Color.new(130, 130, 145)
        row_inactive_icon   = Sketchup::Color.new(130, 130, 145)
      else
        card_bg       = Sketchup::Color.new(247, 247, 248)   # --bg light (#f7f7f8)
        card_border   = Sketchup::Color.new(230, 230, 233)   # --line light (#e6e6e9)
        card_shadow   = Sketchup::Color.new(24, 24, 27, 22)
        row_active_bg = Sketchup::Color.new(24, 24, 27)      # --ink hitam elegan
        row_active_title = Sketchup::Color.new(255, 255, 255)
        row_active_tag   = Sketchup::Color.new(180, 180, 185)
        row_active_icon  = Sketchup::Color.new(255, 255, 255)
        row_inactive_bg  = Sketchup::Color.new(238, 238, 241) # gray muda
        row_inactive_border = Sketchup::Color.new(222, 222, 226)
        row_inactive_title  = Sketchup::Color.new(24, 24, 27)  # --ink
        row_inactive_tag    = Sketchup::Color.new(113, 113, 122) # --muted
        row_inactive_icon   = Sketchup::Color.new(113, 113, 122)
      end

      # Horizontal: Posisi card dihitung setelah beak (triangle) + gap
      beak_gap   = 6.0   # space antara tepi lingkaran dan ujung segitiga
      beak_depth = 10.0  # kedalaman/panjang horizontal segitiga

      right_beak_tip_x = badge_cx + badge_r + beak_gap
      right_card_x     = right_beak_tip_x + beak_depth
      if right_card_x + card_w <= view.vpwidth - margin_right
        is_flipped   = false
        beak_tip_x_h = right_beak_tip_x
        card_x       = right_card_x
      else
        # Flip ke kiri: card di sebelah kiri lingkaran
        is_flipped   = true
        beak_tip_x_h = badge_cx - badge_r - beak_gap
        card_x       = beak_tip_x_h - beak_depth - card_w
      end
      card_x = [card_x, margin_left].max

      # Vertikal: AUTO-FLIP KE ATAS SAAT MENYENTUH BATAS BAWAH (Persis Gambar 2)
      # Normalnya box memanjang ke bawah dari kursor (panah di samping atas).
      # Jika bagian bawah box menyentuh batas bawah model gambar (margin 5),
      # box otomatis PINDAH POSISI KE ATAS sehingga panah triangle berada di samping bawah box!
      normal_card_y = badge_cy - (pad + row_h / 2)
      if normal_card_y + card_h > view.vpheight - margin_bottom
        # Pindah ke atas kursor: baris terbawah sejajar dengan kursor (Persis Gambar 2)
        card_y = badge_cy - card_h + (pad + row_h / 2)
      else
        # Posisi normal di bawah kursor: baris teratas sejajar dengan kursor
        card_y = normal_card_y
      end
      card_y = [card_y, margin_top].max

      # 3. Segitiga Penunjuk
      beak_half_base = 9.0
      beak_base_y = badge_cy
      beak_tip_y  = badge_cy

      # Batasi base beak agar tetap berada di dalam radius sudut kartu
      beak_min_y  = card_y + corner_r + beak_half_base
      beak_max_y  = card_y + card_h - corner_r - beak_half_base
      beak_base_y = [[beak_base_y, beak_min_y].max, beak_max_y].min
      beak_tip_y  = beak_base_y

      if !is_flipped
        # Card di kanan: Beak di sisi kiri card menunjuk ke KIRI (ke lingkaran)
        beak_tip_x  = beak_tip_x_h  # sudah termasuk gap
        beak_edge_x = card_x
        tri_fill_pts = [
          Geom::Point3d.new(beak_tip_x, beak_tip_y, 0),
          Geom::Point3d.new(beak_edge_x + 1, beak_base_y - beak_half_base, 0),
          Geom::Point3d.new(beak_edge_x + 1, beak_base_y + beak_half_base, 0)
        ]
        beak_lines = [
          Geom::Point3d.new(beak_edge_x, beak_base_y - beak_half_base, 0), Geom::Point3d.new(beak_tip_x, beak_tip_y, 0),
          Geom::Point3d.new(beak_tip_x, beak_tip_y, 0), Geom::Point3d.new(beak_edge_x, beak_base_y + beak_half_base, 0)
        ]
        seam_line = [
          Geom::Point3d.new(beak_edge_x, beak_base_y - beak_half_base + 1, 0),
          Geom::Point3d.new(beak_edge_x, beak_base_y + beak_half_base - 1, 0)
        ]
      else
        # Card di kiri: Beak di sisi kanan card menunjuk ke KANAN (ke lingkaran)
        beak_tip_x  = beak_tip_x_h  # sudah termasuk gap
        beak_edge_x = card_x + card_w
        tri_fill_pts = [
          Geom::Point3d.new(beak_tip_x, beak_tip_y, 0),
          Geom::Point3d.new(beak_edge_x - 1, beak_base_y - beak_half_base, 0),
          Geom::Point3d.new(beak_edge_x - 1, beak_base_y + beak_half_base, 0)
        ]
        beak_lines = [
          Geom::Point3d.new(beak_edge_x, beak_base_y - beak_half_base, 0), Geom::Point3d.new(beak_tip_x, beak_tip_y, 0),
          Geom::Point3d.new(beak_tip_x, beak_tip_y, 0), Geom::Point3d.new(beak_edge_x, beak_base_y + beak_half_base, 0)
        ]
        seam_line = [
          Geom::Point3d.new(beak_edge_x, beak_base_y - beak_half_base + 1, 0),
          Geom::Point3d.new(beak_edge_x, beak_base_y + beak_half_base - 1, 0)
        ]
      end

      # 4. Bayangan kartu
      view.drawing_color = card_shadow
      draw_rounded_rect(view, card_x + 2, card_y + 3, card_w, card_h, corner_r, fill: true)

      # 5. Background kartu (tema-aware)
      view.drawing_color = card_bg
      draw_rounded_rect(view, card_x, card_y, card_w, card_h, corner_r, fill: true)

      # Isi background segitiga (menyatu dengan background kartu)
      view.drawing_color = card_bg
      view.draw2d(GL_POLYGON, tri_fill_pts)

      # 6. Border kartu (tema-aware)
      view.drawing_color = card_border
      view.line_width = 1.2
      view.line_stipple = ""
      draw_rounded_rect(view, card_x, card_y, card_w, card_h, corner_r, fill: false)

      # Border segitiga (warna border)
      view.drawing_color = card_border
      view.line_width = 1.2
      view.draw2d(GL_LINES, beak_lines)

      # Hapus garis sambungan antara card dan beak
      view.drawing_color = card_bg
      view.line_width = 2.4
      view.draw2d(GL_LINES, seam_line)

      # 7. Badge Lingkaran Level Kursor (Center Sempurna, Berubah Pink Saat Level > 0)
      draw_cursor_circle(view, badge_cx, badge_cy, badge_r, active_lvl)

      # 8. Palet Warna Pastel Lembut & Estetik untuk Setiap Level
      level_colors = [
        Sketchup::Color.new(126, 142, 196), # Level 0: Pastel Slate Lavender (#7e8ec4)
        Sketchup::Color.new(79, 182, 237),  # Level 1: Pastel Sky Blue (#4fb6ed)
        Sketchup::Color.new(77, 195, 190),  # Level 2: Pastel Turquoise Mint (#4dc3be)
        Sketchup::Color.new(235, 138, 110), # Level 3: Pastel Soft Coral (#eb8a6e)
        Sketchup::Color.new(176, 125, 196), # Level 4: Pastel Soft Orchid (#b07dc4)
        Sketchup::Color.new(238, 168, 88),  # Level 5: Pastel Warm Amber (#eea858)
        Sketchup::Color.new(154, 204, 114), # Level 6: Pastel Sage Green (#9acc72)
        Sketchup::Color.new(232, 120, 154), # Level 7: Pastel Dusty Rose (#e8789a)
        Sketchup::Color.new(144, 164, 174), # Level 8: Pastel Soft Blue Grey (#90a4ae)
        Sketchup::Color.new(121, 134, 203)  # Level 9+: Pastel Soft Indigo (#7986cb)
      ]

      # 9. Gambar Setiap Baris Hierarki
      rows.each_with_index do |item, idx|
        ry = card_y + pad + idx * (row_h + row_gap)
        rw = card_w - pad * 2
        rh = row_h
        is_active = (idx == active_lvl)

        if is_active
          # Baris aktif: warna tema-aware (hitam di light, putih di dark)
          view.drawing_color = row_active_bg
          draw_rounded_rect(view, card_x + pad, ry, rw, rh, 5, fill: true)

          title_color = row_active_title
          tag_color   = row_active_tag
          icon_color  = row_active_icon
        else
          # Baris tidak aktif: gray (light=abu muda, dark=abu gelap)
          view.drawing_color = row_inactive_bg
          draw_rounded_rect(view, card_x + pad, ry, rw, rh, 6, fill: true)
          # Border tipis baris non-aktif
          view.drawing_color = row_inactive_border
          view.line_width = 0.8
          draw_rounded_rect(view, card_x + pad, ry, rw, rh, 6, fill: false)

          title_color = row_inactive_title
          tag_color   = row_inactive_tag
          icon_color  = row_inactive_icon
        end

        # Badge nomor level di dalam baris — UKURAN DIPERBESAR SAMA DENGAN LINGKARAN KURSOR (r = 11.5)
        r_badge_cx = card_x + pad + 18
        r_badge_cy = ry + rh / 2
        r_badge_r  = 11.5
        r_badge_pts = (0...28).map do |i|
          a = i * 2 * Math::PI / 28
          Geom::Point3d.new(r_badge_cx + r_badge_r * Math.cos(a), r_badge_cy + r_badge_r * Math.sin(a), 0)
        end

        # Warna badge nomor baris SELALU konsisten dengan warna pastelnya
        row_badge_color = level_colors[idx % level_colors.length]
        view.drawing_color = row_badge_color
        view.draw2d(GL_POLYGON, r_badge_pts)

        # Angka badge baris — CENTERING DEAD-CENTER DENGAN SEGOE UI
        num_str = idx.to_s
        nx_off = case num_str
                 when '1' then -4
                 when '0', '2', '3', '4', '5', '6', '7', '8', '9' then -4
                 else -4
                 end
        ny_off = -10
        view.draw_text(
          Geom::Point3d.new(r_badge_cx + nx_off, r_badge_cy + ny_off, 0),
          num_str,
          color: Sketchup::Color.new(255, 255, 255), size: 10, bold: true, font: "Segoe UI"
        )

        # Teks Nama & Tag dengan font Segoe UI proporsional dan fit
        tx = card_x + pad + 38
        disp_name = item[:name].length > 14 ? "#{item[:name][0...12]}.." : item[:name]
        disp_tag  = item[:tag].length > 16 ? "#{item[:tag][0...14]}.." : item[:tag]
        view.draw_text(Geom::Point3d.new(tx, ry + 3, 0), disp_name, color: title_color, size: 10, bold: true, font: "Segoe UI")
        view.draw_text(Geom::Point3d.new(tx, ry + 19, 0), disp_tag, color: tag_color, size: 9, bold: false, font: "Segoe UI")

        # Ikon di sisi kanan baris
        icon_cx = card_x + card_w - pad - 18
        icon_cy = ry + rh / 2
        draw_row_icon(view, item[:icon], icon_cx, icon_cy, icon_color)
      end
    end

    def draw_cursor_circle(view, cx, cy, r, active_lvl)
      segments = 28
      badge_pts = (0...segments).map do |i|
        a = i * 2 * Math::PI / segments
        Geom::Point3d.new(cx + r * Math.cos(a), cy + r * Math.sin(a), 0)
      end

      if active_lvl == 0
        # Level 0: Lingkaran putih bersih dengan outline gelap tegas (#18181b)
        view.drawing_color = Sketchup::Color.new(255, 255, 255)
        view.draw2d(GL_POLYGON, badge_pts)
        view.drawing_color = Sketchup::Color.new(24, 24, 27)
        view.line_width = 1.4
        view.line_stipple = ""
        view.draw2d(GL_LINE_LOOP, badge_pts)
        num_color = Sketchup::Color.new(24, 24, 27)
      else
        # Level > 0 (Gambar 2, 3, 4): Lingkaran solid MAGENTA / PINK (#e91e63) tanpa outline hitam!
        view.drawing_color = Sketchup::Color.new(233, 30, 99)
        view.draw2d(GL_POLYGON, badge_pts)
        num_color = Sketchup::Color.new(255, 255, 255)
      end

      # CENTERING PRESISI TINGGI DEAD-CENTER SEGOE UI (Persis Gambar 2, 3, 4):
      text = active_lvl.to_s
      x_off = case text
              when '1' then -4
              when '0', '2', '3', '4', '5', '6', '7', '8', '9' then -4
              else -4
              end
      y_off = -10
      view.draw_text(Geom::Point3d.new(cx + x_off, cy + y_off, 0), text, color: num_color, size: 10, bold: true, font: "Segoe UI")
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

      when :group # 3D Cube dengan 4 Corner Brackets (persis Gambar 2)
        s_cube = 4.0
        cube_pts = [
          Geom::Point3d.new(cx - s_cube, cy - s_cube + 2, 0), Geom::Point3d.new(cx, cy - s_cube - 1, 0),
          Geom::Point3d.new(cx, cy - s_cube - 1, 0), Geom::Point3d.new(cx + s_cube, cy - s_cube + 2, 0),
          Geom::Point3d.new(cx + s_cube, cy - s_cube + 2, 0), Geom::Point3d.new(cx, cy + 1, 0),
          Geom::Point3d.new(cx, cy + 1, 0), Geom::Point3d.new(cx - s_cube, cy - s_cube + 2, 0),

          Geom::Point3d.new(cx - s_cube, cy - s_cube + 2, 0), Geom::Point3d.new(cx - s_cube, cy + s_cube - 1, 0),
          Geom::Point3d.new(cx, cy + 1, 0), Geom::Point3d.new(cx, cy + s_cube + 2, 0),
          Geom::Point3d.new(cx + s_cube, cy - s_cube + 2, 0), Geom::Point3d.new(cx + s_cube, cy + s_cube - 1, 0),

          Geom::Point3d.new(cx - s_cube, cy + s_cube - 1, 0), Geom::Point3d.new(cx, cy + s_cube + 2, 0),
          Geom::Point3d.new(cx, cy + s_cube + 2, 0), Geom::Point3d.new(cx + s_cube, cy + s_cube - 1, 0)
        ]
        view.draw2d(GL_LINES, cube_pts)

        s_brk = 7.0
        brackets = [
          Geom::Point3d.new(cx - s_brk, cy - s_brk + 3, 0), Geom::Point3d.new(cx - s_brk, cy - s_brk, 0),
          Geom::Point3d.new(cx - s_brk, cy - s_brk, 0), Geom::Point3d.new(cx - s_brk + 3, cy - s_brk, 0),

          Geom::Point3d.new(cx + s_brk - 3, cy - s_brk, 0), Geom::Point3d.new(cx + s_brk, cy - s_brk, 0),
          Geom::Point3d.new(cx + s_brk, cy - s_brk, 0), Geom::Point3d.new(cx + s_brk, cy - s_brk + 3, 0),

          Geom::Point3d.new(cx - s_brk, cy + s_brk - 3, 0), Geom::Point3d.new(cx - s_brk, cy + s_brk, 0),
          Geom::Point3d.new(cx - s_brk, cy + s_brk, 0), Geom::Point3d.new(cx - s_brk + 3, cy + s_brk, 0),

          Geom::Point3d.new(cx + s_brk - 3, cy + s_brk, 0), Geom::Point3d.new(cx + s_brk, cy + s_brk, 0),
          Geom::Point3d.new(cx + s_brk, cy + s_brk, 0), Geom::Point3d.new(cx + s_brk, cy + s_brk - 3, 0)
        ]
        view.draw2d(GL_LINES, brackets)

      when :face # Tilted parallelogram dengan corner nodes (persis Gambar 2)
        s = 6.0
        c1 = Geom::Point3d.new(cx - s + 3, cy - s + 1, 0)
        c2 = Geom::Point3d.new(cx + s, cy - s + 1, 0)
        c3 = Geom::Point3d.new(cx + s - 3, cy + s - 1, 0)
        c4 = Geom::Point3d.new(cx - s, cy + s - 1, 0)
        view.draw2d(GL_LINE_LOOP, [c1, c2, c3, c4])

        # Corner nodes (lingkaran kecil di tiap sudut seperti Gambar 2)
        [c1, c2, c3, c4].each do |pt|
          node_pts = (0...8).map do |i|
            a = i * 2 * Math::PI / 8
            Geom::Point3d.new(pt.x + 1.2 * Math.cos(a), pt.y + 1.2 * Math.sin(a), 0)
          end
          view.draw2d(GL_LINE_LOOP, node_pts)
        end

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
