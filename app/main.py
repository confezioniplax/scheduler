# app/main.py
# MIT License (c) 2025 Riccardo Leonelli

from __future__ import annotations

import os
import argparse
from datetime import datetime
from zoneinfo import ZoneInfo
from pathlib import Path

# Carica .env dalla radice progetto (un livello sopra "app")
from dotenv import load_dotenv
load_dotenv(dotenv_path=Path(__file__).resolve().parent.parent / ".env")

# Fuso orario (fallback Europe/Rome)
os.environ.setdefault("TZ", os.getenv("TZ", "Europe/Rome"))

# Import dal package app.*
from .jobs.manutenzioni import (
    list_due,
    list_events,
    insert_event,
    run_send,
)
from app.jobs import manutenzioni
from app.jobs import dwh_refresh   # <-- nuovo import

TZ = ZoneInfo(os.getenv("TZ", "Europe/Rome"))


def cmd_due(args: argparse.Namespace) -> None:
    within = int(args.within)
    rows = list_due(within)
    if not rows:
        print(f"Nessuna scadenza entro {within} giorni.")
        return
    print(f"Scadenze entro {within} giorni:")
    for r in rows:
        task_id = r.get("task_id")
        title = r.get("title")
        dept  = r.get("department_name") or r.get("area_label") or ""
        due   = r.get("next_due_at")
        print(f"- [{task_id}] {title} | {due} | {dept}")


def cmd_send(args: argparse.Namespace) -> None:
    within = int(args.within)
    throttle = int(args.throttle)
    dry_run = bool(args.dry_run)
    res = run_send(
        within_days=within,
        throttle_days=throttle,
        dry_run=dry_run,
        advance_on_send=not args.no_advance
    )
    print("Invio completato:", res)


def cmd_mark_done(args: argparse.Namespace) -> None:
    task_id = int(args.task_id)
    op_id = int(args.operator_id) if args.operator_id is not None else None
    notes = args.notes
    inserted = insert_event(task_id, op_id, notes)
    print(f"Inserito evento per task {task_id}: rows={inserted}")


def cmd_events(args: argparse.Namespace) -> None:
    task_id = int(args.task_id)
    rows = list_events(task_id)
    if not rows:
        print("Nessun evento trovato.")
        return
    print(f"Eventi per task {task_id}:")
    for r in rows:
        done = r.get("done_at")
        opid = r.get("done_by_operator_id")
        who = f"op:{opid}" if opid else "-"
        print(f"- {done} | {who} | {r.get('first_name','') } {r.get('last_name','') } | {r.get('notes','')}")

def cmd_dwh_refresh(args: argparse.Namespace) -> None:
    res = dwh_refresh.run(dry_run=args.dry_run)
    print(res)




def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="scheduler-manutenzioni",
        description="Scheduler manutenzioni (invio email + registrazione eventi)."
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    # due
    pdue = sub.add_parser("due", help="Mostra le scadenze entro N giorni.")
    pdue.add_argument("--within", type=int, default=int(os.getenv("MAINTENANCE_WITHIN", "7")),
                      help="Giorni da verificare (default da .env).")
    pdue.set_defaults(func=cmd_due)

    # send
    psend = sub.add_parser("send", help="Invia email (rispetta throttle/log).")
    psend.add_argument("--within", type=int, default=int(os.getenv("MAINTENANCE_WITHIN", "7")),
                       help="Giorni da verificare.")
    psend.add_argument("--throttle", type=int, default=int(os.getenv("MAINTENANCE_THROTTLE", "7")),
                       help="Finestra anti-duplicazione (giorni).")
    psend.add_argument("--dry-run", action="store_true", help="Mostra cosa invierebbe, senza inviare.")
    psend.add_argument("--no-advance", action="store_true",
                       help="Non creare eventi AUTO_RESET dopo l'invio.")
    psend.set_defaults(func=cmd_send)

    # mark-done
    pmk = sub.add_parser("mark-done", help="Registra manualmente un intervento.")
    pmk.add_argument("task_id", type=int, help="ID del task.")
    pmk.add_argument("--operator-id", type=int, default=None, help="ID operatore (facoltativo).")
    pmk.add_argument("--notes", type=str, default="", help="Note intervento.")
    pmk.set_defaults(func=cmd_mark_done)

    # events
    pe = sub.add_parser("events", help="Storico interventi di un task.")
    pe.add_argument("task_id", type=int, help="ID del task.")
    pe.set_defaults(func=cmd_events)

    # --- DWH REFRESH ---
    pdwh = sub.add_parser("dwh-refresh", help="Ricostruisce completamente il DWH da dwh_executions.sql")
    pdwh.add_argument("--dry-run", action="store_true",
                      help="Non esegue le query, le logga soltanto.")
    pdwh.set_defaults(func=cmd_dwh_refresh)
    
    return p


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
