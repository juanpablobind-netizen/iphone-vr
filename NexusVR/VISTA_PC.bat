@echo off
cd /d "%~dp0"
py -3 -m venv .venv || goto error
.venv\Scripts\python.exe -m pip install -r windows\requirements.txt || goto error
start "Nexus panel" cmd /c "timeout /t 2 /nobreak >nul & start http://127.0.0.1:8765"
.venv\Scripts\python.exe windows\server.py --capture
:error
pause
