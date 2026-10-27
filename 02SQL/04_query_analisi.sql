-- =====================================================================
--  03_query_analisi.sql – Le grandi Borse del mondo 📈
--  Database: borsa.db (SQLite 3.35 o più recente, per POWER, SQRT e LN)
--  Periodo principale: dal 2007-03-30 al 2026-10-26
--  ⚠️ Solo analisi storica: non è un consiglio di investimento
-- =====================================================================


-- =====================================================================
--  0️⃣ CONTROLLI SUI DATI
-- =====================================================================

-- Q0.1 📋 Quanti giorni per indice, primo e ultimo giorno
SELECT i.nome, i.valuta, COUNT(*) AS giorni,
       MIN(p.data) AS primo_giorno, MAX(p.data) AS ultimo_giorno
FROM prezzi p
JOIN indici i ON i.codice = p.codice
GROUP BY i.nome, i.valuta, i.ordine
ORDER BY i.ordine;

-- Q0.2 🔍 Righe con valori strani (massimo sotto il minimo o chiusura fuori dal range)
SELECT codice, COUNT(*) AS righe_strane
FROM prezzi
WHERE massimo < minimo OR chiusura > massimo OR chiusura < minimo
GROUP BY codice;


-- =====================================================================
--  1️⃣ QUALE INDICE È CRESCIUTO DI PIÙ? (2007-2026)
-- =====================================================================

-- Q1.1 🏆 Crescita totale e crescita media all'anno, con la classifica
WITH periodo AS (
    SELECT codice, data, chiusura,
           ROW_NUMBER() OVER (PARTITION BY codice ORDER BY data)      AS n_primo,
           ROW_NUMBER() OVER (PARTITION BY codice ORDER BY data DESC) AS n_ultimo
    FROM prezzi
    WHERE data >= '2007-03-30'
),
estremi AS (
    SELECT codice,
           MAX(CASE WHEN n_primo  = 1 THEN data END)     AS data_inizio,
           MAX(CASE WHEN n_primo  = 1 THEN chiusura END) AS inizio,
           MAX(CASE WHEN n_ultimo = 1 THEN data END)     AS data_fine,
           MAX(CASE WHEN n_ultimo = 1 THEN chiusura END) AS fine
    FROM periodo
    GROUP BY codice
)
SELECT RANK() OVER (ORDER BY fine / inizio DESC)                        AS posizione,
       i.nome, ROUND(inizio, 0) AS valore_2007, ROUND(fine, 0) AS valore_oggi,
       ROUND((fine / inizio - 1) * 100, 1)                              AS crescita_pct,
       ROUND((POWER(fine / inizio, 365.25 / (julianday(data_fine) - julianday(data_inizio))) - 1) * 100, 1)
                                                                        AS crescita_annua_pct
FROM estremi e
JOIN indici i ON i.codice = e.codice
ORDER BY posizione;

-- Q1.2 🌍 Crescita media per area (America, Europa, Asia)
WITH periodo AS (
    SELECT codice, chiusura,
           ROW_NUMBER() OVER (PARTITION BY codice ORDER BY data)      AS n_primo,
           ROW_NUMBER() OVER (PARTITION BY codice ORDER BY data DESC) AS n_ultimo
    FROM prezzi
    WHERE data >= '2007-03-30'
),
crescita AS (
    SELECT codice,
           MAX(CASE WHEN n_ultimo = 1 THEN chiusura END) / MAX(CASE WHEN n_primo = 1 THEN chiusura END) - 1 AS cresc
    FROM periodo
    GROUP BY codice
)
SELECT i.area, COUNT(*) AS indici, ROUND(AVG(cresc) * 100, 1) AS crescita_media_pct,
       GROUP_CONCAT(i.nome, ', ') AS elenco
FROM crescita c
JOIN indici i ON i.codice = c.codice
GROUP BY i.area
ORDER BY crescita_media_pct DESC;

-- Q1.3 🏅 Il record storico (chiusura più alta dal 2000) e quanto si è lontani oggi
WITH record AS (
    SELECT codice, data, chiusura,
           ROW_NUMBER() OVER (PARTITION BY codice ORDER BY chiusura DESC) AS n
    FROM prezzi
),
oggi AS (
    SELECT codice, chiusura,
           ROW_NUMBER() OVER (PARTITION BY codice ORDER BY data DESC) AS n
    FROM prezzi
)
SELECT i.nome, r.data AS data_record, ROUND(r.chiusura, 0) AS record,
       ROUND(o.chiusura, 0) AS oggi,
       ROUND((o.chiusura / r.chiusura - 1) * 100, 1) AS distanza_dal_record_pct
FROM record r
JOIN oggi o   ON o.codice = r.codice AND o.n = 1
JOIN indici i ON i.codice = r.codice
WHERE r.n = 1
ORDER BY distanza_dal_record_pct DESC;


-- =====================================================================
--  2️⃣ E SE CONTO TUTTO IN EURO?
-- =====================================================================

-- Q2.1 💱 Quanto valeva 1 euro nel 2007 e quanto vale oggi
SELECT v.valuta, v.nome,
       (SELECT euro_vale FROM cambi c WHERE c.valuta = v.valuta AND c.data <= '2007-03-30' ORDER BY c.data DESC LIMIT 1) AS euro_2007,
       (SELECT euro_vale FROM cambi c WHERE c.valuta = v.valuta ORDER BY c.data DESC LIMIT 1)                           AS euro_oggi
FROM valute v
WHERE v.valuta <> 'EUR';

-- Q2.2 💶 Crescita in valuta locale e in euro (usa la vista v_prezzi_euro)
WITH estremi AS (
    SELECT codice,
           MIN(data) AS d1, MAX(data) AS d2
    FROM prezzi
    WHERE data >= '2007-03-30'
    GROUP BY codice
)
SELECT v1.nome, v1.valuta,
       ROUND((v2.chiusura / v1.chiusura - 1) * 100, 1)         AS crescita_locale_pct,
       ROUND((v2.chiusura_eur / v1.chiusura_eur - 1) * 100, 1) AS crescita_euro_pct,
       ROUND(10000 * v2.chiusura_eur / v1.chiusura_eur, -2)    AS diecimila_euro_oggi
FROM estremi e
JOIN v_prezzi_euro v1 ON v1.codice = e.codice AND v1.data = e.d1
JOIN v_prezzi_euro v2 ON v2.codice = e.codice AND v2.data = e.d2
ORDER BY crescita_euro_pct DESC;


-- =====================================================================
--  3️⃣ QUALE INDICE È PIÙ RISCHIOSO?
-- =====================================================================

-- Q3.1 🎢 Volatilità annua: deviazione standard dei rendimenti giornalieri × √252
WITH rend AS (
    SELECT codice,
           chiusura / LAG(chiusura) OVER (PARTITION BY codice ORDER BY data) - 1 AS r
    FROM prezzi
    WHERE data >= '2007-03-30'
)
SELECT i.nome,
       ROUND(SQRT(AVG(r * r) - AVG(r) * AVG(r)) * SQRT(252) * 100, 1) AS volatilita_annua_pct,
       ROUND(MIN(r) * 100, 1) AS giorno_peggiore_pct,
       ROUND(MAX(r) * 100, 1) AS giorno_migliore_pct
FROM rend
JOIN indici i ON i.codice = rend.codice
WHERE r IS NOT NULL
GROUP BY i.nome
ORDER BY volatilita_annua_pct;

-- Q3.2 📉 Massima caduta dal punto più alto (drawdown) dal 2007
WITH picchi AS (
    SELECT codice, data, chiusura,
           MAX(chiusura) OVER (PARTITION BY codice ORDER BY data
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS massimo_fino_a_oggi
    FROM prezzi
    WHERE data >= '2007-03-30'
),
cadute AS (
    SELECT codice, data, (chiusura / massimo_fino_a_oggi - 1) * 100 AS caduta,
           ROW_NUMBER() OVER (PARTITION BY codice ORDER BY chiusura / massimo_fino_a_oggi) AS n
    FROM picchi
)
SELECT i.nome, ROUND(caduta, 1) AS massima_caduta_pct, data AS giorno_del_minimo
FROM cadute c
JOIN indici i ON i.codice = c.codice
WHERE n = 1
ORDER BY massima_caduta_pct;

-- Q3.3 ⚡ I 10 giorni peggiori di tutti gli indici (dal 2000)
WITH rend AS (
    SELECT codice, data,
           chiusura / LAG(chiusura) OVER (PARTITION BY codice ORDER BY data) - 1 AS r
    FROM prezzi
)
SELECT i.nome, data, ROUND(r * 100, 1) AS variazione_pct
FROM rend
JOIN indici i ON i.codice = rend.codice
WHERE r IS NOT NULL
ORDER BY r
LIMIT 10;

-- Q3.4 🌪️ Giorni "agitati" (variazione oltre ±3%) per anno: S&P 500 e FTSE MIB
WITH rend AS (
    SELECT codice, substr(data, 1, 4) AS anno,
           chiusura / LAG(chiusura) OVER (PARTITION BY codice ORDER BY data) - 1 AS r
    FROM prezzi
    WHERE codice IN ('SP500', 'FTSEMIB')
)
SELECT anno,
       SUM(CASE WHEN codice = 'SP500'   AND ABS(r) > 0.03 THEN 1 ELSE 0 END) AS sp500,
       SUM(CASE WHEN codice = 'FTSEMIB' AND ABS(r) > 0.03 THEN 1 ELSE 0 END) AS ftse_mib
FROM rend
WHERE r IS NOT NULL
GROUP BY anno
ORDER BY anno;


-- =====================================================================
--  4️⃣ LE CRISI: QUANTO SI PERDE E QUANTO SI ASPETTA
-- =====================================================================

-- Q4.1 🦠 Covid 2020: picco di gen-feb, minimo, caduta e giorno del recupero
WITH picco AS (
    SELECT codice, data AS data_picco, chiusura AS valore_picco,
           ROW_NUMBER() OVER (PARTITION BY codice ORDER BY chiusura DESC) AS n
    FROM prezzi
    WHERE data BETWEEN '2020-01-01' AND '2020-02-29'
),
minimo AS (
    SELECT p.codice, p.data AS data_minimo, p.chiusura AS valore_minimo,
           ROW_NUMBER() OVER (PARTITION BY p.codice ORDER BY p.chiusura) AS n
    FROM prezzi p
    JOIN picco k ON k.codice = p.codice AND k.n = 1
    WHERE p.data BETWEEN k.data_picco AND '2020-06-30'
)
SELECT i.nome, k.data_picco, m.data_minimo,
       ROUND((m.valore_minimo / k.valore_picco - 1) * 100, 1) AS caduta_pct,
       (SELECT MIN(p.data) FROM prezzi p
        WHERE p.codice = k.codice AND p.data > m.data_minimo AND p.chiusura >= k.valore_picco) AS data_recupero,
       ROUND((julianday((SELECT MIN(p.data) FROM prezzi p
                         WHERE p.codice = k.codice AND p.data > m.data_minimo AND p.chiusura >= k.valore_picco))
              - julianday(m.data_minimo)) / 30.44, 1) AS mesi_per_recuperare
FROM picco k
JOIN minimo m ON m.codice = k.codice AND m.n = 1
JOIN indici i ON i.codice = k.codice
WHERE k.n = 1
ORDER BY caduta_pct;

-- Q4.2 🏦 Crisi 2008: caduta dal picco del 2007 e anni per tornarci
WITH picco AS (
    SELECT codice, data AS data_picco, chiusura AS valore_picco,
           ROW_NUMBER() OVER (PARTITION BY codice ORDER BY chiusura DESC) AS n
    FROM prezzi
    WHERE data BETWEEN '2007-01-01' AND '2008-06-30'
),
minimo AS (
    SELECT p.codice, p.data AS data_minimo, p.chiusura AS valore_minimo,
           ROW_NUMBER() OVER (PARTITION BY p.codice ORDER BY p.chiusura) AS n
    FROM prezzi p
    JOIN picco k ON k.codice = p.codice AND k.n = 1
    WHERE p.data BETWEEN k.data_picco AND '2009-12-31'
),
recupero AS (
    SELECT k.codice, MIN(p.data) AS data_recupero
    FROM picco k
    JOIN minimo m ON m.codice = k.codice AND m.n = 1
    LEFT JOIN prezzi p ON p.codice = k.codice AND p.data > m.data_minimo AND p.chiusura >= k.valore_picco
    WHERE k.n = 1
    GROUP BY k.codice
)
SELECT i.nome, k.data_picco, m.data_minimo,
       ROUND((m.valore_minimo / k.valore_picco - 1) * 100, 1) AS caduta_pct,
       r.data_recupero,
       ROUND((julianday(r.data_recupero) - julianday(m.data_minimo)) / 365.25, 1) AS anni_per_recuperare
FROM picco k
JOIN minimo m   ON m.codice = k.codice AND m.n = 1
JOIN recupero r ON r.codice = k.codice
JOIN indici i   ON i.codice = k.codice
WHERE k.n = 1
ORDER BY anni_per_recuperare DESC;


-- =====================================================================
--  5️⃣ ANNO PER ANNO
-- =====================================================================

-- Q5.1 📅 Rendimento di ogni anno (ultima chiusura dell'anno contro quella dell'anno prima)
WITH fine_anno AS (
    SELECT codice, substr(data, 1, 4) AS anno, chiusura,
           ROW_NUMBER() OVER (PARTITION BY codice, substr(data, 1, 4) ORDER BY data DESC) AS n
    FROM prezzi
),
annui AS (
    SELECT codice, anno,
           (chiusura / LAG(chiusura) OVER (PARTITION BY codice ORDER BY anno) - 1) * 100 AS rend
    FROM fine_anno
    WHERE n = 1
)
SELECT anno,
       ROUND(MAX(CASE WHEN codice = 'SP500'       THEN rend END), 1) AS sp500,
       ROUND(MAX(CASE WHEN codice = 'NASDAQ100'   THEN rend END), 1) AS nasdaq100,
       ROUND(MAX(CASE WHEN codice = 'EUROSTOXX50' THEN rend END), 1) AS eurostoxx50,
       ROUND(MAX(CASE WHEN codice = 'DAX'         THEN rend END), 1) AS dax,
       ROUND(MAX(CASE WHEN codice = 'CAC40'       THEN rend END), 1) AS cac40,
       ROUND(MAX(CASE WHEN codice = 'FTSEMIB'     THEN rend END), 1) AS ftse_mib,
       ROUND(MAX(CASE WHEN codice = 'FTSE100'     THEN rend END), 1) AS ftse100,
       ROUND(MAX(CASE WHEN codice = 'NIKKEI225'   THEN rend END), 1) AS nikkei225,
       ROUND(MAX(CASE WHEN codice = 'HANGSENG'    THEN rend END), 1) AS hang_seng
FROM annui
WHERE rend IS NOT NULL
GROUP BY anno
ORDER BY anno;

-- Q5.2 ✅ Anni positivi, anno migliore e anno peggiore (anni completi 2008-2025)
WITH fine_anno AS (
    SELECT codice, CAST(substr(data, 1, 4) AS INTEGER) AS anno, chiusura,
           ROW_NUMBER() OVER (PARTITION BY codice, substr(data, 1, 4) ORDER BY data DESC) AS n
    FROM prezzi
),
annui AS (
    SELECT codice, anno,
           (chiusura / LAG(chiusura) OVER (PARTITION BY codice ORDER BY anno) - 1) * 100 AS rend
    FROM fine_anno
    WHERE n = 1
),
ordinati AS (
    SELECT codice, anno, rend,
           ROW_NUMBER() OVER (PARTITION BY codice ORDER BY rend DESC) AS n_migliore,
           ROW_NUMBER() OVER (PARTITION BY codice ORDER BY rend)      AS n_peggiore
    FROM annui
    WHERE anno BETWEEN 2008 AND 2025
)
SELECT i.nome,
       SUM(CASE WHEN rend > 0 THEN 1 ELSE 0 END) || ' su ' || COUNT(*)            AS anni_positivi,
       MAX(CASE WHEN n_migliore = 1 THEN anno END)                                 AS anno_migliore,
       ROUND(MAX(CASE WHEN n_migliore = 1 THEN rend END), 1)                       AS rend_migliore_pct,
       MAX(CASE WHEN n_peggiore = 1 THEN anno END)                                 AS anno_peggiore,
       ROUND(MAX(CASE WHEN n_peggiore = 1 THEN rend END), 1)                       AS rend_peggiore_pct
FROM ordinati o
JOIN indici i ON i.codice = o.codice
GROUP BY i.nome, i.ordine
ORDER BY i.ordine;

-- Q5.3 🔢 Quanti indici hanno chiuso l'anno in positivo
WITH fine_anno AS (
    SELECT codice, substr(data, 1, 4) AS anno, chiusura,
           ROW_NUMBER() OVER (PARTITION BY codice, substr(data, 1, 4) ORDER BY data DESC) AS n
    FROM prezzi
),
annui AS (
    SELECT codice, anno,
           chiusura / LAG(chiusura) OVER (PARTITION BY codice ORDER BY anno) - 1 AS rend
    FROM fine_anno
    WHERE n = 1
)
SELECT anno, COUNT(*) AS indici,
       SUM(CASE WHEN rend > 0 THEN 1 ELSE 0 END) AS in_positivo,
       SUM(CASE WHEN rend < 0 THEN 1 ELSE 0 END) AS in_negativo
FROM annui
WHERE rend IS NOT NULL AND anno BETWEEN '2008' AND '2025'
GROUP BY anno
ORDER BY in_positivo, anno;


-- =====================================================================
--  6️⃣ LE BORSE SI MUOVONO INSIEME?
-- =====================================================================

-- Q6.1 🔗 Correlazione dei rendimenti mensili: S&P 500 con ogni altro indice
WITH fine_mese AS (
    SELECT codice, substr(data, 1, 7) AS mese, chiusura,
           ROW_NUMBER() OVER (PARTITION BY codice, substr(data, 1, 7) ORDER BY data DESC) AS n
    FROM prezzi
    WHERE data BETWEEN '2007-03-01' AND '2026-09-30'
),
mensili AS (
    SELECT codice, mese,
           chiusura / LAG(chiusura) OVER (PARTITION BY codice ORDER BY mese) - 1 AS r
    FROM fine_mese
    WHERE n = 1
),
coppie AS (
    SELECT b.codice, a.r AS x, b.r AS y
    FROM mensili a
    JOIN mensili b ON b.mese = a.mese
    WHERE a.codice = 'SP500' AND b.codice <> 'SP500' AND a.r IS NOT NULL AND b.r IS NOT NULL
)
SELECT i.nome, COUNT(*) AS mesi,
       ROUND((AVG(x * y) - AVG(x) * AVG(y))
             / (SQRT(AVG(x * x) - AVG(x) * AVG(x)) * SQRT(AVG(y * y) - AVG(y) * AVG(y))), 2) AS correlazione_con_sp500
FROM coppie c
JOIN indici i ON i.codice = c.codice
GROUP BY i.nome
ORDER BY correlazione_con_sp500 DESC;


-- =====================================================================
--  7️⃣ OGGI: SOPRA O SOTTO LA MEDIA DEGLI ULTIMI 200 GIORNI?
-- =====================================================================

-- Q7.1 📏 Media mobile a 200 giorni (solo descrizione della tendenza, non un segnale)
WITH mm AS (
    SELECT codice, data, chiusura,
           AVG(chiusura) OVER (PARTITION BY codice ORDER BY data
                               ROWS BETWEEN 199 PRECEDING AND CURRENT ROW) AS media_200,
           ROW_NUMBER() OVER (PARTITION BY codice ORDER BY data DESC) AS n
    FROM prezzi
)
SELECT i.nome, data, ROUND(chiusura, 0) AS chiusura, ROUND(media_200, 0) AS media_200_giorni,
       ROUND((chiusura / media_200 - 1) * 100, 1) AS distanza_pct,
       CASE WHEN chiusura > media_200 THEN 'sopra la media' ELSE 'sotto la media' END AS tendenza
FROM mm
JOIN indici i ON i.codice = mm.codice
WHERE n = 1
ORDER BY distanza_pct DESC;
