"""
MIT License
(c) 2025 Riccardo Leonelli
"""

class QuerySqlManutenzioniMYSQL:
    # ---------- SCADENZE ----------
    @staticmethod
    def list_due_within_sql() -> str:
        """
        Restituisce le attività di manutenzione con scadenza entro N giorni.
        Parametri:
          - days: numero di giorni (int)
        """
        return """
            SELECT
              t.id            AS task_id,
              t.title,
              v.next_due_at,
              d.name          AS department_name,
              t.area_label
            FROM vw_maintenance_next_due v
            JOIN maintenance_tasks t
              ON t.id = v.task_id
            LEFT JOIN departments d
              ON d.id = t.department_id
            WHERE v.next_due_at <= DATE_ADD(CURDATE(), INTERVAL %s DAY)
              AND t.active = 1
            ORDER BY v.next_due_at ASC, t.title ASC
        """

    # ---------- DESTINATARI (solo RESPONSABILE TASK) ----------
    @staticmethod
    def recipients_for_task_sql() -> str:
        """
        Restituisce l'email del RESPONSABILE del task (se presente).
        Parametri:
          - task_id
        """
        return """
            SELECT o.email AS email
            FROM maintenance_tasks t
            JOIN operators o ON o.id = t.responsible_operator_id
            WHERE t.id = %s
              AND o.email IS NOT NULL
        """

    # ---------- THROTTLE ----------
    @staticmethod
    def throttle_check_sql() -> str:
        """
        Verifica se è già stata inviata una notifica negli ultimi N giorni
        per lo stesso task e destinatario.
        Parametri:
          - task_id
          - email
          - throttle_days
        """
        return """
            SELECT CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END AS recent
            FROM maintenance_notification_log
            WHERE task_id = %s
              AND recipient_email = %s
              AND sent_at >= DATE_SUB(NOW(), INTERVAL %s DAY)
        """

    # ---------- LOG EMAIL ----------
    @staticmethod
    def insert_log_sql() -> str:
        """
        Registra un invio di notifica per evitare duplicati futuri.
        Parametri:
          - task_id
          - email
          - subject
          - reason
        """
        return """
            INSERT INTO maintenance_notification_log
              (task_id, recipient_email, subject, reason)
            VALUES (%s, %s, %s, %s)
        """

    # ---------- EVENTI ----------
    @staticmethod
    def insert_event_sql() -> str:
        """
        Registra un intervento effettuato su una manutenzione.
        Parametri:
          - task_id
          - done_by_operator_id (facoltativo)
          - notes
        """
        return """
            INSERT INTO maintenance_events (task_id, done_at, done_by_operator_id, notes)
            VALUES (%s, NOW(), %s, %s)
        """

    @staticmethod
    def list_events_sql() -> str:
        """
        Elenco storico degli interventi per un determinato task.
        Parametri:
          - task_id
        """
        return """
            SELECT
              e.id,
              e.task_id,
              e.done_at,
              e.done_by_operator_id,
              o.first_name,
              o.last_name,
              e.notes
            FROM maintenance_events e
            LEFT JOIN operators o ON o.id = e.done_by_operator_id
            WHERE e.task_id = %s
            ORDER BY e.done_at DESC
        """
