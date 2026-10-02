// Dipakai semua dialog Boosok Tools: sprite ikon + helper kecil.
// Ikon: Lucide (lucide-static v0.460.0, ISC license, https://lucide.dev).
// Tambah ikon: salin isi <svg> dari lucide.dev jadi <symbol id="i-nama">, pakai icon('nama').
(function () {
  var sprite = '<svg style="display:none" aria-hidden="true">' +
    '<symbol id="i-check" viewBox="0 0 24 24"><path d="M20 6 9 17l-5-5"/></symbol>' +
    '<symbol id="i-x" viewBox="0 0 24 24"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></symbol>' +
    '<symbol id="i-copy" viewBox="0 0 24 24"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></symbol>' +
    '<symbol id="i-mail" viewBox="0 0 24 24"><rect width="20" height="16" x="2" y="4" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/></symbol>' +
    '<symbol id="i-arrow-right" viewBox="0 0 24 24"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></symbol>' +
    '<symbol id="i-arrow-left" viewBox="0 0 24 24"><path d="m12 19-7-7 7-7"/><path d="M19 12H5"/></symbol>' +
    '<symbol id="i-rotate-ccw" viewBox="0 0 24 24"><path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/></symbol>' +
    '<symbol id="i-circle-alert" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><line x1="12" x2="12" y1="8" y2="12"/><line x1="12" x2="12.01" y1="16" y2="16"/></symbol>' +
    '<symbol id="i-circle-check" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/></symbol>' +
    '<symbol id="i-info" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></symbol>' +
    '<symbol id="i-loader-circle" viewBox="0 0 24 24"><path d="M21 12a9 9 0 1 1-6.219-8.56"/></symbol>' +
    '<symbol id="i-search" viewBox="0 0 24 24"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></symbol>' +
    '<symbol id="i-settings" viewBox="0 0 24 24"><path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/></symbol>' +
    '<symbol id="i-settings-2" viewBox="0 0 24 24"><path d="M20 7h-9"/><path d="M14 17H5"/><circle cx="17" cy="17" r="3"/><circle cx="7" cy="7" r="3"/></symbol>' +
    '<symbol id="i-trash-2" viewBox="0 0 24 24"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" x2="10" y1="11" y2="17"/><line x1="14" x2="14" y1="11" y2="17"/></symbol>' +
    '<symbol id="i-plus" viewBox="0 0 24 24"><path d="M5 12h14"/><path d="M12 5v14"/></symbol>' +
    '<symbol id="i-chevron-down" viewBox="0 0 24 24"><path d="m6 9 6 6 6-6"/></symbol>' +
    '<symbol id="i-mouse-pointer-click" viewBox="0 0 24 24"><path d="M14 4.1 12 6"/><path d="m5.1 8-2.9-.8"/><path d="m6 12-1.9 2"/><path d="M7.2 2.2 8 5.1"/><path d="M9.037 9.69a.498.498 0 0 1 .653-.653l11 4.5a.5.5 0 0 1-.074.949l-4.349 1.041a1 1 0 0 0-.74.739l-1.04 4.35a.5.5 0 0 1-.95.074z"/></symbol>' +
    '<symbol id="i-replace" viewBox="0 0 24 24"><path d="M14 4a2 2 0 0 1 2-2"/><path d="M16 10a2 2 0 0 1-2-2"/><path d="M20 2a2 2 0 0 1 2 2"/><path d="M22 8a2 2 0 0 1-2 2"/><path d="m3 7 3 3 3-3"/><path d="M6 10V5a3 3 0 0 1 3-3h1"/><rect x="2" y="14" width="8" height="8" rx="2"/></symbol>' +
    '<symbol id="i-sparkles" viewBox="0 0 24 24"><path d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"/><path d="M20 3v4"/><path d="M22 5h-4"/><path d="M4 17v2"/><path d="M5 18H3"/></symbol>' +
    '<symbol id="i-scale-3d" viewBox="0 0 24 24"><circle cx="19" cy="19" r="2"/><circle cx="5" cy="5" r="2"/><path d="M5 7v12h12"/><path d="m5 19 6-6"/></symbol>' +
    '<symbol id="i-eye-off" viewBox="0 0 24 24"><path d="M10.733 5.076a10.744 10.744 0 0 1 11.205 6.575 1 1 0 0 1 0 .696 10.747 10.747 0 0 1-1.444 2.49"/><path d="M14.084 14.158a3 3 0 0 1-4.242-4.242"/><path d="M17.479 17.499a10.75 10.75 0 0 1-15.417-5.151 1 1 0 0 1 0-.696 10.75 10.75 0 0 1 4.446-5.143"/><path d="m2 2 20 20"/></symbol>' +
    '<symbol id="i-eye" viewBox="0 0 24 24"><path d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"/><circle cx="12" cy="12" r="3"/></symbol>' +
    '<symbol id="i-clapperboard" viewBox="0 0 24 24"><path d="M20.2 6 3 11l-.9-2.4c-.3-1.1.3-2.2 1.3-2.5l13.5-4c1.1-.3 2.2.3 2.5 1.3Z"/><path d="m6.2 5.3 3.1 3.9"/><path d="m12.4 3.4 3.1 4"/><path d="M3 11h18v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"/></symbol>' +
    '<symbol id="i-tag" viewBox="0 0 24 24"><path d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z"/><circle cx="7.5" cy="7.5" r=".5" fill="currentColor"/></symbol>' +
    '<symbol id="i-tags" viewBox="0 0 24 24"><path d="m15 5 6.3 6.3a2.4 2.4 0 0 1 0 3.4L17 19"/><path d="M9.586 5.586A2 2 0 0 0 8.172 5H3a1 1 0 0 0-1 1v5.172a2 2 0 0 0 .586 1.414L8.29 18.29a2.426 2.426 0 0 0 3.42 0l3.58-3.58a2.426 2.426 0 0 0 0-3.42z"/><circle cx="6.5" cy="9.5" r=".5" fill="currentColor"/></symbol>' +
    '<symbol id="i-box" viewBox="0 0 24 24"><path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/><path d="m3.3 7 8.7 5 8.7-5"/><path d="M12 22V12"/></symbol>' +
    '<symbol id="i-package" viewBox="0 0 24 24"><path d="M11 21.73a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73z"/><path d="M12 22V12"/><path d="m3.3 7 7.703 4.734a2 2 0 0 0 1.994 0L20.7 7"/><path d="m7.5 4.27 9 5.15"/></symbol>' +
    '<symbol id="i-paint-bucket" viewBox="0 0 24 24"><path d="m19 11-8-8-8.6 8.6a2 2 0 0 0 0 2.8l5.2 5.2c.8.8 2 .8 2.8 0L19 11Z"/><path d="m5 2 5 5"/><path d="M2 13h15"/><path d="M22 20a2 2 0 1 1-4 0c0-1.6 1.7-2.4 2-4 .3 1.6 2 2.4 2 4Z"/></symbol>' +
    '<symbol id="i-eraser" viewBox="0 0 24 24"><path d="m7 21-4.3-4.3c-1-1-1-2.5 0-3.4l9.6-9.6c1-1 2.5-1 3.4 0l5.6 5.6c1 1 1 2.5 0 3.4L13 21"/><path d="M22 21H7"/><path d="m5 11 9 9"/></symbol>' +
    '<symbol id="i-layers" viewBox="0 0 24 24"><path d="m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65"/><path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/></symbol>' +
    '<symbol id="i-arrow-up" viewBox="0 0 24 24"><path d="m5 12 7-7 7 7"/><path d="M12 19V5"/></symbol>' +
    '<symbol id="i-download" viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" x2="12" y1="15" y2="3"/></symbol>' +
    '<symbol id="i-power" viewBox="0 0 24 24"><path d="M12 2v10"/><path d="M18.4 6.6a9 9 0 1 1-12.77.04"/></symbol>' +
    '<symbol id="i-external-link" viewBox="0 0 24 24"><path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/></symbol>' +
    '<symbol id="i-refresh-cw" viewBox="0 0 24 24"><path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/></symbol>' +
    '<symbol id="i-triangle-alert" viewBox="0 0 24 24"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/></symbol>' +
    '<symbol id="i-focus" viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M3 7V5a2 2 0 0 1 2-2h2"/><path d="M17 3h2a2 2 0 0 1 2 2v2"/><path d="M21 17v2a2 2 0 0 1-2 2h-2"/><path d="M7 21H5a2 2 0 0 1-2-2v-2"/></symbol>' +
    '<symbol id="i-square-dashed-mouse-pointer" viewBox="0 0 24 24"><path d="M12.034 12.681a.498.498 0 0 1 .647-.647l9 3.5a.5.5 0 0 1-.033.943l-3.444 1.068a1 1 0 0 0-.66.66l-1.067 3.443a.5.5 0 0 1-.943.033z"/><path d="M5 3a2 2 0 0 0-2 2"/><path d="M19 3a2 2 0 0 1 2 2"/><path d="M5 21a2 2 0 0 1-2-2"/><path d="M9 3h1"/><path d="M9 21h2"/><path d="M14 3h1"/><path d="M3 9v1"/><path d="M21 9v2"/><path d="M3 14v1"/></symbol>' +
    '<symbol id="i-component" viewBox="0 0 24 24"><path d="M15.536 11.293a1 1 0 0 0 0 1.414l2.376 2.377a1 1 0 0 0 1.414 0l2.377-2.377a1 1 0 0 0 0-1.414l-2.377-2.377a1 1 0 0 0-1.414 0z"/><path d="M2.297 11.293a1 1 0 0 0 0 1.414l2.377 2.377a1 1 0 0 0 1.414 0l2.377-2.377a1 1 0 0 0 0-1.414L6.088 8.916a1 1 0 0 0-1.414 0z"/><path d="M8.916 17.912a1 1 0 0 0 0 1.415l2.377 2.376a1 1 0 0 0 1.414 0l2.377-2.376a1 1 0 0 0 0-1.415l-2.377-2.376a1 1 0 0 0-1.414 0z"/><path d="M8.916 4.674a1 1 0 0 0 0 1.414l2.377 2.376a1 1 0 0 0 1.414 0l2.377-2.376a1 1 0 0 0 0-1.414l-2.377-2.377a1 1 0 0 0-1.414 0z"/></symbol>' +
    '<symbol id="i-key-round" viewBox="0 0 24 24"><path d="M2.586 17.414A2 2 0 0 0 2 18.828V21a1 1 0 0 0 1 1h3a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h1a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h.172a2 2 0 0 0 1.414-.586l.814-.814a6.5 6.5 0 1 0-4-4z"/><circle cx="16.5" cy="7.5" r=".5" fill="currentColor"/></symbol>' +
    '<symbol id="i-sun" viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/></symbol>' +
    '<symbol id="i-moon" viewBox="0 0 24 24"><path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/></symbol>' +
    '<symbol id="i-chevron-right" viewBox="0 0 24 24"><path d="m9 18 6-6-6-6"/></symbol>' +
    '<symbol id="i-spline" viewBox="0 0 24 24"><path d="M21 7.5C21 8.881 19.881 10 18.5 10S16 8.881 16 7.5 17.119 5 18.5 5 21 6.119 21 7.5z"/><path d="M5.5 17.5C5.5 18.881 4.381 20 3 20s-2.5-1.119-2.5-2.5S1.619 15 3 15s2.5 1.119 2.5 2.5z"/><path d="M6 17.7c1-5.4 6.5-6.8 10-4.2"/></symbol>' +
    '<symbol id="i-pentagon" viewBox="0 0 24 24"><path d="M3.5 8.7 12 3l8.5 5.7v6.6L12 21l-8.5-5.7z"/></symbol>' +
    '<symbol id="i-arrow-up-a-z" viewBox="0 0 24 24"><path d="m3 8 4-4 4 4"/><path d="M7 4v16"/><path d="M20 8h-5"/><path d="M15 10V6.5a2.5 2.5 0 0 1 5 0V10"/><path d="M15 14h5l-5 6h5"/></symbol>' +
    '<symbol id="i-arrow-down-z-a" viewBox="0 0 24 24"><path d="m3 16 4 4 4-4"/><path d="M7 20V4"/><path d="M15 4h5l-5 6h5"/><path d="M20 14h-5"/><path d="M15 20v-3.5a2.5 2.5 0 0 1 5 0V20"/></symbol>' +
    '<symbol id="i-chevrons-down-up" viewBox="0 0 24 24"><path d="m7 20 5-5 5 5"/><path d="m7 4 5 5 5-5"/></symbol>' +
    '<symbol id="i-chevrons-up-down" viewBox="0 0 24 24"><path d="m7 15 5 5 5-5"/><path d="m7 9 5-5 5 5"/></symbol>' +
    '<symbol id="i-languages" viewBox="0 0 24 24"><path d="m5 8 6 6"/><path d="m4 14 6-6 2-3"/><path d="M2 5h12"/><path d="M7 2h1"/><path d="m22 22-5-10-5 10"/><path d="M14 18h6"/></symbol>' +
    '<symbol id="i-globe" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/></symbol>' +
    '<symbol id="i-folder-open" viewBox="0 0 24 24"><path d="m6 14 1.5-2.9A2 2 0 0 1 9.24 10H20a2 2 0 0 1 1.94 2.5l-1.54 6a2 2 0 0 1-1.95 1.5H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H18a2 2 0 0 1 2 2v2"/></symbol>' +
    '</svg>';
  document.body.insertAdjacentHTML('afterbegin', sprite);
})();

function icon(id) { return '<svg aria-hidden="true"><use href="#i-' + id + '"/></svg>'; }

function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
  });
}

// <section class="step" id="step1" data-label="1 / 2"> ... ; label tampil di #cur (pill header)
function showStep(n) {
  document.querySelectorAll('.step').forEach(function (el) { el.classList.remove('active'); });
  var s = document.getElementById('step' + n);
  s.classList.add('active');
  var cur = document.getElementById('cur');
  if (cur) cur.textContent = s.dataset.label || '';
}

// Tombol jadi spinner selama Ruby memproses; busy(btn, false) balikin label aslinya
function busy(btn, on) {
  if (typeof btn === 'string') btn = document.getElementById(btn);
  if (on) {
    if (btn.disabled) return;
    btn.dataset.html = btn.innerHTML;
    var procText = (window.t ? window.t('processing', 'Memproses…') : 'Memproses…');
    btn.innerHTML = '<span class="spin">' + icon('loader-circle') + '</span><span>' + procText + '</span>';
    btn.disabled = true;
  } else {
    if (btn.dataset.html != null) btn.innerHTML = btn.dataset.html;
    delete btn.dataset.html;
    btn.disabled = false;
  }
}

// Notifikasi modal dengan tombol OK — menggantikan toast inline.
// type: 'error' (default) | 'success'
function showNotif(msg, type) {
  type = type || 'error';

  var overlay = document.getElementById('notif-overlay');
  if (!overlay) {
    overlay = document.createElement('div');
    overlay.className = 'overlay';
    overlay.id = 'notif-overlay';
    var okLabel = (window.t ? window.t('ok', 'OK') : 'OK');
    overlay.innerHTML =
      '<div class="sheet" id="notif-sheet">' +
        '<div class="notif-head">' +
          '<div class="mark notif-mark"><svg aria-hidden="true"><use href="#i-package"/></svg></div>' +
          '<span class="notif-title">Boosok Tools</span>' +
        '</div>' +
        '<div class="notif-body">' +
          '<svg class="notif-icon" id="notif-icon" aria-hidden="true">' +
            '<use id="notif-icon-href" href="#i-circle-alert"/>' +
          '</svg>' +
          '<span class="notif-msg" id="notif-msg"></span>' +
        '</div>' +
        '<button class="btn primary" id="notif-ok">' + okLabel + '</button>' +
      '</div>';
    document.body.appendChild(overlay);
    document.getElementById('notif-ok').addEventListener('click', function () {
      overlay.classList.remove('open');
      autoFitHeight(0);
    });
    overlay.addEventListener('click', function (e) {
      if (e.target === overlay) {
        overlay.classList.remove('open');
        autoFitHeight(0);
      }
    });
  }

  var iconHref = document.getElementById('notif-icon-href');
  var iconEl   = document.getElementById('notif-icon');
  var msgEl    = document.getElementById('notif-msg');

  iconHref.setAttribute('href', type === 'success' ? '#i-circle-check' : '#i-circle-alert');
  iconEl.className = 'notif-icon ' + type;
  
  var finalMsg = msg;
  if (window.translateMessage) {
    finalMsg = window.translateMessage(msg);
  }
  msgEl.innerHTML = finalMsg;

  overlay.classList.add('open');
  var okBtn = document.getElementById('notif-ok');
  if (okBtn) {
    setTimeout(function () { okBtn.focus(); }, 30);
  }
}

function hideNotif() {
  var ol = document.getElementById('notif-overlay');
  if (ol) {
    ol.classList.remove('open');
    autoFitHeight(0);
  }
}

// Alias agar semua panggilan showToast() dari Ruby tetap berfungsi
var showToast = showNotif;

// Nonaktifkan klik kanan agar tidak membuka context menu / inspect element / devtools
window.addEventListener('contextmenu', function (e) {
  e.preventDefault();
  return false;
}, true);

document.addEventListener('contextmenu', function (e) {
  e.preventDefault();
  return false;
}, true);

// ═══════════════════════════════════════════════════════
// Nonaktifkan CTRL+Scroll Zoom di semua dialog
// Mencegah tata letak dialog rusak akibat zoom tidak sengaja
// ═══════════════════════════════════════════════════════
document.addEventListener('wheel', function (e) {
  if (e.ctrlKey) {
    e.preventDefault();
    e.stopPropagation();
    return false;
  }
}, { passive: false, capture: true });

window.addEventListener('wheel', function (e) {
  if (e.ctrlKey) {
    e.preventDefault();
    e.stopPropagation();
    return false;
  }
}, { passive: false, capture: true });


// Cegah shortcut keyboard devtools & dukung Escape/Enter untuk tutup modal notifikasi
window.addEventListener('keydown', function (e) {
  if (e.key === 'Escape' || e.key === 'Enter') {
    var notifOl = document.getElementById('notif-overlay');
    if (notifOl && notifOl.classList.contains('open')) {
      notifOl.classList.remove('open');
      autoFitHeight(0);
      e.preventDefault();
      return false;
    }
  }

  if (e.key === 'F12' ||
      (e.ctrlKey && e.shiftKey && ['I', 'i', 'J', 'j', 'C', 'c'].indexOf(e.key) !== -1) ||
      (e.ctrlKey && (e.key === 'u' || e.key === 'U'))) {
    e.preventDefault();
    return false;
  }
}, true);

// Esc = klik tombol "Kembali" ke Hub (semua halaman tool). Halaman Hub tidak punya .back-btn,
// jadi tidak terpengaruh. Esc yang sudah ditangani (modal notifikasi, dropdown, dsb.) dilewati,
// dan di dalam kolom input Esc hanya melepas fokus (tekan Esc sekali lagi untuk kembali).
document.addEventListener('keydown', function (e) {
  if (e.key !== 'Escape' || e.defaultPrevented || e.repeat) return;
  var tag = e.target && e.target.tagName;
  if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') {
    if (e.target.blur) e.target.blur();
    return;
  }
  var back = document.querySelector('.back-btn');
  if (back && !back.disabled) {
    e.preventDefault();
    back.click();
  }
});

// ==========================================
// PENGATURAN TEMA (LIGHT / DARK MODE)
// ==========================================
var THEME_KEY = 'boosok_tools_theme';

function getStoredTheme() {
  try {
    return localStorage.getItem(THEME_KEY);
  } catch (e) {
    return null;
  }
}

function setStoredTheme(theme) {
  try {
    localStorage.setItem(THEME_KEY, theme);
  } catch (e) {}
}

function syncThemeWithRuby(theme) {
  try {
    if (window.sketchup && typeof window.sketchup.syncTheme === 'function') {
      window.sketchup.syncTheme(theme);
    } else {
      setTimeout(function () {
        if (window.sketchup && typeof window.sketchup.syncTheme === 'function') {
          window.sketchup.syncTheme(theme);
        }
      }, 100);
    }
  } catch (e) {}
}

function applyTheme(theme) {
  theme = theme === 'dark' ? 'dark' : 'light';
  document.documentElement.setAttribute('data-theme', theme);
  if (document.body) {
    document.body.classList.toggle('dark-mode', theme === 'dark');
  }
  updateThemeButton(theme);
  syncThemeWithRuby(theme);
}

function updateThemeButton(theme) {
  var btn = document.getElementById('themeToggle');
  if (!btn) return;
  var isDark = theme === 'dark';
  btn.setAttribute('aria-label', isDark ? 'Ganti ke Light Mode' : 'Ganti ke Dark Mode');
  btn.setAttribute('title', isDark ? 'Ganti ke Light Mode' : 'Ganti ke Dark Mode');
  btn.innerHTML = icon(isDark ? 'sun' : 'moon');
}

function toggleTheme() {
  var current = document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
  var next = current === 'dark' ? 'light' : 'dark';
  var btn = document.getElementById('themeToggle');
  if (btn) {
    btn.classList.add('toggling');
    setTimeout(function () { btn.classList.remove('toggling'); }, 350);
  }
  setStoredTheme(next);
  applyTheme(next);
}

function initThemeButton() {
  var head = document.querySelector('.head');
  if (!head) return;
  var btn = document.getElementById('themeToggle');
  if (!btn) {
    btn = document.createElement('button');
    btn.id = 'themeToggle';
    btn.className = 'theme-btn';
    btn.type = 'button';
    head.appendChild(btn);
  }
  btn.onclick = toggleTheme;
  updateThemeButton(document.documentElement.getAttribute('data-theme'));
}

// Inisialisasi tema instan agar tidak terjadi flicker/kedip saat membuka dialog
(function () {
  var saved = getStoredTheme();
  var initial = saved ? saved : ((window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light');
  document.documentElement.setAttribute('data-theme', initial);
})();

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', function () {
    initThemeButton();
    syncThemeWithRuby(document.documentElement.getAttribute('data-theme') || 'dark');
  });
} else {
  initThemeButton();
  syncThemeWithRuby(document.documentElement.getAttribute('data-theme') || 'dark');
}

// Sinkronisasi otomatis antar semua jendela dialog yang sedang terbuka
window.addEventListener('storage', function (e) {
  if (e.key === THEME_KEY && e.newValue) {
    applyTheme(e.newValue);
  }
});

// ==========================================
// NAVIGASI KEMBALI KE HUB BOOSOK TOOLS
// ==========================================
function backToHub() {
  var x = window.screenX || window.screenLeft || 0;
  var y = window.screenY || window.screenTop || 0;
  if (x > 10 && y > 10 && window.sketchup && typeof window.sketchup.save_position === 'function') {
    window.sketchup.save_position(JSON.stringify({ left: x, top: y }));
  }
  if (window.sketchup && typeof window.sketchup.back_to_hub === 'function') {
    window.sketchup.back_to_hub(JSON.stringify({ left: x, top: y }));
  }
  window.location.replace('hub.html');
}

// ==========================================
// AUTO FIT HEIGHT DIALOG
// ==========================================
var _lastFitHeight = 0;
function autoFitHeight(extraPadding) {
  // extraPadding: ruang tambahan di bawah konten visual, default 6px (nyaman & proporsional)
  extraPadding = (extraPadding !== undefined) ? extraPadding : 6;
  setTimeout(function () {
    try {
      var bodyStyle = window.getComputedStyle(document.body);
      var pb = parseInt(bodyStyle.paddingBottom) || 18;

      // Hitung batas bawah elemen konten yang sedang aktif/tampak (hanya in-flow content)
      var maxBottom = 0;
      var els = document.body.children;
      for (var i = 0; i < els.length; i++) {
        var el = els[i];
        if (el.nodeType !== 1) continue;
        if (el.tagName === 'SVG' && el.style.display === 'none') continue;
        if (el.id === 'boot' || el.id === 'notif-overlay' || el.classList.contains('overlay') || el.classList.contains('modal')) continue;

        // Elemen fixed/backdrop tidak boleh mempengaruhi tinggi jendela
        var pos = window.getComputedStyle(el).position;
        if (pos === 'fixed') continue;

        if (el.offsetParent !== null || el.offsetHeight > 0) {
          var rect = el.getBoundingClientRect();
          if (rect.bottom > maxBottom) {
            maxBottom = rect.bottom;
          }
        }
      }

      var targetInner = maxBottom > 50 ? Math.ceil(maxBottom + pb + extraPadding) : Math.ceil(document.body.scrollHeight + extraPadding);

      // Selisih antara outerHeight window dan innerHeight document di Windows (~35-40px)
      var frameDiff = (window.outerHeight && window.innerHeight) ? (window.outerHeight - window.innerHeight) : 38;
      if (frameDiff <= 0 || frameDiff > 70) frameDiff = 38;

      var targetOuter = targetInner + frameDiff;
      if (Math.abs(targetOuter - _lastFitHeight) >= 4 && targetOuter > 200 && targetOuter < 1100) {
        _lastFitHeight = targetOuter;
        if (window.sketchup && typeof window.sketchup.set_dialog_height === 'function') {
          window.sketchup.set_dialog_height(targetOuter);
        }
      }
    } catch (e) {}
  }, 60);
}

// Auto save position jika window digeser
var _lastSavedX = null, _lastSavedY = null;
function checkWindowPos() {
  var x = window.screenX !== undefined ? window.screenX : window.screenLeft;
  var y = window.screenY !== undefined ? window.screenY : window.screenTop;
  if (x > 5 && y > 5) {
    if (_lastSavedX === null) {
      _lastSavedX = Math.round(x);
      _lastSavedY = Math.round(y);
    } else if (Math.abs(x - _lastSavedX) >= 3 || Math.abs(y - _lastSavedY) >= 3) {
      _lastSavedX = Math.round(x);
      _lastSavedY = Math.round(y);
      if (window.sketchup && typeof window.sketchup.save_position === 'function') {
        window.sketchup.save_position(JSON.stringify({ left: _lastSavedX, top: _lastSavedY }));
      }
    }
  }
}
setInterval(checkWindowPos, 500);
window.addEventListener('blur', checkWindowPos);
window.addEventListener('beforeunload', checkWindowPos);

// ==========================================
// DEEP PROPERTIES MODULE
// ==========================================
var _dpTags = [];          // array tag dari Ruby
var _dpCtxName = null;     // nama context (nama objek/group/component yang di-scan)
var _dpTotalEnts = 0;
var _dpSortDir = 'asc';    // 'asc' | 'desc'
var _dpAllExpanded = false; // track state expand all
var _dpScanTimer = null;   // timer pengaman tombol scan

// Filter type global (edge, face, group, component) mati secara default
var _dpGlobalTypes = { edge: false, face: false, group: false, component: false };
// Per-tag type filter state: { tagName: { edge: bool, face: bool, group: bool, component: bool } }
var _dpTagFilters = {};

// ── Icons ──────────────────────────────────────────────────────────────────
function iconEdge() {
  return '<svg aria-hidden="true"><use href="#i-spline"/></svg>';
}
function iconFace() {
  return '<svg aria-hidden="true"><use href="#i-pentagon"/></svg>';
}
function iconGroup() {
  return '<svg aria-hidden="true"><use href="#i-box"/></svg>';
}
function iconComp() {
  return '<svg aria-hidden="true"><use href="#i-component"/></svg>';
}

// ── Filter Helpers ─────────────────────────────────────────────────────────
function hasActiveFilters() {
  return _dpGlobalTypes.edge || _dpGlobalTypes.face || _dpGlobalTypes.group || _dpGlobalTypes.component;
}

function activeFilterCount() {
  var n = 0;
  if (_dpGlobalTypes.edge) n++;
  if (_dpGlobalTypes.face) n++;
  if (_dpGlobalTypes.group) n++;
  if (_dpGlobalTypes.component) n++;
  return n;
}

function updateClearFilterBtn() {
  var btn = document.getElementById('btnClearFilter');
  if (!btn) return;
  btn.style.display = (activeFilterCount() > 1) ? 'grid' : 'none';
}

function getRowByTag(tagName) {
  var rows = document.querySelectorAll('.dp-row');
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].getAttribute('data-tag') === tagName) return rows[i];
  }
  return null;
}

// ── Hitung entitas aktif per tag (memperhitungkan filter) ──────────────────
function getTagActiveEnts(tag) {
  if (!tag) return 0;
  var filtering = hasActiveFilters();
  if (!filtering) {
    return (tag.edges || 0) + (tag.faces || 0) + (tag.groups || 0) + (tag.components || 0);
  }
  var showEdge = !filtering || _dpGlobalTypes.edge;
  var showFace = !filtering || _dpGlobalTypes.face;
  var showGroup = !filtering || _dpGlobalTypes.group;
  var showComp = !filtering || _dpGlobalTypes.component;

  var tf = _dpTagFilters[tag.name] || { edge: true, face: true, group: true, component: true };
  var eVis = showEdge && tf.edge;
  var fVis = showFace && tf.face;
  var gVis = showGroup && tf.group;
  var cVis = showComp && tf.component;

  var sum = 0;
  if (eVis) sum += (tag.edges || 0);
  if (fVis) sum += (tag.faces || 0);
  if (gVis) sum += (tag.groups || 0);
  if (cVis) sum += (tag.components || 0);
  return sum;
}

// ── DOM Manipulation: Filter Global & Per-tag (Tanpa Re-render Penuh) ─────
function updateRowTotal(tagName) {
  var row = getRowByTag(tagName);
  if (!row) return;

  var t = _dpTags.find(function(x) { return x.name === tagName; });
  if (!t) return;

  var filtering = hasActiveFilters();
  var showEdge = !filtering || _dpGlobalTypes.edge;
  var showFace = !filtering || _dpGlobalTypes.face;
  var showGroup = !filtering || _dpGlobalTypes.group;
  var showComp = !filtering || _dpGlobalTypes.component;

  var tf = _dpTagFilters[tagName] || { edge: true, face: true, group: true, component: true };
  var eVis = showEdge && tf.edge;
  var fVis = showFace && tf.face;
  var gVis = showGroup && tf.group;
  var cVis = showComp && tf.component;

  var eCount = t.edges || 0;
  var fCount = t.faces || 0;
  var gCount = t.groups || 0;
  var cCount = t.components || 0;

  var subRows = row.querySelectorAll('.dp-sub-row');
  subRows.forEach(function(sub) {
    var subtype = sub.getAttribute('data-subtype');
    if (subtype === 'edge') sub.classList.toggle('hidden-sub', !eVis);
    if (subtype === 'face') sub.classList.toggle('hidden-sub', !fVis);
    if (subtype === 'group') sub.classList.toggle('hidden-sub', !gVis);
    if (subtype === 'component') sub.classList.toggle('hidden-sub', !cVis);
  });

  var total = 0;
  if (eVis) total += eCount;
  if (fVis) total += fCount;
  if (gVis) total += gCount;
  if (cVis) total += cCount;

  var isFilteredOut = filtering && total === 0;
  row.dataset.filteredOut = isFilteredOut ? 'true' : 'false';

  var q = (document.getElementById('dpSearch').value || '').toLowerCase().trim();
  var matchSearch = !q || tagName.toLowerCase().indexOf(q) !== -1;
  row.classList.toggle('hidden-row', isFilteredOut || !matchSearch);
  updateToolbar();
}

function toggleTagFilter(tagName, type, btn) {
  if (!_dpTagFilters[tagName]) {
    _dpTagFilters[tagName] = { edge: true, face: true, group: true, component: true };
  }
  _dpTagFilters[tagName][type] = !_dpTagFilters[tagName][type];
  if (btn) btn.classList.toggle('active', _dpTagFilters[tagName][type]);
  updateRowTotal(tagName);
  updateToolbar();
  autoFitHeight(0);
}

function applyFiltersToDom() {
  var filtering = hasActiveFilters();
  var showEdge = !filtering || _dpGlobalTypes.edge;
  var showFace = !filtering || _dpGlobalTypes.face;
  var showGroup = !filtering || _dpGlobalTypes.group;
  var showComp = !filtering || _dpGlobalTypes.component;
  var q = (document.getElementById('dpSearch').value || '').toLowerCase().trim();

  var rows = document.querySelectorAll('.dp-row');
  rows.forEach(function(row) {
    var tagName = row.getAttribute('data-tag');
    var t = _dpTags.find(function(x) { return x.name === tagName; });
    if (!t) return;

    var tf = _dpTagFilters[tagName] || { edge: true, face: true, group: true, component: true };
    var eVis = showEdge && tf.edge;
    var fVis = showFace && tf.face;
    var gVis = showGroup && tf.group;
    var cVis = showComp && tf.component;

    var eCount = t.edges || 0;
    var fCount = t.faces || 0;
    var gCount = t.groups || 0;
    var cCount = t.components || 0;

    var subRows = row.querySelectorAll('.dp-sub-row');
    subRows.forEach(function(sub) {
      var subtype = sub.getAttribute('data-subtype');
      if (subtype === 'edge') sub.classList.toggle('hidden-sub', !eVis);
      if (subtype === 'face') sub.classList.toggle('hidden-sub', !fVis);
      if (subtype === 'group') sub.classList.toggle('hidden-sub', !gVis);
      if (subtype === 'component') sub.classList.toggle('hidden-sub', !cVis);
    });

    var total = 0;
    if (eVis) total += eCount;
    if (fVis) total += fCount;
    if (gVis) total += gCount;
    if (cVis) total += cCount;

    var isFilteredOut = filtering && total === 0;
    row.dataset.filteredOut = isFilteredOut ? 'true' : 'false';

    var matchSearch = !q || tagName.toLowerCase().indexOf(q) !== -1;
    var shouldHide = isFilteredOut || !matchSearch;
    row.classList.toggle('hidden-row', shouldHide);
  });

  updateToolbar();
  autoFitHeight(0);
  setTimeout(function() { autoFitHeight(0); }, 50);
}

function toggleGlobalFilter(btn) {
  var type = btn.dataset.type;
  _dpGlobalTypes[type] = !_dpGlobalTypes[type];
  btn.classList.toggle('active', _dpGlobalTypes[type]);
  updateClearFilterBtn();
  applyFiltersToDom();
}

function resetFilters() {
  _dpGlobalTypes = { edge: false, face: false, group: false, component: false };
  document.querySelectorAll('#globalFilters .filter-btn').forEach(function(b) {
    b.classList.remove('active');
  });
  updateClearFilterBtn();
  applyFiltersToDom();
}

// ── Toolbar: Update counts chips (Tag terpilih / total tag & entitas) ──────
function updateToolbar() {
  var visibleTags = _dpTags.filter(function(t) {
    var row = getRowByTag(t.name);
    return row && !row.classList.contains('hidden-row');
  });

  var checkedTagCount = 0;
  document.querySelectorAll('.dp-row:not(.hidden-row) .dp-check:checked').forEach(function() {
    checkedTagCount++;
  });

  var el = document.getElementById('tbTagCount');
  if (el) {
    var tagUnit = (window.t ? window.t('tag_unit', 'tag') : 'tag');
    if (visibleTags.length > 0) {
      el.textContent = checkedTagCount + '/' + visibleTags.length + ' ' + tagUnit;
    } else {
      el.textContent = '0 ' + tagUnit;
    }
  }

  // checked / total entitas
  var totalEnts = 0, checkedEnts = 0;
  _dpTags.forEach(function(t) {
    var row = getRowByTag(t.name);
    if (row && !row.classList.contains('hidden-row')) {
      totalEnts += getTagActiveEnts(t);
    } else if (!hasActiveFilters()) {
      totalEnts += getTagActiveEnts(t);
    }
  });
  document.querySelectorAll('.dp-row:not(.hidden-row) .dp-check:checked').forEach(function(cb) {
    var tag = _dpTags.find(function(x) { return x.name === cb.value; });
    if (tag) checkedEnts += getTagActiveEnts(tag);
  });
  var ctEl = document.getElementById('tbCheckedTotal');
  if (ctEl) ctEl.textContent = checkedEnts + '/' + totalEnts;
}

// ── Toolbar: Expand / Collapse All ────────────────────────────────────────
function toggleExpandAll() {
  _dpAllExpanded = !_dpAllExpanded;
  var rows = document.querySelectorAll('.dp-row:not(.hidden-row)');
  rows.forEach(function(row) {
    row.classList.toggle('expanded', _dpAllExpanded);
  });
  var btn = document.getElementById('btnExpandAll');
  if (btn) {
    btn.title = _dpAllExpanded
      ? (window.t ? window.t('deep_collapse', 'Collapse semua') : 'Collapse semua')
      : (window.t ? window.t('deep_expand', 'Expand semua') : 'Expand semua');
    var use = btn.querySelector('use');
    if (use) use.setAttribute('href', _dpAllExpanded ? '#i-chevrons-up-down' : '#i-chevrons-down-up');
  }
  autoFitHeight(0);
  setTimeout(function() { autoFitHeight(0); }, 60);
}

// ── Toolbar: Select All / Unselect All ────────────────────────────────────
function toggleSelectAll(cbEl) {
  var checked = cbEl.checked;
  var rows = document.querySelectorAll('.dp-row:not(.hidden-row) .dp-check');
  rows.forEach(function(cb) { cb.checked = checked; });
  syncSelectAllState();
  updateToolbar();
}

function syncSelectAllState() {
  var all = document.querySelectorAll('.dp-row:not(.hidden-row) .dp-check');
  var checkedCount = 0;
  all.forEach(function(cb) { if (cb.checked) checkedCount++; });
  var cbAll = document.getElementById('cbSelectAll');
  if (cbAll) {
    if (checkedCount === 0) {
      cbAll.checked = false;
      cbAll.indeterminate = false;
    } else if (all.length > 0 && checkedCount === all.length) {
      cbAll.checked = true;
      cbAll.indeterminate = false;
    } else {
      cbAll.checked = false;
      cbAll.indeterminate = true;
    }
  }
  updateToolbar();
}

// ── Toolbar: Sort A→Z / Z→A ───────────────────────────────────────────────
function toggleSort() {
  _dpSortDir = (_dpSortDir === 'asc') ? 'desc' : 'asc';
  var btn = document.getElementById('btnSort');
  if (btn) {
    btn.classList.toggle('asc', _dpSortDir === 'asc');
    btn.classList.toggle('desc', _dpSortDir === 'desc');
    var use = btn.querySelector('use');
    if (use) use.setAttribute('href', _dpSortDir === 'asc' ? '#i-arrow-up-a-z' : '#i-arrow-down-z-a');
  }
  _dpTags.sort(function(a, b) {
    var na = a.name.toLowerCase(), nb = b.name.toLowerCase();
    if (na < nb) return _dpSortDir === 'asc' ? -1 : 1;
    if (na > nb) return _dpSortDir === 'asc' ? 1 : -1;
    return 0;
  });
  renderList();
}

// ── Dipanggil Ruby setelah scan ────────────────────────────────────────────
function initData(data, fromScan) {
  clearTimeout(_dpScanTimer);
  busy('btnScan', false);

  if (data && data.error) {
    if (fromScan) showToast(data.error, 'error');
    _dpTags = [];
    _dpCtxName = null;
    _dpTotalEnts = 0;
    _dpTagFilters = {};
    _dpAllExpanded = false;
    updateToolbar();
    renderList();
    autoFitHeight(0);
    return;
  }

  _dpTags = (data && data.tags) ? data.tags : [];
  _dpCtxName = (data && data.ctx_name) ? data.ctx_name : null;
  _dpTotalEnts = (data && data.total_ents) ? data.total_ents : 0;
  _dpAllExpanded = false;

  _dpTags.sort(function(a, b) {
    var na = a.name.toLowerCase(), nb = b.name.toLowerCase();
    if (na < nb) return _dpSortDir === 'asc' ? -1 : 1;
    if (na > nb) return _dpSortDir === 'asc' ? 1 : -1;
    return 0;
  });

  _dpTagFilters = {};
  _dpTags.forEach(function(t) {
    _dpTagFilters[t.name] = { edge: true, face: true, group: true, component: true };
  });

  renderList();
  updateToolbar();
  autoFitHeight(0);
  setTimeout(function () { autoFitHeight(0); }, 60);
}

// ── Render List ────────────────────────────────────────────────────────────
function renderList() {
  var list = document.getElementById('dpList');
  if (!list) return;
  if (!_dpTags.length) {
    var emptyMsg = (window.t ? window.t('deep_empty', 'Pilih objek di SketchUp lalu klik <b>Scan Objek</b>.') : 'Pilih objek di SketchUp lalu klik <b>Scan Objek</b>.');
    list.innerHTML = '<div class="dp-empty">' + emptyMsg + '</div>';
    autoFitHeight(0);
    return;
  }

  var q = (document.getElementById('dpSearch') ? document.getElementById('dpSearch').value : '').toLowerCase().trim();
  var filtering = hasActiveFilters();
  var showEdge = !filtering || _dpGlobalTypes.edge;
  var showFace = !filtering || _dpGlobalTypes.face;
  var showGroup = !filtering || _dpGlobalTypes.group;
  var showComp = !filtering || _dpGlobalTypes.component;

  var html = '';

  _dpTags.forEach(function(t, idx) {
    var tf = _dpTagFilters[t.name] || { edge: true, face: true, group: true, component: true };
    var eCount = t.edges || 0;
    var fCount = t.faces || 0;
    var gCount = t.groups || 0;
    var cCount = t.components || 0;

    var eVis = showEdge && tf.edge;
    var fVis = showFace && tf.face;
    var gVis = showGroup && tf.group;
    var cVis = showComp && tf.component;

    var total = 0;
    if (eVis) total += eCount;
    if (fVis) total += fCount;
    if (gVis) total += gCount;
    if (cVis) total += cCount;

    var hasChildren = (eCount + fCount + gCount + cCount) > 0;
    var eyeClass = t.visible ? '' : ' hidden';
    var eyeIcon = t.visible ? '#i-eye' : '#i-eye-off';
    var safeTagAttr = esc(t.name).replace(/'/g, "\\'");

    var subEdge = '';
    if (eCount > 0) {
      var hidEdge = eVis ? '' : ' hidden-sub';
      subEdge = '<div class="dp-sub-row' + hidEdge + '" data-parent="' + esc(t.name) + '" data-subtype="edge" ' +
        'onclick="selectSubtype(\'' + safeTagAttr + '\',\'edge\')" title="Klik untuk seleksi Edge pada tag ini">' +
        iconEdge() + '<span>edge</span>' +
        '<span class="sub-count">(' + eCount + ')</span>' +
      '</div>';
    }
    var subFace = '';
    if (fCount > 0) {
      var hidFace = fVis ? '' : ' hidden-sub';
      subFace = '<div class="dp-sub-row' + hidFace + '" data-parent="' + esc(t.name) + '" data-subtype="face" ' +
        'onclick="selectSubtype(\'' + safeTagAttr + '\',\'face\')" title="Klik untuk seleksi Face pada tag ini">' +
        iconFace() + '<span>face</span>' +
        '<span class="sub-count">(' + fCount + ')</span>' +
      '</div>';
    }
    var subGroup = '';
    if (gCount > 0) {
      var hidGroup = gVis ? '' : ' hidden-sub';
      subGroup = '<div class="dp-sub-row' + hidGroup + '" data-parent="' + esc(t.name) + '" data-subtype="group" ' +
        'onclick="selectSubtype(\'' + safeTagAttr + '\',\'group\')" title="Klik untuk seleksi Group pada tag ini">' +
        iconGroup() + '<span>group</span>' +
        '<span class="sub-count">(' + gCount + ')</span>' +
      '</div>';
    }
    var subComp = '';
    if (cCount > 0) {
      var hidComp = cVis ? '' : ' hidden-sub';
      subComp = '<div class="dp-sub-row' + hidComp + '" data-parent="' + esc(t.name) + '" data-subtype="component" ' +
        'onclick="selectSubtype(\'' + safeTagAttr + '\',\'component\')" title="Klik untuk seleksi Component pada tag ini">' +
        iconComp() + '<span>component</span>' +
        '<span class="sub-count">(' + cCount + ')</span>' +
      '</div>';
    }

    var typeIconsHtml = '';
    if (eCount > 0) typeIconsHtml += '<svg aria-hidden="true"><use href="#i-spline"/></svg>';
    if (fCount > 0) typeIconsHtml += '<svg aria-hidden="true"><use href="#i-pentagon"/></svg>';
    if (gCount > 0) typeIconsHtml += '<svg aria-hidden="true"><use href="#i-box"/></svg>';
    if (cCount > 0) typeIconsHtml += '<svg aria-hidden="true"><use href="#i-component"/></svg>';
    var typeIconsWrap = typeIconsHtml ? '<span class="dp-type-icons">' + typeIconsHtml + '</span>' : '';

    var rawTotal = eCount + fCount + gCount + cCount;
    var totalBadge = '<span class="dp-total-badge" title="Total: ' + rawTotal + ' (Edge: ' + eCount + ', Face: ' + fCount + ', Group: ' + gCount + ', Comp: ' + cCount + ')">(' + rawTotal + ')</span>';

    var summaryHtml = typeIconsWrap + totalBadge;

    var isFilteredOut = filtering && total === 0;
    var matchSearch = !q || t.name.toLowerCase().indexOf(q) !== -1;
    var isHiddenRow = isFilteredOut || !matchSearch;

    var detailTitle = (window.t ? window.t('deep_view_detail', 'Lihat detail') : 'Lihat detail');
    var selectPrefix = (window.t ? window.t('deep_select_tag_prefix', 'Pilih tag ') : 'Pilih tag ');
    var eyeTitle = t.visible
      ? (window.t ? window.t('deep_hide_tag', 'Sembunyikan tag') : 'Sembunyikan tag')
      : (window.t ? window.t('deep_show_tag', 'Tampilkan tag') : 'Tampilkan tag');

    html +=
      '<div class="dp-row' + (isHiddenRow ? ' hidden-row' : '') + '" id="dprow-' + idx + '" data-tag="' + esc(t.name) + '" data-filtered-out="' + (isFilteredOut ? 'true' : 'false') + '">' +
        '<div class="dp-tag-row">' +
          '<div class="dp-arrow' + (hasChildren ? '' : ' empty') + '" ' +
            'onclick="toggleExpand(' + idx + ')" title="' + detailTitle + '">' +
            '<svg><use href="#i-chevron-right"/></svg>' +
          '</div>' +
          '<label class="dp-cb-wrap" title="' + selectPrefix + esc(t.name) + '">' +
            '<input type="checkbox" class="dp-check" value="' + esc(t.name) + '">' +
            '<span class="box"><svg><use href="#i-check"/></svg></span>' +
          '</label>' +
          '<div class="dp-color" style="background:' + t.color + ';"></div>' +
          '<span class="dp-tag-name" title="' + esc(t.name) + '">' + esc(t.name) + '</span>' +
          summaryHtml +
          '<div class="dp-eye' + eyeClass + '" title="' + eyeTitle + '" ' +
            'onclick="toggleVis(\'' + safeTagAttr + '\',' + (!t.visible) + ',this)">' +
            '<svg><use href="' + eyeIcon + '"/></svg>' +
          '</div>' +
        '</div>' +
        '<div class="dp-sub-rows">' +
          subEdge + subFace + subGroup + subComp +
        '</div>' +
      '</div>';
  });

  list.innerHTML = html;

  list.querySelectorAll('.dp-check').forEach(function(cb) {
    cb.addEventListener('change', function() {
      syncSelectAllState();
      updateToolbar();
    });
  });
  syncSelectAllState();
  updateToolbar();
  autoFitHeight(0);
  setTimeout(function () { autoFitHeight(0); }, 60);
}

// ── Klik Sub-row: Seleksi Subtipe Spesifik di Model ─────────────────────────
function selectSubtype(tagName, subtype) {
  if (window.sketchup && typeof sketchup.dp_select_subtype === 'function') {
    sketchup.dp_select_subtype(tagName, subtype);
  }
}

// ── Expand / collapse sub-rows saat tree di klik ───────────────────────────
function toggleExpand(idx) {
  var row = document.getElementById('dprow-' + idx);
  if (!row) return;
  row.classList.toggle('expanded');
  autoFitHeight(0);
  setTimeout(function () { autoFitHeight(0); }, 60);
}

// ── Eye toggle ─────────────────────────────────────────────────────────────
function toggleVis(tagName, makeVisible, eyeEl) {
  if (window.sketchup && typeof sketchup.dp_toggle_vis === 'function') {
    sketchup.dp_toggle_vis(tagName, String(makeVisible));
  }
}

function updateEyeIcon(tagName, isVisible) {
  var t = _dpTags.find(function(x) { return x.name === tagName; });
  if (t) t.visible = isVisible;

  var row = getRowByTag(tagName);
  if (row) {
    var eyeEl = row.querySelector('.dp-eye');
    if (eyeEl) {
      eyeEl.classList.toggle('hidden', !isVisible);
      eyeEl.querySelector('use').setAttribute('href', isVisible ? '#i-eye' : '#i-eye-off');
      eyeEl.title = isVisible ? 'Sembunyikan tag' : 'Tampilkan tag';
      var safeTag = tagName.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
      eyeEl.setAttribute('onclick', "toggleVis('" + safeTag + "', " + (!isVisible) + ", this)");
    }
  }
}

// ── Search filter (DOM manipulation tanpa re-render) ───────────────────────
function filterList() {
  var q = (document.getElementById('dpSearch') ? document.getElementById('dpSearch').value : '').toLowerCase().trim();
  var rows = document.querySelectorAll('.dp-row');
  rows.forEach(function(row) {
    var tagName = (row.getAttribute('data-tag') || '').toLowerCase();
    var matchSearch = !q || tagName.indexOf(q) !== -1;
    var isFilteredOut = row.dataset.filteredOut === 'true';
    row.classList.toggle('hidden-row', isFilteredOut || !matchSearch);
  });
  syncSelectAllState();
  updateToolbar();
  autoFitHeight(0);
}

// ── Scan Objek ─────────────────────────────────────────────────────────────
function doScan(btn) {
  busy('btnScan', true);
  clearTimeout(_dpScanTimer);
  _dpScanTimer = setTimeout(function() { busy('btnScan', false); }, 5000);
  try {
    if (window.sketchup && typeof sketchup.dp_scan === 'function') {
      sketchup.dp_scan();
    } else {
      clearTimeout(_dpScanTimer);
      busy('btnScan', false);
      showToast(window.t ? window.t('deep_err_scan', 'Fungsi Scan belum siap.') : 'Fungsi Scan belum siap.', 'error');
    }
  } catch(err) {
    clearTimeout(_dpScanTimer);
    busy('btnScan', false);
    showToast('Error: ' + err.message, 'error');
  }
}

// ── Seleksi Entitas dari Checkbox ───────────────────────────────────────────
function doSelect() {
  var checked = document.querySelectorAll('.dp-check:checked');
  if (!checked.length) {
    showToast(window.t ? window.t('deep_err_min1', 'Centang minimal 1 tag terlebih dahulu.') : 'Centang minimal 1 tag terlebih dahulu.', 'error');
    autoFitHeight(0);
    return;
  }

  var tags = [];
  checked.forEach(function(cb) { tags.push(cb.value); });

  var types = [];
  if (hasActiveFilters()) {
    if (_dpGlobalTypes.edge) types.push('edge');
    if (_dpGlobalTypes.face) types.push('face');
    if (_dpGlobalTypes.group) types.push('group');
    if (_dpGlobalTypes.component) types.push('component');
  } else {
    types = ['edge', 'face', 'group', 'component'];
  }

  var payload = JSON.stringify({ tags: tags, types: types });
  try {
    if (window.sketchup && typeof sketchup.dp_select === 'function') {
      sketchup.dp_select(payload);
    } else {
      showToast(window.t ? window.t('deep_err_select', 'Fungsi Seleksi belum siap.') : 'Fungsi Seleksi belum siap.', 'error');
    }
  } catch(err) {
    showToast('Error: ' + err.message, 'error');
  }
}

// ── Inisialisasi Otomatis Deep Properties ───────────────────────────────────
function initDeepProperties() {
  if (!document.getElementById('dpList')) return;
  try {
    if (window.sketchup && typeof sketchup.dp_ready === 'function') {
      sketchup.dp_ready();
    } else {
      var tries = 0;
      var iv = setInterval(function() {
        tries++;
        if (window.sketchup && typeof sketchup.dp_ready === 'function') {
          clearInterval(iv);
          sketchup.dp_ready();
        } else if (tries > 40) {
          clearInterval(iv);
        }
      }, 60);
    }
  } catch(e) {}
  autoFitHeight(0);
  setTimeout(function () { autoFitHeight(0); }, 80);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initDeepProperties);
} else {
  initDeepProperties();
}



