module HideOnSceneManager
  def self.run
    require 'json'
    require 'set'

    # Satu dialog saja. Buka ulang supaya daftar scene/tag ikut ter-refresh.
    @dialog.close if @dialog && @dialog.visible?

    model = Sketchup.active_model

    # Mendapatkan daftar nama Scene dan Tag
    daftar_scene = model.pages.map(&:name).to_json
    daftar_tag = model.layers.map(&:name).to_json

    # Struktur HTML dan Javascript (Desain Minimalis Wizard Flow)
    html_code = <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <title>Hide on Scene Manager</title>
      <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;800&display=swap');

        :root {
          --primary: #4f46e5;
          --primary-hover: #4338ca;
          --danger: #ef4444;
          --danger-hover: #dc2626;
          --success: #10b981;
          --success-hover: #059669;
          --info: #0ea5e9;
          --info-hover: #0284c7;
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
          /* Padding Presisi: Atas 12px, Kanan 8px, Bawah 8px, Kiri 8px */
          padding: 8px 6px 7px 6px;
          color: var(--text-main);
          font-size: 14px;
          margin: 0;
          height: 100vh;
          box-sizing: border-box;
          display: flex;
          flex-direction: column; 
          /* KUNCI PERBAIKAN: stretch memastikan elemen melebar penuh memenuhi sisa ruang padding */
          align-items: stretch;
        }

        /* --- JUDUL EYE-CATCHING --- */
        .main-title { 
          margin: 0 0 14px 0; 
          font-size: 28px; 
          font-weight: 800;
          letter-spacing: -0.03em;
          background: linear-gradient(135deg, #4f46e5 0%, #0ea5e9 100%);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
          text-align: center;
          flex-shrink: 0; 
        }

        /* --- WIZARD CONTAINER --- */
        .card { 
          background: var(--bg-card); 
          padding: 15px; 
          border-radius: var(--radius-lg); 
          border: 1px solid rgba(0,0,0,0.05);
          box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.05), 0 4px 6px -2px rgba(0, 0, 0, 0.025); 
          display: flex; 
          flex-direction: column; 
          box-sizing: border-box;
          width: 100%;
          flex: 1;
          min-height: 0;
          position: relative;
          overflow: hidden;
        }
        
        /* Step Container */
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
          font-size: 11px;
          font-weight: 600;
          color: var(--text-main);
          margin-bottom: 16px;
          padding-bottom: 12px;
          border-bottom: 1px solid var(--border);
        }

        /* --- INPUT & SEARCH BAR --- */
        .toolbar { display: flex; gap: 6px; margin-bottom: 12px; flex-shrink: 0; }

        .search-wrapper { position: relative; flex: 1; }
        .search-wrapper svg {
          position: absolute; left: 12px; top: 50%; transform: translateY(-50%); width: 14px; height: 14px; color: #9ca3af;
        }
        .toolbar input {
          width: 100%;
          padding: 10px 12px 10px 36px;
          border: 1px solid var(--border);
          border-radius: var(--radius-sm);
          outline: none;
          transition: all 0.2s ease;
          font-size: 10px;
          background: #f9fafb;
          box-sizing: border-box;
          font-family: inherit;
        }
        .toolbar input:focus { border-color: var(--primary); background: #fff; box-shadow: 0 0 0 3px rgba(79, 70, 229, 0.15); }
        
        .btn-action {
          padding: 4px 12px;
          background-color: #fff;
          border: 1px solid var(--border);
          border-radius: var(--radius-sm);
          cursor: pointer;
          color: var(--text-main);
          font-weight: 500;
          transition: all 0.2s ease;
          font-size: 11px;
          font-family: inherit;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .btn-action:hover { background-color: #f3f4f6; }

        /* --- LIST CONTAINER & CUSTOM SCROLLBAR --- */
        .list-container { 
          flex: 1; overflow-y: auto; overflow-x: hidden; border: 1px solid var(--border); 
          border-radius: var(--radius-sm); padding: 8px; background: #fff; 
          min-height: 0; margin-bottom: 16px; 
        }

        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb { background: #cbd5e1; border-radius: 10px; }
        ::-webkit-scrollbar-thumb:hover { background: #94a3b8; }

        /* --- CUSTOM CHECKBOX --- */
        .checkbox-item {
          display: flex;
          align-items: flex-start;
          padding: 3px 2px;
          cursor: pointer;
          border-bottom: 1px solid #f8fafc;
          border-radius: 6px;
          transition: background 0.15s ease;
          user-select: none;
          word-break: break-word;
          line-height: 1.4;
        }
        .checkbox-item:hover { background-color: #f1f5f9; }
        
        .checkbox-item input[type="checkbox"] { 
          appearance: none; -webkit-appearance: none; width: 18px; height: 18px;
          border: 2px solid #cbd5e1; border-radius: 4px; margin-right: 12px; position: relative;
          cursor: pointer; transition: all 0.2s ease; flex-shrink: 0;
          margin-top: 1px; 
        }
        .checkbox-item input[type="checkbox"]:checked { background-color: var(--primary); border-color: var(--primary); }
        .checkbox-item input[type="checkbox"]:checked::after {
          content: ''; position: absolute; left: 5px; top: 2px; width: 4px; height: 8px;
          border: solid white; border-width: 0 2px 2px 0; transform: rotate(45deg);
        }

        /* --- BUTTONS & FOOTER --- */
        .footer-nav {
          display: flex; gap: 12px; justify-content: space-between; margin-top: auto; padding-top: 16px; flex-shrink: 0; border-top: 1px solid var(--border);
        }
        
        .action-row {
          display: flex; gap: 8px; width: 100%;
        }

        .btn {
          padding: 8px 35px;
          font-size: 12px;
          font-weight: 300;
          border: none;
          border-radius: var(--radius-sm);
          cursor: pointer;
          transition: all 0.2s ease;
          font-family: inherit;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 8px;
        }
        .btn:active { transform: scale(0.98); }
        .btn:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }
        
        .btn-primary { background-color: var(--primary); color: white; box-shadow: 0 2px 4px rgba(79, 70, 229, 0.2); flex: 1;}
        .btn-primary:hover { background-color: var(--primary-hover); }
        
        .btn-secondary { background-color: #f1f5f9; color: var(--text-main); border: 1px solid var(--border); }
        .btn-secondary:hover { background-color: #e2e8f0; }

        .btn-danger { background-color: var(--danger); color: white; flex: 1;}
        .btn-danger:hover { background-color: var(--danger-hover); }
        
        .btn-success { background-color: var(--success); color: white; flex: 1;}
        .btn-success:hover { background-color: var(--success-hover); }

        .btn-info { background-color: var(--info); color: white; flex: 1; box-shadow: 0 2px 4px rgba(14, 165, 233, 0.2); }
        .btn-info:hover { background-color: var(--info-hover); }
        
        /* --- TABS --- */
        .tabs { display: flex; margin-bottom: 16px; background: #f1f5f9; border-radius: var(--radius-sm); padding: 4px; flex-shrink: 0; }
        .tablinks {flex: 1;padding: 10px;font-size: 10px;font-weight: 500;cursor: pointer;background: transparent;border: none;border-radius: 4px;color: var(--text-muted);transition: all 0.2s ease;font-family: inherit;}
        .tablinks:hover { color: var(--text-main); }
        .tablinks.active { background: #fff; color: var(--primary); font-weight: 600; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .tabcontent { display: none; flex-direction: column; flex: 1; min-height: 0; }
        
        .note {font-size: 11px;color: #0369a1;background: #e0f2fe;padding: 14px;border-radius: var(--radius-sm);border-left: 4px solid #0284c7;line-height: 1.5;margin-bottom: 16px;flex-shrink: 0;}

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
        .toast.success { background: var(--success); }
        
        @keyframes slideDown { 
          from { opacity: 0; transform: translateY(-20px); } 
          to { opacity: 1; transform: translateY(0); } 
        }
        
        @keyframes fadeOut { 
          from { opacity: 1; } 
          to { opacity: 0; } 
        }

        /* --- SUCCESS STEP ICON --- */
        .success-icon-wrapper { display: flex; justify-content: center; margin: 30px 0 20px 0; }
        .success-icon { width: 80px; height: 80px; background: #10b981; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: white; }
        .success-icon svg { width: 40px; height: 40px; }
      </style>
    </head>
    <body>
      
      <h1 class="main-title">Hide on Scene Manager</h1>
      
      <div class="card">
        
        <!-- ================= LANGKAH 1 ================= -->
        <div id="step1" class="step active">
          <div class="step-header">Langkah 1: Pilih Scene</div>
          
          <div class="toolbar">
            <div class="search-wrapper">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line></svg>
              <input type="text" id="searchScene" placeholder="Cari Scene..." onkeyup="filterList('searchScene', 'listScenes')">
            </div>
            <button class="btn-action" onclick="selectAll('listScenes')" title="Pilih Semua">All</button>
            <button class="btn-action" onclick="clearSelection('listScenes')" title="Bersihkan Pilihan">Clear</button>
          </div>
          
          <div id="listScenes" class="list-container"></div>
          
          <div class="footer-nav">
            <!-- PENYESUAIAN: Tombol Isolate dan Next dibuat sejajar (fit) tanpa gap berlebih -->
            <div class="action-row">
              <button id="btnIsolateActive" class="btn btn-info" onclick="isolateActive()" title="Isolasi di Scene yang sedang Anda buka saat ini">Isolate Scene Aktif</button>
              <button class="btn btn-primary" onclick="goToStep2()">Next ➔</button>
            </div>
          </div>
        </div>

        <!-- ================= LANGKAH 2 ================= -->
        <div id="step2" class="step">
          <div class="step-header">Langkah 2: Pilih Metode</div>
          
          <div class="tabs">
            <button class="tablinks active" onclick="openTab(event, 'TabTag')">Berdasarkan Tag</button>
            <button class="tablinks" onclick="openTab(event, 'TabObject')">Berdasarkan Objek</button>
          </div>
          
          <!-- TAB TAG -->
          <div id="TabTag" class="tabcontent" style="display:flex;">
            <div class="toolbar">
              <div class="search-wrapper">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line></svg>
                <input type="text" id="searchTag" placeholder="Cari Tag..." onkeyup="filterList('searchTag', 'listTags')">
              </div>
              <button class="btn-action" onclick="clearSelection('listTags')" title="Bersihkan Pilihan">Clear</button>
            </div>
            <div id="listTags" class="list-container" style="margin-bottom: 0;"></div>
            
            <div class="footer-nav" style="flex-direction: column; gap: 8px;">
              <button class="btn btn-secondary" style="width: 100%;" onclick="showStep(1)">⬅ Kembali ke Scene</button>
              <div class="action-row">
                <button id="btnHideTag" class="btn btn-danger" onclick="terapkanTag('hide')">Hide Tag</button>
                <button id="btnUnhideTag" class="btn btn-success" onclick="terapkanTag('unhide')">Unhide Tag</button>
              </div>
            </div>
          </div>

          <!-- TAB OBJEK -->
          <div id="TabObject" class="tabcontent" style="display:none;">
            <div class="note">
              <b>Alur Kerja:</b><br><br>
              1. Seleksi (blok) objek / grup di viewport SketchUp.<br>
              2. Pilih aksi di bawah (Hide atau Unhide) untuk mengeksekusi objek tersebut.<br>
              <br>
              *Note: disarankan menggunakan 5D+ Plus Select Tools agar bisa menyeleksi group dalam group tanpa harus membukanya.
            </div>
            <div style="flex:1;"></div>
            
            <div class="footer-nav" style="flex-direction: column; gap: 8px;">
              <button class="btn btn-secondary" style="width: 100%;" onclick="showStep(1)">⬅ Kembali ke Scene</button>
              <div class="action-row">
                <button id="btnHideObj" class="btn btn-danger" onclick="terapkanObjek('hide')">Hide Objek</button>
                <button id="btnUnhideObj" class="btn btn-success" onclick="terapkanObjek('unhide')">Unhide Objek</button>
              </div>
            </div>
          </div>
        </div>

        <!-- ================= LANGKAH 3 (SELESAI) ================= -->
        <div id="step3" class="step" style="text-align: center;">
          <div class="success-icon-wrapper">
            <div class="success-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>
            </div>
          </div>
          
          <h2 style="font-size: 22px; margin-bottom: 8px;">Berhasil!</h2>
          <p id="success-message" style="color: var(--text-muted); margin-bottom: 30px; line-height: 1.5;">Proses selesai dijalankan.</p>
          
          <div class="footer-nav" style="flex-direction: column; border-top: none; padding-top: 0;">
            <button class="btn btn-primary" style="width: 100%; margin-bottom: 8px;" onclick="showStep(1)">⟲ Lanjut (Pilih Lagi)</button>
            <button class="btn btn-secondary" style="width: 100%; color: var(--danger); border-color: #fca5a5;" onclick="sketchup.closeDialog()">Tutup Dialog ✖</button>
          </div>
        </div>

      </div>

      <!-- Wadah Toast -->
      <div id="toast-container"></div>

      <script>
        const scenes = #{daftar_scene};
        const tags = #{daftar_tag};

        function showStep(stepNum) {
          document.querySelectorAll('.step').forEach(el => el.classList.remove('active'));
          document.getElementById('step' + stepNum).classList.add('active');
        }

        function goToStep2() {
          if (getSelectedScenes().length === 0) {
            showToast("Harap centang minimal 1 Scene untuk melanjutkan!", "error");
            return;
          }
          showStep(2);
        }

        function showSuccessStep(message) {
          document.getElementById('success-message').innerText = message;
          showStep(3);
        }

        function showToast(message, type = 'error') {
          const container = document.getElementById('toast-container');
          const toast = document.createElement('div');
          toast.className = `toast ${type}`;
          toast.innerHTML = type === 'error' ? 
            `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="8" x2="12" y2="12"></line><line x1="12" y1="16" x2="12.01" y2="16"></line></svg>` + message :
            `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>` + message;
          container.appendChild(toast);
          setTimeout(() => { toast.remove(); }, 3000);
        }

        function renderCheckboxes(containerId, items) {
          let container = document.getElementById(containerId);
          container.innerHTML = ''; 
          items.forEach(item => {
            let label = document.createElement('label');
            label.className = 'checkbox-item';
            let cb = document.createElement('input');
            cb.type = 'checkbox';
            cb.value = item;
            
            let textSpan = document.createElement('span');
            textSpan.className = 'checkbox-text';
            textSpan.innerText = item;
            
            label.appendChild(cb);
            label.appendChild(textSpan);
            container.appendChild(label);
          });
        }

        renderCheckboxes('listScenes', scenes);
        renderCheckboxes('listTags', tags);

        function filterList(inputId, containerId) {
          let filterText = document.getElementById(inputId).value.toLowerCase();
          let items = document.getElementById(containerId).getElementsByClassName('checkbox-item');
          for (let i = 0; i < items.length; i++) {
            let txtValue = items[i].textContent || items[i].innerText;
            items[i].style.display = txtValue.toLowerCase().indexOf(filterText) > -1 ? "" : "none";
          }
        }

        function selectAll(containerId) {
          document.getElementById(containerId).querySelectorAll('.checkbox-item').forEach(label => {
            if (label.style.display !== "none") {
              label.querySelector('input[type="checkbox"]').checked = true;
            }
          });
        }

        function clearSelection(containerId) {
          document.getElementById(containerId).querySelectorAll('input[type="checkbox"]').forEach(cb => { cb.checked = false; });
        }

        function openTab(evt, tabName) {
          let tabcontents = document.getElementsByClassName("tabcontent");
          for (let i = 0; i < tabcontents.length; i++) { tabcontents[i].style.display = "none"; }
          let tablinks = document.getElementsByClassName("tablinks");
          for (let i = 0; i < tablinks.length; i++) { tablinks[i].classList.remove("active"); }
          document.getElementById(tabName).style.display = "flex";
          evt.currentTarget.classList.add("active");
        }

        function getSelectedScenes() {
          return Array.from(document.getElementById('listScenes').querySelectorAll('input[type="checkbox"]:checked')).map(cb => cb.value);
        }

        function isolateActive() {
          document.getElementById('btnIsolateActive').disabled = true;
          document.getElementById('btnIsolateActive').innerText = 'Memproses...';
          sketchup.prosesIsolateActive();
        }

        function resetIsolateBtn() {
          let btn = document.getElementById('btnIsolateActive');
          btn.disabled = false;
          btn.innerText = 'Isolate Scene Aktif';
        }

        function resetTagButton() { 
          document.getElementById('btnHideTag').disabled = false;
          document.getElementById('btnUnhideTag').disabled = false;
        }
        function resetObjButton() { 
          document.getElementById('btnHideObj').disabled = false;
          document.getElementById('btnUnhideObj').disabled = false;
        }

        function terapkanTag(action_type) {
          let scenes = getSelectedScenes();
          let tags = Array.from(document.getElementById('listTags').querySelectorAll('input[type="checkbox"]:checked')).map(cb => cb.value);
          
          if(tags.length === 0) { 
            showToast("Pilih minimal 1 Tag!", "error"); return; 
          }
          document.getElementById('btnHideTag').disabled = true;
          document.getElementById('btnUnhideTag').disabled = true;
          sketchup.prosesHideTags(scenes, tags, action_type);
        }

        function terapkanObjek(action_type) {
          let scenes = getSelectedScenes();
          document.getElementById('btnHideObj').disabled = true;
          document.getElementById('btnUnhideObj').disabled = true;
          sketchup.prosesHideObjects(scenes, action_type);
        }
      </script>
    </body>
    </html>
    HTML

    # --- BUAT DIALOG UI ---
    dialog = @dialog = UI::HtmlDialog.new(
      {
        :dialog_title => "Hide on Scene",
        :preferences_key => "com.sketchup.hidemanager.pro",
        :scrollable => false,
        :resizable => true,
        :width => 390,
        :min_width => 390,
        :max_width => 390,
        :height => 580,
        :min_height => 450,
        :style => UI::HtmlDialog::STYLE_DIALOG
      }
    )
    dialog.set_html(html_code)

    # --- CALLBACK: TUTUP DIALOG ---
    dialog.add_action_callback("closeDialog") do |action_context|
      dialog.close
    end

    # --- CALLBACK 1: PROSES ISOLATE SCENE AKTIF (LANGSUNG REFRESH VIEWPORT) ---
    dialog.add_action_callback("prosesIsolateActive") do |action_context|
      model = Sketchup.active_model
      selection = model.selection.to_a
      
      if selection.empty?
        dialog.execute_script("resetIsolateBtn();")
        dialog.execute_script("showToast('Gagal: Tidak ada objek yang diseleksi!', 'error');")
        next
      end

      # Cek apakah ada page/scene yang aktif
      page = model.pages.selected_page

      model.start_operation("Isolate Objects (Smart)", true)

      begin
        if page
          page.use_hidden_objects = true if page.respond_to?(:use_hidden_objects=)
          page.use_hidden_geometry = true if page.respond_to?(:use_hidden_geometry=)
          page.use_hidden = true if page.respond_to?(:use_hidden=)
        end

        # ALGORITMA PENCARIAN SILSILAH GRUP:
        selected = selection.to_set
        queue = selection.dup
        visited = {}
        
        while !queue.empty?
          ent = queue.shift
          next if visited[ent]
          visited[ent] = true

          if ent.respond_to?(:parent)
            p = ent.parent
            if p.is_a?(Sketchup::ComponentDefinition)
              p.instances.each do |inst|
                queue << inst
              end
            end
          end
        end

        # ALGORITMA PEMINDAI HIRARKI (Recursive Scanner):
        isolate_recursive = nil
        isolate_recursive = lambda do |entities|
          entities.each do |ent|
            next unless ent.is_a?(Sketchup::Drawingelement)

            if selected.include?(ent)
              # Jika persis objek yang dipilih, Unhide (tampilkan)
              if page
                page.set_drawingelement_visibility(ent, true)
                ent.hidden = false # UPDATE VIEWPORT SECARA INSTAN!
              else
                ent.hidden = false
              end
            elsif visited[ent] # grup induk dari objek terpilih
              # Jika ini adalah grup induk/bungkusan luarnya, tetap tampilkan
              if page
                page.set_drawingelement_visibility(ent, true)
                ent.hidden = false # UPDATE VIEWPORT SECARA INSTAN!
              else
                ent.hidden = false
              end
              
              # Lanjut scan kedalam isi grup tersebut
              if ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
                isolate_recursive.call(ent.definition.entities)
              end
            else
              # Jika bukan objek yang dipilih & bukan grup induknya, Sembunyikan (Hide)
              if page
                page.set_drawingelement_visibility(ent, false)
                ent.hidden = true # UPDATE VIEWPORT SECARA INSTAN!
              else
                ent.hidden = true
              end
            end
          end
        end

        # Eksekusi scan dimulai dari entitas paling atas
        isolate_recursive.call(model.entities)

        model.commit_operation
        dialog.execute_script("resetIsolateBtn();")
        
        nama_scene = page ? page.name : "Model Global"
        dialog.execute_script("showToast(#{("Sukses mengisolasi objek di scene: " + nama_scene).to_json}, 'success');")
        
      rescue => e
        model.abort_operation
        dialog.execute_script("resetIsolateBtn();")
        dialog.execute_script("showToast(#{("Kesalahan Sistem: " + e.message).to_json}, 'error');")
      end
    end

    # --- CALLBACK 2: PROSES HIDE/UNHIDE TAG ---
    dialog.add_action_callback("prosesHideTags") do |action_context, scene_terpilih, tag_terpilih, action_type|
      model = Sketchup.active_model
      model.start_operation("#{action_type.capitalize} Multiple Tags", true)
      begin

        visibility_status = (action_type == 'unhide')

        scene_terpilih.each do |nama_scene|
          page = model.pages[nama_scene]
          next unless page

          page.use_hidden_layers = true
          tag_terpilih.each do |nama_tag|
            layer = model.layers[nama_tag]
            next unless layer

            page.set_visibility(layer, visibility_status)
            layer.visible = visibility_status if model.pages.selected_page == page # REFRESH VIEWPORT
          end
        end
        model.commit_operation
      rescue => e
        model.abort_operation
        dialog.execute_script("resetTagButton();")
        dialog.execute_script("showToast(#{("Kesalahan Sistem: " + e.message).to_json}, 'error');")
        next
      end

      dialog.execute_script("resetTagButton();")
      
      aksi_teks = visibility_status ? "menampilkan" : "menyembunyikan"
      pesan = "Sukses #{aksi_teks} #{tag_terpilih.length} Tag di #{scene_terpilih.length} Scene."
      dialog.execute_script("showSuccessStep('#{pesan}');")
    end

    # --- CALLBACK 3: PROSES HIDE/UNHIDE OBJEK ---
    dialog.add_action_callback("prosesHideObjects") do |action_context, scene_terpilih, action_type|
      model = Sketchup.active_model
      selection = model.selection.to_a
      
      if selection.empty?
        dialog.execute_script("resetObjButton();")
        dialog.execute_script("showToast('Gagal: Tidak ada objek yang diseleksi!', 'error');")
        next
      end
      
      model.start_operation("#{action_type.capitalize} Objects on Scenes", true)
      
      visibility_status = (action_type == 'unhide')
      
      begin
        scene_terpilih.each do |nama_scene|
          page = model.pages[nama_scene]
          next unless page
          
          page.use_hidden_objects = true if page.respond_to?(:use_hidden_objects=)
          page.use_hidden_geometry = true if page.respond_to?(:use_hidden_geometry=)
          page.use_hidden = true if page.respond_to?(:use_hidden=)
          
          selection.each do |ent|
            if ent.respond_to?(:valid?) && ent.valid? && ent.is_a?(Sketchup::Drawingelement)
              page.set_drawingelement_visibility(ent, visibility_status)
              
              # UPDATE VIEWPORT INSTAN JIKA SCENE INI SEDANG DIBUKA DI LAYAR
              if model.pages.selected_page == page
                ent.hidden = !visibility_status 
              end
            end
          end
        end
        
        model.commit_operation
        dialog.execute_script("resetObjButton();")
        
        aksi_teks = visibility_status ? "menampilkan" : "menyembunyikan"
        pesan = "Sukses #{aksi_teks} #{selection.length} objek di #{scene_terpilih.length} Scene."
        dialog.execute_script("showSuccessStep('#{pesan}');")
        
      rescue => e
        model.abort_operation
        dialog.execute_script("resetObjButton();")
        dialog.execute_script("showToast(#{("Kesalahan Sistem: " + e.message).to_json}, 'error');")
      end
    end

    dialog.show
  end
end