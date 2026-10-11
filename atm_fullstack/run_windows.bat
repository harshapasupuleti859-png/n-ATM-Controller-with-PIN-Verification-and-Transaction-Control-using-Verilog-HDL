@echo off
cd /d "%~dp0"
echo Starting ATM software... open http://localhost:8000
start "" http://localhost:8000
python app.py
pause
