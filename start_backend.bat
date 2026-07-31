@echo off
setlocal enabledelayedexpansion
set PORT=8000
set DATABASE_URL=sqlite:///./bus_tracking_backend/bus_tracking.db
set CORS_ORIGINS=*

REM --- Load FIREBASE_KEY from firebase-key.json for local dev ---
REM On Render/Render, set FIREBASE_KEY directly in the dashboard environment.
if exist "bus_tracking_backend\firebase-key.json" (
    for /f "delims=" %%i in ('type "bus_tracking_backend\firebase-key.json"') do set FIREBASE_KEY=%%i
    echo Loaded FIREBASE_KEY from firebase-key.json
) else (
    echo FIREBASE_KEY not found — Firebase features will be disabled or use file fallback
)

cd /d %~dp0
echo Initializing database...
python -m bus_tracking_backend.init_db 2>nul
if errorlevel 1 (
    echo Database already exists, skipping init...
)
echo Starting backend server on 0.0.0.0:!PORT!...
uvicorn bus_tracking_backend.main:app --host 0.0.0.0 --port !PORT!
endlocal
