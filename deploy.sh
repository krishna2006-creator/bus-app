#!/bin/bash
set -e

echo "=========================================="
echo "  BUS TRACKING APP - FULL DEPLOYMENT"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
command -v git >/dev/null 2>&1 || { echo -e "${RED}Error: git is not installed${NC}"; exit 1; }
command -v flutter >/dev/null 2>&1 || { echo -e "${RED}Error: flutter is not installed${NC}"; exit 1; }
command -v node >/dev/null 2>&1 || { echo -e "${RED}Error: node is not installed${NC}"; exit 1; }

echo -e "${GREEN}✓ All prerequisites installed${NC}"
echo ""

# Get Railway URL
echo -e "${YELLOW}Enter your Railway backend URL (e.g., https://your-project.up.railway.app):${NC}"
read -r RAILWAY_URL

if [ -z "$RAILWAY_URL" ]; then
    echo -e "${RED}Error: Railway URL is required${NC}"
    exit 1
fi

echo ""
echo "=========================================="
echo "  STEP 1: UPDATE CONFIGURATION"
echo "=========================================="

# Update app_config.dart with Railway URL
echo "Updating Flutter configuration..."
sed -i "s|bus-tracking-backend-production.up.railway.app|${RAILWAY_URL#https://}|g" lib/config/app_config.dart

echo -e "${GREEN}✓ Configuration updated${NC}"
echo ""

# Get Railway project name for CORS
RAILWAY_DOMAIN=$(echo "$RAILWAY_URL" | sed -E 's|https?://||' | sed -E 's|/.*||')
echo -e "${GREEN}Detected Railway domain: $RAILWAY_DOMAIN${NC}"

echo ""
echo "=========================================="
echo "  STEP 2: COMMIT AND PUSH TO GITHUB"
echo "=========================================="

git add -A
git commit -m "Deploy: Update configuration for production" || true
git push origin main

echo -e "${GREEN}✓ Code pushed to GitHub${NC}"
echo ""

echo ""
echo "=========================================="
echo "  STEP 3: BUILD FLUTTER WEB"
echo "=========================================="

flutter build web --release --web-renderer canvaskit

echo -e "${GREEN}✓ Flutter web build complete${NC}"
echo ""

echo ""
echo "=========================================="
echo "  STEP 4: INSTALL FIREBASE CLI"
echo "=========================================="

if ! command -v firebase &> /dev/null; then
    echo "Installing Firebase CLI..."
    npm install -g firebase-tools
else
    echo -e "${GREEN}✓ Firebase CLI already installed${NC}"
fi

echo ""
echo "=========================================="
echo "  STEP 5: FIREBASE LOGIN"
echo "=========================================="
echo -e "${YELLOW}Please login to Firebase in the browser window...${NC}"
firebase login

echo ""
echo "=========================================="
echo "  STEP 6: DEPLOY TO FIREBASE"
echo "=========================================="

# Check if firebase.json exists
if [ ! -f "firebase.json" ]; then
    echo "Initializing Firebase Hosting..."
    firebase init hosting --project $(firebase projects:list | head -n 2 | tail -n 1 | awk '{print $1}')
fi

firebase deploy --only hosting

echo -e "${GREEN}✓ Frontend deployed to Firebase${NC}"
echo ""

echo ""
echo "=========================================="
echo "  DEPLOYMENT SUMMARY"
echo "=========================================="
echo -e "${GREEN}Backend URL:${NC} $RAILWAY_URL"
echo -e "${GREEN}Backend Health:${NC} $RAILWAY_URL/health"
echo -e "${GREEN}Swagger Docs:${NC} $RAILWAY_URL/docs"
echo ""
echo -e "${YELLOW}NEXT STEPS:${NC}"
echo "1. Update CORS_ORIGINS in Railway with this Firebase URL"
echo "2. Test the API endpoints"
echo "3. Test login from the web app"
echo "4. Monitor Railway logs for any errors"
echo ""
echo -e "${RED}Don't forget to update Railway environment variables:${NC}"
echo "   CORS_ORIGINS=https://your-project.web.app"
echo ""
echo "=========================================="
echo "  DEPLOYMENT COMPLETE!"
echo "=========================================="