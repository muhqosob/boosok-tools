-- Skema database D1 untuk server lisensi Boosok Tools
CREATE TABLE IF NOT EXISTS keys (
  key         TEXT PRIMARY KEY,
  name        TEXT NOT NULL DEFAULT '',   -- nama pembeli
  phone       TEXT NOT NULL DEFAULT '',   -- nomor WhatsApp pembeli
  note        TEXT NOT NULL DEFAULT '',
  max_devices INTEGER NOT NULL DEFAULT 1,
  revoked     INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
  key        TEXT NOT NULL,
  hwid       TEXT NOT NULL,
  first_seen INTEGER NOT NULL,
  last_seen  INTEGER NOT NULL,
  PRIMARY KEY (key, hwid)
);
