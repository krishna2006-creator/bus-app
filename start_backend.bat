@echo off
REM Quick Start Deployment Script for Windows
REM This script sets up and starts the Bus Tracking backend

echo.
echo ================================
echo Bus Tracking Backend - Quick Start
echo ================================
echo.

REM Check if Docker is installed
docker --version >nul 2>&1
if errorlevel 1 (
    echo X Docker is not installed. Please install Docker Desktop.
    echo   Visit: https://www.docker.com/products/docker-desktop
    pause
    exit /b 1
)

echo [OK] Docker is installed
echo.

REM Check if docker-compose is installed
docker-compose --version >nul 2>&1
if errorlevel 1 (
    echo X Docker Compose is not installed.
    echo   It should be included with Docker Desktop.
    pause
    exit /b 1
)

echo [OK] Docker Compose is installed
echo.

REM Check if .env file exists
if not exist "bus_tracking_backend\.env" (
    echo Creating .env file from template...
    copy bus_tracking_backend\.env.example bus_tracking_backend\.env
    echo [OK] .env file created
    echo.
    echo [IMPORTANT] Edit bus_tracking_backend\.env with your Firebase credentials:
    echo   - FCM_SERVER_KEY
    echo   - FCM_PROJECT_ID
    echo   - FCM_SENDER_ID
    echo   - FIREBASE_CREDENTIALS_PATH
    echo.
    pause
)

REM Check if serviceAccountKey.json exists
if not exist "bus_tracking_backend\serviceAccountKey.json" (
    echo.
    echo [WARNING] Firebase service account key not found!
    echo   Download from Firebase Console:
    echo   1. Go to Project Settings
    echo   2. Service Accounts tab
    echo   3. 'Generate new private key'
    echo   4. Save as: bus_tracking_backend\serviceAccountKey.json
    echo.
    pause
)

REM Start Docker Compose
echo.
echo Starting Docker Compose services...
echo (This may take 1-2 minutes on first run)
echo.

docker-compose up --build

echo.
echo ================================
echo Backend is now running!
echo ================================
echo.
echo Access points:
echo   API Documentation: http://localhost:8000/docs
echo   Health Check:      http://localhost:8000/health
echo   MinIO Console:      http://localhost:9001
echo.
echo Test with:
echo   curl http://localhost:8000/health
echo.
echo To stop:
echo   Press Ctrl+C in Docker then: docker-compose down
echo.
pause
