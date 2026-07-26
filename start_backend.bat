@echo off
setlocal enabledelayedexpansion
set PORT=8000
set DATABASE_URL=sqlite:///./bus_tracking_backend/bus_tracking.db
set CORS_ORIGINS=*
cd /d %~dp0
echo Initializing database...
python -m bus_tracking_backend.init_db 2>nul
if errorlevel 1 (
    echo Database already exists, skipping init...
)
echo Starting backend server on 0.0.0.0:!PORT!...
uvicorn bus_tracking_backend.main:app --host 0.0.0.0 --port !PORT!
endlocal
