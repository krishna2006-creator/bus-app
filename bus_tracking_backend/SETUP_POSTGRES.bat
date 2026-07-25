@echo off
echo ============================================
echo PostgreSQL Setup for Bus Tracking System
echo ============================================
echo.

echo Step 1: Checking if PostgreSQL is installed...
where psql >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo PostgreSQL is NOT installed!
    echo.
    echo Please install PostgreSQL first:
    echo 1. Go to https://www.postgresql.org/download/windows/
    echo 2. Download PostgreSQL 15 or 16
    echo 3. Run installer with default settings
    echo 4. Remember the password you set for 'postgres' user
    echo.
    echo After installation, restart this script.
    pause
    exit /b 1
)

echo PostgreSQL is installed.
echo.

echo Step 2: Checking if PostgreSQL service is running...
tasklist | findstr "postgres" >nul
if %errorlevel% neq 0 (
    echo Starting PostgreSQL service...
    net start postgresql-x64-15 2>nul || net start postgresql-x64-14 2>nul || net start postgresql 2>nul
    if %errorlevel% neq 0 (
        echo.
        echo Failed to start PostgreSQL service.
        echo Please start it manually from Services or pgAdmin.
        pause
        exit /b 1
    )
    echo PostgreSQL service started.
) else (
    echo PostgreSQL is already running.
)

echo.
echo Step 3: Creating database...
echo.
echo Please enter your PostgreSQL password when prompted.
echo.

cd /d c:\busappvictory\bus_tracking_backend
python init_postgres.py

echo.
echo ============================================
echo Setup Complete!
echo ============================================
echo.
echo Your database is ready at:
echo   postgresql://postgres:postgres@localhost:5432/bus_tracking
echo.
echo To access from other devices on your network:
echo   postgresql://postgres:postgres@YOUR_IP:5432/bus_tracking
echo.
echo To find your IP address:
echo   ipconfig ^| findstr "IPv4"
echo.
pause