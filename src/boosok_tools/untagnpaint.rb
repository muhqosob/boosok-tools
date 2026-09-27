module UntagUnpaintManager
  def self.run
    require 'json'

    # HTML & CSS & JavaScript (Modern Minimalist UI)
    html_code = <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <title>Untag & Unpaint Manager</title>
      <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');

        :root {
          --primary: #6366f1;
          --primary-hover: #4f46e5;
          --danger: #ef4444;
          --danger-hover: #dc2626;
          --warning: #f59e0b;
          --warning-hover: #d97706;
          --bg-main: #f8fafc;
          --bg-card: #ffffff;
          --border: #e2e8f0;
          --text-main: #0f172a;
          --text-muted: #64748b;
          --radius-lg: 16px;
          --radius-sm: 8px;
        }

        html, body {
          font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
          background-color: var(--bg-main);
          padding: 12px 10px 10px 10px;
          color: var(--text-main);
          font-size: 13px;
          margin: 0;
          height: 100vh;
          box-sizing: border-box;
          display: flex;
          flex-direction: column;
          align-items: stretch;
        }

        /* Header Title */
        .main-title {
          margin: 0 0 12px 0;
          font-size: 24px;
          font-weight: 800;
          letter-spacing: -0.03em;
          background: linear-gradient(135deg, #6366f1 0%, #ec4899 100%);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
          text-align: center;
          flex-shrink: 0;
        }

        /* Container Card */
        .card {
          background: var(--bg-card);
          padding: 16px;
          border-radius: var(--radius-lg);
          border: 1px solid var(--border);
          box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.05), 0 8px 10px -6px rgba(0, 0, 0, 0.01);
          display: flex;
          flex-direction: column;
          box-sizing: border-box;
          width: 100%;
          flex: 1;
          min-height: 0;
          justify-content: space-between;
        }

        .info-box {
          background-color: #f1f5f9;
          border-left: 4px solid var(--primary);
          padding: 12px;
          border-radius: var(--radius-sm);
          font-size: 11px;
          line-height: 1.5;
          color: #334155;
          margin-bottom: 16px;
        }

        .info-box b {
          color: var(--text-main);
        }

        /* Option Switches */
        .options-group {
          display: flex;
          flex-direction: column;
          gap: 10px;
          margin-bottom: 20px;
        }

        .checkbox-card {
          display: flex;
          align-items: center;
          padding: 10px 12px;
          border: 1px solid var(--border);
          border-radius: var(--radius-sm);
          background: #fff;
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .checkbox-card:hover {
          border-color: var(--primary);
          background-color: #f8fafc;
        }

        .checkbox-card input[type="checkbox"] {
          appearance: none;
          -webkit-appearance: none;
          width: 18px;
          height: 18px;
          border: 2px solid #cbd5e1;
          border-radius: 4px;
          margin-right: 12px;
          position: relative;
          cursor: pointer;
          transition: all 0.2s ease;
          flex-shrink: 0;
        }

        .checkbox-card input[type="checkbox"]:checked {
          background-color: var(--primary);
          border-color: var(--primary);
        }

        .checkbox-card input[type="checkbox"]:checked::after {
          content: '';
          position: absolute;
          left: 5px;
          top: 2px;
          width: 4px;
          height: 8px;
          border: solid white;
          border-width: 0 2px 2px 0;
          transform: rotate(45deg);
        }

        .checkbox-label {
          display: flex;
          flex-direction: column;
        }

        .checkbox-title {
          font-weight: 600;
          font-size: 12px;
          color: var(--text-main);
        }

        .checkbox-sub {
          font-size: 10px;
          color: var(--text-muted);
        }

        /* Buttons & Footer */
        .action-row {
          display: flex;
          flex-direction: column;
          gap: 8px;
          margin-top: auto;
        }

        .btn {
          padding: 10px 16px;
          font-size: 12px;
          font-weight: 600;
          border: none;
          border-radius: var(--radius-sm);
          cursor: pointer;
          transition: all 0.2s ease;
          font-family: inherit;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 8px;
          width: 100%;
          box-sizing: border-box;
        }

        .btn:active { transform: scale(0.98); }
        .btn:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }

        .btn-primary { background-color: var(--primary); color: white; box-shadow: 0 4px 6px -1px rgba(99, 102, 241, 0.2); }
        .btn-primary:hover { background-color: var(--primary-hover); }

        .btn-warning { background-color: var(--warning); color: white; box-shadow: 0 4px 6px -1px rgba(245, 158, 11, 0.2); }
        .btn-warning:hover { background-color: var(--warning-hover); }

        .btn-danger { background-color: var(--danger); color: white; box-shadow: 0 4px 6px -1px rgba(239, 68, 68, 0.2); }
        .btn-danger:hover { background-color: var(--danger-hover); }

        /* Toast Container */
        #toast-container {
          position: fixed;
          top: 16px;
          left: 50%;
          transform: translateX(-50%);
          z-index: 9999;
          display: flex;
          flex-direction: column;
          gap: 8px;
          pointer-events: none;
          width: 85%;
          align-items: center;
        }

        .toast {
          background: #1e293b;
          color: #fff;
          padding: 10px 16px;
          border-radius: 30px;
          font-size: 11px;
          font-weight: 500;
          box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
          display: flex;
          align-items: center;
          gap: 8px;
          animation: slideDown 0.3s cubic-bezier(0.16, 1, 0.3, 1) forwards, fadeOut 0.3s ease 2.7s forwards;
          text-align: center;
        }

        .toast.error { background: var(--danger); }
        .toast.success { background: #10b981; }

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

      <h1 class="main-title">Untag & Unpaint</h1>

      <div class="card">
        <div class="info-box">
          <b>Panduan Penggunaan:</b><br>
          Pilih satu atau lebih <b>Group / Component Instance</b> di SketchUp, lalu tekan tombol aksi untuk memproses objek hingga kedalaman terdalam.
        </div>

        <div class="options-group">
          <label class="checkbox-card">
            <input type="checkbox" id="chkDeep" checked>
            <div class="checkbox-label">
              <span class="checkbox-title">Proses Rekursif (Terdalam)</span>
              <span class="checkbox-sub">Proses seluruh sub-group & geometri di dalam.</span>
            </div>
          </label>
        </div>

        <div class="action-row">
          <button id="btnUntag" class="btn btn-primary" onclick="eksekusi('untag')">
            🏷️ Untag Pilihan
          </button>
          <button id="btnUnpaint" class="btn btn-warning" onclick="eksekusi('unpaint')">
            🎨 Unpaint Pilihan
          </button>
          <button id="btnBoth" class="btn btn-danger" onclick="eksekusi('both')">
            ⚡ Untag & Unpaint Sekaligus
          </button>
        </div>
      </div>

      <div id="toast-container"></div>

      <script>
        function showToast(message, type = 'success') {
          const container = document.getElementById('toast-container');
          const toast = document.createElement('div');
          toast.className = `toast ${type}`;
          toast.innerHTML = message;
          container.appendChild(toast);
          setTimeout(() => { toast.remove(); }, 3000);
        }

        function setButtonsState(disabled) {
          document.getElementById('btnUntag').disabled = disabled;
          document.getElementById('btnUnpaint').disabled = disabled;
          document.getElementById('btnBoth').disabled = disabled;
        }

        function eksekusi(actionType) {
          const deep = document.getElementById('chkDeep').checked;
          setButtonsState(true);
          sketchup.prosesAction(actionType, deep);
        }

        function onProcessComplete(msg) {
          setButtonsState(false);
          showToast(msg, 'success');
        }

        function onError(msg) {
          setButtonsState(false);
          showToast(msg, 'error');
        }
      </script>
    </body>
    </html>
    HTML

    # --- MEMBUAT UI DIALOG ---
    dialog = UI::HtmlDialog.new(
      {
        :dialog_title => "Untag & Unpaint Manager",
        :preferences_key => "com.sketchup.untagunpaint.manager",
        :scrollable => false,
        :resizable => false,
        :width => 360,
        :height => 420,
        :style => UI::HtmlDialog::STYLE_DIALOG
      }
    )
    dialog.set_html(html_code)

    # --- CALLBACK PROCESS ---
    dialog.add_action_callback("prosesAction") do |context, action_type, deep_process|
      model = Sketchup.active_model
      selection = model.selection.to_a

      if selection.empty?
        dialog.execute_script("onError('Gagal: Pilih minimal 1 Group / Component!');")
        next
      end

      model.start_operation("Untag / Unpaint Deep", true)

      begin
        count_untag = 0
        count_unpaint = 0

        # Algoritma Rekursif Pembersih
        clean_entity = nil
        clean_entity = lambda do |entity|
          next unless entity.respond_to?(:valid?) && entity.valid?

          # 1. UNTAG PROCESS (Pindahkan ke Layer0 / Untagged)
          if ['untag', 'both'].include?(action_type)
            if entity.layer != model.layers[0]
              entity.layer = model.layers[0]
              count_untag += 1
            end
          end

          # 2. UNPAINT PROCESS (Hapus Material)
          if ['unpaint', 'both'].include?(action_type)
            if entity.respond_to?(:material) && entity.material
              entity.material = nil
              count_unpaint += 1
            end
            if entity.respond_to?(:back_material) && entity.back_material
              entity.back_material = nil
              count_unpaint += 1
            end
          end

          # 3. REKURSIONAL (Masuk ke dalam Group / Component)
          if deep_process
            if entity.is_a?(Sketchup::Group)
              entity.definition.entities.each { |child| clean_entity.call(child) }
            elsif entity.is_a?(Sketchup::ComponentInstance)
              entity.definition.entities.each { |child| clean_entity.call(child) }
            end
          end
        end

        # Jalankan pembersihan pada item terseleksi
        selection.each { |ent| clean_entity.call(ent) }

        model.commit_operation

        # Pesan Balikan
        msg = case action_type
              when 'untag' then "Berhasil untag #{count_untag} elemen!"
              when 'unpaint' then "Berhasil unpaint #{count_unpaint} material!"
              else "Berhasil untag (#{count_untag}) & unpaint (#{count_unpaint})!"
              end

        dialog.execute_script("onProcessComplete('#{msg}');")

      rescue => e
        model.abort_operation
        err_msg = e.message.gsub("'", "\\'")
        dialog.execute_script("onError('Error: #{err_msg}');")
      end
    end

    dialog.show
  end
end

# Untuk menjalankan script langsung dari Ruby Console:
# UntagUnpaintManager.run