@echo off
echo ============================================
echo Bus Tracking Backend - Deployment Script
echo ============================================
echo.

REM Check if PostgreSQL is running
echo [1/5] Checking PostgreSQL...
tasklist | findstr "postgres" >nul
if %errorlevel% neq 0 (
    echo WARNING: PostgreSQL is not running!
    echo The app will use SQLite as fallback.
    echo.
) else (
    echo PostgreSQL is running.
)
echo.

REM Install dependencies
echo [2/5] Installing dependencies...
cd /d c:\busappvictory\bus_tracking_backend
pip install -r requirements.txt
if %errorlevel% neq 0 (
    echo ERROR: Failed to install dependencies
    pause
    exit /b 1
)
echo Dependencies installed.
echo.

REM Create database if not exists
echo [3/5] Creating database tables...
python init_postgres.py 2>nul
echo Tables created (if any).
echo.

REM Kill existing process on port 8000
echo [4/5] Stopping existing server...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :8000 ^| findstr LISTENING') do (
    echo Killing process %%a on port 8000
    taskkill /f /pid %%a >nul 2>&1
)
echo.

REM Start backend with Uvicorn (WebSocket-compatible)
echo [5/5] Starting backend with Uvicorn...
echo.
echo ============================================
echo Backend starting...
echo API: http://localhost:8000
echo Docs: http://localhost:8000/docs
echo ============================================
echo.
uvicorn bus_tracking_backend.main:app --host 0.0.0.0 --port 8000 --reload --ws ping_interval 30
echo.
echo ============================================
echo Backend started successfully!
echo API: http://localhost:8000
echo Docs: http://localhost:8000/docs
echo ============================================
pause