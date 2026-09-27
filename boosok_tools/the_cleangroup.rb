module ConvertToCleanGroup
  @@dialog = nil
  @@last_pos = nil

  # --- FUNGSI INTI ---

  def self.purge_attributes(entity)
    if entity.respond_to?(:attribute_dictionaries) && entity.attribute_dictionaries
      entity.attribute_dictionaries.to_a.each do |d|
        begin
          entity.delete_attribute(d.name)
        rescue
          # Abaikan dictionary internal sistem
        end
      end
    end
  end

  def self.remove_target_completely(container_entities)
    container_entities.to_a.each do |child|
      if child.is_a?(Sketchup::ComponentInstance)
        defn = child.definition
        remove_target_completely(defn.entities)
        
        defn_name = defn.name.to_s.strip
        if defn_name == "2d__Line" || defn_name.include?("2d__Line")
          child.erase! rescue nil
        end
      elsif child.is_a?(Sketchup::Group)
        remove_target_completely(child.entities)
        
        grp_name = child.name.to_s.strip
        if grp_name == "2d__Line" || grp_name.include?("2d__Line")
          child.erase! rescue nil
        end
      end
    end
  end

  def self.convert_remaining_to_groups(container_entities)
    instances = container_entities.grep(Sketchup::ComponentInstance)
    
    instances.each do |inst|
      next unless inst.valid?

      tr = inst.transformation
      defn = inst.definition
      
      original_layer = inst.layer 
      
      purge_attributes(defn)
      convert_remaining_to_groups(defn.entities)
      
      inner_ents = defn.entities.to_a
      unless inner_ents.empty?
        new_group = container_entities.add_group
        new_group.transformation = tr
        
        new_group.layer = original_layer if original_layer
        
        temp_sub = new_group.entities.add_instance(defn, Geom::Transformation.new)
        temp_sub.explode if temp_sub
        
        purge_attributes(new_group)
        inst.erase!
      end
    end

    groups = container_entities.grep(Sketchup::Group)
    groups.each do |grp|
      next unless grp.valid?
      purge_attributes(grp)
      convert_remaining_to_groups(grp.entities)
    end
  end

  # --- UI & DIALOG ---

  def self.run
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
      <title>Clean Group Converter</title>
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
          white-space: nowrap;
        }
        .btn:active { transform: scale(0.98); }
        .btn:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }
        
        .btn-primary { background-color: var(--primary); color: white; box-shadow: 0 2px 4px rgba(79, 70, 229, 0.2); width: 100%; }
        .btn-primary:hover { background-color: var(--primary-hover); }
        
        .btn-secondary { background-color: #f1f5f9; color: var(--text-main); border: 1px solid var(--border); }
        .btn-secondary:hover { background-color: #e2e8f0; }

        .success-icon-wrapper { display: flex; justify-content: center; margin: 15px 0 10px 0; }
        .success-icon { width: 56px; height: 56px; background: var(--success); border-radius: 50%; display: flex; align-items: center; justify-content: center; color: white; }
        .success-icon svg { width: 28px; height: 28px; }

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
      
      <h1 class="main-title">Clean Group</h1>
      
      <div class="card">
        
        <!-- ================= LANGKAH 1: UTAMA ================= -->
        <div id="step1" class="step active">
          <div class="step-header">Pilih & Eksekusi</div>
          <p>1. Seleksi tepat <b>1 buah Komponen</b> di layar SketchUp.</p>
          <p>2. Klik tombol <b>Eksekusi</b> untuk membersihkan atribut dan mengubah semua isinya menjadi Grup murni.</p>
          
          <div style="flex:1;"></div>
          
          <div class="footer-nav">
            <button id="btnExec" class="btn btn-primary" onclick="executeClean()">Eksekusi ⚡</button>
          </div>
        </div>

        <!-- ================= LANGKAH 2: SELESAI ================= -->
        <div id="step2" class="step" style="text-align: center;">
          <div class="success-icon-wrapper">
            <div class="success-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>
            </div>
          </div>
          
          <h2 style="font-size: 16px; margin: 0 0 6px 0;">Berhasil!</h2>
          <p id="success-message" style="color: var(--text-muted); margin-bottom: 15px;">Komponen sukses diubah menjadi Clean Group.</p>
          
          <div class="footer-nav" style="border-top: none; padding-top: 0; gap: 8px; margin-bottom: 6px;">
            <button class="btn btn-secondary" style="flex: 1; margin: 0; color: var(--danger); border-color: #fca5a5;" onclick="sketchup.close_dialog()">Tutup ✖</button>
            <button class="btn btn-primary" style="flex: 1; margin: 0;" onclick="sketchup.restart_process()">⟲ Mulai Kembali</button>
          </div>
        </div>

      </div>

      <div id="toast-container"></div>

      <script>
        function showStep(stepNum) {
          document.querySelectorAll('.step').forEach(el => el.classList.remove('active'));
          document.getElementById('step' + stepNum).classList.add('active');
        }

        function showSuccessStep(message) {
          document.getElementById('success-message').innerText = message;
          showStep(2);
        }

        function executeClean() {
          let btn = document.getElementById('btnExec');
          btn.disabled = true;
          btn.innerText = "Memproses...";
          sketchup.proses_clean_group();
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

    @@dialog = UI::HtmlDialog.new(
      {
        :dialog_title => "Clean Group Converter",
        :scrollable => false,
        :resizable => false,
        :width => 340,
        :height => 340,
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

    # --- CALLBACK: MULAI KEMBALI ---
    @@dialog.add_action_callback("restart_process") do |action_context|
      Sketchup.active_model.selection.clear
      @@dialog.execute_script("showStep(1); resetExecButton();")
    end

    # --- CALLBACK: PROSES EKSEKUSI (VALIDASI SELESAI DI SINI) ---
    @@dialog.add_action_callback("proses_clean_group") do |action_context|
      model = Sketchup.active_model
      sel = model.selection.to_a
      
      # Validasi Cepat di Awal
      if sel.length != 1
        @@dialog.execute_script("showToast('Silakan pilih tepat 1 objek di layar!'); resetExecButton();")
        next
      elsif !sel[0].is_a?(Sketchup::ComponentInstance)
        @@dialog.execute_script("showToast('Error: Objek yang dipilih BUKAN Component!'); resetExecButton();")
        next
      end

      item = sel[0]
      main_layer = item.layer

      model.start_operation("Convert to Clean Group", true)

      # 1. Jadikan unik agar instans lain aman
      item = item.make_unique

      tr = item.transformation
      parent_ents = item.parent.entities
      source_defn = item.definition

      # 2. Hapus 2d__Line di source_defn
      remove_target_completely(source_defn.entities)
      purge_attributes(source_defn)

      # 3. Buat Group Master
      master_group = parent_ents.add_group
      master_group.transformation = tr
      master_group.layer = main_layer if main_layer

      # 4. Masukkan isi ke dalam master group
      temp_inst = master_group.entities.add_instance(source_defn, Geom::Transformation.new)
      temp_inst.explode if temp_inst

      # 5. Hapus komponen asli
      item.erase!

      # 6. Ubah seluruh struktur di dalamnya menjadi grup dan bersihkan atribut
      purge_attributes(master_group)
      convert_remaining_to_groups(master_group.entities)

      model.commit_operation
      model.selection.clear

      @@dialog.execute_script("resetExecButton();")
      @@dialog.execute_script("showSuccessStep('Selesai! Komponen berhasil dibersihkan menjadi Grup murni.');")
    end

    @@dialog.show
  end
end