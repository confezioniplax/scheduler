# core/mailer.py
from __future__ import annotations

import os
import smtplib
import mimetypes
from typing import Iterable, Optional, Sequence
from email.message import EmailMessage


class SchedulerEmailException(Exception):
    """Errore generico di invio email nello scheduler."""


def _env_bool(name: str, default: bool = False) -> bool:
    val = os.getenv(name)
    if val is None:
        return default
    return str(val).strip().lower() in {"1", "true", "yes", "on"}


def _get_cfg():
    class Cfg:
        # --- SMTP (semantica PLAX/Gmail come richiesto) ---
        SMTP_HOST: str = os.getenv("SMTP_HOST", "localhost")
        SMTP_PORT: int = int(os.getenv("SMTP_PORT", "587"))
        SMTP_USER: str = os.getenv("SMTP_USER", "")
        SMTP_PASSWORD: str = os.getenv("SMTP_PASSWORD", "")
        SMTP_FROM: str = os.getenv("SMTP_FROM", "no-reply@example.com")
        SMTP_SENDER_NAME: str = os.getenv("SMTP_SENDER_NAME", "").strip()
        SMTP_TLS: bool = _env_bool("SMTP_TLS", True)   # STARTTLS esplicito
        SMTP_TIMEOUT: int = int(os.getenv("SMTP_TIMEOUT", "30"))
    return Cfg()


_CFG = _get_cfg()


def _flatten(items: Optional[Iterable[str]]) -> list[str]:
    """Normalizza, filtra vuoti e dedup (case-insensitive) preservando l'ordine."""
    if not items:
        return []
    out: list[str] = []
    for x in items:
        if not x:
            continue
        s = str(x).strip()
        if s:
            out.append(s)
    seen = set()
    res: list[str] = []
    for e in out:
        k = e.lower()
        if k not in seen:
            seen.add(k)
            res.append(e)
    return res


def _attach_files(msg: EmailMessage, attachments: Optional[Sequence[str]]):
    if not attachments:
        return
    for path in attachments:
        if not path:
            continue
        ctype, encoding = mimetypes.guess_type(path)
        if ctype is None or encoding is not None:
            ctype = "application/octet-stream"
        maintype, subtype = ctype.split("/", 1)
        try:
            with open(path, "rb") as f:
                data = f.read()
            msg.add_attachment(
                data, maintype=maintype, subtype=subtype, filename=os.path.basename(path)
            )
        except FileNotFoundError:
            raise SchedulerEmailException(f"Attachment non trovato: {path}")
        except Exception as ex:
            raise SchedulerEmailException(f"Errore allegando '{path}': {ex}")


def send_email(
    subject: str,
    html: str,
    to: Iterable[str],
    *,
    text: Optional[str] = None,
    cc: Optional[Iterable[str]] = None,
    bcc: Optional[Iterable[str]] = None,
    reply_to: Optional[str] = None,
    attachments: Optional[Sequence[str]] = None,
) -> int:
    """
    Invia una email HTML (con fallback testo) usando la semantica SMTP_* definita nell'ambiente.

    Ritorna il numero totale di destinatari (To+Cc+Bcc) a cui si è tentato l'invio.
    Lancia SchedulerEmailException in caso di errore.
    """
    to_list = _flatten(to)
    cc_list = _flatten(cc)
    bcc_list = _flatten(bcc)

    if not (to_list or cc_list or bcc_list):
        raise SchedulerEmailException("Nessun destinatario fornito.")

    msg = EmailMessage()
    msg["Subject"] = subject

    # Mittente: "Nome <email>" se SMTP_SENDER_NAME presente, altrimenti solo email
    if _CFG.SMTP_SENDER_NAME:
        msg["From"] = f"{_CFG.SMTP_SENDER_NAME} <{_CFG.SMTP_FROM}>"
    else:
        msg["From"] = _CFG.SMTP_FROM

    if to_list:
        msg["To"] = ", ".join(to_list)
    if cc_list:
        msg["Cc"] = ", ".join(cc_list)
    if reply_to:
        msg["Reply-To"] = reply_to

    # Corpo: testo + HTML
    fallback_text = text or "Questa email contiene contenuto HTML."
    msg.set_content(fallback_text)
    msg.add_alternative(html or "<html><body>(vuoto)</body></html>", subtype="html")

    # Allegati (opzionali)
    _attach_files(msg, attachments)

    all_rcpts = to_list + cc_list + bcc_list

    try:
        # Connessione semplice; STARTTLS se SMTP_TLS=true
        server = smtplib.SMTP(_CFG.SMTP_HOST, _CFG.SMTP_PORT, timeout=_CFG.SMTP_TIMEOUT)
        with server as s:
            if _CFG.SMTP_TLS:
                s.starttls()

            if _CFG.SMTP_USER and _CFG.SMTP_PASSWORD:
                s.login(_CFG.SMTP_USER, _CFG.SMTP_PASSWORD)

            s.send_message(msg, to_addrs=all_rcpts)

        return len(all_rcpts)

    except smtplib.SMTPException as ex:
        raise SchedulerEmailException(f"Errore SMTP: {ex}")
    except OSError as ex:
        raise SchedulerEmailException(f"Errore di rete/connessione: {ex}")
