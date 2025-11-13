-- =========================================================
--  SCHEDULER MANUTENZIONI - SCHEMA + SEED (MySQL 5.7 SAFE)
--  (c) 2025 Riccardo Leonelli — MIT License
-- =========================================================

USE plaxr;

-- ---------------------------------------------------------
-- 0) PULIZIA
-- ---------------------------------------------------------
DROP TABLE IF EXISTS maintenance_task_recipients;

-- ---------------------------------------------------------
-- 1) TABELLE
-- ---------------------------------------------------------

-- 1.1 tasks
CREATE TABLE IF NOT EXISTS maintenance_tasks (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  title VARCHAR(255) NOT NULL,
  notes_oper TEXT NULL,
  estimated_minutes INT NULL,
  department_id BIGINT NULL,
  area_label VARCHAR(120) NULL,
  responsible_operator_id BIGINT NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_mt_department  FOREIGN KEY (department_id)           REFERENCES departments(id),
  CONSTRAINT fk_mt_responsible FOREIGN KEY (responsible_operator_id) REFERENCES operators(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 1.2 rules
CREATE TABLE IF NOT EXISTS maintenance_rules (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  task_id BIGINT NOT NULL,
  kind ENUM('INTERVAL_DAYS','WEEKLY','MONTHLY','YEARLY') NOT NULL,
  interval_days   INT NULL,
  interval_weeks  INT NULL,
  interval_months INT NULL,
  interval_years  INT NULL,
  window_days     INT NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_mr_task FOREIGN KEY (task_id) REFERENCES maintenance_tasks(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 1.3 events
CREATE TABLE IF NOT EXISTS maintenance_events (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  task_id BIGINT NOT NULL,
  done_at DATETIME NOT NULL,
  done_by_operator_id BIGINT NULL,
  notes TEXT NULL,
  CONSTRAINT fk_me_task FOREIGN KEY (task_id) REFERENCES maintenance_tasks(id) ON DELETE CASCADE,
  CONSTRAINT fk_me_op   FOREIGN KEY (done_by_operator_id) REFERENCES operators(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 1.4 notif log
CREATE TABLE IF NOT EXISTS maintenance_notification_log (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  task_id BIGINT NOT NULL,
  recipient_email VARCHAR(190) NOT NULL,
  sent_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  subject VARCHAR(255) NULL,
  reason  VARCHAR(64)  NULL,
  CONSTRAINT fk_mnl_task FOREIGN KEY (task_id) REFERENCES maintenance_tasks(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------
-- 1.x INDICI (compat 5.7 con check su information_schema)
-- ---------------------------------------------------------
-- ix_mt_active
SET @sql := (
  SELECT IF (
    NOT EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'maintenance_tasks'
        AND INDEX_NAME = 'ix_mt_active'
    ),
    'CREATE INDEX ix_mt_active ON maintenance_tasks (active)',
    'SELECT 1'
  )
); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- ix_mt_dept
SET @sql := (
  SELECT IF (
    NOT EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'maintenance_tasks'
        AND INDEX_NAME = 'ix_mt_dept'
    ),
    'CREATE INDEX ix_mt_dept ON maintenance_tasks (department_id)',
    'SELECT 1'
  )
); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- ix_mt_resp
SET @sql := (
  SELECT IF (
    NOT EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'maintenance_tasks'
        AND INDEX_NAME = 'ix_mt_resp'
    ),
    'CREATE INDEX ix_mt_resp ON maintenance_tasks (responsible_operator_id)',
    'SELECT 1'
  )
); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- ix_mr_task
SET @sql := (
  SELECT IF (
    NOT EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'maintenance_rules'
        AND INDEX_NAME = 'ix_mr_task'
    ),
    'CREATE INDEX ix_mr_task ON maintenance_rules (task_id)',
    'SELECT 1'
  )
); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- ix_mr_active
SET @sql := (
  SELECT IF (
    NOT EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'maintenance_rules'
        AND INDEX_NAME = 'ix_mr_active'
    ),
    'CREATE INDEX ix_mr_active ON maintenance_rules (active)',
    'SELECT 1'
  )
); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- ix_me_task
SET @sql := (
  SELECT IF (
    NOT EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'maintenance_events'
        AND INDEX_NAME = 'ix_me_task'
    ),
    'CREATE INDEX ix_me_task ON maintenance_events (task_id)',
    'SELECT 1'
  )
); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- ix_me_doneat
SET @sql := (
  SELECT IF (
    NOT EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'maintenance_events'
        AND INDEX_NAME = 'ix_me_doneat'
    ),
    'CREATE INDEX ix_me_doneat ON maintenance_events (done_at)',
    'SELECT 1'
  )
); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- ix_mnl_task_email_time
SET @sql := (
  SELECT IF (
    NOT EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'maintenance_notification_log'
        AND INDEX_NAME = 'ix_mnl_task_email_time'
    ),
    'CREATE INDEX ix_mnl_task_email_time ON maintenance_notification_log (task_id, recipient_email, sent_at)',
    'SELECT 1'
  )
); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- ix_mnl_sent_at
SET @sql := (
  SELECT IF (
    NOT EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'maintenance_notification_log'
        AND INDEX_NAME = 'ix_mnl_sent_at'
    ),
    'CREATE INDEX ix_mnl_sent_at ON maintenance_notification_log (sent_at)',
    'SELECT 1'
  )
); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- ---------------------------------------------------------
-- 2) VIEW (no CTE → ok 5.7)
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

-- ---------------------------------------------------------
-- 3) SEED ATTIVITÀ + REGOLE
-- ---------------------------------------------------------

-- Mappa reparti (se esistono)
SET @dep_stampa         := (SELECT id FROM departments WHERE UPPER(name)='STAMPA' LIMIT 1);
SET @dep_accoppiamento  := (SELECT id FROM departments WHERE UPPER(name)='ACCOPPIAMENTO' LIMIT 1);
SET @dep_saldatura      := (SELECT id FROM departments WHERE UPPER(name)='SALDATURA' LIMIT 1);
SET @dep_ufficio        := (SELECT id FROM departments WHERE UPPER(name)='UFFICIO' LIMIT 1);

-- 1
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT 'Cambiare acqua e detergente al lava anilox, Smontare e pulire ugelli spara acqua',
       'Al termine chiudere scarico liquidi usati', 60, @dep_stampa, 'STAMPA', 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_tasks WHERE title='Cambiare acqua e detergente al lava anilox, Smontare e pulire ugelli spara acqua');
SET @tid1 := (SELECT id FROM maintenance_tasks WHERE title='Cambiare acqua e detergente al lava anilox, Smontare e pulire ugelli spara acqua');
INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid1, 'MONTHLY', 1, 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_rules WHERE task_id=@tid1 AND kind='MONTHLY' AND interval_months=1 AND active=1);

-- 2
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT 'Cambiare calze di asciugamento al lava cliché','Controllare usura', NULL, @dep_stampa, 'STAMPA', 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_tasks WHERE title='Cambiare calze di asciugamento al lava cliché');
SET @tid2 := (SELECT id FROM maintenance_tasks WHERE title='Cambiare calze di asciugamento al lava cliché');
INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid2, 'MONTHLY', 2, 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_rules WHERE task_id=@tid2 AND kind='MONTHLY' AND interval_months=2 AND active=1);

-- 3
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT 'Pulire inkmaker','Svitare vite e parallela, poi alzare il cassone', NULL, @dep_stampa, 'STAMPA', 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_tasks WHERE title='Pulire inkmaker');
SET @tid3 := (SELECT id FROM maintenance_tasks WHERE title='Pulire inkmaker');
INSERT INTO maintenance_rules (task_id, kind, interval_days, active)
SELECT @tid3, 'INTERVAL_DAYS', 45, 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_rules WHERE task_id=@tid3 AND kind='INTERVAL_DAYS' AND interval_days=45 AND active=1);

-- 4
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT 'Pulire filtri aspirazione', NULL, NULL, NULL, 'All', 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_tasks WHERE title='Pulire filtri aspirazione');
SET @tid4 := (SELECT id FROM maintenance_tasks WHERE title='Pulire filtri aspirazione');
INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid4, 'MONTHLY', 1, 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_rules WHERE task_id=@tid4 AND kind='MONTHLY' AND interval_months=1 AND active=1);

-- 5
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT 'Pulire filtri chiller', NULL, NULL, NULL, 'All', 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_tasks WHERE title='Pulire filtri chiller');
SET @tid5 := (SELECT id FROM maintenance_tasks WHERE title='Pulire filtri chiller');
INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid5, 'MONTHLY', 1, 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_rules WHERE task_id=@tid5 AND kind='MONTHLY' AND interval_months=1 AND active=1);

-- 6
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT 'Pulire filtri acqua accoppiamento', NULL, NULL, @dep_accoppiamento, 'ACCOPPIAMENTO', 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_tasks WHERE title='Pulire filtri acqua accoppiamento');
SET @tid6 := (SELECT id FROM maintenance_tasks WHERE title='Pulire filtri acqua accoppiamento');
INSERT INTO maintenance_rules (task_id, kind, interval_weeks, active)
SELECT @tid6, 'WEEKLY', 1, 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_rules WHERE task_id=@tid6 AND kind='WEEKLY' AND interval_weeks=1 AND active=1);

-- 7
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT 'Pulire radiatori chiller', NULL, NULL, NULL, 'stampa/accoppiamento', 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_tasks WHERE title='Pulire radiatori chiller');
SET @tid7 := (SELECT id FROM maintenance_tasks WHERE title='Pulire radiatori chiller');
INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid7, 'MONTHLY', 6, 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_rules WHERE task_id=@tid7 AND kind='MONTHLY' AND interval_months=6 AND active=1);

-- 8
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT 'Pulire server','Con aspirapolvere', NULL, @dep_ufficio, 'UFFICIO', 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_tasks WHERE title='Pulire server');
SET @tid8 := (SELECT id FROM maintenance_tasks WHERE title='Pulire server');
INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid8, 'MONTHLY', 6, 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_rules WHERE task_id=@tid8 AND kind='MONTHLY' AND interval_months=6 AND active=1);

-- 9
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT 'Cambiare batteria PLC macchina 1','Segnare data sostituzione', NULL, @dep_stampa, 'STAMPA', 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_tasks WHERE title='Cambiare batteria PLC macchina 1');
SET @tid9 := (SELECT id FROM maintenance_tasks WHERE title='Cambiare batteria PLC macchina 1');
INSERT INTO maintenance_rules (task_id, kind, interval_years, active)
SELECT @tid9, 'YEARLY', 1, 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_rules WHERE task_id=@tid9 AND kind='YEARLY' AND interval_years=1 AND active=1);

-- 10
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT 'CHIAMARE MARCO 1 VOLTA ALL ANNO PRIMA DELL ESTATE CHE PULISCE TUTTO', NULL, NULL, NULL, NULL, 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_tasks WHERE title='CHIAMARE MARCO 1 VOLTA ALL ANNO PRIMA DELL ESTATE CHE PULISCE TUTTO');
SET @tid10 := (SELECT id FROM maintenance_tasks WHERE title='CHIAMARE MARCO 1 VOLTA ALL ANNO PRIMA DELL ESTATE CHE PULISCE TUTTO');
INSERT INTO maintenance_rules (task_id, kind, interval_years, active)
SELECT @tid10, 'YEARLY', 1, 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_rules WHERE task_id=@tid10 AND kind='YEARLY' AND interval_years=1 AND active=1);

-- 11
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT 'cambia rulli lava - cliché', NULL, 240, @dep_stampa, 'STAMPA', 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_tasks WHERE title='cambia rulli lava - cliché');
SET @tid11 := (SELECT id FROM maintenance_tasks WHERE title='cambia rulli lava - cliché');
INSERT INTO maintenance_rules (task_id, kind, interval_years, active)
SELECT @tid11, 'YEARLY', 2, 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_rules WHERE task_id=@tid11 AND kind='YEARLY' AND interval_years=2 AND active=1);

-- 12
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT 'verifiche perdite aria combustore', NULL, NULL, NULL, 'combustore fumi', 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_tasks WHERE title='verifiche perdite aria combustore');
SET @tid12 := (SELECT id FROM maintenance_tasks WHERE title='verifiche perdite aria combustore');
INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid12, 'MONTHLY', 1, 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_rules WHERE task_id=@tid12 AND kind='MONTHLY' AND interval_months=1 AND active=1);

-- 13
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT 'Ingrassare rulli saldatura', NULL, NULL, @dep_saldatura, 'SALDATURA', 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_tasks WHERE title='Ingrassare rulli saldatura');
SET @tid13 := (SELECT id FROM maintenance_tasks WHERE title='Ingrassare rulli saldatura');
INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid13, 'MONTHLY', 6, 1
WHERE NOT EXISTS (SELECT 1 FROM maintenance_rules WHERE task_id=@tid13 AND kind='MONTHLY' AND interval_months=6 AND active=1);

-- ---------------------------------------------------------
-- 4) EVENTI SEED
-- ---------------------------------------------------------

-- PLC fatto il 30/10/2025
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid9, '2025-10-30 08:00:00', NULL, 'Sostituzione manuale PLC (seed)'
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_events WHERE task_id=@tid9 AND DATE(done_at)='2025-10-30'
);

-- Baseline 1/1 anno prossimo per TUTTI tranne PLC e “MARCO”
SET @baseline_dt := CONCAT(YEAR(CURDATE()) + 1, '-01-01 08:00:00');

-- helper insert baseline (evita duplicati)
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid1,  @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid1 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM maintenance_events WHERE task_id=@tid1  AND DATE(done_at)=DATE(@baseline_dt));
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid2,  @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid2 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM maintenance_events WHERE task_id=@tid2  AND DATE(done_at)=DATE(@baseline_dt));
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid3,  @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid3 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM maintenance_events WHERE task_id=@tid3  AND DATE(done_at)=DATE(@baseline_dt));
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid4,  @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid4 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM maintenance_events WHERE task_id=@tid4  AND DATE(done_at)=DATE(@baseline_dt));
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid5,  @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid5 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM maintenance_events WHERE task_id=@tid5  AND DATE(done_at)=DATE(@baseline_dt));
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid6,  @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid6 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM maintenance_events WHERE task_id=@tid6  AND DATE(done_at)=DATE(@baseline_dt));
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid7,  @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid7 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM maintenance_events WHERE task_id=@tid7  AND DATE(done_at)=DATE(@baseline_dt));
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid8,  @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid8 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM maintenance_events WHERE task_id=@tid8  AND DATE(done_at)=DATE(@baseline_dt));
-- skip @tid9 (PLC)
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid11, @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid11 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM maintenance_events WHERE task_id=@tid11 AND DATE(done_at)=DATE(@baseline_dt));
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid12, @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid12 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM maintenance_events WHERE task_id=@tid12 AND DATE(done_at)=DATE(@baseline_dt));
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid13, @baseline_dt, NULL, CONCAT('AUTO_SEED baseline ', DATE(@baseline_dt))
WHERE @tid13 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM maintenance_events WHERE task_id=@tid13 AND DATE(done_at)=DATE(@baseline_dt));

-- MARCO: baseline a GIUGNO (non gennaio)
SET @baseline_marco := CONCAT(YEAR(CURDATE()) + 1, '-06-01 08:00:00');
-- elimina eventuale baseline di gennaio per MARCO
DELETE FROM maintenance_events
WHERE task_id=@tid10 AND YEAR(done_at)=YEAR(CURDATE()) + 1 AND MONTH(done_at)=1;
-- inserisce baseline giugno
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid10, @baseline_marco, NULL, CONCAT('AUTO_SEED baseline giugno ', DATE(@baseline_marco))
WHERE @tid10 IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM maintenance_events WHERE task_id=@tid10 AND DATE(done_at)=DATE(@baseline_marco)
);

-- ---------------------------------------------------------
-- 5) CHECK RAPIDI (facoltativi)
-- ---------------------------------------------------------
-- SELECT (SELECT COUNT(*) FROM maintenance_tasks) AS tasks,
--        (SELECT COUNT(*) FROM maintenance_rules) AS rules,
--        (SELECT COUNT(*) FROM maintenance_events) AS events;

-- SELECT t.title, v.next_due_at
-- FROM vw_maintenance_next_due v
-- JOIN maintenance_tasks t ON t.id=v.task_id
-- ORDER BY v.next_due_at, t.title;


-- Inserisci l’attività (se non c’è già)
INSERT INTO maintenance_tasks (title, notes_oper, estimated_minutes, department_id, area_label, active)
SELECT
  'Smontaggio pulizia e lubrificazione dei moduli frizione taglierine',
  'Attività semestrale: moduli frizione taglierine — Ferragosto e dopo la Befana',
  NULL,
  NULL,
  'TAGLIO',
  1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_tasks WHERE title='Smontaggio pulizia e lubrificazione dei moduli frizione taglierine'
);

SET @tid_fric := (SELECT id FROM maintenance_tasks WHERE title='Smontaggio pulizia e lubrificazione dei moduli frizione taglierine' LIMIT 1);

-- Inserisci la regola: ogni 6 mesi (due volte l’anno)
INSERT INTO maintenance_rules (task_id, kind, interval_months, active)
SELECT @tid_fric, 'MONTHLY', 6, 1
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rules WHERE task_id=@tid_fric AND kind='MONTHLY' AND interval_months=6 AND active=1
);


-- Ancoraggio iniziale al 1° gennaio 2026
INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
SELECT @tid_fric, '2026-01-01 08:00:00', NULL, 'AUTO_SEED: ancoraggio semestrale (base 01/01/2026)'
WHERE @tid_fric IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_events
    WHERE task_id=@tid_fric AND DATE(done_at)='2026-01-01'
  );

-- (Facoltativo) verifica prossima scadenza
-- SELECT t.title, v.next_due_at
-- FROM vw_maintenance_next_due v
-- JOIN maintenance_tasks t ON t.id=v.task_id
-- WHERE t.id=@tid_fric;
