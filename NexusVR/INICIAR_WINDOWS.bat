@echo off
cd /d "%~dp0"
where py >nul 2>nul
if errorlevel 1 (
 echo Instala Python 3 desde https://www.python.org/downloads/windows/ y vuelve a ejecutar.
 pause
 exit /b 1
)
start "Nexus panel" cmd /c "timeout /t 2 /nobreak >nul & start http://127.0.0.1:8765"
py -3 windows\server.py
pause
