# app/jobs/manutenzioni.py
from __future__ import annotations

import os
from typing import Dict, List
from datetime import datetime
from zoneinfo import ZoneInfo

# import dal tuo path
from app.core.db import DbManager, MySQLDb, QueryType
from app.core.mailer import send_email, SchedulerEmailException
from app.sql.query.maintenance_queries import QuerySqlManutenzioniMYSQL as Q

TZ = ZoneInfo(os.getenv("TZ", "Europe/Rome"))

# ---------------------------
# Util: render HTML tabellare
# ---------------------------
def _h(s: object) -> str:
    if s is None:
        return "—"
    t = str(s)
    return (
        t.replace("&", "&amp;")
         .replace("<", "&lt;")
         .replace(">", "&gt;")
         .replace('"', "&quot;")
         .replace("'", "&#39;")
    )

def _render_table(rows: List[dict], within_days: int) -> str:
    trs = []
    for r in rows:
        area = r.get("department_name") or r.get("area_label") or ""
        trs.append(
            "<tr>"
            f"<td style='padding:6px;border:1px solid #ddd'>{_h(r['task_id'])}</td>"
            f"<td style='padding:6px;border:1px solid #ddd'>{_h(r['title'])}</td>"
            f"<td style='padding:6px;border:1px solid #ddd'>{_h(r['next_due_at'])}</td>"
            f"<td style='padding:6px;border:1px solid #ddd'>{_h(area)}</td>"
            "</tr>"
        )
    body_rows = "".join(trs) if trs else "<tr><td colspan='4' style='padding:8px;border:1px solid #ddd'>Nessuna scadenza.</td></tr>"
    generated = datetime.now(TZ).strftime("%Y-%m-%d %H:%M")
    return f"""
    <div style="font-family:system-ui,Segoe UI,Arial,sans-serif">
      <h2>Scadenze manutenzione entro {within_days} giorni</h2>
      <p>Generato: {generated}</p>
      <table style="border-collapse:collapse;font-size:14px">
        <thead>
          <tr>
            <th style="padding:6px;border:1px solid #ddd">#</th>
            <th style="padding:6px;border:1px solid #ddd">Attività</th>
            <th style="padding:6px;border:1px solid #ddd">Prossima scadenza</th>
            <th style="padding:6px;border:1px solid #ddd">Area/Reparto</th>
          </tr>
        </thead>
        <tbody>{body_rows}</tbody>
      </table>
    </div>
    """


# ---------------------------
# Lettura scadenze
# ---------------------------
def list_due(within_days: int) -> List[dict]:
    sql = Q.list_due_within_sql()
    with DbManager(MySQLDb()) as db:
        return db.execute_query(sql, (within_days,), fetchall=True, query_type=QueryType.GET) or []


# ---------------------------
# Destinatari (DB)
# ---------------------------
def _recipients_from_db(task_id: int) -> List[str]:
    sql = Q.recipients_for_task_sql()
    params = (task_id,)  # ← ora la query accetta 1 solo parametro
    with DbManager(MySQLDb()) as db:
        rows = db.execute_query(sql, params, fetchall=True, query_type=QueryType.GET) or []
    seen, emails = set(), []
    for r in rows:
        e = (r.get("email") or "").strip()
        if e and e.lower() not in seen:
            seen.add(e.lower())
            emails.append(e)
    return emails


# ---------------------------
# Destinatari (ENV statici)
# ---------------------------
def _split_emails(s: str | None) -> List[str]:
    if not s:
        return []
    parts = [x.strip() for x in s.split(",")]
    seen, out = set(), []
    for e in parts:
        if not e:
            continue
        k = e.lower()
        if k not in seen:
            seen.add(k)
            out.append(e)
    return out

def _static_recipients_from_env() -> dict:
    return {
        "to":  _split_emails(os.getenv("SCHEDULER_DEFAULT_TO", "")),
        "cc":  _split_emails(os.getenv("SCHEDULER_DEFAULT_CC", "")),
        "bcc": _split_emails(os.getenv("SCHEDULER_DEFAULT_BCC", "")),
    }


# ---------------------------
# Throttle / Log
# ---------------------------
def was_recently_mailed(task_id: int, email: str, throttle_days: int) -> bool:
    sql = Q.throttle_check_sql()
    params = (task_id, email, throttle_days)
    with DbManager(MySQLDb()) as db:
        row = db.execute_query(sql, params, fetchall=False, query_type=QueryType.GET) or {}
    return bool(row.get("recent") == 1)

def log_mail(task_id: int, email: str, subject: str, reason: str = "due_time") -> int:
    sql = Q.insert_log_sql()
    params = (task_id, email, subject, reason)
    with DbManager(MySQLDb()) as db:
        return db.execute_query(sql, params, fetchall=True, query_type=QueryType.INSERT)


# ---------------------------
# Storico interventi
# ---------------------------
def insert_event(task_id: int, done_by_operator_id: int | None, notes: str | None) -> int:
    sql = Q.insert_event_sql()
    params = (task_id, done_by_operator_id, notes)
    with DbManager(MySQLDb()) as db:
        return db.execute_query(sql, params, fetchall=True, query_type=QueryType.INSERT)

def list_events(task_id: int) -> List[dict]:
    sql = Q.list_events_sql()
    with DbManager(MySQLDb()) as db:
        return db.execute_query(sql, (task_id,), fetchall=True, query_type=QueryType.GET) or []


# ---------------------------
# Job: invio email scadenze
# ---------------------------
def run_send(within_days: int = 7, throttle_days: int = 7, dry_run: bool = False, advance_on_send: bool = True) -> Dict[str, int]:
    due_rows = list_due(within_days)
    use_db = str(os.getenv("SCHEDULER_USE_DB_RECIPIENTS", "1")).strip().lower() in {"1","true","yes","on"}

    sent = 0
    skipped = 0
    advanced_tasks: set[int] = set()

    if not due_rows:
        return {"rows_found": 0, "distinct_recipients": 0, "sent": 0, "skipped": 0}

    subject = f"[Manutenzioni] Scadenze entro {within_days} giorni ({datetime.now(TZ).date().isoformat()})"
    html_all = _render_table(due_rows, within_days)

    if not use_db:
        # --- Modalità .env: invia UNA mail con tutte le scadenze ---
        rcpts = _static_recipients_from_env()
        to_list = rcpts["to"]
        cc_list = rcpts["cc"]
        bcc_list = rcpts["bcc"]

        if not (to_list or cc_list or bcc_list):
            return {"rows_found": len(due_rows), "distinct_recipients": 0, "sent": 0, "skipped": 1}

        if dry_run:
            return {"rows_found": len(due_rows), "distinct_recipients": 1, "sent": 0, "skipped": 1}

        try:
            send_email(subject=subject, html=html_all, to=to_list, cc=cc_list, bcc=bcc_list)

            # log throttle (qui potresti includere anche cc/bcc se vuoi)
            for r in due_rows:
                for email in to_list:
                    try:
                        if not was_recently_mailed(r["task_id"], email, throttle_days):
                            log_mail(r["task_id"], email, subject, reason="due_time")
                    except Exception:
                        pass

            # AVANZA LE SCADENZE per ogni task notificato
            if advance_on_send:
                for r in due_rows:
                    tid = r["task_id"]
                    if tid in advanced_tasks:
                        continue
                    try:
                        insert_event(tid, None, f"AUTO_RESET: mailed {datetime.now(TZ).isoformat()}")
                        advanced_tasks.add(tid)
                    except Exception:
                        pass

            sent = 1

        except SchedulerEmailException:
            skipped = 1

        return {"rows_found": len(due_rows), "distinct_recipients": 1, "sent": sent, "skipped": skipped}

    # --- Modalità DB: una mail per destinatario (responsabile task) ---
    per_email: Dict[str, List[dict]] = {}
    for r in due_rows:
        for email in _recipients_from_db(r["task_id"]):
            if not was_recently_mailed(r["task_id"], email, throttle_days):
                per_email.setdefault(email, []).append(r)

    for email, rows in per_email.items():
        if not rows:
            skipped += 1
            continue
        if dry_run:
            skipped += 1
            continue
        try:
            html_email = _render_table(rows, within_days)
            send_email(subject=subject, html=html_email, to=[email])
            for r in rows:
                try:
                    log_mail(r["task_id"], email, subject, reason="due_time")
                except Exception:
                    pass

                if advance_on_send:
                    tid = r["task_id"]
                    if tid not in advanced_tasks:
                        try:
                            insert_event(tid, None, f"AUTO_RESET: mailed to {email} at {datetime.now(TZ).isoformat()}")
                            advanced_tasks.add(tid)
                        except Exception:
                            pass

            sent += 1
        except SchedulerEmailException:
            skipped += 1

    return {
        "rows_found": len(due_rows),
        "distinct_recipients": len(per_email),
        "sent": sent,
        "skipped": skipped,
    }
