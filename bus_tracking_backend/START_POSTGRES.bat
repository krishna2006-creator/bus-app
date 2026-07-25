@echo off
echo ============================================
echo Starting PostgreSQL Server
echo ============================================
echo.

REM Check if PostgreSQL is installed
echo [1/3] Checking PostgreSQL installation...
if exist "C:\Program Files\PostgreSQL\15\bin\pg_ctl.exe" (
    set PGHOME=C:\Program Files\PostgreSQL\15
    set PGDATA=C:\Program Files\PostgreSQL\15\data
    set PGPORT=5432
) else if exist "C:\Program Files\PostgreSQL\14\bin\pg_ctl.exe" (
    set PGHOME=C:\Program Files\PostgreSQL\14
    set PGDATA=C:\Program Files\PostgreSQL\14\data
    set PGPORT=5432
) else (
    echo PostgreSQL not found!
    echo.
    echo Please install PostgreSQL from:
    echo https://www.postgresql.org/download/windows/
    echo.
    echo Or download portable PostgreSQL:
    echo https://github.com/EnterpriseDB/postgres_server_binaries/releases
    pause
    exit /b 1
)

echo Found PostgreSQL at: %PGHOME%
echo.

REM Start PostgreSQL service
echo [2/3] Starting PostgreSQL...
cd /d "%PGHOME%\bin"

REM Initialize database if not exists
if not exist "%PGDATA%\PG_VERSION" (
    echo Initializing database cluster...
    initdb -D "%PGDATA%" -U postgres -A trust -E utf8
)

REM Start PostgreSQL
echo Starting PostgreSQL server...
pg_ctl -D "%PGDATA%" -l "%PGHOME%\logfile.txt" start

if %errorlevel% neq 0 (
    echo PostgreSQL may already be running or failed to start.
    echo Checking if already running...
    tasklist | findstr "postgres" >nul
    if %errorlevel% equ 0 (
        echo PostgreSQL is already running.
    ) else (
        echo Failed to start PostgreSQL. Check logs at: %PGHOME%\logfile.txt
        pause
        exit /b 1
    )
) else (
    echo PostgreSQL started successfully.
)

echo.
echo [3/3] Creating database and user...
echo.

REM Create database if not exists
cd /d c:\busappvictory\bus_tracking_backend
python init_postgres.py

echo.
echo ============================================
echo PostgreSQL is READY!
echo ============================================
echo.
echo Local access:
echo   postgresql://postgres:@localhost:5432/bus_tracking
echo.
echo Network access (from other devices):
echo   postgresql://postgres:@YOUR_IP:5432/bus_tracking
echo.
echo To find YOUR IP address:
echo   ipconfig | findstr "IPv4"
echo.
echo Your IP address appears like: 192.168.x.x or 10.x.x.x
echo.
echo Example connection string for Flutter app:
echo   DATABASE_URL=postgresql://postgres:@192.168.1.100:5432/bus_tracking
echo.
pause