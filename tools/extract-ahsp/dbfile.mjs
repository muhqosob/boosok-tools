// Format file database AHSP (ahsp_se47_2026.json): meta rapi, tapi tiap harga dasar dan tiap AHSP satu baris
// supaya diff git-nya terbaca. Dipakai extract.mjs dan harga-serang.mjs.
import fs from 'fs';

export function serializeDb(db) {
  const J = JSON.stringify;
  return '{\n  "meta": ' + J(db.meta, null, 2).replace(/\n/g, '\n  ') + ',\n  "harga_dasar": [\n    ' +
    db.harga_dasar.map(h => J(h)).join(',\n    ') + '\n  ],\n  "ahsp": [\n    ' + db.ahsp.map(a => J(a)).join(',\n    ') + '\n  ]\n}\n';
}

export function readDb(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

export function writeDb(file, db) {
  fs.writeFileSync(file, serializeDb(db));
}
