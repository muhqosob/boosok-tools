module TheReplacer
  @@dialog = nil
  @@last_pos = nil
  @@old_items = []

  def self.run
    model = Sketchup.active_model
    
    # Kosongkan array lama dan jangan beri error di awal agar UI selalu bisa terbuka
    @@old_items = []

    if @@dialog && @@dialog.visible?
      begin
        pos = @@dialog.get_position
        @@last_pos = pos if pos.is_a?(Array) && pos.length == 2
      rescue
      end
      @@dialog.close
    end
    
    html_code = <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <title>The Replacer</title>
      <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;800&display=swap');

        :root {
          --primary: #4f46e5;
          --primary-hover: #4338ca;
          --success: #10b981;
          --danger: #ef4444;
          --bg-main: #f3f4f6;
          --bg-card: #ffffff;
          --border: #e5e7eb;
          --text-main: #111827;
          --text-muted: #6b7280;
          --radius-lg: 16px;
          --radius-sm: 8px;
        }

        html, body {
          font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
          background-color: var(--bg-main);
          padding: 8px 6px 7px 6px;
          color: var(--text-main);
          font-size: 13px;
          margin: 0;
          height: 100vh;
          box-sizing: border-box;
          display: flex;
          flex-direction: column;
          align-items: stretch;
          overflow: hidden;
        }

        .main-title { 
          margin: 0 0 10px 0; 
          font-size: 24px; 
          font-weight: 800;
          letter-spacing: -0.03em;
          background: linear-gradient(135deg, #4f46e5 0%, #0ea5e9 100%);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
          text-align: center;
          flex-shrink: 0; 
        }

        .card { 
          background: var(--bg-card); 
          padding: 12px 14px; 
          border-radius: var(--radius-lg); 
          border: 1px solid rgba(0,0,0,0.05);
          box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.05); 
          display: flex; 
          flex-direction: column; 
          box-sizing: border-box;
          width: 100%;
          flex: 1;
          min-height: 0;
          position: relative;
          overflow: hidden;
        }
        
        .step {
          display: none;
          flex-direction: column;
          flex: 1;
          min-height: 0;
          animation: fadeIn 0.3s ease-out;
        }
        .step.active { display: flex; }
        
        @keyframes fadeIn {
          from { opacity: 0; transform: translateX(10px); }
          to { opacity: 1; transform: translateX(0); }
        }

        .step-header {
          font-size: 13px;
          font-weight: 600;
          color: var(--text-main);
          margin-bottom: 12px;
          padding-bottom: 8px;
          border-bottom: 1px solid var(--border);
        }

        p { font-size: 12px; line-height: 1.5; margin: 0 0 10px 0; color: var(--text-muted); }

        .footer-nav {
          display: flex; gap: 12px; justify-content: space-between; margin-top: auto; padding-top: 12px; flex-shrink: 0; border-top: 1px solid var(--border);
        }

        .btn {
          padding: 8px 20px;
          font-size: 12px;
          font-weight: 500;
          border: none;
          border-radius: var(--radius-sm);
          cursor: pointer;
          transition: all 0.2s ease;
          font-family: inherit;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 8px;
          white-space: nowrap; /* Mencegah teks turun menjadi dua baris */
        }
        .btn:active { transform: scale(0.98); }
        .btn:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }
        
        .btn-primary { background-color: var(--primary); color: white; box-shadow: 0 2px 4px rgba(79, 70, 229, 0.2); flex: 1;}
        .btn-primary:hover { background-color: var(--primary-hover); }
        
        .btn-secondary { background-color: #f1f5f9; color: var(--text-main); border: 1px solid var(--border); }
        .btn-secondary:hover { background-color: #e2e8f0; }

        .success-icon-wrapper { display: flex; justify-content: center; margin: 15px 0 10px 0; }
        .success-icon { width: 56px; height: 56px; background: var(--success); border-radius: 50%; display: flex; align-items: center; justify-content: center; color: white; }
        .success-icon svg { width: 28px; height: 28px; }

/* --- TOAST NOTIFICATIONS (DARI ATAS) --- */
        #toast-container { 
          position: fixed; 
          top: 16px; 
          left: 50%; 
          transform: translateX(-50%); 
          z-index: 9999; 
          display: flex; 
          flex-direction: column; 
          gap: 10px; 
          pointer-events: none; 
          width: 85%; 
          align-items: center;
        }
        
        .toast { 
          background: #1f2937; 
          color: #fff; 
          padding: 10px 18px; 
          border-radius: 30px; 
          font-size: 11px; 
          font-weight: 500; 
          box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1); 
          display: flex; 
          align-items: center; 
          gap: 8px; 
          animation: slideDown 0.3s cubic-bezier(0.16, 1, 0.3, 1) forwards, fadeOut 0.3s ease 2.7s forwards; 
          text-align: center; 
          line-height: 1.4;
        }
        
        .toast.error { background: var(--danger); }
        
        @keyframes slideDown { 
          from { opacity: 0; transform: translateY(-20px); } 
          to { opacity: 1; transform: translateY(0); } 
        }
        
        @keyframes fadeOut { 
          from { opacity: 1; } 
          to { opacity: 0; } 
        }
      </style>
    </head>
    <body>
      
      <h1 class="main-title">The Replacer</h1>
      
      <div class="card">
        
        <!-- ================= LANGKAH 1: ITEM LAMA ================= -->
        <div id="step1" class="step active">
          <div class="step-header">Langkah 1: Pilih Item Lama</div>
          <p>1. Seleksi (blok) satu atau beberapa <b>Item Lama</b> di layar SketchUp Anda.</p>
          <p>2. Klik tombol <b>Next</b> di bawah ini.</p>
          
          <div style="flex:1;"></div>
          
          <div class="footer-nav">
            <div style="flex:1;"></div>
            <button id="btnNext1" class="btn btn-primary" onclick="checkOld()">Next ➔</button>
          </div>
        </div>

        <!-- ================= LANGKAH 2: ITEM BARU ================= -->
        <div id="step2" class="step">
          <div class="step-header">Langkah 2: Pilih Item Baru</div>
          <p>1. Pilih tepat <b>1 Item Baru</b> (Grup/Komponen) di layar sebagai pengganti.</p>
          <p>2. Klik tombol <b>Eksekusi</b> untuk mengganti dan menyesuaikan ukuran.</p>
          
          <div style="flex:1;"></div>
          
          <div class="footer-nav">
            <button class="btn btn-secondary" onclick="showStep(1)">⬅ Back</button>
            <button id="btnExec" class="btn btn-primary" onclick="executeReplace()">Eksekusi ⚡</button>
          </div>
        </div>

        <!-- ================= LANGKAH 3: SELESAI ================= -->
        <div id="step3" class="step" style="text-align: center;">
          <div class="success-icon-wrapper">
            <div class="success-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>
            </div>
          </div>
          
          <h2 style="font-size: 16px; margin: 0 0 6px 0;">Berhasil!</h2>
          <p id="success-message" style="color: var(--text-muted); margin-bottom: 15px;">Objek berhasil diganti.</p>
          
          <!-- Tambahan margin-bottom agar tidak mepet batas bawah jendela -->
          <div class="footer-nav" style="border-top: none; padding-top: 0; gap: 8px; margin-bottom: 6px;">
            <button class="btn btn-secondary" style="flex: 1; margin: 0; color: var(--danger); border-color: #fca5a5;" onclick="sketchup.close_dialog()">Tutup ✖</button>
            <button class="btn btn-primary" style="flex: 1; margin: 0;" onclick="sketchup.restart_process()">⟲ Mulai Kembali</button>
          </div>
        </div>

      </div>

      <!-- Toast Container untuk Error / Notifikasi -->
      <div id="toast-container"></div>

      <script>
        function showStep(stepNum) {
          document.querySelectorAll('.step').forEach(el => el.classList.remove('active'));
          document.getElementById('step' + stepNum).classList.add('active');
        }

        function showSuccessStep(message) {
          document.getElementById('success-message').innerText = message;
          showStep(3);
        }

        function checkOld() {
          sketchup.check_old_items();
        }

        function executeReplace() {
          let btn = document.getElementById('btnExec');
          btn.disabled = true;
          btn.innerText = "Memproses...";
          sketchup.proses_replace();
        }

        function resetExecButton() {
          let btn = document.getElementById('btnExec');
          btn.disabled = false;
          btn.innerText = "Eksekusi ⚡";
        }

        function showToast(message) {
          const container = document.getElementById('toast-container');
          const toast = document.createElement('div');
          toast.className = 'toast error';
          toast.innerHTML = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink:0;"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="8" x2="12" y2="12"></line><line x1="12" y1="16" x2="12.01" y2="16"></line></svg> <span style="text-align:left;">${message}</span>`;
          container.appendChild(toast);
          setTimeout(() => { toast.remove(); }, 3500);
        }
      </script>
    </body>
    </html>
    HTML

    # --- KONFIGURASI DIALOG FIX (Dinaikkan ukurannya agar lebih lega) ---
    @@dialog = UI::HtmlDialog.new(
      {
        :dialog_title => "The Replacer",
        :scrollable => false,
        :resizable => false,
        :width => 340,
        :height => 340, # Diperbesar agar tombol di bawah tidak terpotong
        :style => UI::HtmlDialog::STYLE_DIALOG
      }
    )

    @@dialog.set_html(html_code)

    if @@last_pos.is_a?(Array) && @@last_pos.length == 2
      @@dialog.set_position(@@last_pos[0], @@last_pos[1])
    else
      @@dialog.center if @@dialog.respond_to?(:center)
    end

    @@dialog.set_on_closed {
      begin
        pos = @@dialog.get_position
        @@last_pos = pos if pos.is_a?(Array) && pos.length == 2
      rescue
      end
    }

    @@dialog.add_action_callback("close_dialog") do |action_context|
      @@dialog.close if @@dialog && @@dialog.visible?
    end

    # --- CALLBACK 1: CEK ITEM LAMA SAAT KLIK NEXT ---
    @@dialog.add_action_callback("check_old_items") do |action_context|
      model = Sketchup.active_model
      sel = model.selection
      @@old_items = sel.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }

      if @@old_items.empty?
        @@dialog.execute_script("showToast('Pilih minimal 1 Grup/Komponen Lama terlebih dahulu di layar!');")
      else
        model.selection.clear
        @@dialog.execute_script("showStep(2);")
      end
    end

    # --- CALLBACK 2: MULAI KEMBALI (RESET & UNSELECT) ---
    @@dialog.add_action_callback("restart_process") do |action_context|
      @@old_items = []
      Sketchup.active_model.selection.clear
      @@dialog.execute_script("showStep(1);")
    end

    # --- CALLBACK 3: PROSES PENGGANTIAN & PENSKALAAN ---
    @@dialog.add_action_callback("proses_replace") do |action_context|
      model = Sketchup.active_model
      new_sel = model.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }

      if new_sel.length != 1
        @@dialog.execute_script("showToast('Pastikan Anda memilih tepat 1 Item Baru sebagai pengganti!');")
        @@dialog.execute_script("resetExecButton();")
        next
      end

      item_baru = new_sel[0]

      if @@old_items.include?(item_baru)
        @@dialog.execute_script("showToast('Item baru tidak boleh sama dengan item lama yang tadi dipilih!');")
        @@dialog.execute_script("resetExecButton();")
        next
      end

      # Item lama bisa sudah terhapus / di-undo sejak klik Next
      @@old_items.reject!(&:deleted?)
      if @@old_items.empty?
        @@dialog.execute_script("showToast('Item lama sudah tidak ada (terhapus/di-undo). Ulangi dari Langkah 1.'); resetExecButton(); showStep(1);")
        next
      end

      model.start_operation("The Replacer Wizard", true)
      begin

        definition_baru = item_baru.definition
        dicts_baru = item_baru.attribute_dictionaries

        get_dimension_inch = lambda do |ent, attr_name, axis_idx|
          base_inch = 0.0
          if ent.is_a?(Sketchup::ComponentInstance) && ent.definition.attribute_dictionaries && ent.definition.attribute_dictionaries["dynamic_attributes"]
            dict = "dynamic_attributes"
            base_inch = ent.definition.get_attribute(dict, "_#{attr_name}_nominal").to_f
            base_inch = ent.definition.get_attribute(dict, attr_name).to_f if base_inch == 0
            base_inch = ent.get_attribute(dict, "_#{attr_name}_nominal").to_f if base_inch == 0
            base_inch = ent.get_attribute(dict, attr_name).to_f if base_inch == 0
          end

          if base_inch == 0
            def_bb = ent.definition.bounds rescue ent.bounds
            base_inch = case axis_idx
                        when 0 then def_bb.width
                        when 1 then def_bb.depth
                        when 2 then def_bb.height
                        end
          end

          tr = ent.transformation
          current_scale = case axis_idx
                          when 0 then tr.xaxis.length
                          when 1 then tr.yaxis.length
                          when 2 then tr.zaxis.length
                          end
          return base_inch * current_scale
        end

        @@old_items.each do |item_lama|
          nama_lama = item_lama.name
          transformasi_lama = item_lama.transformation
          context_lama = item_lama.parent.entities
          tag_lama = item_lama.layer 

          target_inch_x = get_dimension_inch.call(item_lama, "lenx", 0)
          target_inch_y = get_dimension_inch.call(item_lama, "leny", 1)

          new_instance = context_lama.add_instance(definition_baru, transformasi_lama)
          new_instance.layer = tag_lama
          new_instance.name = nama_lama unless nama_lama.empty?
        
          if dicts_baru
            dicts_baru.each do |dict|
              dict.each_pair do |key, val|
                new_instance.set_attribute(dict.name, key, val)
              end
            end
          end

          base_inch_x = get_dimension_inch.call(new_instance, "lenx", 0)
          base_inch_y = get_dimension_inch.call(new_instance, "leny", 1)

          if base_inch_x > 0.001 && base_inch_y > 0.001 && target_inch_x > 0.001 && target_inch_y > 0.001
            scale_x = target_inch_x / base_inch_x
            scale_y = target_inch_y / base_inch_y
            scale_z = 1.0

            bb_baru = new_instance.bounds
            center_point = bb_baru.center

            scaling_transform = Geom::Transformation.scaling(center_point, scale_x, scale_y, scale_z)
            new_instance.transform!(scaling_transform)

            if new_instance.is_a?(Sketchup::ComponentInstance) && new_instance.definition.attribute_dictionaries && new_instance.definition.attribute_dictionaries["dynamic_attributes"]
              if defined?($dc_observers) && $dc_observers
                dco = $dc_observers.get_latest_class
                dco.redraw_with_undo(new_instance) if dco.respond_to?(:redraw_with_undo)
              end
            end
          end
        
          item_lama.erase!
        end

        model.commit_operation
      rescue => e
        model.abort_operation
        @@dialog.execute_script("resetExecButton();")
        @@dialog.execute_script("showToast(#{("Gagal: " + e.message).to_json});")
        next
      end

      model.selection.clear

      @@dialog.execute_script("resetExecButton();")
      @@dialog.execute_script("showSuccessStep('Sukses mengganti & menyesuaikan ukuran #{@@old_items.length} objek.');")
    end

    @@dialog.show
  end
end