module UntagUnpaintManager
  def self.run
    require 'json'

    # HTML & CSS & JavaScript (Modern Minimalist UI)
    html_code = <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <title>Untag & Unpaint</title>
      <style>
        :root {
          --bg: #f7f7f8;
          --surface: #ffffff;
          --line: #e6e6e9;
          --line-strong: #d4d4d8;
          --ink: #18181b;
          --muted: #71717a;
          --accent: #4f46e5;
          --accent-soft: #eef0ff;
          --ok: #22c55e;
          --r: 10px;
        }

        * { box-sizing: border-box; }

        html, body {
          margin: 0;
          height: 100vh;
          background: var(--bg);
          color: var(--ink);
          font: 13px/1.45 "Segoe UI", -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
          -webkit-font-smoothing: antialiased;
          user-select: none;
          overflow: hidden;
        }

        body { display: flex; flex-direction: column; padding: 18px 16px 16px; gap: 14px; }

        svg { width: 18px; height: 18px; flex-shrink: 0; fill: none; stroke: currentColor; stroke-width: 1.75; stroke-linecap: round; stroke-linejoin: round; }

        /* Header */
        .head { display: flex; align-items: center; gap: 12px; }
        .mark {
          width: 36px; height: 36px; border-radius: 10px;
          background: var(--ink); color: #fff;
          display: grid; place-items: center;
        }
        .head h1 { margin: 0; font-size: 15px; font-weight: 600; letter-spacing: -0.01em; }
        .head p { margin: 1px 0 0; font-size: 12px; color: var(--muted); }

        /* Switch rekursif */
        .row {
          display: flex; align-items: center; gap: 12px;
          padding: 11px 12px;
          background: var(--surface);
          border: 1px solid var(--line);
          border-radius: var(--r);
          cursor: pointer;
          transition: border-color .15s;
        }
        .row:hover { border-color: var(--line-strong); }
        .row .ic { color: var(--muted); }
        .row .txt { flex: 1; min-width: 0; }
        .row .t { font-weight: 600; font-size: 12.5px; }
        .row .s { font-size: 11.5px; color: var(--muted); }

        .switch {
          width: 32px; height: 18px; border-radius: 999px;
          background: var(--line-strong);
          position: relative; flex-shrink: 0;
          transition: background .18s ease;
        }
        .switch::after {
          content: ""; position: absolute; top: 2px; left: 2px;
          width: 14px; height: 14px; border-radius: 50%;
          background: #fff; box-shadow: 0 1px 2px rgba(0,0,0,.2);
          transition: transform .18s cubic-bezier(.3,.7,.4,1);
        }
        .row[aria-checked="true"] .switch { background: var(--accent); }
        .row[aria-checked="true"] .switch::after { transform: translateX(14px); }

        /* Aksi */
        .label { font-size: 11px; font-weight: 600; color: var(--muted); letter-spacing: .04em; text-transform: uppercase; margin: 4px 2px -6px; }

        .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }

        .tile {
          cursor: pointer;
          display: flex; flex-direction: column; gap: 10px;
          padding: 12px;
          background: var(--surface);
          border: 1px solid var(--line);
          border-radius: var(--r);
          transition: border-color .15s, transform .08s, box-shadow .15s;
        }
        .tile:hover { border-color: var(--line-strong); box-shadow: 0 2px 8px -4px rgba(0,0,0,.12); }
        .tile:active { transform: scale(.98); }
        .tile .ic {
          width: 30px; height: 30px; border-radius: 8px;
          display: grid; place-items: center;
          background: var(--accent-soft); color: var(--accent);
        }
        .tile .t { font-weight: 600; font-size: 12.5px; }
        .tile .s { font-size: 11.5px; color: var(--muted); margin-top: -8px; }

        .primary {
          cursor: pointer;
          display: flex; align-items: center; justify-content: center; gap: 8px;
          height: 40px; margin-top: auto;
          background: var(--ink); color: #fff;
          border-radius: var(--r);
          font-weight: 600; font-size: 12.5px;
          transition: background .15s, transform .08s;
        }
        .primary:hover { background: #27272a; }
        .primary:active { transform: scale(.99); }

        [tabindex]:focus { outline: none; }
        [tabindex]:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
        [aria-disabled="true"] { opacity: .55; pointer-events: none; }

        .spin { animation: spin .7s linear infinite; }
        @keyframes spin { to { transform: rotate(360deg); } }

        .hint { font-size: 11px; color: var(--muted); text-align: center; margin: -4px 0 0; }

        /* Toast */
        #toast {
          position: fixed; left: 16px; right: 16px; bottom: 16px;
          display: flex; align-items: center; gap: 10px;
          padding: 10px 12px;
          background: var(--ink); color: #fff;
          border-radius: var(--r);
          font-size: 12px;
          box-shadow: 0 8px 24px -8px rgba(0,0,0,.35);
          opacity: 0; transform: translateY(8px);
          transition: opacity .2s, transform .2s;
          pointer-events: none;
        }
        #toast.show { opacity: 1; transform: none; }
        #toast .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--ok); flex-shrink: 0; }
        #toast.error .dot { background: #f87171; }
      </style>
    </head>
    <body>

      <!-- Ikon custom: 24x24 stroke, satu gaya -->
      <svg style="display:none">
        <symbol id="i-tag" viewBox="0 0 24 24"><path d="M3 12V4a1 1 0 0 1 1-1h8l9 9-9 9z"/><circle cx="7.5" cy="7.5" r="1.25"/></symbol>
        <symbol id="i-untag" viewBox="0 0 24 24"><path d="M12 3H4a1 1 0 0 0-1 1v8l9 9 4-4M19 14l2-2-6-6"/><circle cx="7.5" cy="7.5" r="1.25"/><path d="M3 3l18 18"/></symbol>
        <symbol id="i-unpaint" viewBox="0 0 24 24"><path d="M12 3s-6 6.5-6 11a6 6 0 0 0 10.2 4.3M17.7 13.6C16.9 9.6 12 3 12 3"/><path d="M3 3l18 18"/></symbol>
        <symbol id="i-clean" viewBox="0 0 24 24"><path d="M14 4l6 6-9.5 9.5H6L3.5 17a2 2 0 0 1 0-2.8z"/><path d="M8.5 9.5l6 6M13 20h8"/></symbol>
        <symbol id="i-layers" viewBox="0 0 24 24"><path d="M12 3l9 5-9 5-9-5z"/><path d="M3 13l9 5 9-5"/></symbol>
        <symbol id="i-spin" viewBox="0 0 24 24"><path d="M21 12a9 9 0 1 1-9-9"/></symbol>
      </svg>

      <header class="head">
        <div class="mark"><svg><use href="#i-tag"/></svg></div>
        <div>
          <h1>Untag & Unpaint</h1>
          <p>Bersihkan tag & material dari seleksi</p>
        </div>
      </header>

      <div class="row" id="deep" role="switch" aria-checked="true" tabindex="0">
        <svg class="ic"><use href="#i-layers"/></svg>
        <div class="txt">
          <div class="t">Rekursif</div>
          <div class="s">Ikut proses isi group & component</div>
        </div>
        <div class="switch"></div>
      </div>

      <div class="label">Aksi</div>

      <div class="grid">
        <div class="tile" role="button" tabindex="0" data-action="untag">
          <div class="ic"><svg><use href="#i-untag"/></svg></div>
          <div class="t">Untag</div>
          <div class="s">Set ke Untagged</div>
        </div>
        <div class="tile" role="button" tabindex="0" data-action="unpaint">
          <div class="ic"><svg><use href="#i-unpaint"/></svg></div>
          <div class="t">Unpaint</div>
          <div class="s">Hapus material</div>
        </div>
      </div>

      <div class="primary" role="button" tabindex="0" data-action="both">
        <svg><use href="#i-clean"/></svg><span>Untag & Unpaint</span>
      </div>
      <p class="hint">Pilih group / component dulu di model</p>

      <div id="toast"><span class="dot"></span><span id="toast-msg"></span></div>

      <script>
        const deep = document.getElementById('deep');
        const actions = document.querySelectorAll('[data-action]');
        let toastTimer, busyEl, busyIcon;

        function onKey(fn) {
          return e => { if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); fn(); } };
        }

        function toggleDeep() {
          deep.setAttribute('aria-checked', deep.getAttribute('aria-checked') !== 'true');
        }
        deep.addEventListener('click', toggleDeep);
        deep.addEventListener('keydown', onKey(toggleDeep));

        actions.forEach(el => {
          el.addEventListener('click', () => eksekusi(el));
          el.addEventListener('keydown', onKey(() => eksekusi(el)));
        });

        function setBusy(el) {
          actions.forEach(a => a.setAttribute('aria-disabled', el ? 'true' : 'false'));
          if (el) {
            busyEl = el;
            const use = el.querySelector('use');
            busyIcon = use.getAttribute('href');
            use.setAttribute('href', '#i-spin');
            use.parentNode.classList.add('spin');
          } else if (busyEl) {
            const use = busyEl.querySelector('use');
            use.setAttribute('href', busyIcon);
            use.parentNode.classList.remove('spin');
            busyEl = null;
          }
        }

        function showToast(message, type) {
          const t = document.getElementById('toast');
          document.getElementById('toast-msg').textContent = message;
          t.className = 'show ' + (type || '');
          clearTimeout(toastTimer);
          toastTimer = setTimeout(() => { t.className = type || ''; }, 2800);
        }

        function eksekusi(el) {
          if (busyEl) return; // Enter/Space masih bisa lolos dari pointer-events
          setBusy(el);
          sketchup.prosesAction(el.dataset.action, deep.getAttribute('aria-checked') === 'true');
        }

        function onProcessComplete(msg) { setBusy(null); showToast(msg); }
        function onError(msg) { setBusy(null); showToast(msg, 'error'); }
      </script>
    </body>
    </html>
    HTML

    # --- MEMBUAT UI DIALOG ---
    dialog = UI::HtmlDialog.new(
      {
        :dialog_title => "Untag & Unpaint",
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