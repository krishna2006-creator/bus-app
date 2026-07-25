#!/bin/bash

# Firebase + WebSocket Connection Test Suite
# Run this script to verify everything is set up correctly

echo "=========================================="
echo "Bus Tracker - Firebase Setup Verification"
echo "=========================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check 1: Flutter installed
echo -e "${YELLOW}[1/8] Checking Flutter installation...${NC}"
if command -v flutter &> /dev/null; then
    echo -e "${GREEN}✓ Flutter found${NC}"
    flutter --version
else
    echo -e "${RED}✗ Flutter not found${NC}"
    exit 1
fi
echo ""

# Check 2: Android SDK
echo -e "${YELLOW}[2/8] Checking Android SDK...${NC}"
if [ -d "$ANDROID_HOME" ]; then
    echo -e "${GREEN}✓ Android SDK found at: $ANDROID_HOME${NC}"
else
    echo -e "${RED}✗ ANDROID_HOME not set${NC}"
fi
echo ""

# Check 3: google-services.json exists
echo -e "${YELLOW}[3/8] Checking google-services.json...${NC}"
if [ -f "android/app/google-services.json" ]; then
    echo -e "${GREEN}✓ google-services.json found${NC}"
    # Check for Firebase credentials
    if grep -q "321252487044" android/app/google-services.json; then
        echo -e "${GREEN}✓ Firebase project ID found (bustracker-aca41)${NC}"
    fi
else
    echo -e "${RED}✗ google-services.json not found${NC}"
fi
echo ""

# Check 4: firebase_options.dart
echo -e "${YELLOW}[4/8] Checking firebase_options.dart...${NC}"
if [ -f "lib/firebase_options.dart" ]; then
    echo -e "${GREEN}✓ firebase_options.dart found${NC}"
    if grep -q "bustracker-aca41" lib/firebase_options.dart; then
        echo -e "${GREEN}✓ Real Firebase credentials detected${NC}"
    elif grep -q "YOUR_" lib/firebase_options.dart; then
        echo -e "${RED}✗ Placeholder credentials still present${NC}"
    fi
else
    echo -e "${RED}✗ firebase_options.dart not found${NC}"
fi
echo ""

# Check 5: Dependencies in pubspec.yaml
echo -e "${YELLOW}[5/8] Checking required dependencies...${NC}"
missing_deps=()
for dep in "firebase_core" "firebase_auth" "google_sign_in" "web_socket_channel" "geolocator"; do
    if grep -q "$dep" pubspec.yaml; then
        echo -e "${GREEN}✓ $dep found${NC}"
    else
        echo -e "${RED}✗ $dep missing${NC}"
        missing_deps+=("$dep")
    fi
done
echo ""

# Check 6: Android Gradle configuration
echo -e "${YELLOW}[6/8] Checking Android Gradle...${NC}"
if grep -q "com.google.gms.google-services" android/app/build.gradle.kts; then
    echo -e "${GREEN}✓ Google services plugin configured${NC}"
else
    echo -e "${RED}✗ Google services plugin not configured${NC}"
fi

if grep -q "firebase-bom" android/app/build.gradle.kts; then
    echo -e "${GREEN}✓ Firebase BoM configured${NC}"
else
    echo -e "${RED}✗ Firebase BoM not configured${NC}"
fi
echo ""

# Check 7: Firebase Auth Service
echo -e "${YELLOW}[7/8] Checking firebase_auth_service.dart...${NC}"
if grep -q "import 'dart:convert'" lib/services/firebase_auth_service.dart; then
    echo -e "${GREEN}✓ dart:convert import found${NC}"
else
    echo -e "${RED}✗ Missing dart:convert import${NC}"
fi

if grep -q "import 'package:http/http.dart'" lib/services/firebase_auth_service.dart; then
    echo -e "${GREEN}✓ http package import found${NC}"
else
    echo -e "${RED}✗ Missing http package import${NC}"
fi
echo ""

# Check 8: WebSocket Manager
echo -e "${YELLOW}[8/8] Checking websocket_manager.dart...${NC}"
if grep -q "await _channel!.ready.timeout" lib/services/websocket_manager.dart; then
    echo -e "${GREEN}✓ WebSocket timeout configured${NC}"
else
    echo -e "${YELLOW}⚠ WebSocket timeout may not be optimized${NC}"
fi

if grep -q "wss://" lib/services/websocket_manager.dart; then
    echo -e "${GREEN}✓ WSS (secure) protocol support added${NC}"
fi
echo ""

echo "=========================================="
echo "Verification Complete!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo "1. Run: flutter pub get"
echo "2. Run: flutter run"
echo "3. Test Google Sign-In"
echo "4. Monitor console for connection messages"
echo "5. Start backend: python bus_tracking_backend/main.py"
echo ""
