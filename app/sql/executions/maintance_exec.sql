-- =========================================================
--  SCHEDULER MANUTENZIONI - SCHEMA COMPLETO
--  (c) 2025 Riccardo Leonelli — MIT License
-- =========================================================

-- Usa il database corretto
USE plaxr;

-- ---------------------------------------------------------
-- 0) PULIZIA: elimina tabella destinatari per-task (ora gestiti da .env)
-- ---------------------------------------------------------
DROP TABLE IF EXISTS maintenance_task_recipients;

-- ---------------------------------------------------------
-- 1) TABELLE PRINCIPALI
-- ---------------------------------------------------------

-- 1.1) Attività di manutenzione (anagrafica)
CREATE TABLE IF NOT EXISTS maintenance_tasks (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  title VARCHAR(255) NOT NULL,              -- nome attività (es. Pulire filtri chiller)
  notes_oper TEXT NULL,                     -- istruzioni operative
  estimated_minutes INT NULL,               -- durata stimata (minuti)
  department_id BIGINT NULL,                -- FK su departments (facoltativa)
  area_label VARCHAR(120) NULL,             -- label di area generica (es. 'STAMPA', 'ALL')
  responsible_operator_id BIGINT NULL,      -- FK su operators (facoltativa)
  active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_mt_department  FOREIGN KEY (department_id)          REFERENCES departments(id),
  CONSTRAINT fk_mt_responsible FOREIGN KEY (responsible_operator_id) REFERENCES operators(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX IF NOT EXISTS ix_mt_active    ON maintenance_tasks (active);
CREATE INDEX IF NOT EXISTS ix_mt_dept      ON maintenance_tasks (department_id);
CREATE INDEX IF NOT EXISTS ix_mt_resp      ON maintenance_tasks (responsible_operator_id);


-- 1.2) Regole di ricorrenza
CREATE TABLE IF NOT EXISTS maintenance_rules (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  task_id BIGINT NOT NULL,
  kind ENUM('INTERVAL_DAYS','WEEKLY','MONTHLY','YEARLY') NOT NULL,
  interval_days   INT NULL,   -- usato se kind='INTERVAL_DAYS'
  interval_weeks  INT NULL,   -- usato se kind='WEEKLY' (moltiplicato x7)
  interval_months INT NULL,   -- usato se kind='MONTHLY'
  interval_years  INT NULL,   -- usato se kind='YEARLY'
  window_days     INT NULL,   -- (opzionale) finestra tolleranza/scivolamento
  active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_mr_task FOREIGN KEY (task_id) REFERENCES maintenance_tasks(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX IF NOT EXISTS ix_mr_task   ON maintenance_rules (task_id);
CREATE INDEX IF NOT EXISTS ix_mr_active ON maintenance_rules (active);


-- 1.3) Eventi di esecuzione (storico interventi)
CREATE TABLE IF NOT EXISTS maintenance_events (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  task_id BIGINT NOT NULL,
  done_at DATETIME NOT NULL,                 -- quando è stato eseguito
  done_by_operator_id BIGINT NULL,           -- chi l’ha eseguito (facoltativo)
  notes TEXT NULL,                           -- es. "AUTO_RESET: mailed ..." oppure note operative
  CONSTRAINT fk_me_task  FOREIGN KEY (task_id) REFERENCES maintenance_tasks(id) ON DELETE CASCADE,
  CONSTRAINT fk_me_op    FOREIGN KEY (done_by_operator_id) REFERENCES operators(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX IF NOT EXISTS ix_me_task   ON maintenance_events (task_id);
CREATE INDEX IF NOT EXISTS ix_me_doneat ON maintenance_events (done_at);


-- 1.4) Log invii email (per throttle/antiduplicati)
CREATE TABLE IF NOT EXISTS maintenance_notification_log (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  task_id BIGINT NOT NULL,
  recipient_email VARCHAR(190) NOT NULL,
  sent_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  subject VARCHAR(255) NULL,
  reason  VARCHAR(64)  NULL,                 -- es. 'due_time'
  CONSTRAINT fk_mnl_task FOREIGN KEY (task_id) REFERENCES maintenance_tasks(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX IF NOT EXISTS ix_mnl_task_email_time ON maintenance_notification_log (task_id, recipient_email, sent_at);
CREATE INDEX IF NOT EXISTS ix_mnl_sent_at         ON maintenance_notification_log (sent_at);


-- ---------------------------------------------------------
-- 2) VISTA: prossima scadenza per task
--    (no CTE, compatibile MySQL 5.7/8.0)
-- ---------------------------------------------------------
DROP VIEW IF EXISTS vw_maintenance_next_due;

CREATE VIEW vw_maintenance_next_due AS
SELECT
  t.id AS task_id,
  t.title,
  MIN(
    CASE r.kind
      WHEN 'INTERVAL_DAYS' THEN DATE_ADD(COALESCE(le.last_done_at, t.created_at), INTERVAL r.interval_days DAY)
      WHEN 'WEEKLY'        THEN DATE_ADD(COALESCE(le.last_done_at, t.created_at), INTERVAL (7 * r.interval_weeks) DAY)
      WHEN 'MONTHLY'       THEN DATE_ADD(COALESCE(le.last_done_at, t.created_at), INTERVAL r.interval_months MONTH)
      WHEN 'YEARLY'        THEN DATE_ADD(COALESCE(le.last_done_at, t.created_at), INTERVAL r.interval_years YEAR)
      ELSE NULL
    END
  ) AS next_due_at
FROM maintenance_tasks t
JOIN maintenance_rules r
  ON r.task_id = t.id AND r.active = 1
LEFT JOIN (
  SELECT task_id, MAX(done_at) AS last_done_at
  FROM maintenance_events
  GROUP BY task_id
) AS le
  ON le.task_id = t.id
WHERE t.active = 1
GROUP BY t.id, t.title;

-- =========================================================
--  SEED MANUTENZIONI - Popolamento attività e regole
--  (c) 2025 Riccardo Leonelli — MIT License
-- =========================================================

USE plaxr;

-- ---------------------------------------------------------
-- Mappa reparti su variabili (se non trovati => NULL)
-- ---------------------------------------------------------
SET @dep_stampa         := (SELECT id FROM departments WHERE UPPER(name)='STAMPA' LIMIT 1);
SET @dep_accoppiamento  := (SELECT id FROM departments WHERE UPPER(name)='ACCOPPIAMENTO' LIMIT 1);
SET @dep_saldatura      := (SELECT id FROM departments WHERE UPPER(name)='SALDATURA' LIMIT 1);
SET @dep_ufficio        := (SELECT id FROM departments WHERE UPPER(name)='UFFICIO' LIMIT 1);

-- Helper per ottenere id task per titolo
-- (pattern che useremo per ogni riga)
-- INSERT del task (se non esiste) + set variabile @tidX al suo id

-- 1) Cambiare acqua e detergente al lava anilox, Smontare e pulire ugelli spara acqua
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT
  'Cambiare acqua e detergente al lava anilox, Smontare e pulire ugelli spara acqua',
  'Al termine chiudere scarico liquidi usati',
  60, @dep_stampa, 'STAMPA', 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_tasks
  WHERE title='Cambiare acqua e detergente al lava anilox, Smontare e pulire ugelli spara acqua'
);
SET @tid1 := (SELECT id FROM maintenance_tasks WHERE title='Cambiare acqua e detergente al lava anilox, Smontare e pulire ugelli spara acqua');

-- Regola: Ogni 1 mese (ignoro “200 anilox lavati” che è contatore non-temporale)
INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid1, 'MONTHLY', 1, 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rules WHERE task_id=@tid1 AND kind='MONTHLY' AND interval_months=1 AND active=1
);

-- 2) Cambiare calze di asciugamento al lava cliché — Ogni 2 mesi / all’occor.
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT
  'Cambiare calze di asciugamento al lava cliché',
  'Controllare usura',
  NULL, @dep_stampa, 'STAMPA', 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_tasks
  WHERE title='Cambiare calze di asciugamento al lava cliché'
);
SET @tid2 := (SELECT id FROM maintenance_tasks WHERE title='Cambiare calze di asciugamento al lava cliché');

INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid2, 'MONTHLY', 2, 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rules WHERE task_id=@tid2 AND kind='MONTHLY' AND interval_months=2 AND active=1
);

-- 3) Pulire inkmaker — Ogni 1,5 mesi (45 gg)
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT
  'Pulire inkmaker',
  'Svitare vite e parallela, poi alzare il cassone',
  NULL, @dep_stampa, 'STAMPA', 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_tasks WHERE title='Pulire inkmaker'
);
SET @tid3 := (SELECT id FROM maintenance_tasks WHERE title='Pulire inkmaker');

INSERT INTO maintenance_rules (task_id, kind, interval_days, active)
SELECT @tid3, 'INTERVAL_DAYS', 45, 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rules WHERE task_id=@tid3 AND kind='INTERVAL_DAYS' AND interval_days=45 AND active=1
);

-- 4) Pulire filtri aspirazione — Ogni 1 mese (All)
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT
  'Pulire filtri aspirazione',
  NULL, NULL, NULL, 'All', 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_tasks WHERE title='Pulire filtri aspirazione'
);
SET @tid4 := (SELECT id FROM maintenance_tasks WHERE title='Pulire filtri aspirazione');

INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid4, 'MONTHLY', 1, 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rules WHERE task_id=@tid4 AND kind='MONTHLY' AND interval_months=1 AND active=1
);

-- 5) Pulire filtri chiller — Ogni 1 mese (All)
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT
  'Pulire filtri chiller',
  NULL, NULL, NULL, 'All', 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_tasks WHERE title='Pulire filtri chiller'
);
SET @tid5 := (SELECT id FROM maintenance_tasks WHERE title='Pulire filtri chiller');

INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid5, 'MONTHLY', 1, 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rules WHERE task_id=@tid5 AND kind='MONTHLY' AND interval_months=1 AND active=1
);

-- 6) Pulire filtri acqua accoppiamento — Ogni 1 settimana (ACCOPPIAMENTO)
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT
  'Pulire filtri acqua accoppiamento',
  NULL, NULL, @dep_accoppiamento, 'ACCOPPIAMENTO', 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_tasks WHERE title='Pulire filtri acqua accoppiamento'
);
SET @tid6 := (SELECT id FROM maintenance_tasks WHERE title='Pulire filtri acqua accoppiamento');

INSERT INTO maintenance_rules (task_id, kind, interval_weeks, active)
SELECT @tid6, 'WEEKLY', 1, 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rules WHERE task_id=@tid6 AND kind='WEEKLY' AND interval_weeks=1 AND active=1
);

-- 7) Pulire radiatori chiller — Ogni 6 mesi (stampa/accoppiamento → area_label)
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT
  'Pulire radiatori chiller',
  NULL, NULL, NULL, 'stampa/accoppiamento', 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_tasks WHERE title='Pulire radiatori chiller'
);
SET @tid7 := (SELECT id FROM maintenance_tasks WHERE title='Pulire radiatori chiller');

INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid7, 'MONTHLY', 6, 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rules WHERE task_id=@tid7 AND kind='MONTHLY' AND interval_months=6 AND active=1
);

-- 8) Pulire server — Ogni 6 mesi (UFFICIO)
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT
  'Pulire server',
  'Con aspirapolvere',
  NULL, @dep_ufficio, 'UFFICIO', 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_tasks WHERE title='Pulire server'
);
SET @tid8 := (SELECT id FROM maintenance_tasks WHERE title='Pulire server');

INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid8, 'MONTHLY', 6, 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rules WHERE task_id=@tid8 AND kind='MONTHLY' AND interval_months=6 AND active=1
);

-- 9) Cambiare batteria PLC macchina 1 — 1 volta all’anno (STAMPA)
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT
  'Cambiare batteria PLC macchina 1',
  'Segnare data sostituzione',
  NULL, @dep_stampa, 'STAMPA', 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_tasks WHERE title='Cambiare batteria PLC macchina 1'
);
SET @tid9 := (SELECT id FROM maintenance_tasks WHERE title='Cambiare batteria PLC macchina 1');

INSERT INTO maintenance_rules (task_id, kind, interval_years, active)
SELECT @tid9, 'YEARLY', 1, 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rules WHERE task_id=@tid9 AND kind='YEARLY' AND interval_years=1 AND active=1
);

-- 10) CHIAMARE MARCO 1 VOLTA ALL ANNO PRIMA DELL ESTATE CHE PULISCE TUTTO — 1 volta anno
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT
  'CHIAMARE MARCO 1 VOLTA ALL ANNO PRIMA DELL ESTATE CHE PULISCE TUTTO',
  NULL, NULL, NULL, NULL, 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_tasks WHERE title='CHIAMARE MARCO 1 VOLTA ALL ANNO PRIMA DELL ESTATE CHE PULISCE TUTTO'
);
SET @tid10 := (SELECT id FROM maintenance_tasks WHERE title='CHIAMARE MARCO 1 VOLTA ALL ANNO PRIMA DELL ESTATE CHE PULISCE TUTTO');

INSERT INTO maintenance_rules (task_id, kind, interval_years, active)
SELECT @tid10, 'YEARLY', 1, 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rules WHERE task_id=@tid10 AND kind='YEARLY' AND interval_years=1 AND active=1
);

-- 11) oggi 2 anni cambia rulli lava -clichè — ogni 2 anni (STAMPA), 4 ore
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT
  'cambia rulli lava - cliché',
  NULL, 240, @dep_stampa, 'STAMPA', 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_tasks WHERE title='cambia rulli lava - cliché'
);
SET @tid11 := (SELECT id FROM maintenance_tasks WHERE title='cambia rulli lava - cliché');

INSERT INTO maintenance_rules (task_id, kind, interval_years, active)
SELECT @tid11, 'YEARLY', 2, 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rules WHERE task_id=@tid11 AND kind='YEARLY' AND interval_years=2 AND active=1
);

-- 12) verifiche perdite aria combustore — ogni 1 mese (area_label dedicata)
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT
  'verifiche perdite aria combustore',
  NULL, NULL, NULL, 'combustore fumi', 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_tasks WHERE title='verifiche perdite aria combustore'
);
SET @tid12 := (SELECT id FROM maintenance_tasks WHERE title='verifiche perdite aria combustore');

INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid12, 'MONTHLY', 1, 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rules WHERE task_id=@tid12 AND kind='MONTHLY' AND interval_months=1 AND active=1
);

-- 13) Ingrassare rulli saldatura — ogni 6 mesi (SALDATURA)
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT
  'Ingrassare rulli saldatura',
  NULL, NULL, @dep_saldatura, 'SALDATURA', 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_tasks WHERE title='Ingrassare rulli saldatura'
);
SET @tid13 := (SELECT id FROM maintenance_tasks WHERE title='Ingrassare rulli saldatura');

INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid13, 'MONTHLY', 6, 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rules WHERE task_id=@tid13 AND kind='MONTHLY' AND interval_months=6 AND active=1
);


-- ---------------------------------------------------------
-- EVENTO STORICO: “Cambiare batteria PLC macchina 1” fatto il 30/10/2025
-- (se l’hai già registrato, questa insert non si ripete)
-- ---------------------------------------------------------
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid9, '2025-10-30 08:00:00', NULL, 'Sostituzione manuale PLC (seed)'
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_events
  WHERE task_id=@tid9 AND DATE(done_at)='2025-10-30'
);

-- =========================================================
-- FINE SEED
-- Verifiche rapide (decommenta se vuoi test)
-- =========================================================
-- SELECT t.id, t.title, v.next_due_at
-- FROM vw_maintenance_next_due v
-- JOIN maintenance_tasks t ON t.id = v.task_id
-- ORDER BY v.next_due_at, t.title;

-- =========================================================
--  Baseline eventi "dall'anno nuovo" per tutte le manutenzioni
--  (esclude: "Cambiare batteria PLC macchina 1" già registrata)
--  Idempotente: non duplica se l'evento già esiste per quella data
--  (c) 2025 Riccardo Leonelli — MIT License
-- =========================================================

USE plaxr;

-- baseline: 1 gennaio dell'anno prossimo, ore 08:00
SET @baseline_dt := CONCAT(YEAR(CURDATE()) + 1, '-01-01 08:00:00');

-- ---------------------------------------------------------
-- Risolve gli ID dei task per titolo (senza creare duplicati)
-- ---------------------------------------------------------

-- 1
SET @tid1 := (
  SELECT id FROM maintenance_tasks
  WHERE title='Cambiare acqua e detergente al lava anilox, Smontare e pulire ugelli spara acqua' LIMIT 1
);

-- 2
SET @tid2 := (
  SELECT id FROM maintenance_tasks
  WHERE title='Cambiare calze di asciugamento al lava cliché' LIMIT 1
);

-- 3
SET @tid3 := (
  SELECT id FROM maintenance_tasks
  WHERE title='Pulire inkmaker' LIMIT 1
);

-- 4
SET @tid4 := (
  SELECT id FROM maintenance_tasks
  WHERE title='Pulire filtri aspirazione' LIMIT 1
);

-- 5
SET @tid5 := (
  SELECT id FROM maintenance_tasks
  WHERE title='Pulire filtri chiller' LIMIT 1
);

-- 6
SET @tid6 := (
  SELECT id FROM maintenance_tasks
  WHERE title='Pulire filtri acqua accoppiamento' LIMIT 1
);

-- 7
SET @tid7 := (
  SELECT id FROM maintenance_tasks
  WHERE title='Pulire radiatori chiller' LIMIT 1
);

-- 8
SET @tid8 := (
  SELECT id FROM maintenance_tasks
  WHERE title='Pulire server' LIMIT 1
);

-- 9 (ESCLUSO perché già registrato manualmente il 30/10/2025)
-- SET @tid9 := (SELECT id FROM maintenance_tasks WHERE title='Cambiare batteria PLC macchina 1' LIMIT 1);

-- 10
SET @tid10 := (
  SELECT id FROM maintenance_tasks
  WHERE title='CHIAMARE MARCO 1 VOLTA ALL ANNO PRIMA DELL ESTATE CHE PULISCE TUTTO' LIMIT 1
);

-- 11
SET @tid11 := (
  SELECT id FROM maintenance_tasks
  WHERE title='cambia rulli lava - cliché' LIMIT 1
);

-- 12
SET @tid12 := (
  SELECT id FROM maintenance_tasks
  WHERE title='verifiche perdite aria combustore' LIMIT 1
);

-- 13
SET @tid13 := (
  SELECT id FROM maintenance_tasks
  WHERE title='Ingrassare rulli saldatura' LIMIT 1
);

-- ---------------------------------------------------------
-- Inserisce eventi baseline (se non esistono già per quella data)
-- ---------------------------------------------------------

INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid1, @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid1 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_events
    WHERE task_id=@tid1 AND DATE(done_at)=DATE(@baseline_dt)
  );

INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid2, @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid2 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_events
    WHERE task_id=@tid2 AND DATE(done_at)=DATE(@baseline_dt)
  );

INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid3, @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid3 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_events
    WHERE task_id=@tid3 AND DATE(done_at)=DATE(@baseline_dt)
  );

INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid4, @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid4 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_events
    WHERE task_id=@tid4 AND DATE(done_at)=DATE(@baseline_dt)
  );

INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid5, @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid5 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_events
    WHERE task_id=@tid5 AND DATE(done_at)=DATE(@baseline_dt)
  );

INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid6, @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid6 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_events
    WHERE task_id=@tid6 AND DATE(done_at)=DATE(@baseline_dt)
  );

INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid7, @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid7 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_events
    WHERE task_id=@tid7 AND DATE(done_at)=DATE(@baseline_dt)
  );

INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid8, @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid8 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_events
    WHERE task_id=@tid8 AND DATE(done_at)=DATE(@baseline_dt)
  );

-- SKIP @tid9 (batteria PLC) perché già registrato a fine 2025

INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid10, @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid10 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_events
    WHERE task_id=@tid10 AND DATE(done_at)=DATE(@baseline_dt)
  );

INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid11, @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid11 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_events
    WHERE task_id=@tid11 AND DATE(done_at)=DATE(@baseline_dt)
  );

INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid12, @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid12 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_events
    WHERE task_id=@tid12 AND DATE(done_at)=DATE(@baseline_dt)
  );

INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid13, @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid13 IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_events
    WHERE task_id=@tid13 AND DATE(done_at)=DATE(@baseline_dt)
  );

-- ---------------------------------------------------------
-- Verifica rapida (facoltativa)
-- ---------------------------------------------------------
-- SELECT t.id, t.title, e.done_at
-- FROM maintenance_events e
-- JOIN maintenance_tasks t ON t.id=e.task_id
-- WHERE DATE(e.done_at)=DATE(@baseline_dt)
-- ORDER BY t.title;


-- =========================================================
--  Correzione: task "CHIAMARE MARCO..." scadenza a GIUGNO
-- =========================================================

-- Calcolo data di baseline: 1 giugno dell'anno prossimo alle 08:00
SET @baseline_marco := CONCAT(YEAR(CURDATE()) + 1, '-06-01 08:00:00');

-- Ottieni id del task
SET @tid_marco := (
  SELECT id
  FROM maintenance_tasks
  WHERE title='CHIAMARE MARCO 1 VOLTA ALL ANNO PRIMA DELL ESTATE CHE PULISCE TUTTO'
  LIMIT 1
);

-- Cancella eventuale baseline precedente (1 gennaio)
DELETE FROM maintenance_events
WHERE task_id=@tid_marco AND YEAR(done_at)=YEAR(CURDATE()) + 1 AND MONTH(done_at)=1;

-- Inserisci nuovo evento baseline a giugno
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid_marco, @baseline_marco, NULL, CONCAT('AUTO_SEED baseline giugno ', DATE(@baseline_marco))
WHERE @tid_marco IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_events
    WHERE task_id=@tid_marco AND DATE(done_at)=DATE(@baseline_marco)
  );
