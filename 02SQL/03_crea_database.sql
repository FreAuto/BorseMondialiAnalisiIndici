-- =====================================================================
--  01_crea_database.sql – Le grandi Borse del mondo 📈
--  Crea le tabelle del database (SQLite).
--  Lo usa 02_carica_dati.py: non serve lanciarlo a mano.
-- =====================================================================

DROP VIEW  IF EXISTS v_prezzi_euro;
DROP TABLE IF EXISTS cambi;
DROP TABLE IF EXISTS prezzi;
DROP TABLE IF EXISTS indici;
DROP TABLE IF EXISTS valute;

-- 💱 le 5 valute
CREATE TABLE valute (
    valuta  TEXT PRIMARY KEY,                   -- 'EUR', 'USD', ...
    nome    TEXT NOT NULL
);

-- 🏛️ i 9 indici di Borsa
CREATE TABLE indici (
    codice        TEXT PRIMARY KEY,             -- 'SP500', 'FTSEMIB', ...
    nome          TEXT NOT NULL,
    paese         TEXT NOT NULL,
    area          TEXT NOT NULL CHECK (area IN ('America', 'Europa', 'Asia')),
    valuta        TEXT NOT NULL REFERENCES valute (valuta),
    ticker_yahoo  TEXT,
    colore        TEXT,
    ordine        INTEGER
);

-- 📈 una riga per indice e giorno di Borsa
CREATE TABLE prezzi (
    codice    TEXT NOT NULL REFERENCES indici (codice),
    data      TEXT NOT NULL,                    -- 'AAAA-MM-GG'
    apertura  REAL,
    massimo   REAL,
    minimo    REAL,
    chiusura  REAL NOT NULL CHECK (chiusura > 0),
    volume    REAL,
    PRIMARY KEY (codice, data)
) WITHOUT ROWID;

-- 💶 quanto vale 1 euro in ogni valuta, giorno per giorno
CREATE TABLE cambi (
    data       TEXT NOT NULL,
    valuta     TEXT NOT NULL REFERENCES valute (valuta),
    euro_vale  REAL NOT NULL CHECK (euro_vale > 0),
    PRIMARY KEY (valuta, data)
) WITHOUT ROWID;

CREATE INDEX idx_prezzi_data ON prezzi (data);

-- 👀 vista comoda: ogni chiusura anche in euro (cambio dell'ultimo giorno disponibile)
CREATE VIEW v_prezzi_euro AS
SELECT p.codice, i.nome, i.area, i.valuta, p.data, p.chiusura,
       CASE WHEN i.valuta = 'EUR' THEN 1.0
            ELSE (SELECT c.euro_vale FROM cambi c
                  WHERE c.valuta = i.valuta AND c.data <= p.data
                  ORDER BY c.data DESC LIMIT 1) END AS cambio,
       p.chiusura / CASE WHEN i.valuta = 'EUR' THEN 1.0
            ELSE (SELECT c.euro_vale FROM cambi c
                  WHERE c.valuta = i.valuta AND c.data <= p.data
                  ORDER BY c.data DESC LIMIT 1) END AS chiusura_eur
FROM prezzi p
JOIN indici i ON i.codice = p.codice;
