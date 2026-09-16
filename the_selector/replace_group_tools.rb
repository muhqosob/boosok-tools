module MyTools
  module ReplaceGroupHelper
    
    @@dialog = nil
    @@last_pos = nil

    def self.run
      model = Sketchup.active_model
      sel = model.selection

      old_groups = sel.to_a.select { |e| e.is_a?(Sketchup::Group) }

      # Jika belum pilih grup lama, buka dialog HTML dengan pesan Error
      if old_groups.empty?
        self.show_message_dialog("Error: Pilih minimal 1 Grup Lama terlebih dahulu di layar, lalu jalankan tool ini.", "error")
        return
      end

      sel.clear

      if @@dialog && @@dialog.visible?
        begin
          pos = @@dialog.get_position
          @@last_pos = pos if pos.is_a?(Array) && pos.length == 2
        rescue
        end
        @@dialog.close
      end

      @@dialog = UI::HtmlDialog.new(
        dialog_title: "Replace Group Tool",
        width: 300,
        height: 160,
        style: UI::HtmlDialog::STYLE_UTILITY
      )

      html = <<-HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <style>
          * { box-sizing: border-box; }
          html, body {
            margin: 0; padding: 0; width: 100%; height: 100%;
            overflow: hidden; background: #f8f9fa;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            color: #333; display: flex; flex-direction: column;
            justify-content: center; align-items: center; text-align: center;
          }
          .container { width: 100%; padding: 15px; }
          
          /* Tampilan Utama */
          #main-view { display: block; }
          p { font-size: 13px; line-height: 1.4; margin: 0 0 14px 0; color: #495057; }
          .btn-primary {
            background: #2ea44f; color: white; border: none;
            padding: 8px 20px; font-size: 13px; font-weight: 600;
            border-radius: 6px; cursor: pointer; box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            transition: background 0.2s;
          }
          .btn-primary:hover { background: #2c974b; }

          /* Tampilan Sukses */
          #success-view { display: none; }
          .success-icon {
            width: 36px; height: 36px; background: #2ea44f; color: white;
            border-radius: 50%; display: flex; align-items: center; justify-content: center;
            font-size: 18px; margin: 0 auto 8px auto; box-shadow: 0 2px 6px rgba(46,164,79,0.3);
            animation: popIn 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
          }
          .success-text { font-size: 14px; font-weight: bold; color: #155724; margin: 0; }
          .success-sub { font-size: 11px; color: #6c757d; margin-top: 3px; }

          /* Tampilan Alert / Error Modern */
          #alert-view { display: none; }
          .alert-icon {
            width: 36px; height: 36px; background: #dc3545; color: white;
            border-radius: 50%; display: flex; align-items: center; justify-content: center;
            font-size: 16px; margin: 0 auto 8px auto; box-shadow: 0 2px 6px rgba(220,53,69,0.3);
            animation: popIn 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
          }
          .alert-text { font-size: 12px; font-weight: 600; color: #721c24; margin: 0 0 12px 0; line-height: 1.3; }
          .btn-danger {
            background: #dc3545; color: white; border: none;
            padding: 6px 16px; font-size: 12px; font-weight: 600;
            border-radius: 4px; cursor: pointer;
          }
          .btn-danger:hover { background: #c82333; }

          @keyframes popIn {
            0% { transform: scale(0); opacity: 0; }
            100% { transform: scale(1); opacity: 1; }
          }
        </style>
      </head>
      <body>

        <!-- TAHAP 1: UTAMA -->
        <div id="main-view" class="container">
          <p><b>Grup Lama tersimpan!</b><br>Pilih 1 Grup Baru di layar, lalu klik Eksekusi.</p>
          <button class="btn-primary" onclick="executeReplace()">OK / Eksekusi</button>
        </div>

        <!-- TAHAP 2: SUKSES -->
        <div id="success-view" class="container">
          <div class="success-icon">✓</div>
          <p class="success-text">Berhasil Diganti!</p>
          <div class="success-sub">Atribut, nama, & axes sukses disalin.</div>
        </div>

        <!-- TAHAP 3: ALERT / ERROR -->
        <div id="alert-view" class="container">
          <div class="alert-icon">!</div>
          <p id="alert-msg" class="alert-text">Pesan error di sini</p>
          <button class="btn-danger" onclick="closeAlert()">OK</button>
        </div>

        <script>
          function executeReplace() {
            sketchup.execute_replace();
          }

          function showSuccessState() {
            document.getElementById('main-view').style.display = 'none';
            document.getElementById('alert-view').style.display = 'none';
            document.getElementById('success-view').style.display = 'block';
          }

          function showAlertState(msg) {
            document.getElementById('main-view').style.display = 'none';
            document.getElementById('success-view').style.display = 'none';
            document.getElementById('alert-msg').innerText = msg;
            document.getElementById('alert-view').style.display = 'block';
          }

          function closeAlert() {
            sketchup.close_dialog();
          }
        </script>
      </body>
      </html>
      HTML

      @@dialog.set_html(html)
      @@dialog.show

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

      # Callback untuk menutup dialog dari tombol OK alert
      @@dialog.add_action_callback("close_dialog") do |action_context|
        @@dialog.close if @@dialog && @@dialog.visible?
      end

      @@dialog.add_action_callback("execute_replace") do |action_context|
        begin
          pos = @@dialog.get_position
          @@last_pos = pos if pos.is_a?(Array) && pos.length == 2
        rescue
        end

        model = Sketchup.active_model
        new_sel = model.selection.to_a.select { |e| e.is_a?(Sketchup::Group) }

        # Validasi 1: Pastikan memilih tepat 1 grup baru
        if new_sel.length != 1
          @@dialog.execute_script("showAlertState('Pastikan Anda memilih tepat 1 Grup Baru di layar SketchUp sebelum klik Eksekusi!');")
          next
        end

        grup_baru = new_sel[0]

        # Validasi 2: Grup baru tidak boleh sama dengan grup lama
        if old_groups.include?(grup_baru)
          @@dialog.execute_script("showAlertState('Grup baru tidak boleh sama dengan grup lama!');")
          next
        end

        model.start_operation("Replace Group Clean", true)

        definition_baru = grup_baru.definition
        dicts_baru = grup_baru.attribute_dictionaries

        old_groups.each do |grup_lama|
          nama_lama = grup_lama.name
          transformasi_lama = grup_lama.transformation
          context_lama = grup_lama.parent.entities
          tag_lama = grup_lama.layer 
          
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
          
          if defined?($dc_observers) && $dc_observers
            begin
              ldc = $dc_observers.get_latest_class
              ldc.determine_movetool_behaviors(new_instance) if ldc.respond_to?(:determine_movetool_behaviors)
              ldc.redraw(new_instance) if ldc.respond_to?(:redraw)
            rescue
            end
          end
          
          grup_lama.erase!
        end

        model.commit_operation

        # Tampilkan animasi sukses, lalu tutup otomatis
        @@dialog.execute_script("showSuccessState();")
        UI.start_timer(2.5, false) {
          @@dialog.close if @@dialog && @@dialog.visible?
        }
      end
    end

    # Fungsi khusus untuk menampilkan dialog error jika belum pilih grup lama
    def self.show_message_dialog(message, type)
      dialog = UI::HtmlDialog.new(
        dialog_title: "Replace Group Tool",
        width: 300,
        height: 150,
        style: UI::HtmlDialog::STYLE_UTILITY
      )

      html = <<-HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <style>
          * { box-sizing: border-box; }
          html, body {
            margin: 0; padding: 0; width: 100%; height: 100%;
            overflow: hidden; background: #f8f9fa;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            color: #333; display: flex; flex-direction: column;
            justify-content: center; align-items: center; text-align: center;
          }
          .container { width: 100%; padding: 15px; }
          .alert-icon {
            width: 34px; height: 34px; background: #dc3545; color: white;
            border-radius: 50%; display: flex; align-items: center; justify-content: center;
            font-size: 15px; margin: 0 auto 8px auto; box-shadow: 0 2px 6px rgba(220,53,69,0.3);
          }
          .alert-text { font-size: 12px; font-weight: 600; color: #721c24; margin: 0 0 12px 0; line-height: 1.3; }
          .btn-danger {
            background: #dc3545; color: white; border: none;
            padding: 6px 16px; font-size: 12px; font-weight: 600;
            border-radius: 4px; cursor: pointer;
          }
          .btn-danger:hover { background: #c82333; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="alert-icon">!</div>
          <p class="alert-text">#{message}</p>
          <button class="btn-danger" onclick="sketchup.close_dialog()">OK</button>
        </div>
      </body>
      </html>
      HTML

      dialog.set_html(html)
      dialog.center if dialog.respond_to?(:center)
      dialog.show

      dialog.add_action_callback("close_dialog") do |action_context|
        dialog.close
      end
    end

  end
end