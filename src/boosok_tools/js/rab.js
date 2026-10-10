// RAB: logika dialog. Dimuat oleh html/rab.html setelah ui.js dan locale.js.
// Dialog RAB bisa di-resize / layar penuh, jadi tinggi jendela tidak lagi mengikuti isi (lihat css/rab.css).
window.autoFitHeight = function () {};

var $ = function (id) { return document.getElementById(id); };
var CUSTOM_DIV = '00. Analisa Saya';
var BASIS = ['auto', 'count', 'length', 'area', 'plane', 'volume'];
var JENIS_CHIP = { upah: 'U', bahan: 'B', alat: 'A' };

var S = {
  catalog: [], officialCatalog: [], byKode: {}, cuBy: {}, comps: {}, base: [], officialBase: [], baseBy: {}, tags: [], report: null, view: 'tag',
  pf: 'used', usedBase: [], usedKey: '', pickKey: null, sel: null, anFilter: 'all', anLimit: 60, sources: null,
  state: { map: {}, prices: {}, op: 10, ppn: 11, ppn_on: true, custom: { ahsp: [], base: [] }, overrides: {}, sources: [], price_sources: [], theme: 'app/biru', weeks: 12 }, themes: []
};
var calcTimer = null;

function fmt(n, d) {
  return Number(n || 0).toLocaleString('id-ID', { minimumFractionDigits: d || 0, maximumFractionDigits: d || 0 });
}
function rp(n) { return fmt(Math.round(n || 0), 0); }
function round(n, d) { var m = Math.pow(10, d); return Math.round(n * m) / m; }
function basisLabel(b) {
  var labels = {
    auto: t('rab_basis_auto', 'Auto'), count: t('rab_basis_count', 'Jumlah'), length: t('rab_basis_length', 'Panjang'),
    area: t('rab_basis_area', 'Luas'), plane: t('rab_basis_plane', 'Luas bidang'), volume: t('rab_basis_volume', 'Volume'),
    manual: t('rab_basis_manual', 'Manual')
  };
  return labels[b] || b;
}
function jenisLabel(j) {
  return j === 'upah' ? t('rab_jenis_upah', 'UPAH') : j === 'alat' ? t('rab_jenis_alat', 'ALAT') : t('rab_jenis_bahan', 'BAHAN');
}

// ── Panggilan ke Ruby ──
function call(name, arg, btn) {
  try {
    if (window.sketchup && typeof sketchup[name] === 'function') {
      if (btn) busy(btn, true);
      sketchup[name](arg === undefined ? '' : arg);
    } else {
      showToast(t('rab_err_notready', 'Fungsi RAB belum siap.'), 'error');
    }
  } catch (err) {
    if (btn) busy(btn, false);
    showToast('Error: ' + err.message, 'error');
  }
}
function stateJson() { return JSON.stringify(S.state); }
function scheduleCalc() {
  clearTimeout(calcTimer);
  calcTimer = setTimeout(function () { call('rab_calc', stateJson()); }, 150);
}

// ── Data: katalog & harga dasar (resmi + analisa sendiri) ──
function customData() {
  if (!S.state.custom) S.state.custom = { ahsp: [], base: [] };
  if (!S.state.overrides) S.state.overrides = {};
  return S.state.custom;
}
function customAhsp() { return customData().ahsp; }
function customBase() { return customData().base; }

function searchText(a) { return (a.kode + ' ' + a.uraian + ' ' + (a.kategori || '') + ' ' + a.divisi).toLowerCase(); }

// Susun ulang indeks setelah data berubah. Yang resmi sudah punya _s (dihitung sekali); yang sendiri dihitung ulang (sedikit).
function rebuildIndex() {
  var base = S.officialBase.slice();
  customBase().forEach(function (b) {
    base.push({ kode: b.kode, jenis: b.jenis, nama: b.nama, satuan: b.satuan, harga: b.harga, custom: true,
      sumber_harga: t('rab_cu_src', 'Analisa saya'), _s: (b.kode + ' ' + b.nama).toLowerCase() });
  });
  S.base = base;
  S.baseBy = {};
  base.forEach(function (b) { S.baseBy[b.kode] = b; });
  S.cuBy = {};
  var cu = customAhsp().map(function (a) {
    S.cuBy[a.kode] = a;
    var e = { kode: a.kode, divisi: CUSTOM_DIV, kategori: a.kategori || '', uraian: a.uraian, satuan: a.satuan, keyakinan: 'sendiri', custom: true };
    e._s = searchText(e);
    return e;
  });
  S.catalog = cu.concat(S.officialCatalog);
  S.byKode = {};
  S.catalog.forEach(function (a) { S.byKode[a.kode] = a; });
}
function priceOf(kode) {
  var o = S.state.prices[kode];
  if (o != null) return o;
  return S.baseBy[kode] ? S.baseBy[kode].harga : 0;
}
function setPrice(kode, v) {
  var b = S.baseBy[kode];
  if (!b) return;
  if (v === b.harga) delete S.state.prices[kode]; else S.state.prices[kode] = v;
}
// Komponen satu AHSP yang berlaku: analisa sendiri -> isinya; AHSP resmi -> versi yang diubah user kalau ada, kalau tidak yang asli.
function compsOf(kode) {
  if (S.cuBy[kode]) return S.cuBy[kode].komponen;
  var ov = S.state.overrides[kode];
  if (ov) return ov.komponen;
  return (S.comps[kode] || []).map(function (c) { return { kode: c[0], koef: c[1] }; });
}
// Komponen yang boleh diubah. AHSP resmi disalin dulu jadi override (database aslinya tetap utuh).
function editableComps(kode) {
  if (S.cuBy[kode]) return S.cuBy[kode].komponen;
  if (!S.state.overrides[kode]) S.state.overrides[kode] = { komponen: compsOf(kode) };
  return S.state.overrides[kode].komponen;
}
function isModified(kode) { return !!S.state.overrides[kode]; }
function hspOf(kode) {
  var sum = compsOf(kode).reduce(function (s, c) { return s + c.koef * priceOf(c.kode); }, 0);
  return { sum: sum, op: sum * (S.state.op || 0) / 100, hsp: sum * (1 + (S.state.op || 0) / 100) };
}
function nextKode(prefix, list) {
  var m = 0;
  list.forEach(function (x) { var n = parseInt(String(x.kode).replace(/\D/g, ''), 10); if (n > m) m = n; });
  return prefix + '.' + ('00' + (m + 1)).slice(-3);
}

// ── Tabel RAB ──
function jobLabel(a) { return a.kode + ' · ' + a.uraian + ' (' + a.satuan + ')'; }
function basisOptions() {
  return BASIS.map(function (b) { return '<option value="' + b + '">' + esc(basisLabel(b)) + '</option>'; }).join('');
}
function measureText(tg) {
  var p = [];
  if (tg.kind === 'mat') {
    if (tg.count) p.push(fmt(tg.count) + ' face');
  } else {
    if (tg.count) p.push(fmt(tg.count) + ' ' + t('rab_m_count', 'obj'));
    if (tg.length) p.push(fmt(tg.length, 2) + ' m');
    if (tg.volume) p.push(fmt(tg.volume, 3) + ' m³');
    if (tg.plane) p.push(fmt(tg.plane, 2) + ' m² ' + t('rab_m_plane', 'bidang'));
  }
  if (tg.area) p.push(fmt(tg.area, 2) + ' m²');
  if (tg.nonsolid) p.push(tg.nonsolid + ' ' + t('rab_m_nonsolid', 'non-solid'));
  return p.join(' · ') || '—';
}

function renderTags() {
  var basis = basisOptions();
  var nTag = 0, nMat = 0;
  S.tags.forEach(function (tg) { if (tg.kind === 'mat') nMat++; else nTag++; });
  $('nTag').textContent = nTag || '';
  $('nMat').textContent = nMat || '';
  var shown = S.tags.filter(function (tg) { return tg.kind === S.view; });
  $('tbody').innerHTML = shown.map(function (tg) {
    var ms = measureText(tg);
    return '<tr data-key="' + esc(tg.key) + '" class="off">' +
      '<td class="tg" title="' + esc(tg.name + ' — ' + ms) + '"><span class="sw" style="background:' + esc(tg.color) + '"></span><span class="nm">' + esc(tg.name) + '</span><div class="ms">' + esc(ms) + '</div></td>' +
      '<td class="jobc"><button type="button" class="input sm job-btn none"></button>' +
        '<button type="button" class="eye-btn" title="' + esc(t('rab_view_ana', 'Lihat / ubah isi analisa')) + '" aria-label="' + esc(t('rab_view_ana', 'Lihat / ubah isi analisa')) + '">' + icon('eye') + '</button></td>' +
      '<td><select class="input sm basis">' + basis + '</select></td>' +
      '<td><input class="input sm num factor" type="number" min="0" step="any" value="1"></td>' +
      '<td class="qtyc"><input class="input sm num qty" type="number" min="0" step="any"><span class="rst" title="' + esc(t('rab_qty_reset', 'Kembali ke hasil ukur')) + '">' + icon('x') + '</span></td>' +
      '<td class="sat"></td><td class="n hsp"></td><td class="n jml"></td></tr>';
  }).join('');
  Array.prototype.forEach.call($('tbody').children, syncRow);
  $('emptyMsg').style.display = shown.length ? 'none' : '';
  $('emptyMsg').textContent = S.view === 'mat'
    ? t('rab_empty_mat', 'Belum ada material yang dipakai di face. Beri material (mis. “Cat Putih”) pada face lalu klik Scan Model.')
    : t('rab_empty', 'Belum ada tag yang punya ukuran. Beri tag pada group/component (mis. “Dinding Bata”) lalu klik Scan Model.');
  $('totalPill').textContent = S.tags.length ? S.tags.length + ' ' + t('rab_sources', 'sumber') : '';
  if (S.report) onReport(S.report);
}

// Samakan kontrol satu baris dengan state (tanpa menyentuh angka hasil hitung)
function syncRow(tr) {
  var e = S.state.map[tr.dataset.key];
  var jb = tr.querySelector('.job-btn'), a = e && S.byKode[e.kode];
  jb.textContent = a ? jobLabel(a) : t('rab_job_none', '— pilih pekerjaan —');
  jb.title = a ? jobLabel(a) + (a.keyakinan === 'periksa' ? ' — ' + t('rab_pk_check', 'periksa ke PDF resmi') : '') : '';
  jb.classList.toggle('none', !a);
  tr.querySelector('.basis').value = e ? e.basis : 'auto';
  var f = tr.querySelector('.factor');
  if (document.activeElement !== f) f.value = e ? e.factor : 1;
  ['.basis', '.factor', '.qty'].forEach(function (s) { tr.querySelector(s).disabled = !e; });
  tr.classList.toggle('off', !e);
  tr.querySelector('.qtyc').classList.toggle('manual', !!(e && e.manual != null));
}

// ── Hasil hitung dari Ruby ──
function onReport(rep) {
  S.report = rep;
  var usedKey = (rep.used_base || []).join('|');
  if (usedKey !== S.usedKey) {
    S.usedKey = usedKey;
    S.usedBase = rep.used_base || [];
    if ($('pnlPrice').classList.contains('active') && !(document.activeElement && document.activeElement.closest('#pbody'))) renderPrices();
    else { $('nUsed').textContent = S.usedBase.length || ''; }
  }
  var byKey = {};
  rep.rows.forEach(function (r) { byKey[r.key] = r; });
  Array.prototype.forEach.call($('tbody').children, function (tr) {
    var r = byKey[tr.dataset.key];
    var q = tr.querySelector('.qty');
    tr.classList.remove('warn', 'bad');
    tr.querySelector('.qtyc').title = '';
    if (!r) {
      q.value = '';
      tr.querySelector('.sat').textContent = '';
      tr.querySelector('.hsp').textContent = '';
      tr.querySelector('.jml').textContent = '';
      return;
    }
    if (document.activeElement !== q) q.value = r.src === 'manual' ? r.qty : round(r.qty, 4);
    tr.querySelector('.basis').title = t('rab_basis_used', 'Dipakai: %{b}').replace('%{b}', basisLabel(r.basis));
    tr.querySelector('.sat').textContent = r.satuan;
    tr.querySelector('.hsp').textContent = rp(r.hsp);
    tr.querySelector('.jml').textContent = rp(r.jumlah);
    if (r.warn === 'nonsolid') {
      tr.classList.add('bad');
      tr.querySelector('.qtyc').title = t('rab_warn_row_nonsolid', 'Ada objek yang bukan solid, volumenya tidak terhitung.');
    } else if (r.warn === 'zero') {
      tr.classList.add('warn');
      tr.querySelector('.qtyc').title = r.basis === 'manual'
        ? t('rab_warn_row_manual', 'Satuan ini tidak bisa diukur dari model, isi volume manual.')
        : t('rab_warn_row_zero', 'Hasil ukur 0. Cek tag, dasar ukur, atau isi volume manual.');
    }
  });

  $('dvList').innerHTML = rep.divisi.map(function (d) {
    return '<div class="ln dv"><span class="k">' + esc(d.name) + '</span><span class="v">' + rp(d.subtotal) + '</span></div>';
  }).join('');
  $('sSub').textContent = rp(rep.subtotal);
  $('sPpn').textContent = rp(rep.ppn);
  $('sTotal').textContent = 'Rp ' + rp(rep.total);

  var nonsolid = 0, zero = 0;
  rep.rows.forEach(function (r) { if (r.warn === 'nonsolid') nonsolid += r.nonsolid; else if (r.warn === 'zero') zero++; });
  var msgs = [];
  if (nonsolid) msgs.push(t('rab_warn_nonsolid', '%{count} objek bukan solid, volumenya tidak dihitung.').replace('%{count}', nonsolid));
  if (zero) msgs.push(t('rab_warn_zero', '%{count} item bervolume 0.').replace('%{count}', zero));
  if (rep.unpriced) msgs.push(t('rab_warn_unpriced', '%{count} komponen harga dasar masih 0, isi di tab Harga Dasar.').replace('%{count}', rep.unpriced));
  $('warnBox').style.display = msgs.length ? '' : 'none';
  $('warnTxt').textContent = msgs.join(' ');
}

function onScan(data) {
  busy('btnScan', false);
  S.scanned = true;
  $('scanHint').style.display = 'none';
  S.tags = data.tags;
  renderTags();
  onReport(data.report);
  showToast(t('rab_scanned', 'Scan selesai: %{count} tag.').replace('%{count}', data.tags.length));
}

// Dipanggil sekali saat dialog dibuka, dan lagi setiap sumber data berganti (onSources).
function init(data) {
  S.officialCatalog = data.catalog;
  S.officialCatalog.forEach(function (a) { a._s = searchText(a); });
  S.comps = data.comps || {};
  S.officialBase = data.base;
  S.officialBase.forEach(function (b) { b._s = (b.kode + ' ' + b.nama).toLowerCase(); });
  S.state = data.state;
  customData();
  S.sources = data.sources;
  S.themes = data.themes || [];
  S.tags = data.tags;
  S.scanned = !!data.scanned;
  $('scanHint').style.display = S.scanned ? 'none' : ''; // dialog baru dibuka: model belum diukur
  rebuildIndex();
  var hm = data.meta && data.meta.harga;
  $('priceSrc').style.display = hm ? '' : 'none';
  if (hm) {
    $('priceSrcTxt').textContent = t('rab_price_src', 'Harga terisi dari %{wilayah} (data TA %{tahun}): %{n} dari %{total} item. Sisanya masih 0.')
      .replace('%{wilayah}', hm.wilayah).replace('%{tahun}', hm.tahun_data).replace('%{n}', hm.terisi).replace('%{total}', hm.dari);
  }
  S.pf = Object.keys(S.state.map || {}).length ? 'used' : 'all';
  setPf(S.pf, true);
  $('projName').textContent = data.project || '';
  $('projName').title = data.project || '';
  $('opPct').value = S.state.op;
  $('ppnPct').value = S.state.ppn;
  $('ppnOn').checked = !!S.state.ppn_on;
  $('weeks').value = S.state.weeks || 12;
  if (!Array.isArray(S.state.info)) { // belum pernah diatur: mulai dari satu baris Nama Pekerjaan = judul model
    S.state.info = [{ label: t('rab_info_p_job', 'Nama Pekerjaan'), value: data.project && data.project !== 'Tanpa judul' ? data.project : '' }];
  }
  if (typeof S.state.info_date !== 'boolean') S.state.info_date = true;
  renderInfo();
  fillThemes();
  if (!S.byKode[S.sel]) S.sel = customAhsp().length ? customAhsp()[0].kode : null;
  renderTags();
  renderPrices();
  fillAnaDivisions();
  renderAna();
  renderSources();
  onReport(data.report);
}

// ── Interaksi tabel RAB ──
$('tbody').addEventListener('change', function (ev) {
  var tr = ev.target.closest('tr');
  if (!tr) return;
  var tag = tr.dataset.key, el = ev.target;
  if (el.classList.contains('basis') && S.state.map[tag]) S.state.map[tag].basis = el.value;
  else return;
  scheduleCalc();
});
$('tbody').addEventListener('input', function (ev) {
  var tr = ev.target.closest('tr');
  if (!tr) return;
  var e = S.state.map[tr.dataset.key];
  if (!e) return;
  var el = ev.target, v = parseFloat(el.value);
  if (el.classList.contains('factor')) {
    if (!(v > 0)) return; // kosong / 0 / negatif: tunggu isian valid
    e.factor = v;
  } else if (el.classList.contains('qty')) {
    e.manual = el.value === '' || isNaN(v) || v < 0 ? null : v;
    tr.querySelector('.qtyc').classList.toggle('manual', e.manual != null);
  } else {
    return;
  }
  scheduleCalc();
});
$('tbody').addEventListener('click', function (ev) {
  var jb = ev.target.closest('.job-btn');
  if (jb) return openPicker(jb.closest('tr').dataset.key);
  var eye = ev.target.closest('.eye-btn');
  if (eye) {
    var m = S.state.map[eye.closest('tr').dataset.key];
    if (m) openAnalysis(m.kode);
    return;
  }
  var rst = ev.target.closest('.rst');
  if (!rst) return;
  var tr = rst.closest('tr'), e = S.state.map[tr.dataset.key];
  if (!e) return;
  e.manual = null;
  tr.querySelector('.qty').value = '';
  tr.querySelector('.qtyc').classList.remove('manual');
  scheduleCalc();
});

$('opPct').addEventListener('input', function () {
  var v = parseFloat(this.value);
  if (isNaN(v) || v < 0 || v > 100) return;
  S.state.op = v;
  renderAna();
  scheduleCalc();
});
$('ppnPct').addEventListener('input', function () {
  var v = parseFloat(this.value);
  if (isNaN(v) || v < 0 || v > 100) return;
  S.state.ppn = v;
  scheduleCalc();
});
$('ppnOn').addEventListener('change', function () {
  S.state.ppn_on = this.checked;
  scheduleCalc();
});

// ── Tab Harga Dasar ──
// Database SE 47/2026 punya ribuan harga dasar: tampilkan yang dipakai di RAB (default) atau cari di semua,
// dan batasi jumlah baris yang digambar supaya dialog tetap ringan.
var PRICE_LIMIT = 150;
function setPf(pf, silent) {
  S.pf = pf;
  document.querySelectorAll('#pfSeg button').forEach(function (b) { b.setAttribute('aria-selected', b.dataset.pf === pf ? 'true' : 'false'); });
  if (!silent) renderPrices();
}
function renderPrices() {
  var q = $('priceSearch').value.toLowerCase().trim();
  var tokens = q ? q.split(/\s+/) : [];
  var used = {};
  S.usedBase.forEach(function (k) { used[k] = true; });
  $('nUsed').textContent = S.usedBase.length || '';
  $('nAll').textContent = S.base.length || '';
  var html = '', lastJenis = null, shown = 0, matched = 0;
  S.base.forEach(function (b) {
    if (S.pf === 'used' && !used[b.kode]) return;
    if (tokens.length) {
      for (var i = 0; i < tokens.length; i++) if (b._s.indexOf(tokens[i]) < 0) return;
    }
    matched++;
    if (shown >= PRICE_LIMIT) return;
    shown++;
    if (b.jenis !== lastJenis) {
      lastJenis = b.jenis;
      html += '<tr><td colspan="4" class="jn">' + esc(jenisLabel(b.jenis)) + '</td></tr>';
    }
    var changed = S.state.prices[b.kode] != null;
    var val = changed ? S.state.prices[b.kode] : b.harga;
    html += '<tr data-kode="' + esc(b.kode) + '" class="' + (changed ? 'chg ' : '') + (!(val > 0) ? 'zero' : '') + '"' + (b.sumber_harga ? ' title="' + esc(b.sumber_harga) + '"' : '') + '>' +
      '<td class="kd">' + esc(b.kode) + '</td><td class="nmc">' + esc(b.nama) + copyBtnHtml(b.nama) + '</td><td class="sat">' + esc(b.satuan) + '</td>' +
      '<td class="pv"><input class="input sm" style="text-align:right" type="number" min="0" step="any" value="' + esc(val) + '"></td></tr>';
  });
  if (matched > shown) {
    html += '<tr class="more"><td colspan="4">' + esc(t('rab_price_more', 'Menampilkan %{shown} dari %{total}. Persempit dengan kolom cari.').replace('%{shown}', shown).replace('%{total}', matched)) + '</td></tr>';
  }
  var empty = S.pf === 'used' && !tokens.length ? t('rab_price_none_used', 'Belum ada pekerjaan dipilih di tab RAB. Pilih “Semua” untuk mengisi harga lebih dulu.') : '—';
  $('pbody').innerHTML = html || '<tr><td colspan="4" class="jn" style="text-align:center;padding:14px">' + esc(empty) + '</td></tr>';
}
$('pbody').addEventListener('input', function (ev) {
  var tr = ev.target.closest('tr'), kode = tr && tr.dataset.kode;
  if (!kode) return;
  var v = parseFloat(ev.target.value);
  if (isNaN(v) || v < 0) return;
  setPrice(kode, v);
  tr.classList.toggle('chg', S.state.prices[kode] != null);
  tr.classList.toggle('zero', !(v > 0));
  scheduleCalc();
});
$('priceSearch').addEventListener('input', renderPrices);
document.querySelectorAll('#pfSeg button').forEach(function (b) {
  b.addEventListener('click', function () { setPf(b.dataset.pf); });
});
function resetPrices() {
  S.state.prices = {};
  renderPrices();
  renderAna();
  scheduleCalc();
}

// ── Tombol salin nama item (muncul saat kursor di atas baris): untuk mencari harga di web tanpa mengetik ulang ──
function copyBtnHtml(text) {
  var tip = t('rab_copy_name', 'Salin nama');
  return '<span class="cp" role="button" tabindex="-1" data-cp="' + esc(text) + '" title="' + esc(tip) + '" aria-label="' + esc(tip) + '">' + icon('copy') + '</span>';
}
function copyText(text) {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    return navigator.clipboard.writeText(text).catch(function () { return legacyCopy(text); });
  }
  return legacyCopy(text);
}
function legacyCopy(text) {
  return new Promise(function (resolve, reject) {
    var el = document.createElement('textarea');
    el.value = text;
    el.style.cssText = 'position:fixed;opacity:0;top:0;left:0';
    document.body.appendChild(el);
    el.select();
    var ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    document.body.removeChild(el);
    if (ok) resolve(); else reject(new Error('copy'));
  });
}
document.addEventListener('click', function (ev) {
  var b = ev.target.closest('.cp[data-cp]');
  if (!b) return;
  ev.stopPropagation();
  copyText(b.dataset.cp).then(function () {
    b.classList.add('done');
    b.innerHTML = icon('check');
    b.title = t('rab_copied', 'Tersalin');
    setTimeout(function () { b.classList.remove('done'); b.innerHTML = icon('copy'); b.title = t('rab_copy_name', 'Salin nama'); }, 1200);
  }).catch(function () { showToast(t('rab_copy_fail', 'Gagal menyalin.'), 'error'); });
}, true);

// ── Menu kecil (Ekspor ▾) ──
function closeMenus() { document.querySelectorAll('.mn.open').forEach(function (m) { m.classList.remove('open'); }); }
document.addEventListener('click', function (ev) {
  var trigger = ev.target.closest('[data-menu]');
  var target = trigger ? $(trigger.dataset.menu) : null;
  var wasOpen = target && target.classList.contains('open');
  closeMenus();
  if (target && !wasOpen) target.classList.add('open');
});

// Ekspor harga ke Excel / JSON dan impor lagi sebagai daftar harga (tab Sumber Data)
$('mnPrc').addEventListener('click', function (ev) {
  var b = ev.target.closest('button[data-fmt]');
  if (!b) return;
  if (b.dataset.fmt === 'template') return exportTemplate('harga', $('prcExport'));
  call('rab_export_prices', JSON.stringify({ state: S.state, format: b.dataset.fmt }), $('prcExport'));
});
// Template Excel kosong (kind: 'harga' | 'ahsp'): diisi user lalu diimpor lagi
function exportTemplate(kind, btn) { call('rab_export_template', JSON.stringify({ state: S.state, kind: kind }), btn); }
$('srcTpl').addEventListener('click', function () { exportTemplate('ahsp', this); });
$('prcTpl').addEventListener('click', function () { exportTemplate('harga', this); });
function importPrices() { call('rab_import_prices', stateJson(), this); }
$('prcImport').addEventListener('click', importPrices);
$('prcAdd').addEventListener('click', importPrices);

// ── Tema dokumen (Excel & PDF) + durasi proyek (kurva S) ──
var DEFAULT_THEME = 'app/biru';
function themeId() {
  var id = S.state.theme || DEFAULT_THEME;
  return S.themes.some(function (th) { return th.id === id; }) ? id : DEFAULT_THEME; // file tema yang tidak ada di komputer ini -> bawaan
}
function fillThemes() {
  var cur = themeId();
  var html = S.themes.map(function (th) {
    return '<option value="' + esc(th.id) + '"' + (th.id === cur ? ' selected' : '') + '>' + esc(th.nama) + (th.kind === 'user' ? ' ★' : '') + '</option>';
  }).join('');
  $('themeSel').innerHTML = html;
  $('pvTheme').innerHTML = html;
  $('themeDel').hidden = cur.indexOf('user/') !== 0;
}
function setTheme(id) {
  S.state.theme = id;
  fillThemes();
  scheduleCalc();
  if ($('pv').classList.contains('open')) pvRequest();
}
$('themeSel').addEventListener('change', function () { setTheme(this.value); });
$('pvTheme').addEventListener('change', function () { setTheme(this.value); });
$('weeks').addEventListener('input', function () {
  var v = parseInt(this.value, 10);
  if (isNaN(v) || v < 2 || v > 104) return;
  S.state.weeks = v;
  scheduleCalc();
});
$('weeks').addEventListener('change', function () { // di luar rentang: kembalikan ke nilai terakhir yang sah
  var v = parseInt(this.value, 10);
  if (isNaN(v) || v < 2 || v > 104) this.value = S.state.weeks || 12;
});
$('mnTheme').addEventListener('click', function (ev) {
  var b = ev.target.closest('button[data-act]');
  if (!b) return;
  if (b.dataset.act === 'template') return call('rab_theme_template', stateJson(), $('themeMenu'));
  if (b.dataset.act === 'import') return call('rab_theme_import', stateJson(), $('themeMenu'));
  // hapus tema: dua klik (menu tetap terbuka di klik pertama)
  ev.stopPropagation();
  if (!b.dataset.armed) {
    b.dataset.armed = '1';
    b.classList.add('armed');
    b.dataset.label = b.textContent;
    b.textContent = t('rab_theme_del_confirm', 'Klik lagi untuk menghapus tema ini');
    return;
  }
  closeMenus();
  call('rab_theme_remove', JSON.stringify({ state: S.state, id: themeId() }), $('themeMenu'));
});
$('themeMenu').addEventListener('click', function () { // menu dibuka ulang: reset tombol hapus
  var d = $('themeDel');
  if (d.dataset.armed) { delete d.dataset.armed; d.classList.remove('armed'); d.textContent = d.dataset.label; }
});

// ── Data pekerjaan (kepala dokumen): baris { label, value } bebas ditambah / dikurangi ──
var INFO_MAX = 20;
var INFO_PRESETS = [
  ['rab_info_p_job', 'Nama Pekerjaan'], ['rab_info_p_act', 'Nama Kegiatan'], ['rab_info_p_no', 'Nomor Kontrak'], ['rab_info_p_loc', 'Lokasi'],
  ['rab_info_p_val', 'Nilai Kontrak'], ['rab_info_p_time', 'Waktu Pelaksanaan'], ['rab_info_p_fund', 'Sumber Dana']
];
function infoRows() { return S.state.info; }
function infoCount() { return infoRows().filter(function (r) { return String(r.value || '').trim(); }).length; }
function renderInfo(keepFocus) {
  var rows = infoRows();
  $('infoList').innerHTML = rows.length ? rows.map(function (r, i) {
    return '<div class="info-row" data-i="' + i + '">' +
      '<input class="input il" data-f="label" maxlength="60" value="' + esc(r.label) + '" placeholder="' + esc(t('rab_info_label_ph', 'Judul (mis. Lokasi)')) + '" autocomplete="off" spellcheck="false">' +
      '<input class="input iv" data-f="value" maxlength="300" value="' + esc(r.value) + '" placeholder="' + esc(t('rab_info_value_ph', 'Isi')) + '" autocomplete="off" spellcheck="false">' +
      '<button class="btn ghost sm icon" type="button" data-del="1" title="' + esc(t('rab_info_del', 'Hapus baris')) + '" aria-label="' + esc(t('rab_info_del', 'Hapus baris')) + '"><svg><use href="#i-trash-2"/></svg></button>' +
      '</div>';
  }).join('') : '<div class="info-empty">' + esc(t('rab_info_none', 'Belum ada baris. Tambah dari tombol di bawah.')) + '</div>';
  var have = rows.map(function (r) { return String(r.label || '').trim().toLowerCase(); });
  $('infoPresets').innerHTML = INFO_PRESETS.map(function (p, i) {
    var label = t(p[0], p[1]);
    return '<button type="button" data-p="' + i + '"' + (have.indexOf(label.toLowerCase()) >= 0 || rows.length >= INFO_MAX ? ' disabled' : '') + '>+ ' + esc(label) + '</button>';
  }).join('');
  $('infoAdd').disabled = rows.length >= INFO_MAX;
  $('infoDate').checked = S.state.info_date !== false;
  $('nInfo').textContent = infoCount() || '';
}
function infoAddRow(label) {
  if (infoRows().length >= INFO_MAX) return;
  infoRows().push({ label: label || '', value: '' });
  renderInfo();
  var inputs = $('infoList').querySelectorAll('.info-row:last-child input');
  if (inputs.length) (label ? inputs[1] : inputs[0]).focus();
  var list = $('infoList');
  list.scrollTop = list.scrollHeight;
}
$('btnInfo').addEventListener('click', function () { renderInfo(); $('info').classList.add('open'); });
$('infoClose').addEventListener('click', function () { $('info').classList.remove('open'); });
$('infoAdd').addEventListener('click', function () { infoAddRow(''); });
$('infoPresets').addEventListener('click', function (ev) {
  var b = ev.target.closest('button[data-p]');
  if (!b) return;
  var p = INFO_PRESETS[+b.dataset.p];
  infoAddRow(t(p[0], p[1]));
  scheduleCalc();
});
$('infoList').addEventListener('input', function (ev) {
  var row = ev.target.closest('.info-row');
  if (!row || !ev.target.dataset.f) return;
  infoRows()[+row.dataset.i][ev.target.dataset.f] = ev.target.value; // tanpa render ulang supaya fokus & kursor tetap
  $('nInfo').textContent = infoCount() || '';
  scheduleCalc();
});
$('infoList').addEventListener('click', function (ev) {
  var b = ev.target.closest('button[data-del]');
  if (!b) return;
  infoRows().splice(+b.closest('.info-row').dataset.i, 1);
  renderInfo();
  scheduleCalc();
});
$('infoDate').addEventListener('change', function () { S.state.info_date = this.checked; scheduleCalc(); });
document.addEventListener('keydown', function (ev) {
  if (ev.key === 'Escape' && $('info').classList.contains('open')) $('info').classList.remove('open');
});

// ── Progress bar impor / ekspor (Ruby mengirim kemajuan per langkah) ──
var progTimer = null;
function pgLabel(key) {
  var labels = {
    rab_pg_measure: t('rab_pg_measure', 'Mengukur model…'), rab_pg_book: t('rab_pg_book', 'Menyusun dokumen…'),
    rab_pg_write: t('rab_pg_write', 'Menulis file…'), rab_pg_layout: t('rab_pg_layout', 'Menyusun halaman…'),
    rab_pg_pdf: t('rab_pg_pdf', 'Membuat PDF…'), rab_pg_collect: t('rab_pg_collect', 'Mengumpulkan data…'),
    rab_pg_read: t('rab_pg_read', 'Membaca file…'), rab_pg_merge: t('rab_pg_merge', 'Menggabungkan data…'),
    rab_pg_check: t('rab_pg_check', 'Memeriksa file…'), rab_pg_save: t('rab_pg_save', 'Menyimpan…'),
    rab_pg_reload: t('rab_pg_reload', 'Memuat ulang data…')
  };
  return labels[key] || key || '';
}
function rabProgress(pct, key) {
  var p = Math.max(0, Math.min(100, Math.round(pct || 0)));
  $('prog').classList.add('open');
  $('progFill').style.width = p + '%';
  $('progPct').textContent = p + '%';
  $('progTrack').setAttribute('aria-valuenow', p);
  if (key) $('progStep').textContent = pgLabel(key);
  clearTimeout(progTimer);
  progTimer = setTimeout(rabProgressEnd, 90000); // pengaman: kalau Ruby berhenti tanpa kabar, jangan mengunci dialog
}
function rabProgressEnd() {
  clearTimeout(progTimer);
  $('prog').classList.remove('open');
  $('progFill').style.width = '0%';
  $('progPct').textContent = '0%';
  $('progStep').textContent = '';
}

// ── Tab ──
function showTab(id) {
  document.querySelectorAll('#tabs button').forEach(function (b) { b.setAttribute('aria-selected', b.dataset.tab === id ? 'true' : 'false'); });
  document.querySelectorAll('.pnl').forEach(function (p) { p.classList.toggle('active', p.id === id); });
  if (id === 'pnlPrice') renderPrices(); // daftar "Dipakai di RAB" bisa berubah sejak terakhir dibuka
  if (id === 'pnlAna') renderAna();
  if (id === 'pnlSrc') renderSources();
}
document.querySelectorAll('#tabs button').forEach(function (b) {
  b.addEventListener('click', function () { showTab(b.dataset.tab); });
});

// Sumber ukur: tag (objek) atau material face (luas permukaan yang dicat/dilapis)
document.querySelectorAll('#srcSeg button').forEach(function (b) {
  b.addEventListener('click', function () {
    S.view = b.dataset.src;
    document.querySelectorAll('#srcSeg button').forEach(function (x) { x.setAttribute('aria-selected', x === b ? 'true' : 'false'); });
    renderTags();
  });
});

// ── Isi sebuah analisa: komponen x koefisien x harga ──
function fk(n) { return Number(n || 0).toLocaleString('id-ID', { maximumFractionDigits: 4 }); }
function usedCount(kode) {
  var n = 0;
  Object.keys(S.state.map).forEach(function (k) { if (S.state.map[k].kode === kode) n++; });
  return n;
}
// Tabel baca-saja (dipakai pratinjau di pemilih pekerjaan)
function previewHtml(kode) {
  var a = S.byKode[kode], comps = compsOf(kode), h = hspOf(kode);
  var rows = comps.map(function (c) {
    var b = S.baseBy[c.kode] || { nama: c.kode, satuan: '', jenis: 'bahan' }, pr = priceOf(c.kode);
    return '<tr><td title="' + esc(c.kode + ' · ' + b.nama) + '"><span class="chip" title="' + esc(jenisLabel(b.jenis)) + '">' + (JENIS_CHIP[b.jenis] || 'B') + '</span>' + esc(b.nama) + copyBtnHtml(b.nama) + '</td>' +
      '<td>' + esc(b.satuan) + '</td><td class="n">' + fk(c.koef) + '</td><td class="n">' + (pr > 0 ? rp(pr) : '—') + '</td><td class="n">' + rp(c.koef * pr) + '</td></tr>';
  }).join('') || '<tr><td colspan="5">' + esc(t('rab_cu_no_comps', 'Belum ada komponen. Tambahkan upah, bahan atau alat.')) + '</td></tr>';
  return '<div class="pk-pv" data-kode="' + esc(kode) + '">' +
    (isModified(kode) ? '<div class="mod">' + esc(t('rab_ana_modified_note', 'Komponen sudah Anda ubah dari aslinya.')) + '</div>' : '') +
    '<table><colgroup><col><col style="width:48px"><col style="width:70px"><col style="width:96px"><col style="width:96px"></colgroup>' +
    '<thead><tr><th>' + esc(t('rab_cu_c_name', 'Komponen')) + '</th><th>' + esc(t('rab_col_unit', 'Sat.')) + '</th><th class="n">' + esc(t('rab_cu_c_koef', 'Koefisien')) + '</th>' +
    '<th class="n">' + esc(t('rab_pcol_harga', 'Harga (Rp)')) + '</th><th class="n">' + esc(t('rab_col_total', 'Jumlah')) + '</th></tr></thead><tbody>' + rows +
    '<tr class="tot"><td colspan="4">' + esc(t('rab_cu_sum', 'Jumlah upah + bahan + alat')) + '</td><td class="n">' + rp(h.sum) + '</td></tr>' +
    '<tr class="tot"><td colspan="4">' + esc(t('rab_op', 'Overhead & Profit')) + ' ' + esc(S.state.op) + '%</td><td class="n">' + rp(h.op) + '</td></tr>' +
    '<tr class="tot"><td colspan="4">' + esc(t('rab_cu_hsp', 'Harga satuan pekerjaan')) + ' / ' + esc(a.satuan) + '</td><td class="n">' + rp(h.hsp) + '</td></tr></tbody></table>' +
    '<div class="acts">' +
      (S.pickKey ? '<button type="button" class="btn primary sm" data-act="pick">' + icon('check') + '<span>' + esc(t('rab_pk_use', 'Pilih pekerjaan ini')) + '</span></button>' : '') +
      '<button type="button" class="btn ghost sm" data-act="edit">' + icon('eye') + '<span>' + esc(t('rab_pk_edit', 'Buka & ubah di tab Analisa')) + '</span></button></div></div>';
}

// ── Pemilih pekerjaan (AHSP) ──
var PK_PAGE = 80;
var pk = { limit: PK_PAGE, hits: [], cur: -1, open: null };

function divisionsOf() {
  var divs = [], seen = {};
  S.catalog.forEach(function (a) { if (!seen[a.divisi]) { seen[a.divisi] = true; divs.push(a.divisi); } });
  return divs;
}
function divisionOptions(selected) {
  return '<option value="">' + esc(t('rab_pk_all_div', 'Semua divisi')) + '</option>' +
    divisionsOf().map(function (d) { return '<option value="' + esc(d) + '"' + (d === selected ? ' selected' : '') + '>' + esc(d) + '</option>'; }).join('');
}
function fillDivisions() {
  $('pkDiv').innerHTML = divisionOptions('');
  fillCategories();
}
function fillCategories() {
  var div = $('pkDiv').value, cats = [], seen = {};
  S.catalog.forEach(function (a) {
    if (div && a.divisi !== div) return;
    if (a.kategori && !seen[a.kategori]) { seen[a.kategori] = true; cats.push(a.kategori); }
  });
  $('pkCat').innerHTML = '<option value="">' + esc(t('rab_pk_all_cat', 'Semua kategori')) + '</option>' +
    cats.map(function (c) { return '<option value="' + esc(c) + '">' + esc(c) + '</option>'; }).join('');
  $('pkCat').disabled = !div;
}
function pickerHits() {
  var tokens = $('pkQ').value.toLowerCase().trim().split(/\s+/).filter(Boolean);
  var div = $('pkDiv').value, cat = $('pkCat').value;
  var hits = S.catalog.filter(function (a) {
    if (div && a.divisi !== div) return false;
    if (cat && a.kategori !== cat) return false;
    for (var i = 0; i < tokens.length; i++) if (a._s.indexOf(tokens[i]) < 0) return false;
    return true;
  });
  var first = tokens[0];
  if (tokens.length) {
    // urut menurut kecocokan: awalan kode, lalu kata di uraian (kata utuh / awal uraian lebih tinggi); seri tetap urutan katalog
    var score = function (a) {
      var u = a.uraian.toLowerCase(), s = 0;
      if (/^[0-9]/.test(first) && a.kode.indexOf(first) === 0) s += 100;
      tokens.forEach(function (tk) {
        var i = u.indexOf(tk);
        if (i >= 0) s += i === 0 ? 30 : (u.charAt(i - 1) === ' ' ? 20 : 10);
      });
      return s - u.length / 1000 + (a.custom ? 0.5 : 0);
    };
    hits.forEach(function (a, i) { a._r = score(a); a._i = i; });
    hits.sort(function (x, y) { return (y._r - x._r) || (x._i - y._i); });
  }
  return hits;
}
function renderPicker(keepScroll) {
  var cur = S.state.map[S.pickKey], curKode = cur && cur.kode, scroll = $('pkList').scrollTop;
  pk.hits = pickerHits();
  var shown = pk.hits.slice(0, pk.limit), html = '', lastDiv = null;
  var grouped = !$('pkQ').value.trim(); // tanpa kata kunci: per divisi; dengan kata kunci: daftar menurut kecocokan
  shown.forEach(function (a, i) {
    if (grouped && a.divisi !== lastDiv) { lastDiv = a.divisi; html += '<div class="pk-grp">' + esc(a.divisi) + '</div>'; }
    html += '<div class="pk-it job' + (a.kode === curKode ? ' sel' : '') + '" data-i="' + i + '" data-kode="' + esc(a.kode) + '">' +
      '<span class="kd">' + esc(a.kode) + '</span>' +
      '<span class="ur">' + esc(a.uraian) + (a.kategori || !grouped ? '<small>' + esc((grouped ? '' : a.divisi + (a.kategori ? ' · ' : '')) + (a.kategori || '')) + '</small>' : '') + '</span>' +
      '<span class="su">' + esc(a.satuan) + (a.keyakinan === 'periksa' ? '<i title="' + esc(t('rab_pk_check', 'periksa ke PDF resmi')) + '">!</i>' : '') + '</span>' +
      '<span class="eye' + (pk.open === a.kode ? ' on' : '') + '" title="' + esc(t('rab_pk_preview', 'Lihat isi analisa')) + '">' + icon('eye') + '</span></div>';
    if (pk.open === a.kode) html += previewHtml(a.kode);
  });
  if (!shown.length) html = '<div class="empty">' + esc(t('rab_pk_none', 'Tidak ada pekerjaan yang cocok.')) + '</div>';
  else if (pk.hits.length > shown.length) html += '<div class="more" id="pkMore">' + esc(t('rab_pk_more', 'Tampilkan lebih banyak (%{n} lagi)').replace('%{n}', pk.hits.length - shown.length)) + '</div>';
  $('pkList').innerHTML = html;
  if (keepScroll) $('pkList').scrollTop = scroll;
  $('pkCount').textContent = pk.hits.length + ' / ' + S.catalog.length;
  pk.cur = -1;
  $('pkClear').style.display = cur ? '' : 'none';
}
function pkMove(d) {
  var items = $('pkList').querySelectorAll('.pk-it');
  if (!items.length) return;
  if (pk.cur >= 0 && items[pk.cur]) items[pk.cur].classList.remove('on');
  pk.cur = Math.max(0, Math.min(items.length - 1, pk.cur + d));
  items[pk.cur].classList.add('on');
  items[pk.cur].scrollIntoView({ block: 'nearest' });
}
// Pilih pekerjaan untuk satu tag / material
function openPicker(key) {
  S.pickKey = key;
  var kind = key.split(':')[0], name = key.slice(kind.length + 1);
  $('pkFor').textContent = (kind === 'mat' ? t('rab_src_mat', 'Material face') : t('rab_src_tag', 'Tag')) + ': ' + name;
  pk.limit = PK_PAGE;
  pk.open = null;
  $('pkQ').value = '';
  fillDivisions();
  $('pkDiv').value = '';
  fillCategories();
  renderPicker();
  $('pk').classList.add('open');
  setTimeout(function () { $('pkQ').focus(); }, 30);
}
function closePicker() { $('pk').classList.remove('open'); S.pickKey = null; pk.open = null; }
function pickJob(kode) {
  var key = S.pickKey;
  if (!key) return;
  if (!kode) delete S.state.map[key];
  else {
    var prev = S.state.map[key];
    S.state.map[key] = { kode: kode, basis: prev ? prev.basis : 'auto', factor: prev ? prev.factor : 1, manual: prev ? prev.manual : null };
  }
  Array.prototype.forEach.call($('tbody').children, function (tr) { if (tr.dataset.key === key) syncRow(tr); });
  closePicker();
  scheduleCalc();
}
var pkTimer = null;
$('pkQ').addEventListener('input', function () { clearTimeout(pkTimer); pkTimer = setTimeout(function () { pk.limit = PK_PAGE; renderPicker(); }, 120); });
$('pkQ').addEventListener('keydown', function (ev) {
  if (ev.key === 'ArrowDown') { ev.preventDefault(); pkMove(1); }
  else if (ev.key === 'ArrowUp') { ev.preventDefault(); pkMove(-1); }
  else if (ev.key === 'Enter') {
    ev.preventDefault();
    var items = $('pkList').querySelectorAll('.pk-it'), it = items[pk.cur >= 0 ? pk.cur : 0];
    if (it) pickJob(it.dataset.kode);
  }
});
$('pkDiv').addEventListener('change', function () { fillCategories(); pk.limit = PK_PAGE; renderPicker(); });
$('pkCat').addEventListener('change', function () { pk.limit = PK_PAGE; renderPicker(); });
$('pkList').addEventListener('click', function (ev) {
  if (ev.target.closest('#pkMore')) { pk.limit += PK_PAGE * 2; return renderPicker(true); }
  var act = ev.target.closest('[data-act]');
  if (act) {
    var kode = act.closest('.pk-pv').dataset.kode;
    if (act.dataset.act === 'pick') return pickJob(kode);
    closePicker();
    return openAnalysis(kode);
  }
  var eye = ev.target.closest('.eye');
  if (eye) {
    var k = eye.closest('.pk-it').dataset.kode;
    pk.open = pk.open === k ? null : k;
    return renderPicker(true);
  }
  if (ev.target.closest('.pk-pv')) return;
  var it = ev.target.closest('.pk-it');
  if (it) pickJob(it.dataset.kode);
});
$('pkClose').addEventListener('click', closePicker);
$('pkClear').addEventListener('click', function () { pickJob(''); });

// ── Tab Analisa: semua AHSP (resmi, sudah diubah, dan buatan sendiri) ──
var ANA_PAGE = 60;

function fillAnaDivisions() {
  var cur = $('anDiv').value;
  $('anDiv').innerHTML = divisionOptions(cur);
  $('anDiv').value = divisionsOf().indexOf(cur) >= 0 ? cur : '';
}
function anaHits() {
  var tokens = $('anQ').value.toLowerCase().trim().split(/\s+/).filter(Boolean), div = $('anDiv').value, f = S.anFilter, used = {};
  if (f === 'used') Object.keys(S.state.map).forEach(function (k) { used[S.state.map[k].kode] = true; });
  return S.catalog.filter(function (a) {
    if (div && a.divisi !== div) return false;
    if (f === 'used' && !used[a.kode]) return false;
    if (f === 'mine' && !a.custom && !isModified(a.kode)) return false;
    for (var i = 0; i < tokens.length; i++) if (a._s.indexOf(tokens[i]) < 0) return false;
    return true;
  });
}
function renderAnaList() {
  var hits = anaHits();
  if (S.reveal) { // dibuka dari tempat lain: pastikan item terpilih ikut tergambar
    for (var i = 0; i < hits.length; i++) if (hits[i].kode === S.sel) { if (i >= S.anLimit) S.anLimit = i + 1; break; }
    S.reveal = false;
  }
  var shown = hits.slice(0, S.anLimit);
  $('nCu').textContent = customAhsp().length + Object.keys(S.state.overrides).length || '';
  $('anCount').textContent = hits.length + ' / ' + S.catalog.length;
  var html = shown.map(function (a) {
    var bd = a.custom ? '<span class="bd">' + esc(t('rab_ana_badge_mine', 'SAYA')) + '</span>' : isModified(a.kode) ? '<span class="bd mod">' + esc(t('rab_ana_badge_mod', 'DIUBAH')) + '</span>' : '';
    return '<div class="cu-it' + (a.kode === S.sel ? ' sel' : '') + '" data-kode="' + esc(a.kode) + '"><div class="k">' + esc(a.kode) + bd + '</div>' +
      '<div class="u">' + esc(a.uraian) + '</div>' + copyBtnHtml(a.uraian) + '<div class="h">' + rp(hspOf(a.kode).hsp) + ' / ' + esc(a.satuan) + '</div></div>';
  }).join('');
  if (!shown.length) html = '<div class="empty">' + esc(t('rab_ana_none', 'Tidak ada analisa yang cocok.')) + '</div>';
  else if (hits.length > shown.length) html += '<div class="more" id="anMore">' + esc(t('rab_pk_more', 'Tampilkan lebih banyak (%{n} lagi)').replace('%{n}', hits.length - shown.length)) + '</div>';
  $('cuList').innerHTML = html;
  var sel = $('cuList').querySelector('.cu-it.sel');
  if (sel && S.scrollSel) sel.scrollIntoView({ block: 'nearest' });
  S.scrollSel = false;
}
function updateAnaTotals() {
  if (!S.byKode[S.sel] || !$('cuSum')) return;
  var h = hspOf(S.sel);
  $('cuSum').textContent = rp(h.sum);
  $('cuOp').textContent = rp(h.op);
  $('cuHsp').textContent = rp(h.hsp);
}
function compRowsHtml(kode) {
  return compsOf(kode).map(function (c, i) {
    var b = S.baseBy[c.kode] || { nama: c.kode, satuan: '', jenis: 'bahan' };
    var pr = priceOf(c.kode);
    return '<tr data-i="' + i + '" class="' + (pr > 0 ? '' : 'zero') + '">' +
      '<td class="nm" title="' + esc(c.kode + ' · ' + b.nama) + '"><span class="chip" title="' + esc(jenisLabel(b.jenis)) + '">' + (JENIS_CHIP[b.jenis] || 'B') + '</span>' + esc(b.nama) + copyBtnHtml(b.nama) + '</td>' +
      '<td>' + esc(b.satuan) + '</td>' +
      '<td class="n"><input class="input sm num koef" type="number" min="0" step="any" value="' + esc(c.koef) + '"></td>' +
      '<td class="pr"><input class="input sm num price" type="number" min="0" step="any" value="' + esc(pr) + '" title="' + esc(t('rab_ana_price_tip', 'Harga dasar ini dipakai semua analisa yang memuatnya')) + '"></td>' +
      '<td class="n jml">' + rp(c.koef * pr) + '</td>' +
      '<td><span class="x" title="' + esc(t('rab_cu_remove', 'Hapus komponen')) + '">' + icon('x') + '</span></td></tr>';
  }).join('');
}
function resetButtonHtml() {
  return '<button class="btn ghost sm danger" id="anReset" type="button">' + icon('rotate-ccw') + '<span>' + esc(t('rab_ana_reset', 'Kembalikan ke asli')) + '</span></button>';
}
// AHSP resmi baru saja diubah: pasang lencana DIUBAH dan tombol "kembalikan" langsung di editor yang sedang terbuka
function showModifiedUi() {
  var title = document.querySelector('#cuEdit .ro-head .t');
  if (title && !title.querySelector('.bd')) title.insertAdjacentHTML('beforeend', '<span class="bd">' + esc(t('rab_ana_badge_mod', 'DIUBAH')) + '</span>');
  if ($('cuDup') && !$('anReset')) $('cuDup').insertAdjacentHTML('beforebegin', resetButtonHtml());
}
function renderAnaEditor() {
  var a = S.byKode[S.sel];
  if (!a) {
    $('cuEdit').innerHTML = '<div class="empty">' + esc(t('rab_cu_empty_edit', 'Pilih analisa di kiri, atau buat yang baru.')) + '</div>';
    return;
  }
  var cu = S.cuBy[a.kode], mod = isModified(a.kode), used = usedCount(a.kode);
  var units = ['m3', 'm2', 'm', 'buah', 'unit', 'titik', 'set', 'kg', 'ls'];
  var head;
  if (cu) {
    head = '<div class="row">' +
      '<label class="f grow"><span>' + esc(t('rab_cu_f_uraian', 'Uraian pekerjaan')) + ' · ' + esc(a.kode) + '</span><input class="input" id="cuUraian" maxlength="200" value="' + esc(cu.uraian) + '" autocomplete="off"></label>' +
      '<label class="f"><span>' + esc(t('rab_col_unit', 'Sat.')) + '</span><input class="input" id="cuSat" list="cuUnits" maxlength="12" style="width:84px" value="' + esc(cu.satuan) + '" autocomplete="off">' +
        '<datalist id="cuUnits">' + units.map(function (u) { return '<option value="' + u + '">'; }).join('') + '</datalist></label>' +
      '<label class="f grow"><span>' + esc(t('rab_cu_f_kat', 'Kategori (opsional)')) + '</span><input class="input" id="cuKat" maxlength="80" value="' + esc(cu.kategori || '') + '" autocomplete="off"></label></div>';
  } else {
    head = '<div class="ro-head"><div class="t">' + esc(a.uraian) + (mod ? '<span class="bd">' + esc(t('rab_ana_badge_mod', 'DIUBAH')) + '</span>' : '') +
      (a.keyakinan === 'periksa' ? '<span class="bd warn" title="' + esc(t('rab_pk_check', 'periksa ke PDF resmi')) + '">' + esc(t('rab_ana_check', 'PERIKSA')) + '</span>' : '') + '</div>' +
      '<div class="s">' + esc(a.kode + ' · ' + a.divisi + (a.kategori ? ' · ' + a.kategori : '') + ' · ' + t('rab_col_unit', 'Sat.') + ' ' + a.satuan) + '</div></div>';
  }
  var rows = compRowsHtml(a.kode);
  $('cuEdit').innerHTML = head +
    '<table class="cu-comps"><colgroup><col><col style="width:54px"><col style="width:86px"><col style="width:112px"><col style="width:104px"><col style="width:30px"></colgroup>' +
      '<thead><tr><th>' + esc(t('rab_cu_c_name', 'Komponen')) + '</th><th>' + esc(t('rab_col_unit', 'Sat.')) + '</th><th class="n">' + esc(t('rab_cu_c_koef', 'Koefisien')) + '</th>' +
      '<th class="n">' + esc(t('rab_cu_c_price', 'Harga (Rp)')) + '</th><th class="n">' + esc(t('rab_col_total', 'Jumlah')) + '</th><th></th></tr></thead>' +
      '<tbody>' + (rows || '<tr><td colspan="6" class="empty">' + esc(t('rab_cu_no_comps', 'Belum ada komponen. Tambahkan upah, bahan atau alat.')) + '</td></tr>') + '</tbody></table>' +
    '<div class="row"><button class="btn ghost sm" id="cuAddComp" type="button">' + icon('plus') + '<span>' + esc(t('rab_cu_add', 'Tambah komponen')) + '</span></button>' +
      '<span style="flex:1"></span>' +
      (mod ? resetButtonHtml() : '') +
      '<button class="btn ghost sm" id="cuDup" type="button">' + icon('copy') + '<span>' + esc(cu ? t('rab_cu_dup', 'Duplikat') : t('rab_ana_tocopy', 'Salin jadi analisa saya')) + '</span></button>' +
      (cu ? '<button class="btn ghost sm danger" id="cuDel" type="button">' + icon('trash-2') + '<span>' + esc(t('rab_cu_del', 'Hapus analisa')) + '</span></button>' : '') + '</div>' +
    (used ? '<div class="used-note">' + esc(t('rab_ana_used', 'Dipakai di %{n} baris RAB.').replace('%{n}', used)) + '</div>' : '') +
    '<div class="cu-tot"><div>' + esc(t('rab_cu_sum', 'Jumlah upah + bahan + alat')) + ' <span class="v" id="cuSum"></span></div>' +
      '<div>' + esc(t('rab_op', 'Overhead & Profit')) + ' ' + esc(S.state.op) + '% <span class="v" id="cuOp"></span></div>' +
      '<div class="hsp"><b>' + esc(t('rab_cu_hsp', 'Harga satuan pekerjaan')) + ' / <span id="cuHspU">' + esc(a.satuan) + '</span></b> <span class="v" id="cuHsp"></span></div></div>';
  updateAnaTotals();
}
function renderAna() {
  if (!S.byKode[S.sel]) S.sel = customAhsp().length ? customAhsp()[0].kode : null;
  renderAnaList();
  renderAnaEditor();
}
// Dipakai setelah data berubah. structural: susunan komponen / jumlah analisa berubah (gambar ulang editor).
function anaChanged(structural) {
  rebuildIndex();
  Array.prototype.forEach.call($('tbody').children, syncRow);
  if (structural) renderAna(); else { renderAnaList(); updateAnaTotals(); }
  scheduleCalc();
}
function addCustom(a) {
  customAhsp().push(a);
  S.sel = a.kode;
  S.anFilter = 'all';
  syncAnaFilter();
  $('anQ').value = '';
  $('anDiv').value = '';
  S.reveal = true;
  S.scrollSel = true;
  showTab('pnlAna');
  anaChanged(true);
  var u = $('cuUraian');
  if (u) { u.focus(); u.select(); }
}
// Buka analisa tertentu di tab Analisa (dari baris RAB / pratinjau di pemilih pekerjaan)
function openAnalysis(kode) {
  if (!S.byKode[kode]) return;
  S.sel = kode;
  S.anFilter = 'all';
  syncAnaFilter();
  $('anQ').value = '';
  $('anDiv').value = '';
  S.reveal = true;
  S.scrollSel = true;
  showTab('pnlAna');
}
function syncAnaFilter() {
  document.querySelectorAll('#anSeg button').forEach(function (b) { b.setAttribute('aria-selected', b.dataset.an === S.anFilter ? 'true' : 'false'); });
}
function resetAnaList() { S.anLimit = ANA_PAGE; renderAnaList(); }
var anTimer = null;
$('anQ').addEventListener('input', function () { clearTimeout(anTimer); anTimer = setTimeout(resetAnaList, 120); });
$('anDiv').addEventListener('change', resetAnaList);
document.querySelectorAll('#anSeg button').forEach(function (b) {
  b.addEventListener('click', function () { S.anFilter = b.dataset.an; syncAnaFilter(); resetAnaList(); });
});
$('cuNew').addEventListener('click', function () {
  addCustom({ kode: nextKode('U', customAhsp()), uraian: t('rab_cu_default_name', 'Analisa baru'), satuan: 'm2', komponen: [] });
});
$('mnAna').addEventListener('click', function (ev) {
  var b = ev.target.closest('button[data-fmt]');
  if (!b) return;
  if (b.dataset.fmt === 'mine') return call('rab_export_custom', stateJson(), $('cuExport'));
  if (b.dataset.fmt === 'template') return exportTemplate('ahsp', $('cuExport'));
  var kodes = anaHits().map(function (a) { return a.kode; }); // persis yang tampil di daftar (sesuai cari & filter), bukan hanya halaman pertama
  if (!kodes.length) return showToast(t('rab_ana_none', 'Tidak ada analisa yang cocok.'), 'error');
  call('rab_export_analyses', JSON.stringify({ state: S.state, kodes: kodes, format: b.dataset.fmt }), $('cuExport'));
});
$('cuImport').addEventListener('click', function () { call('rab_import_custom', stateJson(), this); });
$('cuList').addEventListener('click', function (ev) {
  if (ev.target.closest('#anMore')) { S.anLimit += ANA_PAGE * 2; return renderAnaList(); }
  var it = ev.target.closest('.cu-it');
  if (!it) return;
  S.sel = it.dataset.kode;
  renderAna();
});
$('cuEdit').addEventListener('input', function (ev) {
  var a = S.byKode[S.sel], el = ev.target, cu = S.cuBy[S.sel];
  if (!a) return;
  if (cu && el.id === 'cuUraian') { cu.uraian = el.value; anaChanged(false); }
  else if (cu && el.id === 'cuSat') { cu.satuan = el.value; $('cuHspU').textContent = el.value; anaChanged(false); }
  else if (cu && el.id === 'cuKat') { cu.kategori = el.value; anaChanged(false); }
  else if (el.classList.contains('koef') || el.classList.contains('price')) {
    var tr = el.closest('tr'), i = +tr.dataset.i, c = compsOf(S.sel)[i], v = parseFloat(el.value);
    if (!c || isNaN(v) || v < 0) return;
    if (el.classList.contains('koef')) {
      if (!(v > 0)) return;
      var first = !cu && !isModified(S.sel);
      editableComps(S.sel)[i].koef = v;
      if (first) showModifiedUi(); // tanpa gambar ulang editor, supaya kursor tetap di isian yang sedang diketik
    } else {
      setPrice(c.kode, v);
    }
    var pr = priceOf(c.kode);
    tr.classList.toggle('zero', !(pr > 0));
    tr.querySelector('.jml').textContent = rp(compsOf(S.sel)[i].koef * pr);
    anaChanged(false);
  }
});
var armedTimer = null;
// Tombol dua klik: klik pertama minta konfirmasi, klik kedua menjalankan (tanpa dialog bawaan browser)
function confirmTwice(btn, label, run, restore) {
  if (!btn.dataset.armed) {
    btn.dataset.armed = '1';
    btn.classList.add('armed');
    btn.querySelector('span').textContent = label;
    clearTimeout(armedTimer);
    armedTimer = setTimeout(restore || renderAnaEditor, 3000);
    return;
  }
  clearTimeout(armedTimer);
  run();
}
$('cuEdit').addEventListener('click', function (ev) {
  var a = S.byKode[S.sel], cu = S.cuBy[S.sel];
  if (!a) return;
  var x = ev.target.closest('.x');
  if (x) {
    editableComps(S.sel).splice(+x.closest('tr').dataset.i, 1);
    return anaChanged(true);
  }
  if (ev.target.closest('#cuAddComp')) return openCompPicker();
  if (ev.target.closest('#cuDup')) {
    return addCustom({ kode: nextKode('U', customAhsp()), uraian: a.uraian + ' ' + t('rab_cu_copy_suffix', '(salinan)'), satuan: a.satuan,
      kategori: a.kategori || '', komponen: compsOf(S.sel).map(function (c) { return { kode: c.kode, koef: c.koef }; }) });
  }
  var reset = ev.target.closest('#anReset');
  if (reset) {
    return confirmTwice(reset, t('rab_ana_reset_confirm', 'Klik lagi untuk mengembalikan'), function () {
      delete S.state.overrides[S.sel];
      anaChanged(true);
    });
  }
  var del = ev.target.closest('#cuDel');
  if (del && cu) {
    confirmTwice(del, t('rab_cu_del_confirm', 'Klik lagi untuk menghapus'), function () {
      var list = customAhsp(), i = list.indexOf(cu);
      list.splice(i, 1);
      Object.keys(S.state.map).forEach(function (k) { if (S.state.map[k].kode === cu.kode) delete S.state.map[k]; });
      S.sel = list.length ? list[Math.min(i, list.length - 1)].kode : null;
      anaChanged(true);
    });
  }
});

// Hasil ekspor / impor file analisa
function onCustomFile(res) {
  rabProgressEnd();
  ['cuExport', 'cuImport'].forEach(function (id) { if ($(id).dataset.html != null) busy(id, false); });
  if (!res) return;
  if (res.custom) {
    S.state.custom = res.custom;
    S.sel = res.custom.ahsp.length ? res.custom.ahsp[res.custom.ahsp.length - 1].kode : null;
    S.reveal = true;
    S.scrollSel = true;
    anaChanged(true);
    showToast(t('rab_cu_imported', 'Diimpor: %{a} analisa, %{b} harga dasar baru.').replace('%{a}', res.info.ahsp).replace('%{b}', res.info.base), 'success');
  } else if (res.path) {
    showToast(t('rab_cu_exported', 'Tersimpan: %{path}').replace('%{path}', res.path), 'success');
  }
}

// ── Tab Sumber Data: file JSON AHSP yang dipakai ──
function activeSourceIds() {
  return (S.sources ? S.sources.items : []).filter(function (s) { return s.active; }).map(function (s) { return s.id; });
}
function srcError(code) {
  if (code === 'json') return t('rab_src_err_json', 'File bukan JSON yang valid.');
  if (code === 'format') return t('rab_src_err_format', 'Bukan file AHSP (tidak ada daftar "ahsp").');
  return t('rab_src_err_path', 'File tidak ditemukan.');
}
function renderSources() {
  var src = S.sources;
  if (!src) return;
  var prices = src.prices || { items: [], missing: [] };
  $('nSrc').textContent = (activeSourceIds().length + prices.items.filter(function (s) { return s.active; }).length) || '';
  var held = S.state.hold || {};
  var nHeld = Object.keys(held.map || {}).length;
  $('srcHold').style.display = nHeld ? '' : 'none';
  $('srcHoldTxt').textContent = t('rab_src_hold', '%{n} pekerjaan di RAB memakai analisa dari file yang sedang tidak dipakai. Datanya tersimpan dan tampil lagi saat file itu dicentang.').replace('%{n}', nHeld);
  var html = src.items.map(function (s) {
    var kind = s.kind === 'app' ? t('rab_src_builtin', 'BAWAAN') : t('rab_src_user', 'FILE SAYA');
    var meta = s.error
      ? '<div class="meta err">' + esc(srcError(s.error)) + ' (' + esc(s.file) + ')</div>'
      : '<div class="meta">' + esc(fmt(s.ahsp) + ' ' + t('rab_src_n_ahsp', 'analisa') + ' · ' + fmt(s.base) + ' ' + t('rab_src_n_base', 'harga dasar') + (s.versi ? ' · v' + s.versi : '') + ' · ' + s.file) +
        (s.skipped || s.reserved ? ' · ' + esc(t('rab_src_skipped', '%{n} baris dilewati (tidak valid / kode dicadangkan)').replace('%{n}', s.skipped + s.reserved)) : '') + '</div>' +
        (s.sumber ? '<div class="meta">' + esc(s.sumber) + '</div>' : '');
    return srcCard(s, s.nama || s.file, kind, meta, s.kind === 'user', true);
  }).join('');
  html += src.missing.map(function (id) { return srcMissing(id); }).join('');
  $('srcList').innerHTML = html || '<div class="empty">' + esc(t('rab_src_none', 'Belum ada file AHSP.')) + '</div>';

  var ph = prices.items.map(function (s) {
    var meta = s.error
      ? '<div class="meta err">' + esc(srcError(s.error)) + ' (' + esc(s.file) + ')</div>'
      : '<div class="meta">' + esc(fmt(s.items) + ' ' + t('rab_prc_n_items', 'item') + ' · ' + t('rab_prc_matched', '%{n} cocok dengan harga dasar saat ini').replace('%{n}', fmt(s.matched)) +
        (s.wilayah ? ' · ' + s.wilayah : '') + (s.tahun ? ' · ' + s.tahun : '') + ' · ' + s.file) + '</div>' +
        (s.sumber ? '<div class="meta">' + esc(s.sumber) + '</div>' : '');
    return srcCard(s, s.nama || s.file, t('rab_prc_badge', 'HARGA'), meta, true);
  }).join('');
  ph += prices.missing.map(function (id) { return srcMissing(id); }).join('');
  $('prcList').innerHTML = ph || '<div class="empty">' + esc(t('rab_prc_none', 'Belum ada daftar harga. Harga memakai bawaan file AHSP.')) + '</div>';
  $('srcList').classList.toggle('loading', !!S.srcBusy);
  $('prcList').classList.toggle('loading', !!S.srcBusy);
}
function srcCard(s, title, badge, meta, deletable, exportable) {
  var exp = exportable && !s.error
    ? '<button type="button" class="btn ghost sm src-exp" data-fmt="book" title="' + esc(t('rab_src_exp_book', 'Ekspor ke Excel format AHSP (bisa diedit & diimpor lagi)')) + '">' + icon('download') + '<span>Excel</span></button>' +
      '<button type="button" class="btn ghost sm src-exp" data-fmt="json" title="' + esc(t('rab_src_exp_json', 'Ekspor ke JSON (file AHSP)')) + '"><span>JSON</span></button>'
    : '';
  var del = deletable ? '<button type="button" class="btn ghost sm danger src-del">' + icon('trash-2') + '<span>' + esc(t('rab_src_del', 'Hapus file')) + '</span></button>' : '';
  return '<div class="src-it' + (s.active ? '' : ' off') + '" data-id="' + esc(s.id) + '">' +
    '<label class="check"><input type="checkbox" class="src-cb"' + (s.active ? ' checked' : '') + (s.error ? ' disabled' : '') + '><span class="box"><svg><use href="#i-check"/></svg></span></label>' +
    '<div><div class="nm">' + esc(title) + '<span class="bd">' + esc(badge) + '</span></div>' + meta + '</div>' +
    (exp || del ? '<div class="src-act">' + exp + del + '</div>' : '<span></span>') + '</div>';
}
function onSrcExport(ev) {
  var b = ev.target.closest('.src-exp');
  if (!b || S.srcBusy) return;
  call('rab_export_source', JSON.stringify({ state: S.state, id: b.closest('.src-it').dataset.id, format: b.dataset.fmt }), b);
}
$('srcList').addEventListener('click', onSrcExport);
function resetSrcExport() {
  document.querySelectorAll('#srcList .src-exp').forEach(function (b) { if (b.dataset.html != null) busy(b, false); });
}
function srcMissing(id) {
  return '<div class="src-it miss" data-id="' + esc(id) + '"><label class="check"><input type="checkbox" class="src-cb" checked><span class="box"><svg><use href="#i-check"/></svg></span></label>' +
    '<div><div class="nm">' + esc(id.split('/').pop()) + '</div><div class="meta err">' + esc(t('rab_src_missing', 'File ini tidak ada di komputer ini. Pilihan yang memakainya tetap tersimpan; hilangkan centang untuk melepasnya.')) + '</div></div><span></span></div>';
}
// Centang file: daftar analisa (minimal satu yang terbaca) atau daftar harga (boleh kosong)
function onSrcToggle(ev) {
  var cb = ev.target.closest('.src-cb');
  if (!cb || S.srcBusy) return;
  var isPrice = ev.currentTarget.id === 'prcList', field = isPrice ? 'price_sources' : 'sources';
  var id = cb.closest('.src-it').dataset.id, ids = (S.state[field] || []).filter(function (x) { return x !== id; });
  if (cb.checked) ids.push(id);
  if (!isPrice) {
    var usable = (S.sources.items || []).filter(function (s) { return !s.error && ids.indexOf(s.id) >= 0; }).length;
    if (!usable) {
      cb.checked = true;
      return showToast(t('rab_src_min', 'Minimal satu file AHSP harus dipakai.'), 'error');
    }
  }
  S.state[field] = ids;
  S.srcBusy = true;
  renderSources();
  call('rab_set_sources', stateJson());
}
function onSrcDelete(ev) {
  var del = ev.target.closest('.src-del');
  if (!del || S.srcBusy) return;
  var id = del.closest('.src-it').dataset.id;
  confirmTwice(del, t('rab_cu_del_confirm', 'Klik lagi untuk menghapus'), function () {
    S.srcBusy = true;
    renderSources();
    call('rab_remove_source', JSON.stringify({ state: S.state, id: id }));
  }, renderSources);
}
['srcList', 'prcList'].forEach(function (id) {
  $(id).addEventListener('change', onSrcToggle);
  $(id).addEventListener('click', onSrcDelete);
});
$('srcAdd').addEventListener('click', function () { call('rab_add_source', stateJson(), this); });

// Dari Ruby: sumber berganti -> semua data dikirim ulang
function onSources(data) {
  S.srcBusy = false;
  onSourcesCancel();
  init(data);
  var n = data.note || {}, items = data.sources.items.filter(function (s) { return s.active; });
  var ahsp = 0, base = 0;
  items.forEach(function (s) { ahsp += s.ahsp || 0; base += s.base || 0; });
  if (n.theme_added) return showToast(t('rab_theme_added', 'Tema diimpor dan dipakai: %{f}').replace('%{f}', n.theme_added), 'success');
  if (n.theme_removed) return showToast(t('rab_theme_removed', 'Tema dihapus; kembali ke tema bawaan.'), 'success');
  if (n.price_added) {
    var none = !n.matched;
    return showToast((n.updated ? t('rab_prc_updated', 'Harga diperbarui: %{f}') : t('rab_prc_added', 'Harga diimpor: %{f}')).replace('%{f}', n.price_added) + ' — ' +
      (none ? t('rab_prc_none_matched', 'tidak ada item yang cocok dengan harga dasar saat ini (cek kode / nama / satuan).')
            : t('rab_prc_match_info', '%{m} dari %{n} item cocok.').replace('%{m}', fmt(n.matched)).replace('%{n}', fmt(n.total))), none ? 'error' : 'success');
  }
  var msg = n.added ? (n.updated ? t('rab_src_updated', 'Diperbarui: %{f}') : t('rab_src_added', 'Ditambahkan: %{f}')).replace('%{f}', n.added)
    : n.removed ? t('rab_src_removed', 'File dihapus.') : t('rab_src_switched', 'Sumber data diperbarui.');
  var warn = Array.isArray(n.warn) && n.warn.length ? ' ⚠ ' + n.warn.join(' ') : '';
  showToast(msg + ' ' + t('rab_src_total', '(%{a} analisa, %{b} harga dasar)').replace('%{a}', fmt(ahsp)).replace('%{b}', fmt(base)) + warn, warn ? 'error' : 'success');
}
function onSourcesCancel() { rabProgressEnd(); ['srcAdd', 'srcTpl', 'prcAdd', 'prcTpl', 'prcImport', 'themeMenu'].forEach(function (id) { if ($(id).dataset.html != null) busy(id, false); }); }
// Hasil ekspor harga / analisa (path file, atau null kalau dibatalkan)
function onFileSaved(path) {
  rabProgressEnd();
  ['prcExport', 'cuExport', 'themeMenu', 'srcTpl', 'prcTpl'].forEach(function (id) { if ($(id).dataset.html != null) busy(id, false); });
  resetSrcExport();
  if (path) showToast(t('rab_exported', 'Tersimpan: %{path}').replace('%{path}', path), 'success');
}

// ── Pemilih komponen untuk analisa sendiri ──
var CP_PAGE = 80;
var cp = { limit: CP_PAGE };
function cpHits() {
  var tokens = $('cpQ').value.toLowerCase().trim().split(/\s+/).filter(Boolean), jenis = $('cpJenis').value;
  return S.base.filter(function (b) {
    if (jenis && b.jenis !== jenis) return false;
    for (var i = 0; i < tokens.length; i++) if (b._s.indexOf(tokens[i]) < 0) return false;
    return true;
  });
}
function renderCompPicker() {
  var hits = cpHits(), shown = hits.slice(0, cp.limit);
  var html = shown.map(function (b) {
    var pr = priceOf(b.kode);
    return '<div class="pk-it base" data-kode="' + esc(b.kode) + '"><span class="kd">' + esc(b.kode) + '</span>' +
      '<span class="ur"><span class="chip" title="' + esc(jenisLabel(b.jenis)) + '">' + (JENIS_CHIP[b.jenis] || 'B') + '</span>' + esc(b.nama) + '</span>' +
      '<span class="su">' + esc(b.satuan) + '<em>' + (pr > 0 ? rp(pr) : '—') + '</em></span></div>';
  }).join('');
  if (!shown.length) html = '<div class="empty">' + esc(t('rab_cp_none', 'Tidak ada komponen yang cocok. Buat komponen baru di bawah.')) + '</div>';
  else if (hits.length > shown.length) html += '<div class="more" id="cpMore">' + esc(t('rab_pk_more', 'Tampilkan lebih banyak (%{n} lagi)').replace('%{n}', hits.length - shown.length)) + '</div>';
  $('cpList').innerHTML = html;
  $('cpCount').textContent = hits.length + ' / ' + S.base.length;
}
function openCompPicker() {
  cp.limit = CP_PAGE;
  $('cpQ').value = '';
  $('cpJenis').value = '';
  $('cpNName').value = '';
  $('cpNSat').value = '';
  $('cpNHarga').value = '';
  renderCompPicker();
  $('cp').classList.add('open');
  setTimeout(function () { $('cpQ').focus(); }, 30);
}
function closeCompPicker() { $('cp').classList.remove('open'); }
function addComponent(kode) {
  closeCompPicker();
  if (!S.byKode[S.sel] || !S.baseBy[kode]) return;
  var list = editableComps(S.sel), idx = -1;
  list.forEach(function (c, i) { if (c.kode === kode) idx = i; });
  if (idx < 0) { list.push({ kode: kode, koef: 1 }); idx = list.length - 1; }
  anaChanged(true);
  var inp = document.querySelector('#cuEdit tr[data-i="' + idx + '"] .koef');
  if (inp) { inp.focus(); inp.select(); }
}
var cpTimer = null;
$('cpQ').addEventListener('input', function () { clearTimeout(cpTimer); cpTimer = setTimeout(function () { cp.limit = CP_PAGE; renderCompPicker(); }, 120); });
$('cpJenis').addEventListener('change', function () { cp.limit = CP_PAGE; renderCompPicker(); });
$('cpList').addEventListener('click', function (ev) {
  if (ev.target.closest('#cpMore')) { cp.limit += CP_PAGE * 2; return renderCompPicker(); }
  var it = ev.target.closest('.pk-it');
  if (it) addComponent(it.dataset.kode);
});
$('cpClose').addEventListener('click', closeCompPicker);
$('cpNAdd').addEventListener('click', function () {
  var nama = $('cpNName').value.trim();
  if (!nama) { $('cpNName').focus(); return showToast(t('rab_cp_name_req', 'Isi nama komponen dulu.'), 'error'); }
  var harga = parseFloat($('cpNHarga').value);
  var b = { kode: nextKode('C', customBase()), jenis: $('cpNJenis').value, nama: nama, satuan: $('cpNSat').value.trim() || 'ls', harga: isNaN(harga) || harga < 0 ? 0 : harga };
  customBase().push(b);
  rebuildIndex();
  addComponent(b.kode);
});

// ── Pratinjau & simpan PDF ──
var PV = { layout: null, ppp: 0, fit: true, timer: null };
function pvParts() {
  var parts = [];
  document.querySelectorAll('#pv .pv-tools input[data-part]').forEach(function (c) { if (c.checked) parts.push(c.dataset.part); });
  return parts;
}
function pvPayload() { return JSON.stringify({ state: S.state, parts: pvParts() }); }
function openPreview() {
  if (!S.scanned) return showToast(t('rab_need_scan', 'Klik Scan Model dulu supaya volume terukur.'), 'error');
  if (!S.report || !S.report.rows.length) return showToast(t('rab_export_empty', 'Pilih pekerjaan untuk minimal satu tag dulu.'), 'error');
  $('pv').classList.add('open');
  pvRequest();
}
function closePreview() { $('pv').classList.remove('open'); }
function pvRequest() {
  $('pvBody').innerHTML = '<div class="pv-msg">' + esc(t('rab_pv_loading', 'Menyusun pratinjau…')) + '</div>';
  call('rab_preview', pvPayload());
}
function pvSvg(items) {
  var out = '';
  items.forEach(function (it) {
    if (it.t === 'rect') {
      out += '<rect x="' + it.x + '" y="' + it.y + '" width="' + it.w + '" height="' + it.h + '" fill="' + (it.fill ? '#' + it.fill : 'none') + '"' +
        (it.stroke ? ' stroke="#' + it.stroke + '" stroke-width="' + it.sw + '"' : '') + '/>';
    } else if (it.t === 'line') {
      out += '<line x1="' + it.x1 + '" y1="' + it.y1 + '" x2="' + it.x2 + '" y2="' + it.y2 + '" stroke="#' + it.c + '" stroke-width="' + it.w + '"/>';
    } else if (it.t === 'text') {
      out += '<text x="' + it.x + '" y="' + it.y + '" font-size="' + it.z + '" font-family="Helvetica, Arial, sans-serif"' + (it.f === 'B' ? ' font-weight="700"' : '') +
        ' text-anchor="' + (it.a === 'r' ? 'end' : it.a === 'c' ? 'middle' : 'start') + '" fill="#' + it.c + '">' + esc(it.s) + '</text>';
    }
  });
  return out;
}
function pvFitPpp() {
  var w = $('pvBody').clientWidth - 40;
  return Math.max(0.5, Math.min(2.6, w / PV.layout.w));
}
function pvRender() {
  var L = PV.layout;
  if (!L) return;
  if (PV.fit) PV.ppp = pvFitPpp();
  $('pvBody').innerHTML = L.pages.map(function (p) {
    var pw = p.w || L.w, ph = p.h || L.h;
    return '<div class="pv-page" style="width:' + (pw * PV.ppp).toFixed(1) + 'px;height:' + (ph * PV.ppp).toFixed(1) + 'px"><svg viewBox="0 0 ' + pw + ' ' + ph + '" xmlns="http://www.w3.org/2000/svg">' + pvSvg(p.items) + '</svg></div>';
  }).join('');
  $('pvZ').textContent = Math.round(PV.ppp / (4 / 3) * 100) + '%';
  $('pvPages').textContent = t('rab_pv_pages', '%{n} halaman').replace('%{n}', L.pages.length);
}
function onPreview(layout) {
  PV.layout = layout;
  pvRender();
}
function pvZoom(f) { PV.fit = false; PV.ppp = Math.max(0.4, Math.min(3.5, PV.ppp * f)); pvRender(); }
$('pvZi').addEventListener('click', function () { pvZoom(1.2); });
$('pvZo').addEventListener('click', function () { pvZoom(1 / 1.2); });
$('pvFit').addEventListener('click', function () { PV.fit = true; pvRender(); });
$('pvClose').addEventListener('click', closePreview);
$('pvSave').addEventListener('click', function () { call('rab_save_pdf', pvPayload(), this); });
document.querySelectorAll('#pv .pv-tools input[data-part]').forEach(function (c) {
  c.addEventListener('change', function () {
    if (!pvParts().length) { c.checked = true; return; } // minimal satu bagian
    clearTimeout(PV.timer);
    PV.timer = setTimeout(pvRequest, 120);
  });
});
function onPdfSaved(path) {
  rabProgressEnd();
  busy('pvSave', false);
  if (path) showToast(t('rab_pdf_saved', 'PDF tersimpan: %{path}').replace('%{path}', path), 'success');
}

// ── Aksi ──
function doScan() { call('rab_scan', stateJson(), 'btnScan'); }
function doExport(name, btn) {
  if (!S.report || !S.report.rows.length) return showToast(t('rab_export_empty', 'Pilih pekerjaan untuk minimal satu tag dulu.'), 'error');
  call(name, stateJson(), btn);
}

// ── Dipanggil dari Ruby ──
function onExported(path) {
  rabProgressEnd();
  busy('btnXlsx', false);
  if (path) showToast(t('rab_exported', 'Tersimpan: %{path}').replace('%{path}', path), 'success');
}
function rabError(msg) {
  rabProgressEnd();
  S.srcBusy = false;
  if (S.sources) renderSources();
  ['btnScan', 'btnXlsx', 'pvSave', 'cuExport', 'cuImport', 'srcAdd', 'srcTpl', 'prcAdd', 'prcTpl', 'prcImport', 'prcExport', 'themeMenu'].forEach(function (id) { if ($(id).dataset.html != null) busy(id, false); });
  resetSrcExport();
  showToast(msg, 'error');
}

// Pratinjau yang dipas ke jendela ikut menyesuaikan saat ukuran jendela berubah (mis. animasi lebar/tinggi)
window.addEventListener('resize', function () {
  if ($('pv').classList.contains('open') && PV.fit) pvRender();
});
// Esc menutup lapisan paling atas (menu, progress tak bisa dibatalkan, pemilih komponen, pemilih pekerjaan, pratinjau PDF). Dipasang di fase
// capture dan menghentikan peristiwanya, supaya Esc yang sudah dipakai di sini tidak ikut memicu "kembali ke Hub" milik ui.js.
window.addEventListener('keydown', function (ev) {
  if (ev.key !== 'Escape') return;
  var layer = document.querySelector('.mn.open') ? 'menu' : $('prog').classList.contains('open') ? 'prog' : $('cp').classList.contains('open') ? 'cp'
    : $('pk').classList.contains('open') ? 'pk' : $('pv').classList.contains('open') ? 'pv' : '';
  if (!layer) return;
  ev.preventDefault();
  ev.stopImmediatePropagation();
  if (layer === 'menu') closeMenus();
  else if (layer === 'cp') closeCompPicker();
  else if (layer === 'pk') closePicker();
  else if (layer === 'pv') closePreview();
}, true);

function requestInit() {
  function tryReady() {
    if (window.sketchup && typeof sketchup.ready === 'function') { sketchup.ready(); return true; }
    return false;
  }
  if (!tryReady()) {
    var retries = 0;
    var iv = setInterval(function () {
      retries++;
      if (tryReady() || retries > 30) clearInterval(iv);
    }, 50);
  }
}
requestInit();
