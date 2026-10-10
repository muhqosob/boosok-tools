// Isi harga dasar database AHSP SE 47/2026 dengan harga Kota Serang.
//
// Sumber: Harga Satuan Dasar (HSD) BPJN Banten, Ditjen Bina Marga - https://binamarga.pu.go.id/balai-banten/hsd
// (tabel Tenaga / Material / Alat, filter "Kota Serang"). Data terbaru yang terisi di situs itu TA 2024; TA 2025 dan 2026 kosong
// (dicek 10 Okt 2026). HSD disusun untuk pekerjaan jalan/jembatan, jadi hanya sebagian kecil bahan gedung yang ada padanannya.
// Peraturan Wali Kota Serang No 1/2026 (SSH 2026) tidak memuat harga bahan bangunan, jadi bukan sumber.
//
// Prinsip: HANYA item yang padanannya jelas (nama dan satuan sama) yang diisi. Sisanya tetap 0, tidak ditebak.
//
// Pakai:
//   node harga-serang.mjs             # pakai data/ahsp/hsd_kota_serang_ta2024.json (diunduh dulu kalau belum ada)
//   node harga-serang.mjs --refresh   # unduh ulang dari situs BPJN Banten
// extract.mjs memanggil applyHarga() otomatis kalau file HSD-nya ada, jadi harga tidak hilang saat database dibuat ulang.
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { readDb, writeDb } from './dbfile.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const HSD_FILE = path.resolve(HERE, '../../data/ahsp/hsd_kota_serang_ta2024.json');
const DB_FILE = path.resolve(HERE, '../../src/boosok_tools/data/ahsp_se47_2026.json');
const BASE_URL = 'https://binamarga.pu.go.id/balai-banten/hsd/show_table/';
const YEAR = 2024;
const JAM_PER_HARI = 7; // jam kerja efektif per hari (Permen PUPR 8/2023): OH -> OJ dan alat per jam -> per hari

// ── Unduh & parse HSD ─────────────────────────────────────────────────────────

const text = s => s.replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim();

function parseTable(html, jenis) {
  const items = [];
  for (const tr of html.split('<tr').slice(1)) {
    const tds = [...tr.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map(m => text(m[1]));
    if (tds.length < 5 || !/Rp\./.test(tds[3])) continue;
    const harga = parseInt(tds[3].replace(/Rp\./, '').replace(/\./g, '').trim(), 10);
    if (!Number.isFinite(harga)) continue;
    items.push({ jenis, kode: tds[1].replace(/[()]/g, ''), nama: tds[0], satuan: tds[2], harga, wilayah: tds[4] });
  }
  return items;
}

export async function fetchHsd() {
  const items = [];
  for (const [type, jenis] of [['Tenaga', 'upah'], ['Material', 'bahan'], ['Alat', 'alat']]) {
    const url = `${BASE_URL}?year=${YEAR}&type=${type}&kab=${encodeURIComponent('Kota Serang')}`;
    const res = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0', 'X-Requested-With': 'XMLHttpRequest' } });
    if (!res.ok) throw new Error(`${url} -> HTTP ${res.status}`);
    const json = JSON.parse(await res.text());
    const rows = parseTable(json.shtml, jenis).filter(r => r.wilayah === 'Kota Serang');
    if (!rows.length) throw new Error(`HSD ${type} Kota Serang kosong (${url})`);
    items.push(...rows);
  }
  const hsd = {
    sumber: 'Harga Satuan Dasar BPJN Banten, Ditjen Bina Marga, Kementerian PU',
    url: 'https://binamarga.pu.go.id/balai-banten/hsd', wilayah: 'Kota Serang', tahun: YEAR,
    diambil: new Date().toISOString().slice(0, 10), items
  };
  fs.mkdirSync(path.dirname(HSD_FILE), { recursive: true });
  fs.writeFileSync(HSD_FILE, JSON.stringify(hsd, null, 1) + '\n');
  return hsd;
}

// ── Aturan padanan: item database -> kode HSD ─────────────────────────────────
// Tiap aturan: nama (regex, tanpa membedakan huruf besar), satuan item database, kode HSD, faktor pengali harga HSD.
// `factor` dipakai untuk konversi satuan yang pasti (liter -> m3 = 1000; hari = 7 jam).

const RULES = [
  // Upah (kode resmi L.xx database -> kode HSD). OJ = OH / 7
  { jenis: 'upah', kode: 'L.01', hsd: 'L01' }, { jenis: 'upah', kode: 'L.02', hsd: 'L02' },
  { jenis: 'upah', kode: 'L.03', hsd: 'L10' }, { jenis: 'upah', kode: 'L.04', hsd: 'L03' },
  { jenis: 'upah', kode: 'L.01-OJ', hsd: 'L01', factor: 1 / JAM_PER_HARI }, { jenis: 'upah', kode: 'L.02-OJ', hsd: 'L02', factor: 1 / JAM_PER_HARI },
  { jenis: 'upah', kode: 'L.04-OJ', hsd: 'L03', factor: 1 / JAM_PER_HARI },
  // Bahan: hanya yang namanya dan satuannya sama dengan HSD
  { re: /^semen portland( \(pc\))?$/i, unit: 'kg', hsd: 'M12' },
  { re: /^pasir pasang$/i, unit: 'm3', hsd: 'M01b' },
  { re: /^pasir beton$/i, unit: 'm3', hsd: 'M01a' },
  { re: /^pasir uruk?$/i, unit: 'm3', hsd: 'M01d' },
  { re: /^batu belah$/i, unit: 'm3', hsd: 'M06' },
  { re: /^(kerikil|koral beton)$/i, unit: 'm3', hsd: 'M07' },
  { re: /^batu pecah \/ kerikil$/i, unit: 'm3', hsd: 'M03' },
  { re: /^sirtu$/i, unit: 'm3', hsd: 'M16a' },
  { re: /^tanah biasa\/ liat berpasir$/i, unit: 'm3', hsd: 'M08' },
  { re: /^air( bersih)?$/i, unit: 'liter', hsd: 'M170' },
  { re: /^air$/i, unit: 'm3', hsd: 'M170', factor: 1000 },
  { re: /^kawat (beton|tali beton|bendrat)$/i, unit: 'kg', hsd: 'M14' },
  { re: /^paku\b/i, not: /beton|asbes|payung|sekrup|skrup|usuk|seng|tembak|pancing|tripleks/i, unit: 'kg', hsd: 'M18' },
  { re: /^(baja tulangan|besi beton polos)$/i, unit: 'kg', hsd: 'M39a' },
  { re: /^baja tulangan polos \(bjtp\)/i, unit: 'kg', hsd: 'M39a' },
  { re: /^baja tulangan sirip \(bjts\)/i, unit: 'kg', hsd: 'M39b' },
  { re: /^baja profil$/i, unit: 'kg', hsd: 'M122' },
  { re: /^(baja|besi) siku/i, unit: 'kg', hsd: 'M16' },
  { re: /^multiplek 12 mm$/i, unit: 'lembar', hsd: 'M73' },
  { re: /^aspal$/i, unit: 'kg', hsd: 'M10' },
  { re: /^(solar)$/i, unit: 'liter', hsd: 'M21' }, { re: /^bensin$/i, unit: 'liter', hsd: 'M20' },
  { re: /^minyak tanah$/i, unit: 'liter', hsd: 'M11' },
  { re: /^beton( ready mixed)? f'?c'? ?10 mpa$/i, unit: 'm3', hsd: 'M47' },
  { re: /^beton( ready mixed)? f'?c'? ?15 mpa$/i, unit: 'm3', hsd: 'M60' },
  { re: /^beton( ready mixed)? f'?c'? ?20 mpa$/i, unit: 'm3', hsd: 'M186' },
  { re: /^beton( ready mixed)? f'?c'? ?25 mpa$/i, unit: 'm3', hsd: 'M37' },
  { re: /^beton( ready mixed)? f'?c'? ?30 mpa$/i, unit: 'm3', hsd: 'M59' },
  // Alat: HSD dalam Rp/jam. Alat berstatuan jam langsung, alat berstatuan hari dikali 7 jam
  { re: /^(sewa )?alat las listrik$/i, unit: 'jam', hsd: 'E32' }, { re: /^(sewa )?alat las listrik$/i, unit: 'hari', hsd: 'E32', factor: JAM_PER_HARI },
  { re: /^excavator \(std\.\)/i, unit: 'jam', hsd: 'E10' },
  { re: /^sewa excavator type 225/i, unit: 'hari', hsd: 'E10', factor: JAM_PER_HARI },
  { re: /^concrete vibrator$/i, unit: 'hari', hsd: 'E20', factor: JAM_PER_HARI },
  { re: /^molen.*0,35 m3|^molen\/beton mixer 0,35 m3/i, unit: 'hari', hsd: 'E06', factor: JAM_PER_HARI },
  { re: /^stamper kodok/i, unit: 'hari', hsd: 'E25', factor: JAM_PER_HARI },
  { re: /^sewa water truck$/i, unit: 'hari', hsd: 'E23', factor: JAM_PER_HARI }
];

export function applyHarga(db, hsd) {
  const byKode = new Map(hsd.items.map(i => [i.kode, i]));
  const label = `HSD ${hsd.wilayah} TA${hsd.tahun}`;
  const filled = [], missing = [];
  for (const h of db.harga_dasar) {
    h.harga = 0;
    delete h.sumber_harga;
  }
  for (const h of db.harga_dasar) {
    const rule = RULES.find(r => (r.kode ? r.kode === h.kode : r.re.test(h.nama) && !(r.not && r.not.test(h.nama)) && r.unit === h.satuan));
    if (!rule) continue;
    const src = byKode.get(rule.hsd);
    if (!src) { missing.push(`${h.kode} ${h.nama} -> ${rule.hsd}`); continue; }
    h.harga = Math.round(src.harga * (rule.factor || 1));
    h.sumber_harga = `${label} ${src.kode} ${src.nama}${rule.factor && rule.factor !== 1 ? ` (x${+rule.factor.toFixed(4)})` : ''}`;
    filled.push(h);
  }
  db.meta.harga = {
    wilayah: hsd.wilayah, tahun_data: hsd.tahun, sumber: hsd.sumber, url: hsd.url, diambil: hsd.diambil,
    catatan: 'HSD Bina Marga (jalan/jembatan) TA 2024, belum disesuaikan inflasi. Hanya item bernama dan bersatuan sama yang terisi; selebihnya 0 dan harus diisi manual.',
    terisi: filled.length, dari: db.harga_dasar.length
  };
  db.meta.catatan_harga = `Harga dasar: ${filled.length} dari ${db.harga_dasar.length} terisi dari ${label}. Sisanya 0, isi sesuai harga daerah/proyek.`;
  return { filled, missing };
}

// ── CLI ───────────────────────────────────────────────────────────────────────

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const refresh = process.argv.includes('--refresh');
  const hsd = !refresh && fs.existsSync(HSD_FILE) ? JSON.parse(fs.readFileSync(HSD_FILE, 'utf8')) : await fetchHsd();
  console.log(`HSD ${hsd.wilayah} TA${hsd.tahun}: ${hsd.items.length} item (diambil ${hsd.diambil})`);
  const db = readDb(DB_FILE);
  const { filled, missing } = applyHarga(db, hsd);
  writeDb(DB_FILE, db);
  const used = new Map();
  for (const a of db.ahsp) for (const c of a.komponen) used.set(c.kode, (used.get(c.kode) || 0) + 1);
  const pemakaian = filled.reduce((s, h) => s + (used.get(h.kode) || 0), 0);
  const total = [...used.values()].reduce((s, n) => s + n, 0);
  console.log(`Terisi ${filled.length}/${db.harga_dasar.length} harga dasar (menutup ${pemakaian} dari ${total} pemakaian komponen di AHSP)`);
  const lengkap = db.ahsp.filter(a => a.komponen.every(c => filled.some(h => h.kode === c.kode))).length;
  console.log(`AHSP yang semua komponennya sudah berharga: ${lengkap} dari ${db.ahsp.length}`);
  if (missing.length) console.log('Padanan tak ditemukan di HSD:', missing);
}
