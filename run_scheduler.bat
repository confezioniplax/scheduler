@echo off
setlocal

REM ==== PLAX - Scheduler (Windows 11) ====

set "PROJ=C:\Users\Plax\Desktop\Apps\scheduler"
set "PY=%PROJ%\.venv\Scripts\python.exe"
set "LOG=%PROJ%\plax_scheduler.log"

cd /d "%PROJ%"
chcp 65001 >nul

echo [%DATE% %TIME%] ==== START ==== >> "%LOG%"
echo [INFO] CWD=%CD% >> "%LOG%"
"%PY%" --version >> "%LOG%" 2>&1

REM ---- JOB 1: manutenzioni (come prima) ----
echo [%DATE% %TIME%] -- JOB manutenzioni/send -- >> "%LOG%"
"%PY%" -m app.main send --within 7 --throttle 7 >> "%LOG%" 2>&1
set "ERR1=%ERRORLEVEL%"

REM ---- JOB 2: DWH REFRESH ----
echo [%DATE% %TIME%] -- JOB dwh-refresh -- >> "%LOG%"
"%PY%" -m app.main dwh-refresh >> "%LOG%" 2>&1
set "ERR2=%ERRORLEVEL%"

set /a ERR=ERR1+ERR2

echo [%DATE% %TIME%] ==== END err=%ERR% ==== >> "%LOG%"

endlocal & exit /b %ERR%
