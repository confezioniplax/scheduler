@echo off
setlocal

REM ==== PLAX - Scheduler Manutenzioni (Windows 11) ====

REM Percorsi assoluti
set "PROJ=C:\Users\Plax\Desktop\Apps\scheduler"
set "PY=%PROJ%\.venv\Scripts\python.exe"
set "LOG=%PROJ%\plax_scheduler.log"

REM Lavora nella cartella del progetto
cd /d "%PROJ%"

REM (opzionale) imposta UTF-8 per log pulito
chcp 65001 >nul

REM Header di log
echo [%DATE% %TIME%] ==== START ==== >> "%LOG%"
echo [INFO] CWD=%CD% >> "%LOG%"
"%PY%" --version >> "%LOG%" 2>&1

REM ---- ESECUZIONE JOB ----
"%PY%" -m app.main send --within 7 --throttle 7 >> "%LOG%" 2>&1
set "ERR=%ERRORLEVEL%"

REM Footer di log
echo [%DATE% %TIME%] ==== END err=%ERR% ==== >> "%LOG%"

endlocal & exit /b %ERR%
