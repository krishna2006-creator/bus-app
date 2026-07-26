@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ==========================================
echo   FIREBASE HOSTING DEPLOYMENT
echo ==========================================
echo.

set "GREEN=[92m"
set "YELLOW=[93m"
set "RED=[91m"
set "NC=[0m"

echo %YELLOW%Step 1: Building Flutter Web...%NC%
echo.

flutter build web --release

if errorlevel 1 (
    echo %RED%Error: Flutter build failed%NC%
    pause
    exit /b 1
)

echo %GREEN%✓ Flutter web build complete%NC%
echo.

echo %YELLOW%Step 2: Deploying to Firebase...%NC%
echo.

firebase deploy --only hosting --project bustracker-bc73f

if errorlevel 1 (
    echo %RED%Error: Firebase deploy failed%NC%
    pause
    exit /b 1
)

echo.
echo ==========================================
echo   DEPLOYMENT COMPLETE!
echo ==========================================
echo.
echo %GREEN%Your app is now live at:%NC%
echo https://bustracker-bc73f.web.app
echo.
echo %YELLOW%Next steps:%NC%
echo 1. Update CORS_ORIGINS in Railway with this URL
echo 2. Test the app
echo 3. Check browser console for any errors
echo.
pause