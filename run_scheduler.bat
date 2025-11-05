@echo off
setlocal enabledelayedexpansion

REM ==== PLAX - Scheduler Manutenzioni (Windows 11) ====
REM Percorso progetto
set PROJ=C:\Users\leone\OneDrive\Desktop\Plax\apps\scheduler

REM Vai nella cartella progetto ( /d cambia anche drive se serve )
cd /d "%PROJ%"

REM Attiva il virtualenv
call .venv\Scripts\activate.bat

REM Info utili
echo [%DATE% %TIME%] Working dir: %CD%
python --version

REM === ESECUZIONE ===
REM Per il primo test usa DRY-RUN (non invia email)
REM python -m app.main send --within 7 --throttle 7 --dry-run

REM Invio reale:
python -m app.main send --within 7 --throttle 7 >> "%PROJ%\plax_scheduler.log" 2>&1

REM Mantieni la finestra visibile
echo.
echo Finito. Premi un tasto per chiudere...
pause >nul

endlocal
