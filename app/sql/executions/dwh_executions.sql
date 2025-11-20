-- ==========================================
-- STEP 1: creazione database DWH + dim_date
-- ==========================================

-- 1) Crea (o ricrea) il DB DWH
DROP DATABASE IF EXISTS dwh;
CREATE DATABASE dwh
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_520_ci;

USE dwh;

-- 2) Tabella calendario: dim_date (SOLO STRUTTURA)
DROP TABLE IF EXISTS dim_date;

CREATE TABLE dim_date (
  `date_key`     INT         NOT NULL,      -- es: 20251119
  `full_date`    DATE        NOT NULL,
  `year_num`     SMALLINT    NOT NULL,
  `month_num`    TINYINT     NOT NULL,
  `day_num`      TINYINT     NOT NULL,
  `year_month`   CHAR(7)     NOT NULL,      -- formato YYYY-MM
  `quarter_num`  TINYINT     NOT NULL,
  `day_of_week`  TINYINT     NOT NULL,      -- 1=Sunday (DAYOFWEEK)
  `day_name`     VARCHAR(10) NOT NULL,
  `month_name`   VARCHAR(15) NOT NULL,
  `is_weekend`   TINYINT(1)  NOT NULL,

  PRIMARY KEY (`date_key`),
  KEY `idx_full_date` (`full_date`)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_520_ci;

USE dwh;
-- ================================
-- POPOLAMENTO DIM_DATE (2015–2035)
-- ================================
-- Nessuna PROCEDURE, nessun DELIMITER.
-- Usiamo una “numbers table” generata al volo (10^4 giorni = 10.000 > 2015–2035).

INSERT INTO dim_date (
  `date_key`,
  `full_date`,
  `year_num`,
  `month_num`,
  `day_num`,
  `year_month`,
  `quarter_num`,
  `day_of_week`,
  `day_name`,
  `month_name`,
  `is_weekend`
)
SELECT
  CAST(DATE_FORMAT(d, '%Y%m%d') AS SIGNED) AS date_key,
  d                                        AS full_date,
  YEAR(d)                                  AS year_num,
  MONTH(d)                                 AS month_num,
  DAY(d)                                   AS day_num,
  DATE_FORMAT(d, '%Y-%m')                  AS `year_month`,
  QUARTER(d)                               AS quarter_num,
  DAYOFWEEK(d)                             AS day_of_week,
  DATE_FORMAT(d, '%W')                     AS day_name,
  DATE_FORMAT(d, '%M')                     AS month_name,
  CASE WHEN DAYOFWEEK(d) IN (1,7) THEN 1 ELSE 0 END AS is_weekend
FROM (
  SELECT DATE('2015-01-01') + INTERVAL seq DAY AS d
  FROM (
    SELECT
      n0.i + 10*n1.i + 100*n2.i + 1000*n3.i AS seq
    FROM (SELECT 0 i UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) AS n0
    CROSS JOIN (SELECT 0 i UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4        
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) AS n1
    CROSS JOIN (SELECT 0 i UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4        
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) AS n2
    CROSS JOIN (SELECT 0 i UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4        
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) AS n3
  ) AS seqs
) AS dates
WHERE d <= '2035-12-31';

USE dwh;

DROP TABLE IF EXISTS dim_customer;

CREATE TABLE dim_customer (
  customer_key   INT          NOT NULL AUTO_INCREMENT,
  codice         CHAR(6)      NOT NULL,              -- ANAGRAFE.CODICE
  descrizion     VARCHAR(50)  NULL,                  -- ragione sociale
  supragsoc      VARCHAR(40)  NULL,
  partita_iva    VARCHAR(28)  NULL,
  codice_fiscale VARCHAR(16)  NULL,
  estero         TINYINT      NULL,
  stato_cf       CHAR(1)      NULL,                  -- ANAGRAFE.STATOCF (se usato come stato)
  cod_nazione    CHAR(3)      NULL,                  -- CODNAZIONE
  cod_iso        CHAR(2)      NULL,                  -- CODICEISO
  localita       VARCHAR(40)  NULL,
  provincia      CHAR(2)      NULL,
  cap            VARCHAR(5)   NULL,
  indirizzo      VARCHAR(50)  NULL,
  telefono       VARCHAR(16)  NULL,
  email          VARCHAR(80)  NULL,
  cli_pa         TINYINT      NULL,                  -- cliente PA (flag)
  dt_ult_agg     DATE         NULL,                  -- DTULTAGG, se valorizzata

  PRIMARY KEY (customer_key),
  UNIQUE KEY uk_codice (codice),
  KEY idx_piva (partita_iva),
  KEY idx_cf   (codice_fiscale)
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_520_ci;

INSERT INTO dim_customer (
  codice,
  descrizion,
  supragsoc,
  partita_iva,
  codice_fiscale,
  estero,
  stato_cf,
  cod_nazione,
  cod_iso,
  localita,
  provincia,
  cap,
  indirizzo,
  telefono,
  email,
  cli_pa,
  dt_ult_agg
)
SELECT
  a.`CODICE`,
  a.`DESCRIZION`,
  a.`SUPRAGSOC`,
  a.`PARTIVA`,
  a.`CODFISCALE`,
  a.`ESTERO`,
  a.`STATOCF`,
  a.`CODNAZIONE`,
  a.`CODICEISO`,
  a.`LOCALITA`,
  a.`PROV`,
  a.`CAP`,
  a.`INDIRIZZO`,
  a.`TELEFONO`,
  a.`EMAIL`,
  a.`CLI_PA`,
  a.`DTULTAGG`
FROM fox_staging.anagrafe a;

USE dwh;

DROP TABLE IF EXISTS dim_article;

CREATE TABLE dim_article (
  article_key      INT           NOT NULL AUTO_INCREMENT,

  codicearti       VARCHAR(20)   NOT NULL,     -- codice articolo Fox
  descrizion       VARCHAR(50)   NULL,
  unmisura         CHAR(2)       NULL,

  gruppo           VARCHAR(5)    NULL,
  classe           VARCHAR(5)    NULL,
  classeabc        CHAR(1)       NULL,
  statoart         CHAR(1)       NULL,

  pesounit         DECIMAL(18,6) NULL,
  qtaconf          DECIMAL(18,6) NULL,

  ubicazione       VARCHAR(6)    NULL,
  marca            VARCHAR(3)    NULL,
  cer              VARCHAR(6)    NULL,

  timestamp_src    DATETIME      NULL,
  username_src     VARCHAR(20)   NULL,

  PRIMARY KEY (article_key),
  UNIQUE KEY uk_codicearti (codicearti),
  KEY idx_gruppo (gruppo),
  KEY idx_classe (classe)
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_520_ci;

INSERT INTO dim_article (
  codicearti,
  descrizion,
  unmisura,
  gruppo,
  classe,
  classeabc,
  statoart,
  pesounit,
  qtaconf,
  ubicazione,
  marca,
  cer,
  timestamp_src,
  username_src
)
SELECT
  m.`CODICE`,
  m.`DESCRIZION`,
  m.`UNMISURA`,
  m.`GRUPPO`,
  m.`CLASSE`,
  m.`CLASSEABC`,
  m.`STATOART`,
  m.`PESOUNIT`,
  m.`QTACONF`,
  m.`UBICAZIONE`,
  m.`MARCA`,
  m.`CER`,
  m.`TIMESTAMP`,
  m.`USERNAME`
FROM fox_staging.magart m;
 
 USE dwh;

-- Drop per sicurezza
DROP TABLE IF EXISTS dim_warehouse;

-- ============================================
-- CREATE TABLE dim_warehouse
-- ============================================
CREATE TABLE dim_warehouse (
    warehouse_key   INT          NOT NULL AUTO_INCREMENT,
    codice          VARCHAR(5)   NOT NULL,     -- es. M01, P01, ecc.
    descrizion      VARCHAR(50)  NULL,
    fiscale         TINYINT(1)   NULL,
    nonfiscale      TINYINT(1)   NULL,
    cantiere        VARCHAR(12)  NULL,
    vds             VARCHAR(11)  NULL,
    timestamp_src   DATETIME     NULL,
    username_src    VARCHAR(20)  NULL,

    PRIMARY KEY (warehouse_key),
    UNIQUE KEY uk_codice (codice)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_520_ci;

-- ============================================
-- POPOLAMENTO INIZIALE (da fox_staging.magana)
-- ============================================
INSERT INTO dim_warehouse (
    codice,
    descrizion,
    fiscale,
    nonfiscale,
    cantiere,
    vds,
    timestamp_src,
    username_src
)
SELECT
    m.`codice`,
    m.`descrizion`,
    m.`fiscale`,
    m.`nonfiscale`,
    m.`cantiere`,
    m.`vds`,
    m.`timestamp_row`,
    m.`username`
FROM fox_staging.magana m;

USE dwh;

-- ============================================
-- DIM TIPODOC
-- ============================================
DROP TABLE IF EXISTS dim_tipodoc;

CREATE TABLE dim_tipodoc (
  tipodoc_key  INT         NOT NULL AUTO_INCREMENT,
  tipodoc      CHAR(2)     NOT NULL,       -- es: OC, OF, FA, FB, DD, DT, ...
  descrizione  VARCHAR(50) NULL,           -- etichetta leggibile (di base uguale a tipodoc)
  tipo_fiscale VARCHAR(20) NULL,           -- ORDINE / FATTURA / DDT / ALTRO
  direction    VARCHAR(10) NULL,           -- OUT / IN / OTHER
  is_order     TINYINT(1)  NOT NULL DEFAULT 0,
  is_invoice   TINYINT(1)  NOT NULL DEFAULT 0,
  is_ddt       TINYINT(1)  NOT NULL DEFAULT 0,

  PRIMARY KEY (tipodoc_key),
  UNIQUE KEY uk_tipodoc (tipodoc)
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_520_ci;


-- ============================================
-- POPOLAMENTO INIZIALE da fox_staging.doctes
-- ============================================
INSERT INTO dim_tipodoc (
  tipodoc,
  descrizione,
  tipo_fiscale,
  direction,
  is_order,
  is_invoice,
  is_ddt
)
SELECT
  t.tipodoc,

  -- descrizione base = il codice stesso (poi eventualmente aggiorni a mano)
  t.tipodoc        AS descrizione,

  -- classificazione "fiscale"
  CASE
    WHEN t.tipodoc IN ('OC','OF','OR','OX')   THEN 'ORDINE'
    WHEN t.tipodoc IN ('FA','FB','FI')        THEN 'FATTURA'
    WHEN t.tipodoc IN ('DD','DT')             THEN 'DDT'
    ELSE 'ALTRO'
  END AS tipo_fiscale,

  -- direzione documento (grezza ma utile)
  CASE
    WHEN t.tipodoc IN ('OC','OF','OR','OX','DD','DT') THEN 'OUT'   -- nostri verso esterno
    WHEN t.tipodoc IN ('AI','AF','NA')               THEN 'IN'    -- documenti che arrivano
    ELSE 'OTHER'
  END AS direction,

  -- flag comodi per i filtri
  CASE WHEN t.tipodoc IN ('OC','OF','OR','OX') THEN 1 ELSE 0 END AS is_order,
  CASE WHEN t.tipodoc IN ('FA','FB','FI')      THEN 1 ELSE 0 END AS is_invoice,
  CASE WHEN t.tipodoc IN ('DD','DT')           THEN 1 ELSE 0 END AS is_ddt

FROM (
  SELECT DISTINCT tipodoc
  FROM fox_staging.doctes
  WHERE tipodoc IS NOT NULL AND tipodoc <> ''
) AS t;


USE dwh;

-- =====================================================
-- FACT DOCRIG - Righe documenti da fox_staging.docrig
-- =====================================================
DROP TABLE IF EXISTS fact_docrig;

CREATE TABLE fact_docrig (
  fact_id        BIGINT       NOT NULL AUTO_INCREMENT,

  -- chiave naturale del documento
  tipodoc        CHAR(2)      NOT NULL,
  esanno         CHAR(4)      NOT NULL,
  numerodoc      VARCHAR(20)  NOT NULL,
  numeroriga     INT          NOT NULL,

  -- chiavi verso calendario
  doc_date_key    INT         NULL,
  deliv_date_key  INT         NULL,

  -- chiavi verso dimensioni
  customer_key    INT         NULL,
  article_key     INT         NULL,
  warehouse_key   INT         NULL,
  tipodoc_key     INT         NULL,

  -- copie dei codici “di business” (degenerate / audit)
  codicecf       CHAR(6)      NULL,
  codicearti     VARCHAR(20)  NULL,
  magpartenz     VARCHAR(5)   NULL,
  magarrivo      VARCHAR(5)   NULL,
  lotto          VARCHAR(20)  NULL,

  -- misure economiche/quantitative
  quantita       DECIMAL(18,6) NULL,
  quantitare     DECIMAL(18,6) NULL,
  prezzoun       DECIMAL(18,8) NULL,
  prezzotot      DECIMAL(18,8) NULL,
  scontiv        DECIMAL(18,8) NULL,
  aliiva         CHAR(3)       NULL,
  valuta         CHAR(3)       NULL,
  cambio         DECIMAL(18,8) NULL,
  eurocambio     DECIMAL(18,6) NULL,

  PRIMARY KEY (fact_id),

  KEY idx_doc          (tipodoc, esanno, numerodoc, numeroriga),
  KEY idx_doc_date     (doc_date_key),
  KEY idx_deliv_date   (deliv_date_key),
  KEY idx_customer     (customer_key),
  KEY idx_article      (article_key),
  KEY idx_warehouse    (warehouse_key),
  KEY idx_tipodoc      (tipodoc_key),

  CONSTRAINT fk_fact_docrig_dim_date_doc
    FOREIGN KEY (doc_date_key)   REFERENCES dim_date(date_key),

  CONSTRAINT fk_fact_docrig_dim_date_deliv
    FOREIGN KEY (deliv_date_key) REFERENCES dim_date(date_key),

  CONSTRAINT fk_fact_docrig_dim_customer
    FOREIGN KEY (customer_key)   REFERENCES dim_customer(customer_key),

  CONSTRAINT fk_fact_docrig_dim_article
    FOREIGN KEY (article_key)    REFERENCES dim_article(article_key),

  CONSTRAINT fk_fact_docrig_dim_warehouse
    FOREIGN KEY (warehouse_key)  REFERENCES dim_warehouse(warehouse_key),

  CONSTRAINT fk_fact_docrig_dim_tipodoc
    FOREIGN KEY (tipodoc_key)    REFERENCES dim_tipodoc(tipodoc_key)
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_520_ci;


INSERT INTO fact_docrig (
  tipodoc,
  esanno,
  numerodoc,
  numeroriga,
  doc_date_key,
  deliv_date_key,
  customer_key,
  article_key,
  warehouse_key,
  tipodoc_key,
  codicecf,
  codicearti,
  magpartenz,
  magarrivo,
  lotto,
  quantita,
  quantitare,
  prezzoun,
  prezzotot,
  scontiv,
  aliiva,
  valuta,
  cambio,
  eurocambio
)
SELECT
  r.tipodoc,
  r.esanno,
  r.numerodoc,
  r.numeroriga,

  dd_doc.date_key    AS doc_date_key,
  dd_deliv.date_key  AS deliv_date_key,

  c.customer_key,
  a.article_key,
  w.warehouse_key,
  td.tipodoc_key,

  t.codicecf,
  r.codicearti,
  r.magpartenz,
  r.magarrivo,
  r.lotto,

  r.quantita,
  r.quantitare,
  r.prezzoun,
  r.prezzotot,
  r.scontiv,
  r.aliiva,

  t.valuta,
  t.cambio,
  t.eurocambio
FROM fox_staging.docrig r
JOIN fox_staging.doctes t
  ON t.tipodoc   = r.tipodoc
 AND t.esanno    = r.esanno
 AND t.numerodoc = r.numerodoc
LEFT JOIN dwh.dim_date dd_doc
  ON dd_doc.full_date = t.datadoc
LEFT JOIN dwh.dim_date dd_deliv
  ON dd_deliv.full_date = t.dataconseg
LEFT JOIN dwh.dim_customer c
  ON c.codice = t.codicecf
LEFT JOIN dwh.dim_article a
  ON a.codicearti = r.codicearti
LEFT JOIN dwh.dim_warehouse w
  ON w.codice = r.magpartenz
LEFT JOIN dwh.dim_tipodoc td
  ON td.tipodoc = r.tipodoc;

USE dwh;

-- ============================================
-- DIM CAUSALE MAGAZZINO
-- ============================================
DROP TABLE IF EXISTS dim_causale_mag;

CREATE TABLE dim_causale_mag (
  causale_key   INT         NOT NULL AUTO_INCREMENT,
  codice        VARCHAR(5)  NOT NULL,      -- caumag.codice
  descrizion    VARCHAR(80) NULL,          -- caumag.descrizion

  magpflag      TINYINT(1)  NULL,          -- parte prodotti
  magaflag      TINYINT(1)  NULL,          -- parte acquisti
  clifor        SMALLINT    NULL,          -- 1=cliente, 2=fornitore

  ppordin       CHAR(1)     NULL,
  ppimpegn      CHAR(1)     NULL,
  pcordin       CHAR(1)     NULL,
  pcimpegn      CHAR(1)     NULL,
  apordin       CHAR(1)     NULL,
  apimpegn      CHAR(1)     NULL,
  acordin       CHAR(1)     NULL,
  acimpegn      CHAR(1)     NULL,

  timestamp_src DATETIME    NULL,
  username_src  VARCHAR(40) NULL,

  PRIMARY KEY (causale_key),
  UNIQUE KEY uk_causale_codice (codice)
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_520_ci;

INSERT INTO dim_causale_mag (
  codice,
  descrizion,
  magpflag,
  magaflag,
  clifor,
  ppordin,
  ppimpegn,
  pcordin,
  pcimpegn,
  apordin,
  apimpegn,
  acordin,
  acimpegn,
  timestamp_src,
  username_src
)
SELECT
  c.codice,
  c.descrizion,
  c.magpflag,
  c.magaflag,
  c.clifor,
  c.ppordin,
  c.ppimpegn,
  c.pcordin,
  c.pcimpegn,
  c.apordin,
  c.apimpegn,
  c.acordin,
  c.acimpegn,
  c.timestamp_row,
  c.username
FROM fox_staging.caumag c;

USE dwh;

-- ============================================
-- DIM LOTTO
-- ============================================
DROP TABLE IF EXISTS dim_lotto;

CREATE TABLE dim_lotto (
  lotto_key     INT          NOT NULL AUTO_INCREMENT,
  codicearti    VARCHAR(20)  NOT NULL,     -- lotti.codicearti
  codice        VARCHAR(20)  NOT NULL,     -- lotti.codice (lotto)
  descrizion    VARCHAR(40)  NULL,
  datascad      DATE         NULL,
  timestamp_src DATETIME     NULL,
  username_src  VARCHAR(20)  NULL,

  PRIMARY KEY (lotto_key),
  UNIQUE KEY uk_art_lotto (codicearti, codice),
  KEY idx_lotto (codice),
  KEY idx_datascad (datascad)
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_520_ci;

INSERT INTO dim_lotto (
  codicearti,
  codice,
  descrizion,
  datascad,
  timestamp_src,
  username_src
)
SELECT
  l.codicearti,
  l.codice,
  l.descrizion,
  l.datascad,
  l.timestamp_row,
  l.username
FROM fox_staging.lotti l;

USE dwh;

-- =====================================================
-- FACT MAGMOV - Movimenti di magazzino
-- =====================================================
DROP TABLE IF EXISTS fact_magmov;

CREATE TABLE fact_magmov (
  fact_id        BIGINT       NOT NULL AUTO_INCREMENT,

  -- chiave sorgente (ID FoxPro)
  mov_id         BIGINT       NULL,

  -- calendari
  mov_date_key   INT          NULL,

  -- dimensioni surrogate
  customer_key   INT          NULL,
  article_key    INT          NULL,
  warehouse_key  INT          NULL,
  causale_key    INT          NULL,

  -- copie codici business
  codicecf       VARCHAR(6)   NULL,
  codicearti     VARCHAR(20)  NULL,
  magazzino      VARCHAR(5)   NULL,
  codcausale     VARCHAR(5)   NULL,
  lotto          VARCHAR(20)  NULL,

  -- misure principali
  quantita       DECIMAL(18,6) NULL,
  quantitare     DECIMAL(18,6) NULL,
  qtaindist      DECIMAL(18,6) NULL,
  valore         DECIMAL(18,6) NULL,
  ultcosto       DECIMAL(18,6) NULL,

  -- flag di politica stock (come da MAGMOV)
  ordin          SMALLINT     NULL,
  impegn         SMALLINT     NULL,
  qtacar         SMALLINT     NULL,
  qtascar        SMALLINT     NULL,
  qtatcar        SMALLINT     NULL,
  qtatscar       SMALLINT     NULL,
  qtaret         SMALLINT     NULL,

  PRIMARY KEY (fact_id),

  KEY idx_mov_date    (mov_date_key),
  KEY idx_customer    (customer_key),
  KEY idx_article     (article_key),
  KEY idx_warehouse   (warehouse_key),
  KEY idx_causale     (causale_key),

  CONSTRAINT fk_fact_magmov_dim_date
    FOREIGN KEY (mov_date_key)   REFERENCES dim_date(date_key),

  CONSTRAINT fk_fact_magmov_dim_customer
    FOREIGN KEY (customer_key)   REFERENCES dim_customer(customer_key),

  CONSTRAINT fk_fact_magmov_dim_article
    FOREIGN KEY (article_key)    REFERENCES dim_article(article_key),

  CONSTRAINT fk_fact_magmov_dim_warehouse
    FOREIGN KEY (warehouse_key)  REFERENCES dim_warehouse(warehouse_key),

  CONSTRAINT fk_fact_magmov_dim_causale
    FOREIGN KEY (causale_key)    REFERENCES dim_causale_mag(causale_key)
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_520_ci;


INSERT INTO fact_magmov (
  mov_id,
  mov_date_key,
  customer_key,
  article_key,
  warehouse_key,
  causale_key,
  codicecf,
  codicearti,
  magazzino,
  codcausale,
  lotto,
  quantita,
  quantitare,
  qtaindist,
  valore,
  ultcosto,
  ordin,
  impegn,
  qtacar,
  qtascar,
  qtatcar,
  qtatscar,
  qtaret
)
SELECT
  m.id                                       AS mov_id,

  dd.date_key                                AS mov_date_key,

  c.customer_key                             AS customer_key,
  a.article_key                              AS article_key,
  w.warehouse_key                            AS warehouse_key,
  cm.causale_key                             AS causale_key,

  m.codicecf,
  m.codicearti,
  m.magazzino,
  m.codcausale,
  m.lotto,

  m.quantita,
  m.quantitare,
  m.qtaindist,
  m.valore,
  m.ultcosto,

  m.ordin,
  m.impegn,
  m.qtacar,
  m.qtascar,
  m.qtatcar,
  m.qtatscar,
  m.qtaret
FROM fox_staging.magmov m
LEFT JOIN dwh.dim_date dd
  ON dd.full_date = m.datamov
LEFT JOIN dwh.dim_customer c
  ON c.codice = m.codicecf
LEFT JOIN dwh.dim_article a
  ON a.codicearti = m.codicearti
LEFT JOIN dwh.dim_warehouse w
  ON w.codice = m.magazzino
LEFT JOIN dwh.dim_causale_mag cm
  ON cm.codice = m.codcausale;
