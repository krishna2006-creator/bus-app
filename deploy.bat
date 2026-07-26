@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ==========================================
echo   BUS TRACKING APP - FULL DEPLOYMENT
echo ==========================================
echo.

set "RED=[91m"
set "GREEN=[92m"
set "YELLOW=[93m"
set "NC=[0m"

REM Check prerequisites
where git >nul 2>&1 || { echo %RED%Error: git is not installed%NC% & exit /b 1 }
where flutter >nul 2>&1 || { echo %RED%Error: flutter is not installed%NC% & exit /b 1 }
where node >nul 2>&1 || { echo %RED%Error: node is not installed%NC% & exit /b 1 }

echo %GREEN%✓ All prerequisites installed%NC%
echo.

REM Get Railway URL
set /p RAILWAY_URL="Enter your Railway backend URL (e.g., https://your-project.up.railway.app): "

if "%RAILWAY_URL%"=="" (
    echo %RED%Error: Railway URL is required%NC%
    exit /b 1
)

echo.
echo ==========================================
echo   STEP 1: UPDATE CONFIGURATION
echo ==========================================

REM Update app_config.dart with Railway URL
echo Updating Flutter configuration...
powershell -Command "(Get-Content 'lib/config/app_config.dart') -replace 'bus-tracking-backend-production.up.railway.app', '%RAILWAY_URL:https://=%' | Set-Content 'lib/config/app_config.dart'"

echo %GREEN%✓ Configuration updated%NC%
echo.

REM Get Railway domain for CORS
for /f "delims=" %%a in ('echo %RAILWAY_URL% ^| powershell -Command "$input -replace 'https?://','' -replace '/.*',''"') do set RAILWAY_DOMAIN=%%a
echo %GREEN%Detected Railway domain: %RAILWAY_DOMAIN%%NC%

echo.
echo ==========================================
echo   STEP 2: COMMIT AND PUSH TO GITHUB
echo ==========================================

git add -A
git commit -m "Deploy: Update configuration for production" || echo "Nothing to commit"
git push origin main

echo %GREEN%✓ Code pushed to GitHub%NC%
echo.

echo.
echo ==========================================
echo   STEP 3: BUILD FLUTTER WEB
echo ==========================================

flutter build web --release --web-renderer canvaskit

echo %GREEN%✓ Flutter web build complete%NC%
echo.

echo.
echo ==========================================
echo   STEP 4: INSTALL FIREBASE CLI
echo ==========================================

where firebase >nul 2>&1 || (
    echo Installing Firebase CLI...
    call npm install -g firebase-tools
)

echo %GREEN%✓ Firebase CLI ready%NC%
echo.

echo.
echo ==========================================
echo   STEP 5: FIREBASE LOGIN
echo ==========================================
echo %YELLOW%Please login to Firebase in the browser window...%NC%
call firebase login

echo.
echo ==========================================
echo   STEP 6: DEPLOY TO FIREBASE
echo ==========================================

if not exist "firebase.json" (
    echo Initializing Firebase Hosting...
    call firebase init hosting
)

call firebase deploy --only hosting

echo %GREEN%✓ Frontend deployed to Firebase%NC%
echo.

echo.
echo ==========================================
echo   DEPLOYMENT SUMMARY
echo ==========================================
echo %GREEN%Backend URL:%NC% %RAILWAY_URL%
echo %GREEN%Backend Health:%NC% %RAILWAY_URL%/health
echo %GREEN%Swagger Docs:%NC% %RAILWAY_URL%/docs
echo.
echo %YELLOW%NEXT STEPS:%NC%
echo 1. Update CORS_ORIGINS in Railway with this Firebase URL
echo 2. Test the API endpoints
echo 3. Test login from the web app
echo 4. Monitor Railway logs for any errors
echo.
echo %RED%Don't forget to update Railway environment variables:%NC%
echo    CORS_ORIGINS=https://your-project.web.app
echo.
echo ==========================================
echo   DEPLOYMENT COMPLETE!
echo ==========================================

pause