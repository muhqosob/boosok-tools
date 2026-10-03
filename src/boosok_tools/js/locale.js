/**
 * Boosok Tools - Shared Locale / i18n System
 * Dipakai oleh SEMUA halaman HTML.
 *
 * Sumber terjemahan TUNGGAL: locales/<kode>.json. Ruby mengekspornya otomatis ke js/strings.js
 * (window.BOOSOK_LOCALES = { id: {...}, en: {...}, ... }) — file ini hanya berisi logikanya.
 * Menambah bahasa = menambah satu file JSON (lihat locales/README.md); tidak perlu mengubah JS.
 *
 * Bahasa dibaca dari localStorage('boosok_language') yang di-set oleh hub.html.
 */
(function () {
  var DEFAULT_LANG = 'id'; // bahasa sumber: teks bawaan HTML & pesan dari Ruby berbahasa Indonesia

  // dari js/strings.js; kalau file itu belum ada, halaman tetap jalan dengan teks bawaan HTML
  var LOCALES = window.BOOSOK_LOCALES || {};
  window.BOOSOK_LOCALES = LOCALES;

  // Kompatibilitas: window.STRINGS[kode] = { kunci: teks }
  window.STRINGS = {};
  function syncStrings() {
    Object.keys(LOCALES).forEach(function (code) {
      window.STRINGS[code] = (LOCALES[code] && LOCALES[code].strings) || {};
    });
  }
  syncStrings();

  // Tambah / perbarui bahasa saat halaman berjalan (mis. file bahasa baru dikirim Ruby ke Hub)
  window.registerBoosokLocales = function (map) {
    if (!map || typeof map !== 'object') return;
    Object.keys(map).forEach(function (code) { LOCALES[code] = map[code]; });
    syncStrings();
  };

  var currentLang = DEFAULT_LANG;
  try {
    var saved = localStorage.getItem('boosok_language');
    if (saved && LOCALES[saved]) currentLang = saved;
  } catch (e) {}

  window.BOOSOK_LANG = currentLang;

  window.setBoosokLang = function (code) {
    if (!code) return;
    var c = code.toString().trim().toLowerCase();
    window.BOOSOK_LANG = c;
    try { localStorage.setItem('boosok_language', c); } catch (e) {}
  };

  // Terjemahkan satu kunci: bahasa terpilih → bahasa sumber (id) → fallback → kunci itu sendiri
  window.t = function (key, fallback, langOverride) {
    var lang = langOverride || window.BOOSOK_LANG || DEFAULT_LANG;
    var s = window.STRINGS[lang];
    if (s && s[key] != null) return s[key];
    var base = window.STRINGS[DEFAULT_LANG];
    if (base && base[key] != null) return base[key];
    return fallback !== undefined ? fallback : key;
  };

  // Terjemahkan pesan notifikasi dari Ruby / JS (aslinya bahasa Indonesia).
  // Memakai "messages" (pesan persis) lalu "patterns" (regex + $1,$2) dari file bahasa terpilih.
  window.translateMessage = function (msg) {
    if (!msg || typeof msg !== 'string') return msg;
    var lang = window.BOOSOK_LANG || DEFAULT_LANG;
    if (lang === DEFAULT_LANG) return msg;
    var loc = LOCALES[lang];
    if (!loc) return msg;

    if (loc.messages && Object.prototype.hasOwnProperty.call(loc.messages, msg)) return loc.messages[msg];

    var pats = loc.patterns || [];
    for (var i = 0; i < pats.length; i++) {
      var p = pats[i];
      if (!p || typeof p.match !== 'string' || typeof p.replace !== 'string') continue;
      try {
        var re = new RegExp(p.match);
        if (re.test(msg)) return msg.replace(re, p.replace);
      } catch (e) { /* regex salah di file bahasa: lewati */ }
    }
    return msg;
  };

  window.applyPageTranslations = function () {
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var v = window.t(el.getAttribute('data-i18n'), null); // null: kunci belum ada → pertahankan teks bawaan HTML
      if (v) el.textContent = v;
    });
    document.querySelectorAll('[data-i18n-placeholder]').forEach(function (el) {
      var v = window.t(el.getAttribute('data-i18n-placeholder'), null);
      if (v) el.placeholder = v;
    });
    document.querySelectorAll('[data-i18n-title]').forEach(function (el) {
      var v = window.t(el.getAttribute('data-i18n-title'), null);
      if (v) el.title = v;
    });
    document.querySelectorAll('[data-i18n-aria]').forEach(function (el) {
      var v = window.t(el.getAttribute('data-i18n-aria'), null);
      if (v) el.setAttribute('aria-label', v);
    });
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', window.applyPageTranslations);
  } else {
    window.applyPageTranslations();
  }
})();
