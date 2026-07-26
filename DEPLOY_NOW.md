# 🚀 DEPLOY NOW - Step-by-Step Instructions

## **Your code is ready! Follow these EXACT steps to deploy.**

---

## **PART 1: DEPLOY BACKEND TO RAILWAY (5 minutes)**

### **Step 1.1: Go to Railway**
1. Open https://railway.app in your browser
2. Sign up / Login with GitHub

### **Step 1.2: Create Project**
1. Click **"New Project"**
2. Select **"Deploy from GitHub repo"**
3. Find and select your **`bus-app`** repository
4. Railway will start building automatically
5. **Wait for build to complete** (you'll see "Deploy succeeded")
6. Your backend URL will be something like:
   ```
   https://bus-tracking-backend-production.up.railway.app
   ```
7. **COPY THIS URL** - you'll need it later

### **Step 1.3: Add PostgreSQL Database**
1. In your Railway project, click **"+ New"**
2. Select **"Database"**
3. Click **"PostgreSQL"**
4. Railway will create it and show you connection details
5. Click on the PostgreSQL service that was created
6. Click the **"Connect"** tab
7. You'll see a variable like:
   ```
   DATABASE_URL = postgresql://user:pass@host:5432/railway
   ```
8. **COPY THE DATABASE_URL**

### **Step 1.4: Configure Environment Variables**
1. Go back to your **backend** service (the main one)
2. Click the **"Variables"** tab
3. Click **"+ New Variable"** and add EACH of these:

#### **Required Variables:**

**Variable 1:**
- Name: `DATABASE_URL`
- Value: `${{Postgres.DATABASE_URL}}`
- (Use the dropdown to select from PostgreSQL service)

**Variable 2:**
- Name: `ENVIRONMENT`
- Value: `production`

**Variable 3:**
- Name: `SECRET_KEY`
- Value: Generate one using:
  ```bash
  python -c "import secrets; print(secrets.token_hex(32))"
  ```
  OR use this one (CHANGE IT!):
  ```
  abc123def456ghi789jkl012mno345pqrs678tuv901wxy234zab567cde890fgh123
  ```

**Variable 4:**
- Name: `ALGORITHM`
- Value: `HS256`

**Variable 5:**
- Name: `ACCESS_TOKEN_EXPIRE_MINUTES`
- Value: `30`

**Variable 6:**
- Name: `WORKERS`
- Value: `2`

**Variable 7:**
- Name: `LOG_LEVEL`
- Value: `info`

**Variable 8 (add this later after Firebase deploy):**
- Name: `CORS_ORIGINS`
- Value: `https://your-project.web.app` (will update after frontend deploy)

4. Click **"Deploy"** or Railway will auto-redeploy

### **Step 1.5: Verify Backend is Working**
1. Go to your Railway backend URL (e.g., `https://bus-tracking-backend-production.up.railway.app`)
2. You should see: **"Bus Tracking Backend is running successfully."**
3. Visit: `https://bus-tracking-backend-production.up.railway.app/health`
4. Should return: `{"status":"ok","environment":"production"}`

5. Visit: `https://bus-tracking-backend-production.up.railway.app/docs`
6. Should show Swagger API documentation

### **Step 1.6: Check Logs**
1. In Railway, click your backend service
2. Click **"Logs"** tab
3. Look for: **"Application startup complete"**
4. If you see errors, share them with me

---

## **PART 2: DEPLOY FRONTEND TO FIREBASE (5 minutes)**

### **Step 2.1: Open Terminal**
1. Open Command Prompt (Windows) or Terminal (Mac/Linux)
2. Navigate to your project folder:
   ```bash
   cd c:\busappvictory
   ```

### **Step 2.2: Install Firebase CLI** (if not installed)
```bash
npm install -g firebase-tools
```

### **Step 2.3: Login to Firebase**
```bash
firebase login
```
- This will open a browser window
- Sign in with your Google account
- Grant permissions

### **Step 2.4: Initialize Firebase Hosting**
```bash
firebase init hosting
```

**When prompted:**
1. Select your Firebase project from the list
2. Public directory: Type `build/web` and press Enter
3. Single-page app: Type `Yes` and press Enter
4. Set up automatic builds: Type `No` and press Enter

### **Step 2.5: Update app_config.dart with YOUR Railway URL**

**CRITICAL STEP**: You must update the Railway URL in Flutter code.

```bash
# Open this file in your editor:
lib/config/app_config.dart
```

Change this line:
```dart
const productionUrl = 'bus-tracking-backend-production.up.railway.app';
```

To your actual Railway backend URL (without https://):
```dart
const productionUrl = 'bus-tracking-backend-production.up.railway.app';  // <-- your actual URL
```

### **Step 2.6: Build Flutter Web**
```bash
flutter build web --release --web-renderer canvaskit
```
Wait for it to complete (takes 2-3 minutes)

### **Step 2.7: Deploy to Firebase**
```bash
firebase deploy --only hosting
```

After deployment, Firebase will give you a URL like:
```
https://your-project.web.app
```
**COPY THIS URL** - you need it for CORS

### **Step 2.8: Update CORS in Railway**
1. Go back to Railway dashboard
2. Open your backend service
3. Click **"Variables"** tab
4. Find `CORS_ORIGINS` variable (or create it if not exists)
5. Update it to:
   ```
   https://your-project.web.app
   ```
   (Replace with your actual Firebase URL)
6. Railway will auto-redeploy

### **Step 2.9: Verify Frontend**
1. Open your Firebase URL: `https://your-project.web.app`
2. The app should load
3. Try logging in
4. Test the features

---

## **PART 3: FINAL CONFIGURATION**

### **Step 3.1: Update Firebase Authorization Domains**
1. Go to https://console.firebase.google.com
2. Select your project
3. Go to **Authentication** → **Settings** → **Authorized domains**
4. Add your Railway backend domain:
   ```
   bus-tracking-backend-production.up.railway.app
   ```
   (or your actual Railway domain)

### **Step 3.2: Test Everything**

**Test Backend:**
```bash
# Health check
curl https://your-railway-url.up.railway.app/health

# API docs
# Visit: https://your-railway-url.up.railway.app/docs
```

**Test Frontend:**
1. Open `https://your-project.web.app`
2. Open browser console (F12)
3. Look for any errors
4. Test login
5. Test location sharing
6. Test WebSocket connection

---

## **QUICK DEPLOYMENT SCRIPT**

If you want to skip manual steps, run this in terminal:

```bash
# Windows:
deploy.bat

# Mac/Linux:
chmod +x deploy.sh && ./deploy.sh
```

The script will guide you through everything.

---

## **TROUBLESHOOTING**

### **"Build failed" in Railway**
- Check **Build Logs** tab in Railway
- Common issue: Missing dependencies
- Fix: Check `requirements.txt` has all packages

### **"Module not found" error**
- Already fixed in your code
- If still happens, check `railway.toml` uses `uvicorn main:app`

### **"Database connection error"**
- Ensure `DATABASE_URL` is set in Railway
- It should be: `${{Postgres.DATABASE_URL}}`

### **"CORS error" in browser**
- Update `CORS_ORIGINS` in Railway with your Firebase URL
- Make sure Firebase URL is included (no trailing slash)

### **"WebSocket connection failed"**
- Check CORS settings
- Verify `wss://` is used (not `ws://`)
- Check Railway logs for WebSocket errors

### **App works locally but not in production**
- Check that `app_config.dart` has correct Railway URL
- Verify environment variables are set in Railway
- Check browser console for errors

---

## **YOUR DEPLOYMENT URLS**

After deployment, you'll have:
- **Backend API**: `https://bus-tracking-backend-production.up.railway.app`
- **Swagger Docs**: `https://bus-tracking-backend-production.up.railway.app/docs`
- **Health Check**: `https://bus-tracking-backend-production.up.railway.app/health`
- **Frontend**: `https://your-project.web.app`

---

## **NEXT STEPS AFTER DEPLOYMENT**

1. ✅ Monitor Railway logs for 24 hours
2. ✅ Test all features from the web app
3. ✅ Set up PostgreSQL backups in Railway
4. ✅ Add custom domain (optional)
5. ✅ Monitor performance metrics in Railway
6. ✅ Set up error tracking (Sentry)

---

## **NEED HELP?**

1. Check Railway logs: Railway Dashboard → Your Service → Logs
2. Check browser console: Press F12 → Console tab
3. Check Firebase logs: Firebase Console → Hosting
4. Share error messages with me

---

## **YOUR APP IS READY TO DEPLOY!**

Everything is configured. Just follow the steps above and your app will be live in 10-15 minutes.

**For 50,000 users on Railway:**
- Free tier: Good for testing (512MB RAM)
- Pro tier ($5/month): Recommended for 50K users
- PostgreSQL Pro ($5/month)
- Redis Pro ($3/month)
- **Total: ~$13/month for 50K users**