# app/jobs/dwh_refresh.py
# Ricostruzione completa del DWH eseguendo app/sql/executions/dwh_executions.sql

from __future__ import annotations

import logging
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List

from app.core.db import DbManager, MySQLDb, QueryType

logger = logging.getLogger(__name__)

# Percorso del file SQL con tutti i CREATE/INSERT del DWH
SQL_FILE = (
    Path(__file__)
    .resolve()
    .parents[1]  # sali da jobs/ a app/
    / "sql"
    / "executions"
    / "dwh_executions.sql"
)


def _load_sql_statements(path: Path) -> List[str]:
    """
    Carica il file .sql e lo splitta in statement singoli.
    - Rimuove le righe che iniziano con "--"
    - Spezza sui ';'
    - Scarta gli statement vuoti

    ATTENZIONE: va bene perché nel tuo dwh_executions.sql NON ci sono
    DELIMITER / procedure / trigger.
    """
    text = path.read_text(encoding="utf-8")

    # togli commenti "-- ..." e righe vuote
    lines: List[str] = []
    for raw in text.splitlines():
        stripped = raw.strip()
        if not stripped:
            continue
        if stripped.startswith("--"):
            continue
        lines.append(raw)

    cleaned = "\n".join(lines)

    stmts: List[str] = []
    for chunk in cleaned.split(";"):
        stmt = chunk.strip()
        if stmt:
            stmts.append(stmt)
    return stmts


def _guess_query_type(sql: str) -> QueryType:
    """
    Decide il tipo SOLO per logging/metriche.

    Nota: nel tuo DbManager, qualsiasi tipo diverso da GET viene
    eseguito con execute() + commit() senza fetch.
    Per questo trattiamo DDL (CREATE/DROP/...) come INSERT.
    """
    if not sql.strip():
        return QueryType.GET

    first = sql.strip().split(None, 1)[0].upper()

    # DDL -> usiamo INSERT come "tipo generico di scrittura"
    if first in ("CREATE", "DROP", "ALTER", "TRUNCATE"):
        return QueryType.INSERT

    if first == "INSERT":
        return QueryType.INSERT
    if first in ("UPDATE", "REPLACE"):
        return QueryType.UPDATE
    if first == "DELETE":
        return QueryType.DELETE

    # il resto (SELECT, USE, SET, ecc.) lo trattiamo come GET
    return QueryType.GET


def run(*, dry_run: bool = False) -> Dict[str, Any]:
    """
    Job principale chiamato dal tuo scheduler.

    - Legge dwh_executions.sql
    - Esegue TUTTI gli statement in ordine, dentro una singola connessione MySQL
    - Logga in plax_scheduler.log
    - Restituisce un dict riassuntivo
    """
    start_ts = datetime.now()

    if not SQL_FILE.exists():
        msg = f"File SQL DWH non trovato: {SQL_FILE}"
        logger.error(msg)
        raise FileNotFoundError(msg)

    stmts = _load_sql_statements(SQL_FILE)
    total = len(stmts)
    logger.info("DWH_REFRESH start: file=%s, statements=%s", SQL_FILE, total)

    if dry_run:
        # solo logga gli statement senza eseguirli
        for i, stmt in enumerate(stmts, 1):
            one_line = " ".join(stmt.split())
            logger.info("[DRY-RUN] #%s: %s", i, one_line[:200])
        return {"ok": True, "dry_run": True, "statements": total}

    executed = 0

    # Usa la stessa infrastruttura DB del resto del progetto
    with DbManager(MySQLDb()) as db:
        for i, stmt in enumerate(stmts, 1):
            qtype = _guess_query_type(stmt)
            preview = " ".join(stmt.split())[:120]

            logger.info("Esecuzione statement %s/%s (%s): %s", i, total, qtype.name, preview)

            try:
                db.execute_query(stmt, None, fetchall=False, query_type=qtype)
                executed += 1
            except Exception as e:
                logger.exception(
                    "Errore su statement %s/%s (type=%s): %s\nSQL: %s",
                    i, total, qtype.name, e, stmt,
                )
                raise

    elapsed = (datetime.now() - start_ts).total_seconds()
    logger.info("DWH_REFRESH completato: executed=%s/%s, elapsed=%.1fs", executed, total, elapsed)

    return {
        "ok": True,
        "statements": total,
        "executed": executed,
        "elapsed_sec": elapsed,
    }
