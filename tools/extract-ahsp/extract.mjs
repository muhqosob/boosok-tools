// Ekstrak AHSP dari PDF "Lampiran VI SE DJBK No 47 Tahun 2026 - AHSP Bidang Cipta Karya" jadi JSON
// yang formatnya sama dengan data/ahsp/ahsp_starter.json (meta, harga_dasar, ahsp) supaya bisa dipakai fitur RAB.
//
// Pakai:
//   cd tools/extract-ahsp && npm install
//   node extract.mjs "C:\path\ke\Lampiran-VI-SE-DJBK-No-47-Tahun-2026-AHSP-Bidang-Cipta-Karya.pdf" [output.json]
//
// Cara kerja: PDF-nya teks (bukan scan), jadi tiap item teks dibaca beserta koordinatnya (pdf.js), dikelompokkan
// jadi baris, lalu tiap tabel AHSP (judul berkode "1.3.1.1", header "No Uraian Kode Satuan Koefisien", bagian
// A Tenaga Kerja / B Bahan / C Peralatan) di-parse berdasarkan kolom. Nama komponen yang terbungkus beberapa baris
// dibagi ke barisnya lewat DP terhadap posisi vertikal koefisien. Satuan dicocokkan dengan daftar isi di awal PDF.
// Bahan & alat di PDF tidak punya kode, jadi katalog harga dasar dibuat otomatis (nama + satuan -> M.0001 / E.0001).
// AHSP ini cuma koefisien. Harga dasar awalnya 0; kalau data/ahsp/hsd_kota_serang_ta2024.json ada, harga Kota Serang
// ikut diisi untuk item yang padanannya jelas (lihat harga-serang.mjs). Selebihnya harus diisi user per daerah/proyek.
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import * as pdfjs from 'pdfjs-dist/legacy/build/pdf.mjs';
import { writeDb } from './dbfile.mjs';
import { applyHarga, HSD_FILE } from './harga-serang.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PDF = process.argv[2];
const OUT = process.argv[3] || path.resolve(HERE, '../../src/boosok_tools/data/ahsp_se47_2026.json');
if (!PDF) {
  console.error('Pakai: node extract.mjs <file.pdf> [output.json]');
  process.exit(1);
}

const DIVISI = {
  1: 'Persiapan Lapangan/Site Work', 2: 'Pekerjaan Struktur', 3: 'Pekerjaan Arsitektur', 4: 'Pekerjaan Lansekap',
  5: 'Pekerjaan Mekanikal dan Elektrikal', 6: 'Pekerjaan Plambing', 7: 'Jalan pada Permukiman', 8: 'Drainase Jalan',
  9: 'Jaringan Pipa di Luar Gedung', 10: 'Sistem Struktur RISHA', 11: 'Tipologi RISHA'
};

// Kodefikasi tenaga kerja (Tabel IV.1 di PDF)
const LABOR = {
  'L.01': 'Pekerja', 'L.02': 'Tukang', 'L.03': 'Kepala Tukang', 'L.04': 'Mandor', 'L.05': 'Juru Ukur',
  'L.06': 'Pembantu Juru Ukur', 'L.07': 'Mekanik Alat Berat', 'L.08': 'Operator Alat Berat', 'L.09': 'Pembantu Operator',
  'L.10': 'Supir Truk', 'L.11': 'Kenek Truk', 'L.12a': 'Tenaga Ahli Utama', 'L.12b': 'Tenaga Ahli Madya',
  'L.12c': 'Tenaga Ahli Muda', 'L.12d': 'Tenaga Ahli Pratama', 'L.13a': 'Narasumber Pejabat Eselon II',
  'L.13b': 'Narasumber Pejabat Eselon III', 'L.13c': 'Narasumber Praktisi', 'L.14a': 'Tenaga Terampil Teknisi',
  'L.14b': 'Tenaga Terampil Operator', 'L.14c': 'Tenaga Terampil Analis', 'L.15': 'Tenaga Kerja Lainnya'
};

// ── 1. Baca teks PDF beserta koordinat ────────────────────────────────────────

async function readPages(file) {
  const data = new Uint8Array(fs.readFileSync(file));
  const doc = await pdfjs.getDocument({ data, useSystemFonts: true, verbosity: 0 }).promise;
  const pages = [];
  for (let n = 1; n <= doc.numPages; n++) {
    const page = await doc.getPage(n);
    const tc = await page.getTextContent();
    pages.push(tc.items.filter(i => i.str.trim() !== '').map(i => ({
      s: i.str, x: +i.transform[4].toFixed(1), y: +i.transform[5].toFixed(1), h: +i.height.toFixed(1), w: +i.width.toFixed(1)
    })));
    if (n % 200 === 0) console.log(`  baca halaman ${n}/${doc.numPages}`);
  }
  return pages;
}

// ── 2. Item -> baris ──────────────────────────────────────────────────────────

function buildLines(pages) {
  const out = [];
  pages.forEach((raw, pi) => {
    let items = raw.map(i => ({ ...i }));
    // Pangkat (m2, m3) disimpan PDF sebagai item kecil yang lebih tinggi dari teks dasarnya: tempel ke item dasar
    const dead = new Set();
    for (const a of items) {
      if (a.h > 8.5 || !/^[0-9\-+]{1,2}$/.test(a.s.trim())) continue;
      let best = null, bd = 1e9;
      for (const b of items) {
        if (b === a || dead.has(b) || b.h < a.h * 1.25) continue;
        const dx = a.x - (b.x + b.w), dy = a.y - b.y;
        if (dx > -3 && dx < 9 && dy > 0.5 && dy < 7 && /[A-Za-z’'”"]$/.test(b.s.trim()) && dx < bd) { bd = dx; best = b; }
      }
      if (best) { best.s = best.s.trimEnd() + a.s.trim(); best.w += a.w; dead.add(a); }
    }
    items = items.filter(i => !dead.has(i));
    // Judul kadang satu item "9.3.3.1 Pengelasan ...": pisahkan kodenya
    const extra = [];
    for (const it of items) {
      const m = it.h >= 11.5 && it.x < 80 && it.s.match(/^(\d+(?:[.,]\d+)+(?:\.?[a-z])?)\s+(\S.*)$/);
      if (m) { it.s = m[1]; extra.push({ s: m[2], x: it.x + 60, y: it.y, h: it.h, w: 100 }); }
    }
    items.push(...extra);
    items.sort((a, b) => b.y - a.y || a.x - b.x);
    const lines = [];
    for (const it of items) {
      const l = lines[lines.length - 1];
      if (l && Math.abs(l.y - it.y) <= 2.5) l.it.push(it);
      else lines.push({ y: it.y, page: pi + 1, it: [it] });
    }
    for (const l of lines) { l.it.sort((a, b) => a.x - b.x); l.h = Math.max(...l.it.map(i => i.h)); }
    out.push(...lines);
  });
  return out;
}

// ── 3. Parse tabel AHSP ───────────────────────────────────────────────────────

const CODE_RE = /^\d+([.,]\d+)+(\.?[a-z])?$/;
const norm = s => s.replace(/\s+/g, ' ').trim();
const isNum = s => /^[0-9]+([.,][0-9]+)?$/.test(s);

function parseTables(L, problems) {
  const isCodeStr = s => CODE_RE.test(s) && !/^\d+[.,]\d{3}$/.test(s) && parseInt(s, 10) <= 12;
  const isCodeLine = l => l.it[0].x < 80 && isCodeStr(l.it[0].s.trim());
  const txt = l => norm(l.it.map(i => i.s.trim()).join(' '));
  const isHeaderLine = l => l.it.some(t => t.s.replace(/ /g, '') === 'Uraian') && l.it.some(t => t.s.trim() === 'Koefisien');
  const tables = [];
  let cur = null;

  function startTable(idx) {
    const tl = [];
    let j = idx;
    while (j < L.length && L[j].h >= 11.5) { tl.push(L[j]); j++; }
    let m = 0;
    tl.forEach((l, n) => { if (isCodeLine(l)) m = n; });
    let hdr = null;
    for (let k = j; k < Math.min(j + 8, L.length); k++) {
      if (isHeaderLine(L[k])) { hdr = k; break; }
      if (L[k].h > 10.5 && L[k].h < 11.5) break; // paragraf/caption di antara judul dan header: bukan awal tabel
      if (/^-\d+-$/.test(L[k].it[0].s.trim()) || isCodeLine(L[k])) break; // pindah halaman / judul lain
      if (/^[A-F]$/.test(L[k].it[0].s.trim()) && L[k].it.length > 1) break;
    }
    if (hdr === null) return null;
    const hl = L[hdr];
    const find = re => hl.it.find(t => re.test(t.s.trim().replace(/ /g, '')));
    let no = find(/^No$/);
    if (!no) for (const k of [hdr - 1, hdr + 1]) { const f = L[k] && L[k].it.find(t => t.s.trim() === 'No' && t.x < 100); if (f) no = f; }
    const ur = find(/^Uraian$/), kd = find(/^Kode$/), kf = find(/^Koefisien$/);
    const sat = hl.it.find(t => t.s.trim() === 'Satuan' && t.x < (kf ? kf.x : 1e9));
    if (!ur || !kf) return null;
    const titleLines = L.slice(idx + m, hdr).filter(l => l.h >= 11.5);
    const title = norm(titleLines.map((l, n) => (n === 0 ? l.it.slice(1) : l.it).map(t => t.s.trim()).join(' ')).join(' '));
    const t = {
      code: L[idx + m].it[0].s.trim(), title, page: L[idx + m].page,
      no: no ? no.x : null, ur: ur.x, kd: kd ? kd.x : null, sat: sat ? sat.x : null, kf: kf.x,
      rows: [], sect: null, pending: [], done: false, notes: [], noteY: null, prefix: ''
    };
    return { t, next: hdr + 1 };
  }

  function colOf(t, x) {
    if (x < (t.no !== null ? t.no + 17 : t.ur - 50)) return 'letter';
    if (t.kd !== null && x < t.kd - 4) return 'name';
    if (t.kd === null) return x < t.kf - 4 ? 'name' : (x < t.kf + 60 ? 'koef' : 'x');
    if (t.sat !== null && t.sat < t.kf && x < t.sat - 4) return 'kode';
    if (x < t.kf - 4) return 'unit';
    if (x < t.kf + 60) return 'koef';
    return 'x';
  }

  // Bagi baris-baris satu bagian (A/B/C) jadi baris komponen. Koefisien (anchor) jumlahnya = jumlah komponen;
  // nama bisa terbungkus 1-3 baris dengan perataan vertikal atas/tengah/bawah, jadi cari pemotongan terbaik (DP).
  function flush(t) {
    let lines = t.pending; t.pending = [];
    if (!lines.length) return;
    // Sub-judul bernomor ("3 Steger" lalu "a bambu", "b tali") jadi awalan nama anak-anaknya
    let prefix = '';
    const kept = [];
    for (let n = 0; n < lines.length; n++) {
      const l = lines[n], next = lines[n + 1];
      if (/^\d+$/.test(l.lab) && !l.koef && !l.unit && next && /^[a-z]$/.test(next.lab)) { prefix = l.name; continue; }
      if (/^\d+$/.test(l.lab)) prefix = '';
      kept.push({ ...l, prefix });
    }
    lines = kept;
    const anchors = lines.filter(l => l.koef).sort((a, b) => b.y - a.y);
    const names = lines.filter(l => l.name).sort((a, b) => b.y - a.y);
    if (!anchors.length) { if (names.length) problems.push({ code: t.code, page: t.page, msg: 'no anchors' }); return; }
    if (!names.length) { problems.push({ code: t.code, page: t.page, msg: 'no names' }); return; }
    const nr = anchors.length, N = names.length;
    if (nr > N) { problems.push({ code: t.code, page: t.page, msg: 'fewer name lines than rows' }); return; }
    const gapAt = k => names[k - 1].y - names[k].y;
    const maxGap = Math.max(...names.slice(1).map((_, k) => gapAt(k + 1)), 0);
    const target = (m, ymax, ymin) => (m === 0 ? ymax : m === 1 ? (ymax + ymin) / 2 : ymin);
    let best = null;
    for (let mode = 0; mode < 3; mode++) {
      const INF = 1e9;
      const dp = Array.from({ length: nr + 1 }, () => Array(N + 1).fill(INF));
      const bk = Array.from({ length: nr + 1 }, () => Array(N + 1).fill(-1));
      dp[0][0] = 0;
      for (let r = 1; r <= nr; r++) for (let j = r; j <= N; j++) for (let i = r - 1; i < j; i++) {
        if (dp[r - 1][i] >= INF) continue;
        const ymax = names[i].y, ymin = names[j - 1].y, cy = anchors[r - 1].y;
        let c = 1e9;
        for (let m = 0; m < 3; m++) c = Math.min(c, Math.abs(cy - target(m, ymax, ymin)) + (m === mode ? 0 : 1.5));
        const v = dp[r - 1][i] + c + (i > 0 ? 0.15 * (maxGap - gapAt(i)) : 0);
        if (v < dp[r][j]) { dp[r][j] = v; bk[r][j] = i; }
      }
      const tot = dp[nr][N] + (mode === 1 ? 0 : 0.6); // perataan tengah paling umum: menang kalau seri
      if (dp[nr][N] < INF && (!best || tot < best.cost)) best = { cost: tot, bk };
    }
    if (!best) return;
    const cuts = []; let j = N;
    for (let r = nr; r >= 1; r--) { const i = best.bk[r][j]; cuts.push([i, j]); j = i; }
    cuts.reverse();
    const clusters = cuts.map(([i, jj]) => names.slice(i, jj));
    if (best.cost / nr > 1.2 && !/^4\.1\./.test(t.code)) problems.push({ code: t.code, page: t.page, msg: 'wrap cost tinggi', cost: +best.cost.toFixed(1) });
    const rows = clusters.map((c, n) => ({
      names: c.map(l => l.name), prefix: c[0].prefix || '', kode: [], unit: [], koef: anchors[n].koef,
      anchorY: anchors[n].y, y: (c[0].y + c.at(-1).y) / 2
    }));
    const near = y => {
      let b = 0, bd = 1e9;
      rows.forEach((r, n) => { const d = Math.min(Math.abs(y - r.anchorY), Math.abs(y - r.y)); if (d < bd) { bd = d; b = n; } });
      return rows[b];
    };
    for (const l of lines) {
      if (l.unit) near(l.y).unit.push(l.unit);
      if (l.kode) near(l.y).kode.push(l.kode);
    }
    for (const r of rows) {
      t.rows.push({
        sect: t.sect,
        name: norm((r.prefix ? r.prefix + ' ' : '') + r.names.join(' ')).replace(/\s*:\s*\d+\s*%/, ''),
        kode: norm(r.kode.join(' ')), unit: norm(r.unit.join(' ')), koef: r.koef
      });
    }
  }

  let i = 0;
  while (i < L.length) {
    const l = L[i];
    const first = l.it[0].s.trim();
    if (/^-\d+-$/.test(first) && l.it.length === 1) { i++; continue; }
    if (l.h >= 11.5 && isCodeLine(l)) {
      const r = startTable(i);
      if (r) { if (cur) flush(cur); cur = r.t; tables.push(cur); i = r.next; continue; }
    }
    if (!cur) { i++; continue; }
    const t = cur;
    if (t.done) {
      // Catatan tepat di bawah tabel: "Catatan:", "*) ...", butir "●". Berhenti kalau ada jeda vertikal / judul baru.
      if (t.done === true && l.h < 11.5 && !isCodeLine(l)) {
        const s = txt(l);
        const gap = t.noteY === null ? 0 : t.noteY - l.y;
        if (gap > 18 || t.notes.length >= 8) t.done = 'closed';
        else if (t.notes.length === 0 ? /^(catatan|keterangan|\*\)|\*|●)/i.test(s) : true) { t.notes.push(s); t.noteY = l.y; }
        else t.done = 'closed';
      } else t.done = 'closed';
      i++; continue;
    }
    if (isHeaderLine(l)) { i++; continue; }
    const cells = {};
    for (const it of l.it) (cells[colOf(t, it.x)] ??= []).push(it.s.trim());
    const letter = cells.letter ? cells.letter.join(' ') : '';
    const nameTxt = cells.name ? norm(cells.name.join(' ')) : '';
    const hasData = !!(cells.unit || cells.koef || cells.kode);
    if (/^[A-F]$/.test(letter) && (nameTxt || !hasData)) {
      flush(t);
      if (letter === 'D' || letter === 'E' || letter === 'F') t.sect = null;
      else if (/tenaga/i.test(nameTxt)) t.sect = 'TK';
      else if (/bahan/i.test(nameTxt)) t.sect = 'BH';
      else if (/peralatan|alat/i.test(nameTxt)) t.sect = 'AL';
      else { t.sect = 'XX'; t.subPekerjaan = true; }
      if (letter === 'F') { t.done = true; i++; continue; }
      // header bagian kadang sudah memuat satuan/koefisien ("C PERALATAN | Hari | 0,2275")
      if (t.sect && hasData && cells.koef) {
        const k = cells.koef.join('').replace(/\s+/g, '');
        if (isNum(k)) t.pending.push({ y: l.y, name: '', lab: '', kode: cells.kode ? cells.kode.join(' ') : '', unit: cells.unit ? cells.unit.join(' ') : '', koef: k });
      }
      i++; continue;
    }
    if (/^jumlah harga/i.test(txt(l)) || (cells.x && !cells.name && !cells.koef && !cells.unit)) { i++; continue; }
    if (t.sect) {
      const line = { y: l.y, name: nameTxt, lab: letter, kode: cells.kode ? cells.kode.join(' ') : '', unit: cells.unit ? cells.unit.join(' ') : '', koef: null };
      if (cells.koef) { const k = cells.koef.join('').replace(/\s+/g, ''); if (isNum(k)) line.koef = k; }
      t.pending.push(line);
    }
    i++;
  }
  if (cur) flush(cur);
  return tables;
}

// ── 4. Daftar isi (satuan + status) dan nama kategori ─────────────────────────

function parseIndex(L) {
  const idx = {}, cats = {};
  for (const l of L) {
    if (l.page > 200) break;
    const s = l.it.map(i => i.s.trim());
    const ti = s.findIndex(x => /^(Normatif|Informatif)/i.test(x));
    if (ti > 0 && CODE_RE.test(s[0])) {
      idx[fixCode(s[0])] = { unit: s[ti - 1], tipe: s[ti], baru: s.slice(ti).some(x => /^Baru$/i.test(x)) };
    } else if (l.page >= 8 && l.it[0].x < 80 && /^\d+([.,]\d+)+$/.test(s[0]) && s.length >= 2 && s[0].split(/[.,]/).length <= 3) {
      cats[fixCode(s[0])] = norm(s.slice(1).join(' '));
    }
  }
  return { idx, cats };
}

// ── 5. Normalisasi & susun katalog ────────────────────────────────────────────

function fixCode(c) {
  return c.replace(',', '.').replace(/\.([a-z])$/, '$1');
}

function tidy(s) {
  return norm(s
    .replace(/[‘’]/g, "'").replace(/[“”]/g, '"')
    .replace(/\(\s+/g, '(').replace(/\s+\)/g, ')').replace(/\s+,/g, ',')
    .replace(/(\w)-\s+(\w)/g, '$1-$2')
    .replace(/\s*\*\)\s*$/, '').replace(/\s*\*$/, ''));
}

function normUnit(u) {
  let x = tidy(u).toLowerCase().replace(/\s+/g, ' ');
  x = x.replace(/ ?\/ ?/g, '/');
  const flat = x.replace(/ /g, '');
  const map = { "m'": 'm', m: 'm', 'm²': 'm2', 'm³': 'm3', m2: 'm2', m3: 'm3', bh: 'buah', buah: 'buah', unit: 'unit', kg: 'kg', set: 'set', ha: 'ha' };
  if (map[flat]) return map[flat];
  if (/^(unit|buah)[ \/]hari$/.test(x)) return x.replace(' ', '/');
  return x;
}

function laborKode(row) {
  const name = row.name.toLowerCase();
  const byName = /^kepala ?tukang/.test(name) ? 'L.03' : /^tukang/.test(name) ? 'L.02' : /^pekerja/.test(name) ? 'L.01' : /^mandor/.test(name) ? 'L.04' : null;
  let k = row.kode.replace(/\s+/g, '').replace(/^(L\.\d+)\.([a-d])$/i, (_, a, b) => a + b.toLowerCase());
  if (!/^L\.\d+[a-d]?$/.test(k)) k = '';
  if (k && byName && /^L\.0[1-4]$/.test(k) && k !== byName) k = byName; // salah ketik di PDF (mis. "Tukang Ereksi | L.01")
  return k || byName;
}

// Nama kategori di daftar isi kadang HURUF BESAR semua: jadikan "Dinding Bata Merah" (singkatan 2-3 huruf seperti PC, AC, BAS tetap besar)
function titleCase(s) {
  if (s !== s.toUpperCase()) return s;
  return s.toLowerCase().replace(/[a-z][a-z']*/g, w => (w.length <= 2 && !/^(di|ke|dan|atau|pada|dengan|untuk)$/.test(w) ? w.toUpperCase() : w[0].toUpperCase() + w.slice(1)))
    .replace(/\b(Dan|Atau|Pada|Dengan|Untuk|Di|Ke)\b/g, m => m.toLowerCase()).replace(/^./, c => c.toUpperCase());
}

const UNIT_FROM_TITLE = /\b1\s*(m3|m2|m'|m’|m1|kg|buah|unit|titik|set|bh|lembar|batang|paket|ha|tunggul|liter)(?![a-z0-9])/i;

function cleanNotes(notes) {
  const out = [];
  for (const n of notes) {
    const s = tidy(n.replace(/^●\s*/, ''));
    if (!s || /^catatan:?$/i.test(s)) continue;
    if (/^(●|\*\)|\*)/.test(n) || /^catatan/i.test(s) || !out.length) out.push(s.replace(/^catatan:?\s*/i, ''));
    else out[out.length - 1] += ' ' + s;
  }
  return out.join(' • ').replace(/\s+/g, ' ').trim();
}

function build(tables, { idx, cats }, problems) {
  const used = tables.filter(t => t.rows.length);
  const mostCommon = counts => [...counts.entries()].sort((a, b) => b[1] - a[1])[0][0];

  // Perbaikan tetap: "Tukang Pemelihara | Taman | Mandor" salah bungkus di beberapa tabel lansekap
  for (const t of used) t.rows.forEach((r, n) => {
    if (r.sect === 'TK' && /^Taman Mandor$/i.test(r.name) && n > 0) { t.rows[n - 1].name += ' Taman'; r.name = 'Mandor'; }
  });

  // Katalog bahan & alat: kunci = nama (dirapikan, huruf kecil) + satuan
  // Spasi dibuang dari kunci: "Phenol film 12 mm" = "Phenol film 12mm", "Vibrato r" = "Vibrator"; tanda lain (< ≤ x ,) tetap membedakan
  const keyOf = (name, unit) => tidy(name).toLowerCase().replace(/[–—]/g, '-').replace(/\s+/g, '') + '|' + unit;
  const mat = new Map(), alat = new Map();
  const reg = (map, row, unit) => {
    const key = row.kode && map === alat ? 'kode:' + row.kode : keyOf(row.name, unit);
    let e = map.get(key);
    if (!e) { e = { names: new Map(), unit, kode: map === alat ? row.kode : '' }; map.set(key, e); }
    const nm = tidy(row.name);
    e.names.set(nm, (e.names.get(nm) || 0) + 1);
    return key;
  };
  const prepared = used.map(t => {
    const comps = [];
    let tkProblem = false;
    for (const r of t.rows) {
      let unit = r.unit, kode = r.kode;
      if (!unit && kode && !/^[LE]\.\d/.test(kode)) { unit = kode; kode = ''; } // satuan nyasar ke kolom kode
      const row = { ...r, unit, kode };
      let koef = parseFloat(r.koef.replace(',', '.'));
      if (/^\d\.\d{3}$/.test(r.koef) && /kg/i.test(unit)) koef = parseFloat(r.koef.replace('.', '')); // 1.009 kg = seribu sembilan kg
      if (!(koef > 0)) { problems.push({ code: t.code, page: t.page, msg: 'koefisien tidak valid: ' + r.koef }); continue; }
      if (r.sect === 'TK') {
        const lk = laborKode(row);
        if (!lk) { problems.push({ code: t.code, page: t.page, msg: 'kode tenaga kerja tak dikenal: ' + r.name }); tkProblem = true; continue; }
        const oj = /^oj$/i.test(unit);
        const c = { kind: 'upah', kode: oj ? lk + '-OJ' : lk, lk, oj, koef, nama: tidy(r.name) };
        comps.push(c);
      } else if (r.sect === 'AL') {
        const nu = normUnit(unit);
        comps.push({ kind: 'alat', key: reg(alat, row, nu), koef, nama: tidy(r.name), alatKode: kode });
      } else {
        const nu = normUnit(unit);
        comps.push({ kind: 'bahan', key: reg(mat, row, nu), koef, nama: tidy(r.name), sub: r.sect === 'XX' });
      }
    }
    return { t, comps, tkProblem };
  });

  // Kode katalog: bahan M.0001.., alat E.0001.. (alat yang di PDF sudah berkode E.xx dipakai apa adanya)
  const baseList = [];
  const matKode = new Map(), alatKode = new Map();
  const nameOf = e => mostCommon(e.names);
  [...mat.entries()].sort((a, b) => nameOf(a[1]).toLowerCase().localeCompare(nameOf(b[1]).toLowerCase()) || a[1].unit.localeCompare(b[1].unit))
    .forEach(([key, e], n) => {
      const kode = 'M.' + String(n + 1).padStart(4, '0');
      matKode.set(key, kode);
      baseList.push({ kode, jenis: 'bahan', nama: nameOf(e), satuan: e.unit, harga: 0 });
    });
  let ga = 0;
  [...alat.entries()].sort((a, b) => nameOf(a[1]).toLowerCase().localeCompare(nameOf(b[1]).toLowerCase()) || a[1].unit.localeCompare(b[1].unit))
    .forEach(([key, e]) => {
      const kode = e.kode || 'E.' + String(++ga).padStart(4, '0');
      alatKode.set(key, kode);
      baseList.push({ kode, jenis: 'alat', nama: nameOf(e), satuan: e.unit, harga: 0 });
    });
  const laborUsed = new Map(); // kode dasar -> {lk, oj}
  for (const p of prepared) for (const c of p.comps) if (c.kind === 'upah') laborUsed.set(c.kode, c);
  const laborList = [...laborUsed.values()].sort((a, b) => a.kode.localeCompare(b.kode, 'en', { numeric: true })).map(c => ({
    kode: c.kode, jenis: 'upah', nama: LABOR[c.lk] + (c.oj ? ' (per jam)' : ''), satuan: c.oj ? 'OJ' : 'OH', harga: 0
  }));
  const harga_dasar = [...laborList, ...baseList.filter(b => b.jenis === 'bahan'), ...baseList.filter(b => b.jenis === 'alat')];
  const baseCodes = new Set(harga_dasar.map(h => h.kode));
  if (baseCodes.size !== harga_dasar.length) throw new Error('kode harga dasar dobel');

  // AHSP
  const seen = new Set();
  const stats = { noUnit: [], fallbackUnit: 0, periksa: 0 };
  const probByCode = new Set(problems.filter(p => /wrap cost|no anchors|no names|fewer|tidak valid|tak dikenal/.test(p.msg)).map(p => p.code));
  const ahsp = [];
  for (const { t, comps, tkProblem } of prepared) {
    const kode = fixCode(t.code);
    if (seen.has(kode)) { problems.push({ code: kode, page: t.page, msg: 'kode AHSP dobel, dilewati' }); continue; }
    seen.add(kode);
    let uraian = tidy(t.title), acuan = '';
    const ref = uraian.match(/\(\s*Lihat\s+Permen\s+PUPR\s+Nomor\s+8\s+Tahun\s+2023\s+Lampiran\s+(.*)\)\s*$/i);
    if (ref) { acuan = 'Permen PUPR 8/2023 Lampiran ' + tidy(ref[1]); uraian = tidy(uraian.slice(0, ref.index)); }
    const ix = idx[kode];
    let satuan = ix && /^[A-Za-z0-9'’²³\/ ]{1,12}$/.test(ix.unit) && !CODE_RE.test(ix.unit) ? normUnit(ix.unit) : '';
    if (!satuan) {
      const m = t.title.match(UNIT_FROM_TITLE) || t.title.match(/\bPer-(m)'/i);
      if (m) { satuan = normUnit(m[1] === 'm1' ? 'm' : m[1]); stats.fallbackUnit++; }
    }
    if (!satuan) { satuan = 'ls'; stats.noUnit.push(kode); }
    const top = parseInt(kode, 10);
    let kategori = '';
    const parts = kode.replace(/[a-z]$/, '').split('.');
    for (let n = parts.length - 1; n >= 2 && !kategori; n--) kategori = cats[parts.slice(0, n).join('.')] || '';
    const komponen = comps.map(c => {
      const kodeC = c.kind === 'upah' ? c.kode : c.kind === 'alat' ? alatKode.get(c.key) : matKode.get(c.key);
      const k = { kode: kodeC, koef: c.koef };
      if (c.kind === 'upah' && c.nama.toLowerCase().replace(/\s/g, '') !== LABOR[c.lk].toLowerCase().replace(/\s/g, '')) k.ket = c.nama;
      return k;
    });
    const periksa = tkProblem || probByCode.has(t.code) || t.subPekerjaan;
    if (periksa) stats.periksa++;
    const notes = cleanNotes(t.notes);
    const item = {
      kode, divisi: String(top).padStart(2, '0') + '. ' + (DIVISI[top] || 'Lainnya'), kategori: kategori ? titleCase(tidy(kategori)) : undefined,
      uraian, satuan, keyakinan: periksa ? 'periksa' : 'resmi', acuan: acuan || undefined,
      baru: ix && ix.baru ? true : undefined, komponen, catatan: notes ? notes.slice(0, 600) : undefined
    };
    if (t.subPekerjaan) item.catatan = ((item.catatan || '') + ' Sebagian komponen berupa sub-pekerjaan (harga satuan pekerjaan lain), isi harganya manual.').trim();
    ahsp.push(item);
  }
  ahsp.sort((a, b) => a.kode.localeCompare(b.kode, 'en', { numeric: true }));
  return { harga_dasar, ahsp, stats };
}

// ── Main ──────────────────────────────────────────────────────────────────────

console.log('Membaca PDF...');
const pages = await readPages(PDF);
console.log(`  ${pages.length} halaman`);
const L = buildLines(pages);
const problems = [];
const tables = parseTables(L, problems);
const index = parseIndex(L);
console.log(`Tabel AHSP ditemukan: ${tables.filter(t => t.rows.length).length}; daftar isi: ${Object.keys(index.idx).length} kode`);
const { harga_dasar, ahsp, stats } = build(tables, index, problems);

const meta = {
  nama: 'AHSP Bidang Cipta Karya - SE DJBK No 47/SE/Dk/2026 (Lampiran VI)',
  versi: '1.0.0',
  sumber: 'Surat Edaran Direktur Jenderal Bina Konstruksi Nomor 47/SE/Dk/2026, Lampiran VI: AHSP Bidang Cipta Karya',
  catatan_koefisien: 'Koefisien diekstrak otomatis dari PDF resmi (tabel per AHSP), lalu dicek silang dengan daftar isi. Item dengan keyakinan "periksa" sebaiknya dicocokkan manual ke PDF.',
  catatan_harga: 'Semua harga dasar = 0. AHSP hanya memuat koefisien; isi harga upah/bahan/alat sesuai daerah dan proyek.',
  catatan_kode: 'Upah memakai kode resmi L.xx (Tabel IV.1; "-OJ" = satuan orang-jam). Bahan (M.xxxx) dan alat (E.xxxx) tidak berkode di PDF, kodenya dibuat otomatis dari nama + satuan.',
  mata_uang: 'IDR',
  overhead_profit_persen: 10,
  ppn_persen: 11,
  jumlah_ahsp: ahsp.length
};

const db = { meta, harga_dasar, ahsp };
// Harga Kota Serang (HSD BPJN Banten) ikut diterapkan kalau datanya sudah diunduh (lihat harga-serang.mjs)
if (fs.existsSync(HSD_FILE)) {
  const { filled } = applyHarga(db, JSON.parse(fs.readFileSync(HSD_FILE, 'utf8')));
  console.log(`  Harga ${db.meta.harga.wilayah} TA${db.meta.harga.tahun_data}: ${filled.length} dari ${harga_dasar.length} harga dasar terisi`);
}
fs.mkdirSync(path.dirname(OUT), { recursive: true });
writeDb(OUT, db);

const byJenis = harga_dasar.reduce((m, h) => (m[h.jenis] = (m[h.jenis] || 0) + 1, m), {});
console.log(`\nSelesai -> ${OUT} (${(fs.statSync(OUT).size / 1048576).toFixed(2)} MB)`);
console.log(`  AHSP: ${ahsp.length}, komponen: ${ahsp.reduce((a, x) => a + x.komponen.length, 0)}`);
console.log(`  Harga dasar: ${harga_dasar.length}`, byJenis);
console.log(`  Satuan dari judul (tidak ada di daftar isi): ${stats.fallbackUnit}; tanpa satuan (diisi "ls"): ${stats.noUnit.length} ${stats.noUnit.slice(0, 10).join(' ')}`);
console.log(`  Ditandai "periksa": ${stats.periksa}`);
if (problems.length) {
  console.log(`\nCatatan parser (${problems.length}):`);
  for (const p of problems.slice(0, 40)) console.log(`  ${p.code} (hal ${p.page}): ${p.msg}${p.cost ? ' ' + p.cost : ''}`);
}
