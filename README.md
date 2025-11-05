# 🧭 PLAX Scheduler Manutenzioni  
**Versione:** 1.0  
**Autore:** Riccardo Leonelli  
**Licenza:** MIT License  
**Ultimo aggiornamento:** Novembre 2025  

---

## 📘 Descrizione generale
Il **PLAX Scheduler Manutenzioni** è un programma Python che automatizza la gestione e l’invio di email di promemoria per le **scadenze di manutenzione programmata**.

Ogni giorno lo scheduler:
1. Controlla nel database aziendale (`archivio`, MySQL) la vista `vw_maintenance_next_due`.
2. Trova tutte le attività di manutenzione con scadenza entro **N giorni** (es. 7 giorni).
3. Invia un’email riepilogativa ai destinatari predefiniti.
4. Registra nel log l’invio per evitare duplicazioni (meccanismo *throttle*).
5. Scrive nel file `plax_scheduler.log` la data, l’ora e l’esito dell’esecuzione.

---

## ⚙️ Funzionamento sulla VM (Windows 11)

### 📁 Percorso installazione
```
C:\Users\Plax\Desktop\Apps\scheduler\
```

### 📂 Struttura principale
```
scheduler/
├── app/
│   ├── main.py                # Entry point dello scheduler
│   ├── core/                  # Componenti base (db, mailer, utils)
│   ├── jobs/                  # Logica di business (manutenzioni)
│   └── sql/query/             # Query SQL per le manutenzioni
├── .env                       # Credenziali DB e SMTP
├── run_scheduler.bat          # Script batch per esecuzione automatica
├── plax_scheduler.log         # Log con data, ora, stato
└── requirements.txt           # Dipendenze Python
```

---

## ⚙️ File di configurazione (.env)
```dotenv
API_MYSQL_HOSTNAME=localhost
API_MYSQL_PORT=3307
API_MYSQL_USERNAME=root
API_MYSQL_PASSWORD=root
API_MYSQL_DB=plaxr

SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=confezioniplax@gmail.com
SMTP_PASSWORD=ygqznrzvgssxfrcz
SMTP_FROM=riccardo@plaxpackaging.it
SMTP_SENDER_NAME=PLAX
SMTP_TLS=true

SCHEDULER_DEFAULT_TO=massimo@plaxpackaging.it
SCHEDULER_USE_DB_RECIPIENTS=0
MAINTENANCE_WITHIN=7
MAINTENANCE_THROTTLE=7
TZ=Europe/Rome
```

---

## 🧰 Ambiente virtuale
Il progetto usa un ambiente virtuale Python dedicato, creato in:
```
C:\Users\Plax\Desktop\Apps\scheduler\.venv\
```

Lo scheduler lo esegue automaticamente tramite:
```
C:\Users\Plax\Desktop\Apps\scheduler\.venv\Scripts\python.exe
```

---

## ⏰ Automazione giornaliera (Task Scheduler)
Nel **Task Scheduler di Windows** è configurata l’attività:

| Parametro | Valore |
|------------|---------|
| **Nome** | PLAX Scheduler Manutenzioni |
| **Programma/script** | `cmd.exe` |
| **Argomenti** | `/c "C:\Users\Plax\Desktop\Apps\scheduler\run_scheduler.bat"` |
| **Avvio in** | `C:\Users\Plax\Desktop\Apps\scheduler` |
| **Orario** | 08:00 ogni giorno |

✅ L’attività:
- Parte anche se l’utente non è connesso.
- Scrive automaticamente nel log `plax_scheduler.log`.
- Restituisce **codice 0x0** (successo) in caso di esecuzione corretta.

---

## 🧾 Log file
Percorso:
```
C:\Users\Plax\Desktop\Apps\scheduler\plax_scheduler.log
```

Esempio di contenuto:
```
[06/11/2025 08:00:00] ==== START ====
[INFO] CWD=C:\Users\Plax\Desktop\Apps\scheduler
Python 3.13.9
Invio completato: {'rows_found': 2, 'distinct_recipients': 1, 'sent': 1, 'skipped': 0}
[06/11/2025 08:00:05] ==== END err=0 ====
```

---

## 🧪 Test manuale
Per eseguire manualmente lo scheduler:

```powershell
cd "C:\Users\Plax\Desktop\Apps\scheduler"
.\.venv\Scripts\Activate.ps1
python -m app.main send --within 7 --throttle 7
```

oppure con doppio click su:
```
run_scheduler.bat
```

---

## 🛠️ Manutenzione e aggiornamenti

### 📦 Aggiornare le dipendenze
```powershell
cd "C:\Users\Plax\Desktop\Apps\scheduler"
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### ⚙️ Modificare frequenza e limiti
- `MAINTENANCE_WITHIN`: giorni di anticipo scadenza (es. 7 → entro una settimana)  
- `MAINTENANCE_THROTTLE`: giorni di “anti-duplicazione” tra due invii consecutivi (es. 7)

### 🧩 Controllare l’esecuzione
- **Task Scheduler → Libreria → PLAX Scheduler Manutenzioni**
- Verifica le colonne:
  - **Ultimo risultato:** 0x0 = OK
  - **Ultima esecuzione:** ora recente
- Controlla `plax_scheduler.log` per i dettagli.

---

## 🧱 Setup realizzato nella VM

| Step | Stato | Descrizione |
|------|--------|-------------|
| Installazione Python 3.13 + venv | ✅ | Ambiente virtuale locale configurato |
| Clone del progetto Git | ✅ | Cartella `C:\Users\Plax\Desktop\Apps\scheduler\` |
| File `.env` configurato | ✅ | Credenziali DB e SMTP reali |
| Popolamento DB `plaxr` | ✅ | Tabelle `maintenance_*` e vista `vw_maintenance_next_due` |
| Test manuale invio email | ✅ | Email ricevuta con successo |
| Script `run_scheduler.bat` | ✅ | Funzionante e loggante |
| Task “PLAX Scheduler Manutenzioni” | ✅ | Pianificato giornalmente alle 08:00 |
| Log operativo | ✅ | File `plax_scheduler.log` aggiornato giornalmente |

---

## 🏁 Riepilogo
✅ Scheduler giornaliero funzionante su Windows 11  
✅ Invio email automatico scadenze manutenzione  
✅ Log completo e tracciabile  
✅ Configurazione stabile e riutilizzabile su altre VM o server

---

© 2025 Riccardo Leonelli — MIT License  
Sistema di automazione manutenzioni PLAX Packaging.
