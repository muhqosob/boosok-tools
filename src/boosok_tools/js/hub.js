    /* ═══════════════════════════════════════════════
       Locale & Internationalization (i18n)
    ═══════════════════════════════════════════════ */
    var currentLang = 'id';
    try {
      var savedL = localStorage.getItem('boosok_language');
      if (savedL) currentLang = savedL;
    } catch (e) { }

    // Semua bahasa berasal dari locales/*.json (diekspor Ruby ke js/strings.js, dimuat locale.js).
    // Menambah bahasa = menambah file JSON; daftar bahasa di panel Bahasa ikut otomatis.
    var LOCALES = window.BOOSOK_LOCALES || {};

    // Catatan: JANGAN dinamai t() — akan menimpa window.t milik locale.js (rekursi tak berujung).
    function ht(key, fallback) {
      return window.t(key, fallback, currentLang || window.BOOSOK_LANG);
    }

    function formatTrialTime(lic) {
      if (!lic) return '0 ' + (currentLang === 'en' ? 'mins' : 'menit');
      var rem = (lic.rem_seconds !== undefined) ? lic.rem_seconds : ((lic.mins_left ? lic.mins_left * 60 : 3600));
      if (rem <= 0) return '0 ' + (currentLang === 'en' ? 'mins' : 'menit');
      if (rem >= 86400) {
        var days = Math.floor(rem / 86400);
        var dh = Math.floor((rem % 86400) / 3600);
        if (currentLang === 'en') return days + (days === 1 ? ' day' : ' days') + (dh ? ' ' + dh + ' hr' : '');
        return days + ' hari' + (dh ? ' ' + dh + ' jam' : '');
      }
      var mins = Math.ceil(rem / 60);
      if (mins > 60) {
        var hrs = Math.floor(mins / 60);
        var m = mins % 60;
        return currentLang === 'en' ? (hrs + ' hr ' + m + ' mins') : (hrs + ' jam ' + m + ' menit');
      } else if (mins > 1) {
        return mins + ' ' + (currentLang === 'en' ? 'mins' : 'menit');
      } else {
        return rem + ' ' + (currentLang === 'en' ? 'secs' : 'detik');
      }
    }

    function getToolTitle(tool) {
      if (!tool) return '';
      return ht('tool_' + tool.id + '_title', tool.t);
    }

    function getToolDesc(tool) {
      if (!tool) return '';
      return ht('tool_' + tool.id + '_desc', tool.s);
    }

    function applyTranslations() {
      var sub = document.getElementById('hubSub');
      if (sub) sub.textContent = ht('hub_subtitle', 'Pilih tool yang mau dipakai');
      var si = document.getElementById('searchInput');
      if (si) si.placeholder = ht('search_placeholder', 'Cari tool...');
      var sc = document.getElementById('searchClear');
      if (sc) sc.title = ht('search_clear', 'Hapus pencarian');
      var sBtn = document.getElementById('settingsBtn');
      if (sBtn) { sBtn.title = ht('settings', 'Pengaturan'); sBtn.setAttribute('aria-label', ht('settings', 'Pengaturan')); }
      var tBtn = document.getElementById('themeToggle');
      if (tBtn) { tBtn.title = ht('theme_toggle', 'Ganti Tema'); tBtn.setAttribute('aria-label', ht('theme_toggle', 'Ganti Tema')); }

      var mLang = document.getElementById('menuLangLabel');
      if (mLang) mLang.textContent = ht('menu_language', 'Bahasa');
      var mAb = document.getElementById('menuAboutLabel');
      if (mAb) mAb.textContent = ht('menu_about', 'Tentang');

      var lpTitle = document.getElementById('langPanelTitle');
      if (lpTitle) lpTitle.textContent = ht('lang_select', 'Pilih Bahasa');
      var lHintTitle = document.getElementById('langHintTitle');
      if (lHintTitle) lHintTitle.textContent = ht('lang_hint_title', 'Bahasa Disimpan dalam JSON:');
      var lHintDesc = document.getElementById('langHintDesc');
      if (lHintDesc) lHintDesc.textContent = ht('lang_hint_desc', 'Anda bisa mengedit terjemahan atau menambahkan file bahasa baru (.json) di folder bahasa.');
      var lOpenText = document.getElementById('btnOpenLocalesText');
      if (lOpenText) lOpenText.textContent = ht('lang_open_folder', 'Buka Folder Bahasa');


      // About & License modal translations
      var abLblCreated = document.getElementById('aboutLblCreated');
      if (abLblCreated) abLblCreated.textContent = ht('about_created_by', 'Dibuat oleh');
      var abLblPlatform = document.getElementById('aboutLblPlatform');
      if (abLblPlatform) abLblPlatform.textContent = ht('about_platform', 'Platform');
      var abValPlatform = document.getElementById('aboutValPlatform');
      if (abValPlatform) abValPlatform.textContent = ht('about_platform_val', 'SketchUp Extension');
      var abLblLic = document.getElementById('aboutLblLic');
      if (abLblLic) abLblLic.textContent = ht('about_lic_status', 'Lisensi Plugin');
      var abLblHwid = document.getElementById('aboutLblHwid');
      if (abLblHwid) abLblHwid.textContent = ht('about_hwid', 'Hardware ID');
      var copyBtn = document.getElementById('btnCopyHwId');
      if (copyBtn) copyBtn.title = ht('about_copy_title', 'Salin Hardware ID ke clipboard');
      var copyText = document.getElementById('copyText');
      if (copyText && copyText.textContent !== ht('about_copied', 'Tersalin!')) {
        copyText.textContent = ht('about_copy', 'Salin');
      }
      var licQrLbl = document.getElementById('licQrLbl');
      if (licQrLbl) licQrLbl.textContent = ht('about_qr_label', 'Scan QR DANA');
      var licNoticePrefix = document.getElementById('licNoticePrefix');
      if (licNoticePrefix) licNoticePrefix.innerHTML = ht('about_send_hwid_prefix', 'Kirim <strong style="color:var(--ink);">nama, nomor HP, dan bukti bayar</strong> ke WhatsApp:');
      var licNoticeSuffix = document.getElementById('licNoticeSuffix');
      if (licNoticeSuffix) licNoticeSuffix.textContent = ht('about_send_hwid_suffix', 'untuk mendapatkan lisensi key. Harga = Rp25.000.');
      var licMailLink = document.getElementById('licMailLink');
      if (licMailLink) licMailLink.title = ht('about_open_wa', 'Buka WhatsApp');
      var abLblRegName = document.getElementById('aboutLblRegName');
      if (abLblRegName) abLblRegName.textContent = ht('about_reg_name', 'Nama terdaftar');
      var abLblRegPhone = document.getElementById('aboutLblRegPhone');
      if (abLblRegPhone) abLblRegPhone.textContent = ht('about_reg_phone', 'Nomor HP terdaftar');
      var abLblEnterKey = document.getElementById('aboutLblEnterKey');
      if (abLblEnterKey) abLblEnterKey.textContent = ht('about_enter_key', 'Masukkan Lisensi Key');
      var licActText = document.getElementById('licActivateBtnText');
      if (licActText) licActText.textContent = ht('about_activate', 'Aktifkan Lisensi');
      var licCloseText = document.getElementById('licCloseBtnText');
      if (licCloseText) licCloseText.textContent = ht('about_close', 'Tutup');
      var licRemoveText = document.getElementById('licRemoveBtnText');
      if (licRemoveText) licRemoveText.textContent = ht('about_remove_lic', 'Hapus Aktivasi');
      var licActCloseText = document.getElementById('licActiveCloseBtnText');
      if (licActCloseText) licActCloseText.textContent = ht('about_close', 'Tutup');

      if (S.data && S.data.license) {
        onLicenseStatus(S.data.license);
      }
    }

    function openLanguagePanel() {
      closeSettingsMenu();
      var panel = document.getElementById('languagePanel');
      if (panel) {
        panel.classList.add('open');
        renderLanguageList();
        if (window.sketchup && typeof sketchup.get_languages === 'function') {
          sketchup.get_languages();
        }
      }
    }

    function closeLanguagePanel() {
      var panel = document.getElementById('languagePanel');
      if (panel) panel.classList.remove('open');
    }

    function renderLanguageList() {
      var list = document.getElementById('langList');
      if (!list) return;
      var codes = Object.keys(LOCALES);
      if (!codes.length) {
        codes = ['id', 'en'];
      }
      list.innerHTML = codes.map(function (c) {
        var loc = LOCALES[c] || {};
        var name = loc.name || loc.native_name || c.toUpperCase();
        var file = loc.file || (c + '.json');
        var isActive = (currentLang === c);
        return '<div class="lang-item' + (isActive ? ' active' : '') + '" onclick="selectLanguage(\'' + esc(c) + '\')">' +
          '<div class="lang-badge">' + esc(c.toUpperCase()) + '</div>' +
          '<div class="lang-info">' +
          '<div class="lang-name">' + esc(name) + '</div>' +
          '<div class="lang-file">' + esc(file) + '</div>' +
          '</div>' +
          '<div class="lang-check">' + icon('check') + '</div>' +
          '</div>';
      }).join('');
    }

    function selectLanguage(code) {
      if (!code) return;
      currentLang = code;
      if (typeof window.setBoosokLang === 'function') {
        window.setBoosokLang(code);
      } else {
        window.BOOSOK_LANG = code;
        try { localStorage.setItem('boosok_language', code); } catch (e) { }
      }
      if (window.sketchup && typeof sketchup.set_language === 'function') {
        sketchup.set_language(JSON.stringify(code));
      }
      applyTranslations();
      renderLanguageList();
      draw();
    }

    function openLocalesFolder() {
      if (window.sketchup && typeof sketchup.open_locales_folder === 'function') {
        sketchup.open_locales_folder();
      }
    }

    function onLanguagesLoaded(locs, cur) {
      // Daftar terbaru dari Ruby (termasuk file bahasa yang baru ditambahkan saat SketchUp berjalan)
      if (locs && typeof locs === 'object') window.registerBoosokLocales(locs);
      if (cur) {
        var userSavedLang = '';
        try { userSavedLang = localStorage.getItem('boosok_language'); } catch (e) { }
        if (!userSavedLang) currentLang = cur;
      }
      applyTranslations();
      renderLanguageList();
      draw();
    }

    function onLanguageSaved(savedCode) {
      if (savedCode) {
        currentLang = savedCode;
      }
    }

    var LS_RECENT = 'boosok_recent_tool';

    var TOOLS = [
      { id: 'selector', icon: 'mouse-pointer-click', t: 'Selector', s: 'Seleksi by tag, nama, atribut', needs: 'objects' },
      { id: 'custom_select', icon: 'square-dashed-mouse-pointer', t: 'Select Tools', s: 'Seleksi multi-level viewport', needs: 'objects' },
      { id: 'replacer', icon: 'replace', t: 'Replacer', s: 'Ganti objek sekaligus', needs: 'objects' },
      { id: 'clean', icon: 'sparkles', t: 'Grp Cleaner', s: 'Component jadi group murni', needs: 'objects' },
      { id: 'reset', icon: 'scale-3d', t: 'Reset Scale', s: 'Kembalikan skala group', needs: 'objects' },
      { id: 'scene', icon: 'eye-off', t: 'Hide Scene', s: 'Atur visibilitas per scene', needs: 'scenes' },
      { id: 'untag', icon: 'paint-bucket', t: 'Untag', s: 'Hapus tag & material', needs: 'objects' },
      { id: 'deep', icon: 'layers', t: 'Deep Props', s: 'Analisis tag & entitas mendalam', needs: 'objects' },
      { id: 'purge', icon: 'trash-2', t: 'Purge', s: 'Hapus component, material, tag tak terpakai', needs: 'objects' },
      { id: 'void', icon: 'square-minus', t: 'Void', s: 'Group pelubang group lain', needs: 'objects' },
      { id: 'slice', icon: 'scissors', t: 'Slice', s: 'Potong group dengan garis', needs: 'objects' },
      { id: 'trowel', icon: 'shovel', t: 'Trowel', s: 'Push/Pull & Offset dalam group', needs: 'objects' }
    ];

    var TOOL_MAP = {};
    TOOLS.forEach(function (t) { TOOL_MAP[t.id] = t; });

    /* ═══════════════════════════════════════════════
       Boot loader: tampil SEKALI per sesi SketchUp (pembukaan Hub pertama).
       Membuka Hub lagi / kembali dari tool langsung tanpa loader.
    ═══════════════════════════════════════════════ */
    var sid = window.BOOSOK_SESSION_ID || '';
    var bootedSid = '';
    try { bootedSid = localStorage.getItem('boosok_session_booted'); } catch (e) { }
    var sessBooted = false;
    try { sessBooted = sessionStorage.getItem('boosok_hub_booted') === '1'; } catch (e) { }
    var isAlreadyBooted = (sid && bootedSid === sid) || sessBooted;
    var BOOT_TIMEOUT_MS = 10000;
    var LETTER_STEP = 0.12;    // detik antar huruf
    var CYCLE = 5;             // detik, harus sama dengan --cycle di hub.css
    var WORD = 'Boosok Tools';
    // Loader baru dilepas setelah huruf terakhir selesai muncul dan tenang (30% siklus)
    var MIN_BOOT_MS = Math.round((0.1 + (WORD.length - 1) * LETTER_STEP + CYCLE * 0.3) * 1000);
    var bootStart = Date.now(), pending = null, bootTimer = null;
    document.documentElement.style.setProperty('--boot', MIN_BOOT_MS + 'ms');
    if (isAlreadyBooted) {
      var _bootEl = document.getElementById('boot');
      if (_bootEl) { _bootEl.style.display = 'none'; _bootEl.classList.add('done'); }
    } else {
      // Susun teks loader: tiap huruf punya delay animasi sendiri
      (function buildLoader() {
        var box = document.getElementById('loaderText');
        if (!box) return;
        WORD.split('').forEach(function (ch, i) {
          var span = document.createElement('span');
          span.className = 'loader-letter';
          span.textContent = ch;
          span.style.animationDelay = (0.1 + i * LETTER_STEP).toFixed(3) + 's';
          box.insertBefore(span, box.lastChild);
        });
      })();
    }

    var S = {
      status: isAlreadyBooted ? 'ready' : 'booting',
      data: {
        version: '',
        stats: { objects: 0, scenes: 0, selected: 0 },
        license: { status: 'trial', can_use: true, rem_seconds: 3600 }
      },
      lastKey: null
    };
    var searchQuery = '';

    function getRecent() {
      try { return JSON.parse(localStorage.getItem(LS_RECENT)) || []; } catch (e) { return []; }
    }
    function saveRecent(id) {
      try {
        var arr = getRecent().filter(function (x) { return x !== id; });
        arr.unshift(id);
        localStorage.setItem(LS_RECENT, JSON.stringify(arr.slice(0, 5)));
      } catch (e) { }
    }
    function getLastUsed() {
      var arr = getRecent();
      return arr.length ? arr[0] : null;
    }

    /* ═══════════════════════════════════════════════
       Hub Render (Instant, Zero Delay)
    ═══════════════════════════════════════════════ */
    function requestState() {
      clearTimeout(bootTimer);
      bootTimer = setTimeout(function () {
        render({ status: 'error', error: 'SketchUp tidak merespon. Tutup jendela ini lalu buka lagi dari menu Extensions.' });
      }, BOOT_TIMEOUT_MS);
      function tryReady() {
        if (window.sketchup) {
          if (typeof sketchup.hub_ready === 'function') { sketchup.hub_ready(); return true; }
          else if (typeof sketchup.ready === 'function') { sketchup.ready(); return true; }
        }
        return false;
      }
      if (!tryReady()) {
        var retries = 0;
        var ri = setInterval(function () {
          retries++;
          if (tryReady() || retries > 60) clearInterval(ri);
        }, 25);
      }
    }

    function markBooted(curSid) {
      if (curSid) { try { localStorage.setItem('boosok_session_booted', curSid); } catch (e) { } }
      try { sessionStorage.setItem('boosok_hub_booted', '1'); } catch (e) { }
    }

    var bootHiding = false;
    function hideBoot(animated) {
      var bootEl = document.getElementById('boot');
      if (!bootEl || bootHiding) return;
      bootEl.classList.add('done');
      if (animated) {
        bootHiding = true; // fade 0,9 dtk jangan dipotong oleh pemanggilan berikutnya
        setTimeout(function () { bootEl.style.display = 'none'; }, 950);
      } else {
        bootEl.style.display = 'none';
      }
    }

    // Selesai menahan loader: pudarkan loader, tampilkan hub lewat jalur render biasa, kabari Ruby.
    function finishBoot() {
      if (S.status !== 'booting' || !pending) return;
      var st = pending; pending = null;
      markBooted(window.BOOSOK_SESSION_ID || st.session_id || '');
      S.status = 'ready';
      hideBoot(true);
      render(st);
      if (window.sketchup && sketchup.boot_done) sketchup.boot_done();
    }

    function render(st) {
      if (!st) return;
      clearTimeout(bootTimer);

      // Gerbang boot: apakah sesi ini sudah pernah menampilkan loader?
      var curSid = window.BOOSOK_SESSION_ID || st.session_id || '';
      var curBooted = '';
      try { curBooted = localStorage.getItem('boosok_session_booted'); } catch (e) { }
      var curSess = false;
      try { curSess = sessionStorage.getItem('boosok_hub_booted') === '1'; } catch (e) { }
      var isBooted = st.has_booted || (curSid && curBooted === curSid) || curSess;

      if (st.status === 'error') {
        // Error tidak boleh tertahan di balik loader
        pending = null; S.status = 'ready'; hideBoot(false);
      } else if (isBooted) {
        markBooted(curSid);
        if (S.status === 'booting') S.status = 'ready';
        hideBoot(false);
      } else if (S.status === 'booting') {
        // Loader pertama kali: tahan sampai animasinya selesai (MIN_BOOT_MS), baru tampilkan hub
        pending = st;
        clearTimeout(bootTimer);
        bootTimer = setTimeout(finishBoot, Math.max(0, MIN_BOOT_MS - (Date.now() - bootStart)));
        return;
      }

      if (st.theme && !getStoredTheme()) applyTheme(st.theme);
      if (st.locales) window.registerBoosokLocales(st.locales);
      if (st.language) {
        var userSavedLang = '';
        try { userSavedLang = localStorage.getItem('boosok_language'); } catch (e) { }
        if (!userSavedLang) {
          currentLang = st.language;
          if (typeof window.setBoosokLang === 'function') window.setBoosokLang(st.language);
          else window.BOOSOK_LANG = st.language;
        }
      }
      var key = JSON.stringify(st);
      if (key === S.lastKey) return;
      S.lastKey = key;
      S.status = st.status;
      S.data = st;
      applyTranslations();
      draw();
    }

    // Refresh ringan saat jendela kembali difokus: hanya angka statistik & lisensi.
    function onHubRefresh(d) {
      if (!d || !S.data || S.status !== 'ready') return;
      var oldLic = S.data.license || {};
      var lic = d.license || oldLic;
      S.data.stats = d.stats || S.data.stats;
      S.data.license = lic;
      if (lic.status !== oldLic.status || lic.can_use !== oldLic.can_use) { draw(); return; }
      var note = document.getElementById('statsNote');
      if (note) note.innerHTML = statsNoteInner(S.data.stats);
      var tt = document.querySelector('.tb-trial-text span');
      if (tt && lic.status === 'trial') tt.innerHTML = trialText(lic);
    }

    function statsNoteInner(stats) {
      stats = stats || {};
      return icon('info') +
        '<span><b>' + (stats.selected || 0) + '</b> ' + esc(ht('selected', 'terseleksi')) + ' · <b>' + (stats.objects || 0) +
        '</b> ' + esc(ht('group_comp', 'group/comp')) + ' · <b>' + (stats.scenes || 0) + '</b> ' + esc(ht('scene', 'scene')) + '</span>';
    }

    function trialText(lic) {
      var timeStr = formatTrialTime(lic);
      return ht('trial_active', 'Trial: <strong>{time} tersisa</strong>').replace('{time}', timeStr).replace('{days} hari', timeStr);
    }

    var hasAnimated = false;

    function draw() {
      var app = document.getElementById('app');
      if (!app) return;
      // Animasi masuk hanya sekali per load halaman; redraw berikutnya langsung tampil
      if (!hasAnimated) { app.classList.add('enter'); hasAnimated = true; }
      else app.classList.remove('enter');

      if (!S.data) {
        S.data = {
          version: '',
          stats: { objects: 0, scenes: 0, selected: 0 },
          license: { status: 'trial', can_use: true, rem_seconds: 3600 }
        };
      }

      if (S.status === 'error') {
        updateSettingsLock(true);
        app.innerHTML =
          '<div class="hero"><div class="badge err">' + icon('triangle-alert') + '</div>' +
          '<h2>' + esc(ht('error_title', 'Gagal memuat')) + '</h2><p>' + esc(ht('error_desc', 'Tool belum bisa dibuka.')) + '</p></div>' +
          '<div class="note err">' + icon('circle-alert') + '<span>' + esc(S.data.error) + '</span></div>' +
          '<div class="spacer"></div>' +
          '<div class="actions"><button class="btn primary" onclick="retry(this)">' +
          icon('refresh-cw') + '<span>' + esc(ht('try_again', 'Coba lagi')) + '</span></button></div>';
        autoFitHeight(0); return;
      }

      var stats = S.data.stats || { objects: 0, scenes: 0, selected: 0 };
      var foot = '<div class="foot"><span class="pill">v' + esc(S.data.version || '1.0.0') + '</span>' +
        '<button class="btn link" id="updBtn" onclick="openUpdate(this)">' +
        icon('download') + '<span>' + esc(ht('check_update', 'Cek update')) + '</span></button></div>';

      updateSettingsLock(false);

      var lic = (S.data && S.data.license) ? S.data.license : null;

      var trialBannerHtml = '';
      if (lic) {
        if (lic.status === 'expired') {
          trialBannerHtml =
            '<div class="trial-banner expired" onclick="openAbout()">' +
            '<div class="tb-icon">' + icon('triangle-alert') + '</div>' +
            '<div class="tb-body">' +
            '<div class="tb-title">' + esc(ht('trial_expired_title', 'Masa Trial 7 Hari Telah Habis')) + '</div>' +
            '<div class="tb-desc">' + esc(ht('trial_expired_desc', 'Masukkan lisensi key untuk membuka semua tool.')) + '</div>' +
            '</div>' +
            '<button class="tb-action" onclick="openAbout(); event.stopPropagation();">' + esc(ht('activate', 'Aktifkan')) + '</button>' +
            '</div>';
        } else if (lic.status === 'trial') {
          var tText = trialText(lic);
          trialBannerHtml =
            '<div class="trial-banner trial" onclick="openAbout()" title="' + esc(ht('about_title', 'Tentang Boosok Tools')) + '">' +
            '<div class="tb-trial-text">' + icon('info') + '<span>' + tText + '</span></div>' +
            '<span class="tb-trial-link">' + esc(ht('activate_license', 'Aktifkan Lisensi →')) + '</span>' +
            '</div>';
        }
      }

      var lastId = getLastUsed();
      var lastTool = lastId ? TOOL_MAP[lastId] : null;

      var recentHtml = '';
      if (lastTool) {
        var lTitle = getToolTitle(lastTool);
        var lDesc = getToolDesc(lastTool);
        if (isToolLocked(lastTool.id)) {
          recentHtml =
            '<div id="recentSection">' +
            '<div class="sec-label">' + esc(ht('recent_label', 'Terakhir dipakai')) + '</div>' +
            '<div id="recentCard" class="locked" role="button" tabindex="0" onclick="onLicenseExpiredPrompt()">' +
            '<div class="rc-ic">' + icon(lastTool.icon) + '</div>' +
            '<div class="rc-txt"><div class="t">' + esc(lTitle) + '</div><div class="s">' + esc(lDesc) + '</div></div>' +
            '<span class="rc-badge" style="background:var(--err-soft,#fff0f0);color:var(--err,#dc2626);border-color:var(--err,#dc2626);font-weight:700;">' + esc(ht('locked', 'Terkunci')) + '</span>' +
            '</div></div>';
        } else {
          recentHtml =
            '<div id="recentSection">' +
            '<div class="sec-label">' + esc(ht('recent_label', 'Terakhir dipakai')) + '</div>' +
            '<div id="recentCard" role="button" tabindex="0" onclick="openTool(\'' + lastTool.id + '\')">' +
            '<div class="rc-ic">' + icon(lastTool.icon) + '</div>' +
            '<div class="rc-txt"><div class="t">' + esc(lTitle) + '</div><div class="s">' + esc(lDesc) + '</div></div>' +
            '<span class="rc-badge">' + esc(ht('open_again', 'Buka lagi')) + '</span>' +
            '</div></div>';
        }
      }

      var searchHtml =
        '<div class="search-wrap">' +
        '<svg class="lead" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>' +
        '<input id="searchInput" type="text" placeholder="' + esc(ht('search_placeholder', 'Cari tool...')) + '" autocomplete="off" value="' + esc(searchQuery) + '" oninput="onSearch(this.value)">' +
        '<button id="searchClear" class="' + (searchQuery ? 'vis' : '') + '" onclick="clearSearch()" title="' + esc(ht('search_clear', 'Hapus pencarian')) + '">' +
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>' +
        '</button></div>';

      var gridHtml = '<div class="grid-wrap" id="gridWrap">' + buildGrid(stats) +
        '<div id="noResult">' +
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/><line x1="8" y1="11" x2="14" y2="11"/></svg>' +
        esc(ht('no_tools_found', 'Tidak ada tool yang cocok')) + '</div></div>';

      var statsNote = '<div class="note" id="statsNote">' + statsNoteInner(stats) + '</div>';

      app.innerHTML = searchHtml + trialBannerHtml + recentHtml +
        '<div class="sec-label all-label">' + esc(ht('all_tools_label', 'Semua tools')) + '</div>' +
        gridHtml + statsNote + foot;

      if (searchQuery) {
        var si = document.getElementById('searchInput');
        if (si) { si.focus(); si.setSelectionRange(9999, 9999); filterGrid(searchQuery); }
      }

      autoFitHeight(0);
      setTimeout(function () { autoFitHeight(0); }, 50);
    }

    /* Tool gratis tetap bisa dipakai walau trial habis (daftar utama dari Ruby: S.data.free_tools) */
    var FREE_TOOLS_DEFAULT = ['selector', 'replacer', 'reset', 'clean', 'untag', 'purge'];
    function isToolLocked(id) {
      var lic = S.data && S.data.license;
      if (!lic || lic.can_use) return false;
      var free = (S.data && S.data.free_tools) || FREE_TOOLS_DEFAULT;
      return free.indexOf(id) < 0;
    }

    function isFreeTool(id) {
      return ((S.data && S.data.free_tools) || FREE_TOOLS_DEFAULT).indexOf(id) >= 0;
    }

    /* Satu grid 4 kolom; tool gratis di bagian atas, lalu yang berbayar (urutan asli dipertahankan di tiap bagian) */
    function buildGrid(stats) {
      var sorted = TOOLS.filter(function (t) { return isFreeTool(t.id); })
        .concat(TOOLS.filter(function (t) { return !isFreeTool(t.id); }));
      return '<div class="grid4" id="grid4">' + sorted.map(buildTile).join('') + '</div>';
    }

    function buildTile(tool) {
      {
        var isLocked = isToolLocked(tool.id);
        var cls = 'tile4';
        var attr = '';
        var tTitle = getToolTitle(tool);
        var tDesc = getToolDesc(tool);
        if (isLocked) {
          cls += ' locked';
          attr = ' onclick="onLicenseExpiredPrompt()" title="' + esc(ht('locked_trial_title', 'Terkunci — Masa trial 7 hari telah habis')) + '"';
        } else {
          attr = ' onclick="openTool(\'' + tool.id + '\')"';
        }
        var searchLabel = (tTitle + ' ' + tool.id + ' ' + tDesc).toLowerCase();
        return '<button class="' + cls + '" data-id="' + tool.id + '" data-label="' + esc(searchLabel) + '"' + attr + '>' +
          (isLocked ? '<span class="lock-tag">' + icon('key-round') + '</span>' : '') +
          '<div class="ic4">' + icon(tool.icon) + '</div>' +
          '<div class="t4">' + esc(tTitle) + '</div>' +
          '</button>';
      }
    }

    /* ═══════════════════════════════════════════════
       Search
    ═══════════════════════════════════════════════ */
    function onSearch(val) {
      searchQuery = val.trim().toLowerCase();
      var clrBtn = document.getElementById('searchClear');
      if (clrBtn) clrBtn.classList.toggle('vis', searchQuery.length > 0);
      var recentSec = document.getElementById('recentSection');
      if (recentSec) recentSec.style.display = searchQuery ? 'none' : '';
      filterGrid(searchQuery);
    }

    function clearSearch() {
      searchQuery = '';
      var si = document.getElementById('searchInput');
      if (si) { si.value = ''; si.focus(); }
      var clrBtn = document.getElementById('searchClear');
      if (clrBtn) clrBtn.classList.remove('vis');
      filterGrid('');
      var recentSec = document.getElementById('recentSection');
      if (recentSec) recentSec.style.display = '';
    }

    function filterGrid(q) {
      var tiles = document.querySelectorAll('.tile4'), visible = 0;
      tiles.forEach(function (tile) {
        var show = !q || (tile.dataset.label || '').indexOf(q) !== -1;
        tile.style.display = show ? '' : 'none';
        if (show) visible++;
      });
      var nr = document.getElementById('noResult');
      if (nr) nr.style.display = visible === 0 ? 'block' : 'none';
    }

    /* ═══════════════════════════════════════════════
       Open Tool
    ═══════════════════════════════════════════════ */
    // Klik tool saat terkunci: cukup notifikasi (tanpa membuka panel aktivasi).
    // Aktivasi tetap bisa lewat tombol "Aktifkan" di banner atau Pengaturan > Tentang.
    function onLicenseExpiredPrompt() {
      showToast(ht('lic_trial_expired_toast', 'Masa trial 7 hari telah habis.'), 'error');
    }

    function openTool(id) {
      if (S.status !== 'ready') return;
      if (isToolLocked(id)) {
        onLicenseExpiredPrompt();
        return;
      }
      saveRecent(id);

      /* custom_select hanya mengaktifkan tool di SketchUp lalu menutup dialog —
         tidak perlu state 'opening' atau animasi tile */
      if (id === 'custom_select') {
        if (window.sketchup && typeof sketchup.open === 'function') {
          var x = window.screenX || window.screenLeft || 0;
          var y = window.screenY || window.screenTop || 0;
          sketchup.open(id, JSON.stringify({ left: x, top: y }));
        }
        return;
      }

      S.status = 'opening';
      document.querySelectorAll('.tile4').forEach(function (el) {
        el.disabled = true;
        if (el.dataset.id === id) {
          el.classList.add('opening');
          el.querySelector('.ic4').innerHTML = icon('loader-circle');
        }
      });
      var rc = document.getElementById('recentCard');
      if (rc) rc.style.pointerEvents = 'none';
      var x = window.screenX || window.screenLeft || 0;
      var y = window.screenY || window.screenTop || 0;
      if (window.sketchup && typeof sketchup.open === 'function') {
        sketchup.open(id, JSON.stringify({ left: x, top: y }));
      }
      setTimeout(function () {
        if (S.status === 'opening') { S.status = 'ready'; draw(); }
      }, 4000);
    }

    function onOpenFailed(msg) { S.status = 'ready'; draw(); showToast(esc(msg)); }

    function retry(btn) { busy(btn, true); S.lastKey = null; requestState(); }

    // Kembali dari jendela model: cukup refresh angka (ringan), bukan state + redraw penuh.
    var lastFocusRefresh = 0;
    window.addEventListener('focus', function () {
      var now = Date.now();
      if (now - lastFocusRefresh < 800) return;
      lastFocusRefresh = now;
      if (S.status === 'error') { requestState(); return; }
      if (S.status !== 'ready') return;
      if (window.sketchup && typeof sketchup.hub_refresh === 'function') sketchup.hub_refresh();
      else requestState();
    });

    /* ═══════════════════════════════════════════════
       Inline Update Panel
    ═══════════════════════════════════════════════ */
    var updOpen = false;

    function openUpdate(btn) {
      // Animasikan tombol loading
      if (btn) {
        btn.disabled = true;
        btn.innerHTML = icon('loader-circle') + '<span>Memeriksa…</span>';
        btn.querySelector('svg').style.animation = 'spin .8s linear infinite';
      }
      showUpdatePanel({ status: 'checking' });
      // Request ke Ruby
      if (window.sketchup && typeof sketchup.updates === 'function') {
        sketchup.updates();
      }
    }

    function showUpdatePanel(st) {
      updOpen = true;
      var panel = document.getElementById('updatePanel');
      panel.classList.add('open');
      renderUpdatePanel(st);
    }

    function closeUpdate() {
      updOpen = false;
      var panel = document.getElementById('updatePanel');
      panel.classList.remove('open');
      // Restore tombol Cek update di footer
      var btn = document.getElementById('updBtn');
      if (btn) {
        btn.disabled = false;
        btn.innerHTML = icon('download') + '<span>Cek update</span>';
      }
    }

    /**
     * Dipanggil dari Ruby via hub.rb: renderUpdate(state_json)
     * state: { status, current, latest, changelog, download_url, progress, error }
     * status: checking | latest | available | downloading | installing | done | error
     */
    function renderUpdate(st) {
      // Buka panel otomatis jika belum terbuka (mis. update tersedia saat startup)
      if (!updOpen) showUpdatePanel(st);
      else renderUpdatePanel(st);
    }

    function renderUpdatePanel(st) {
      var ic = document.getElementById('updIc');
      var title = document.getElementById('updTitle');
      var vers = document.getElementById('updVersions');
      var curr = document.getElementById('updCurrent');
      var latest = document.getElementById('updLatest');
      var prog = document.getElementById('updProgress');
      var bar = document.getElementById('updBar');
      var log = document.getElementById('updLog');
      var msg = document.getElementById('updMsg');
      var acts = document.getElementById('updActions');

      // reset
      vers.style.display = 'none';
      prog.style.display = 'none';
      log.style.display = 'none';
      msg.className = 'upd-msg';
      msg.textContent = '';
      acts.style.display = 'none';
      acts.innerHTML = '';

      var s = st.status || 'checking';

      if (s === 'checking') {
        ic.innerHTML = spinIcon();
        title.textContent = 'Memeriksa pembaruan…';
        msg.textContent = 'Menghubungi server…';

      } else if (s === 'latest') {
        ic.innerHTML = checkIcon();
        ic.style.background = 'var(--ok-soft)';
        ic.style.color = 'var(--ok)';
        title.textContent = 'Sudah versi terbaru';
        if (st.current) {
          curr.textContent = 'v' + st.current;
          vers.style.display = 'none'; // hanya 1 versi, tidak perlu arrow
          msg.textContent = 'v' + st.current + ' — tidak ada pembaruan baru.';
        }
        msg.className = 'upd-msg ok';
        acts.innerHTML = '<button class="btn ghost sm" onclick="closeUpdate()">' + icon('x') + '<span>Tutup</span></button>';
        acts.style.display = 'flex';

      } else if (s === 'available') {
        ic.innerHTML = downloadIcon();
        ic.style.background = '';
        ic.style.color = '';
        title.textContent = 'Ada pembaruan tersedia!';
        curr.textContent = 'v' + (st.current || '?');
        latest.textContent = 'v' + (st.latest || '?');
        vers.style.display = 'flex';
        if (st.changelog) {
          log.textContent = st.changelog;
          log.style.display = 'block';
        }
        acts.innerHTML =
          '<button class="btn ghost sm" onclick="closeUpdate()">' + icon('x') + '<span>Nanti</span></button>' +
          '<button class="btn primary sm" onclick="doDownload(this)">' + icon('download') + '<span>Update Sekarang</span></button>';
        acts.style.display = 'flex';

      } else if (s === 'downloading') {
        ic.innerHTML = spinIcon();
        title.textContent = 'Mengunduh…';
        var pct = typeof st.progress === 'number' ? st.progress : 0;
        bar.style.width = pct + '%';
        prog.style.display = 'block';
        msg.textContent = pct > 0 ? pct + '%' : 'Sedang mengunduh…';

      } else if (s === 'installing') {
        ic.innerHTML = spinIcon();
        title.textContent = 'Memasang…';
        msg.textContent = 'Mohon tunggu, jangan tutup SketchUp.';

      } else if (s === 'done') {
        ic.innerHTML = checkIcon();
        ic.style.background = 'var(--ok-soft)';
        ic.style.color = 'var(--ok)';
        title.textContent = 'Update berhasil dipasang!';
        msg.textContent = st.restart
          ? 'Update terpasang. Restart SketchUp agar versi baru aktif.'
          : 'Plugin sudah aktif, tidak perlu restart SketchUp.';
        msg.className = 'upd-msg ok';
        acts.innerHTML = '<button class="btn primary sm" onclick="closeUpdate()">' + icon('check') + '<span>Selesai</span></button>';
        acts.style.display = 'flex';

      } else if (s === 'error') {
        ic.innerHTML = alertIcon();
        ic.style.background = 'var(--err-soft)';
        ic.style.color = 'var(--err)';
        title.textContent = 'Gagal memeriksa';
        msg.textContent = st.error || 'Terjadi kesalahan.';
        msg.className = 'upd-msg err';
        acts.innerHTML =
          '<button class="btn ghost sm" onclick="closeUpdate()">' + icon('x') + '<span>Tutup</span></button>' +
          '<button class="btn primary sm" onclick="retryUpdate(this)">' + icon('refresh-cw') + '<span>Coba lagi</span></button>';
        acts.style.display = 'flex';
      }
    }

    function doDownload(btn) {
      btn.disabled = true;
      if (window.sketchup && typeof sketchup.update_download === 'function') {
        sketchup.update_download();
      }
    }

    function retryUpdate(btn) {
      btn.disabled = true;
      renderUpdatePanel({ status: 'checking' });
      if (window.sketchup && typeof sketchup.updates === 'function') {
        sketchup.updates();
      }
    }

    /* Inline SVG helpers untuk update panel */
    function spinIcon() {
      return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" style="animation:spin .8s linear infinite"><path d="M21 12a9 9 0 1 1-6.219-8.56"/></svg>';
    }
    function checkIcon() {
      return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>';
    }
    function downloadIcon() {
      return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>';
    }
    function alertIcon() {
      return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>';
    }

    /* Render instan dengan data default agar grid langsung tampil.
       Ruby akan mengirim state asli via render() sesaat kemudian. */
    draw();
    requestState();

    /* ═══════════════════════════════════════════════
       Settings Dropdown
    ═══════════════════════════════════════════════ */
    function toggleSettingsMenu() {
      var menu = document.getElementById('settingsMenu');
      if (!menu) return;
      var isOpen = menu.classList.contains('open');
      menu.classList.toggle('open', !isOpen);
      if (!isOpen) {
        // tutup jika klik di luar
        setTimeout(function () {
          document.addEventListener('click', closeSettingsOnOutside, { once: true });
        }, 10);
      }
    }

    function closeSettingsOnOutside(e) {
      var wrap = document.getElementById('settingsWrap');
      if (wrap && !wrap.contains(e.target)) {
        var menu = document.getElementById('settingsMenu');
        if (menu) menu.classList.remove('open');
      }
    }

    function closeSettingsMenu() {
      var menu = document.getElementById('settingsMenu');
      if (menu) menu.classList.remove('open');
    }

    /* Kunci / buka tombol Settings (Bahasa & Tentang) saat model kosong */
    function updateSettingsLock(locked) {
      var wrap = document.getElementById('settingsWrap');
      var btn = document.getElementById('settingsBtn');
      if (!wrap || !btn) return;
      if (locked) {
        wrap.classList.add('locked');
        btn.disabled = true;
        btn.title = 'Tersedia setelah ada isi model';
        /* Tutup menu jika kebetulan sedang terbuka */
        closeSettingsMenu();
      } else {
        wrap.classList.remove('locked');
        btn.disabled = false;
        btn.title = 'Pengaturan';
      }
    }

    /* ═══════════════════════════════════════════════
       About + Lisensi
    ═══════════════════════════════════════════════ */
    function openAbout() {
      closeSettingsMenu();
      var verEl = document.getElementById('aboutVer');
      if (verEl && S.data && S.data.version) verEl.textContent = 'v' + S.data.version;
      document.getElementById('aboutOverlay').classList.add('open');
      applyTranslations();
      // Muat status lisensi dari Ruby
      if (window.sketchup && typeof sketchup.get_license_status === 'function') {
        sketchup.get_license_status();
      } else {
        // Mode browser preview — tampilkan placeholder
        onLicenseStatus({ status: 'unlicensed', hw_id: 'PREVIEW00', hw_short: 'PREVIEW0' });
      }
    }

    function closeAbout() {
      document.getElementById('aboutOverlay').classList.remove('open');
    }

    // Nomor HP disamarkan di tampilan: 081234567890 -> 0812-****-7890
    function maskPhone(p) {
      var raw = String(p || '').trim();
      if (!raw) return '';
      var plus = raw.charAt(0) === '+' ? '+' : '';
      var d = raw.replace(/[^0-9]/g, '');
      if (d.length < 8) return plus + d.charAt(0) + '***';
      return plus + d.slice(0, 4) + '-****-' + d.slice(-4);
    }

    // Dipanggil oleh Ruby setelah get_license_status
    function onLicenseStatus(st) {
      var badge = document.getElementById('licBadge');
      var hwEl = document.getElementById('licHwId');
      var notice = document.getElementById('licNotice');
      var mailLink = document.getElementById('licMailLink');
      var inputWrap = document.getElementById('licInputWrap');
      var unlicensedBtns = document.getElementById('licUnlicensedBtns');
      var activeBtns = document.getElementById('licActiveBtns');
      var keyInput = document.getElementById('licKeyInput');

      if (!badge) return;

      // Update Hardware ID
      if (hwEl && st.hw_id) {
        hwEl.textContent = st.hw_id;
      }

      // Simpan Hardware ID untuk URL email
      if (st.hw_id) {
        window._currentHwId = st.hw_id;
      }

      // Sinkronkan ke S.data.license agar Hub langsung responsif
      if (S.data) {
        S.data.license = st;
      }

      var isActive = (st.status === 'active');
      // Nama & nomor HP terdaftar di server (hanya saat aktif dan datanya ada)
      [['licNameRow', 'licNameVal', st.name], ['licPhoneRow', 'licPhoneVal', maskPhone(st.phone)]].forEach(function (r) {
        var row = document.getElementById(r[0]), val = document.getElementById(r[1]);
        if (!row || !val) return;
        var txt = isActive ? String(r[2] || '').trim() : '';
        val.textContent = txt;
        val.title = txt;
        row.style.display = txt ? 'flex' : 'none';
      });
      if (isActive) {
        badge.textContent = ht('lic_active', '✓ AKTIF');
        badge.style.background = 'var(--ok-soft, #e6f9ee)';
        badge.style.borderColor = 'var(--ok, #16a34a)';
        badge.style.color = 'var(--ok, #16a34a)';
        if (notice) notice.style.display = 'none';
        if (inputWrap) inputWrap.style.display = 'none';
        if (unlicensedBtns) unlicensedBtns.style.display = 'none';
        if (activeBtns) activeBtns.style.display = 'flex';
      } else if (st.status === 'trial') {
        var timeStr = formatTrialTime(st);
        var trialTpl = ht('lic_trial', 'TRIAL ({time})');
        badge.textContent = trialTpl.replace('{time}', timeStr).replace('{days} HARI', timeStr).replace('{days}', timeStr);
        badge.style.background = 'var(--surface)';
        badge.style.borderColor = 'var(--accent, #6366f1)';
        badge.style.color = 'var(--accent, #6366f1)';
        if (notice) notice.style.display = 'block';
        if (inputWrap) inputWrap.style.display = 'flex';
        if (unlicensedBtns) unlicensedBtns.style.display = 'flex';
        if (activeBtns) activeBtns.style.display = 'none';
        if (keyInput) {
          keyInput.style.borderColor = 'var(--line)';
          keyInput.value = '';
          keyInput.placeholder = 'XXXXX-XXXXX-XXXXX-XXXXX';
        }
      } else if (st.status === 'expired') {
        badge.textContent = ht('lic_expired', '✗ TERKUNCI (EXPIRED)');
        badge.style.background = 'var(--err-soft, #fff0f0)';
        badge.style.borderColor = 'var(--err, #dc2626)';
        badge.style.color = 'var(--err, #dc2626)';
        if (notice) notice.style.display = 'block';
        if (inputWrap) inputWrap.style.display = 'flex';
        if (unlicensedBtns) unlicensedBtns.style.display = 'flex';
        if (activeBtns) activeBtns.style.display = 'none';
        if (keyInput) {
          keyInput.style.borderColor = 'var(--err, #dc2626)';
          keyInput.value = '';
          keyInput.placeholder = ht('lic_placeholder_expired', 'Masukkan lisensi untuk membuka');
        }
      } else if (st.status === 'invalid') {
        badge.textContent = ht('lic_invalid', '✗ TIDAK VALID');
        badge.style.background = 'var(--err-soft, #fff0f0)';
        badge.style.borderColor = 'var(--err, #dc2626)';
        badge.style.color = 'var(--err, #dc2626)';
        if (notice) notice.style.display = 'block';
        if (inputWrap) inputWrap.style.display = 'flex';
        if (unlicensedBtns) unlicensedBtns.style.display = 'flex';
        if (activeBtns) activeBtns.style.display = 'none';
        if (keyInput) {
          keyInput.style.borderColor = 'var(--err, #dc2626)';
          keyInput.value = '';
          keyInput.placeholder = ht('lic_placeholder_invalid', 'Kode tidak valid — coba lagi');
        }
      } else {
        badge.textContent = ht('lic_unlicensed', 'BELUM AKTIF');
        badge.style.background = 'var(--surface)';
        badge.style.borderColor = 'var(--line)';
        badge.style.color = 'var(--muted)';
        if (notice) notice.style.display = 'block';
        if (inputWrap) inputWrap.style.display = 'flex';
        if (unlicensedBtns) unlicensedBtns.style.display = 'flex';
        if (activeBtns) activeBtns.style.display = 'none';
        if (keyInput) {
          keyInput.style.borderColor = 'var(--line)';
          keyInput.value = '';
          keyInput.placeholder = 'XXXXX-XXXXX-XXXXX-XXXXX';
        }
      }
    }

    // Kirim key ke Ruby untuk divalidasi
    function activateLicense(btn) {
      var keyInput = document.getElementById('licKeyInput');
      var key = keyInput ? keyInput.value.trim() : '';
      if (!key || key.length < 10) {
        if (keyInput) {
          keyInput.style.borderColor = 'var(--err, #dc2626)';
          keyInput.focus();
        }
        return;
      }
      if (btn) { busy(btn, true); }
      if (window.sketchup && typeof sketchup.validate_license === 'function') {
        sketchup.validate_license(JSON.stringify(key));
      }
      // Timeout fallback jika Ruby tidak menjawab
      setTimeout(function () {
        if (btn && btn.disabled) busy(btn, false);
      }, 5000);
    }

    // Dipanggil Ruby setelah validasi
    // Pesan hasil aktivasi (reason dari license.rb: invalid_key, revoked, device_limit, network, bad_response, error)
    function licenseErrorText(reason, extra) {
      if (reason === 'device_limit') {
        var n = (extra && extra.max) ? extra.max : '?';
        return ht('lic_err_device_limit', 'Key ini sudah dipakai di {n} perangkat. Lepas perangkat lama lewat Tentang > Hapus Aktivasi, atau hubungi author.').replace('{n}', n);
      }
      if (reason === 'revoked') return ht('lic_err_revoked', 'Key ini sudah dicabut. Hubungi author.');
      if (reason === 'network') return ht('lic_err_network', 'Tidak bisa terhubung ke server lisensi. Periksa koneksi internet lalu coba lagi.');
      if (reason === 'bad_response') return ht('lic_err_bad_response', 'Jawaban server tidak valid. Coba lagi nanti.');
      return ht('lic_err_invalid', 'Key tidak valid.');
    }

    function onLicenseValidated(success, st, reason, extra) {
      var btn = document.getElementById('licActivateBtn');
      if (btn) busy(btn, false);
      var keyInput = document.getElementById('licKeyInput');
      if (success) {
        if (keyInput) keyInput.style.borderColor = 'var(--ok, #16a34a)';
        if (st) {
          if (S.data) S.data.license = st;
          onLicenseStatus(st);
          draw(); // Refresh tampilan Hub secara langsung
        }
      } else {
        if (keyInput) {
          keyInput.style.borderColor = 'var(--err, #dc2626)';
          keyInput.value = '';
          keyInput.placeholder = ht('lic_placeholder_invalid', 'Kode tidak valid — coba lagi');
        }
        if (reason && reason !== 'invalid_key') showToast(licenseErrorText(reason, extra), 'error');
        var badge = document.getElementById('licBadge');
        if (badge) {
          badge.textContent = ht('lic_invalid', '✗ TIDAK VALID');
          badge.style.background = 'var(--err-soft, #fff0f0)';
          badge.style.borderColor = 'var(--err, #dc2626)';
          badge.style.color = 'var(--err, #dc2626)';
        }
      }
    }

    // Dipanggil Ruby setelah "Hapus Aktivasi" (online: perangkat dilepas dari key di server)
    function onLicenseRemoved(ok, reason) {
      if (!ok) showToast(licenseErrorText(reason || 'network'), 'error');
      else draw();
    }

    // Hapus lisensi yang tersimpan
    function removeLicense() {
      if (window.sketchup && typeof sketchup.remove_license === 'function') {
        sketchup.remove_license();
      } else {
        var hwText = document.getElementById('licHwId') ? document.getElementById('licHwId').textContent : '';
        onLicenseStatus({ status: 'unlicensed', hw_id: hwText });
        draw();
      }
    }

    // Salin Hardware ID ke clipboard dengan feedback visual jelas
    function copyHwId() {
      var hwEl = document.getElementById('licHwId');
      if (!hwEl) return;
      var text = hwEl.textContent.trim();
      var btn = document.getElementById('btnCopyHwId');
      var copyText = document.getElementById('copyText');
      var copyIconUse = btn ? btn.querySelector('use') : null;

      function onCopied() {
        if (copyText) copyText.textContent = ht('about_copied', 'Tersalin!');
        if (copyIconUse) copyIconUse.setAttribute('href', '#i-check');
        if (btn) {
          btn.style.borderColor = 'var(--ok, #16a34a)';
          btn.style.color = 'var(--ok, #16a34a)';
        }
        setTimeout(function () {
          if (copyText) copyText.textContent = ht('about_copy', 'Salin');
          if (copyIconUse) copyIconUse.setAttribute('href', '#i-copy');
          if (btn) {
            btn.style.borderColor = '';
            btn.style.color = '';
          }
        }, 2000);
      }

      try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(onCopied).catch(function () {
            fallbackCopy(text);
            onCopied();
          });
        } else {
          fallbackCopy(text);
          onCopied();
        }
      } catch (e) {
        fallbackCopy(text);
        onCopied();
      }
    }

    function selectHwId() {
      var hwEl = document.getElementById('licHwId');
      if (!hwEl) return;
      var range = document.createRange();
      range.selectNodeContents(hwEl);
      var sel = window.getSelection();
      if (sel) {
        sel.removeAllRanges();
        sel.addRange(range);
      }
    }

    function fallbackCopy(text) {
      var el = document.createElement('textarea');
      el.value = text;
      el.style.position = 'fixed';
      el.style.opacity = '0';
      document.body.appendChild(el);
      el.select();
      try { document.execCommand('copy'); } catch (e) { }
      document.body.removeChild(el);
    }

    // Nomor WhatsApp author untuk permintaan lisensi key (format internasional tanpa + / 0 di depan)
    var WA_NUMBER = '6282116605101';

    // Link WhatsApp dengan pesan pembelian: pembeli mengisi Nama dan Nomor HP di chat, lalu melampirkan bukti bayar
    function getWaUrl() {
      var text =
        ht('wa_greeting', 'Halo Muh Qosob,') + '\n\n' +
        ht('wa_request', 'Saya ingin membeli lisensi Boosok Tools.') + '\n\n' +
        ht('wa_name', 'Nama') + ' : \n' +
        ht('wa_phone', 'Nomor HP') + ' : \n\n' +
        ht('wa_attach', '(Bukti pembayaran DANA saya kirim di chat ini)') + '\n\n' +
        ht('email_thanks', 'Terima kasih!');
      return 'https://wa.me/' + WA_NUMBER + '?text=' + encodeURIComponent(text);
    }

    function openWhatsApp(e) {
      if (e) {
        try { e.preventDefault(); e.stopPropagation(); } catch (err) { }
      }
      var url = getWaUrl();
      if (window.sketchup && typeof sketchup.open_external_url === 'function') {
        sketchup.open_external_url(url);
      } else {
        window.open(url, '_blank');
      }
      return false;
    }

    // Klik QR DANA: tampilkan lebih besar supaya mudah di-scan dari HP
    function zoomQr() {
      var src = (document.getElementById('licQrImg') || {}).src;
      if (!src) return;
      var ov = document.createElement('div');
      ov.id = 'qrZoom';
      ov.style.cssText = 'position:fixed;inset:0;z-index:150;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,.55);cursor:zoom-out;';
      ov.innerHTML = '<div style="background:#fff;padding:12px;border-radius:14px;box-shadow:0 10px 40px rgba(0,0,0,.4);text-align:center;">' +
        '<img src="' + src + '" alt="QR DANA" style="width:min(300px,80vw);height:auto;display:block;border-radius:6px;">' +
        '<div style="margin-top:6px;font:700 12px/1.3 Segoe UI,sans-serif;color:#18181b;">' + esc(ht('about_qr_label', 'Scan QR DANA')) + ' · Rp25.000</div></div>';
      ov.addEventListener('click', function () { ov.remove(); });
      document.body.appendChild(ov);
    }

    /* Escape menutup language panel, atau about overlay */
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape') return;
      if (document.getElementById('aboutOverlay').classList.contains('open')) { closeAbout(); return; }
      if (document.getElementById('languagePanel') && document.getElementById('languagePanel').classList.contains('open')) { closeLanguagePanel(); return; }
      closeSettingsMenu();
    });
