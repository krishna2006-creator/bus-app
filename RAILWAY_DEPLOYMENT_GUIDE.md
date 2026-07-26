# 🚀 Railway Deployment Guide for 50,000+ Users
# Bus Tracking Backend - Error-Free Deployment

## ✅ WHAT THIS GUIDE COVERS
- Step-by-step Railway deployment
- PostgreSQL database setup
- Environment variables configuration
- Common errors and their fixes
- Scaling for 50,000+ users

---

## 📋 PRE-REQUISITES
1. GitHub account with your code pushed
2. Railway account (sign up at railway.app)
3. Your project already has: `railway.toml`, `Dockerfile`, `requirements.txt`

---

## 🚂 STEP 1: DEPLOY BACKEND TO RAILWAY

### **1.1 Create New Project**
1. Go to https://railway.app
2. Click **"New Project"**
3. Select **"Deploy from GitHub repo"**
4. Choose your repository: `bus-app`
5. Click **"Deploy Now"**

### **1.2 Add PostgreSQL Database**
1. In your project, click **"+ New"**
2. Select **"Database"** → **"PostgreSQL"**
3. Railway creates a PostgreSQL instance
4. **IMPORTANT**: Copy these values (click "Connect" → "Variables"):
   - `DATABASE_URL` = `postgresql://user:pass@host:5432/railway`

### **1.3 Add Redis (For WebSocket Scaling)**
1. Click **"+ New"** → **"Database"** → **"Redis"**
2. Copy the `REDIS_URL` variable

### **1.4 Configure Environment Variables**
Click on your backend service → **"Variables"** tab → Add these:

```bash
# Required Variables
DATABASE_URL=${{Postgres.DATABASE_URL}}
REDIS_URL=${{Redis.REDIS_URL}}
ENVIRONMENT=production
SECRET_KEY=your-super-secret-jwt-key-min-32-characters-long-1234567890
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
WORKERS=2
LOG_LEVEL=info

# CORS - Add your frontend domains (add your Firebase/Netlify URL later)
CORS_ORIGINS=https://your-project.web.app,https://your-project.netlify.app

# Optional: FCM (Firebase Cloud Messaging)
FCM_SERVER_KEY=your-fcm-server-key
FCM_PROJECT_ID=your-project-id
FCM_SENDER_ID=your-sender-id

# Optional: File Uploads (MinIO/S3)
MINIO_BUCKET_DOCUMENTS=documents
MINIO_BUCKET_ANNOUNCEMENTS=announcements
```

**⚠️ CRITICAL: Generate a strong SECRET_KEY**
```bash
# Run this in terminal to generate:
openssl rand -hex 32
# OR use: python -c "import secrets; print(secrets.token_hex(32))"
```

### **1.5 Update railway.toml (Already Fixed)**
Your `railway.toml` is already configured correctly:
- Uses `uvicorn` (not gunicorn - WebSockets won't work with gunicorn)
- Uses `$PORT` environment variable
- Mounts `/app/uploads` volume for file storage

### **1.6 Deploy**
Railway will automatically:
1. Detect your `railway.toml`
2. Build using Nixpacks
3. Install requirements
4. Start uvicorn server
5. Deploy to URL: `https://your-project.up.railway.app`

---

## 🚨 COMMON DEPLOYMENT ERRORS & FIXES

### **ERROR 1: "ModuleNotFoundError: No module named 'main'"**
**CAUSE**: Wrong import path in Dockerfile or Procfile
**FIX**: 
```dockerfile
# In Dockerfile - use this:
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
# NOT: gunicorn bus_tracking_backend.main:app
```

**Already fixed in your project** ✅

---

### **ERROR 2: "ModuleNotFoundError: No module named 'uvloop'"**
**CAUSE**: `uvloop` requires compilation, not included in base image
**FIX**: Remove `uvloop` from requirements.txt OR add system dependencies:
```dockerfile
RUN apt-get update && apt-get install -y gcc musl-dev
```

**Your Dockerfile already has gcc** ✅

---

### **ERROR 3: "Database connection failed"**
**CAUSE**: SQLite being used instead of PostgreSQL
**FIX**: Ensure `DATABASE_URL` is set in Railway environment variables

**Check your code handles both**:
```python
# In config.py - already correct
DATABASE_URL: str = os.getenv("DATABASE_URL", "sqlite:///./bus_tracking.db")
USE_SQLITE: bool = "DATABASE_URL" not in os.environ or "sqlite" in os.getenv("DATABASE_URL", "")
```

---

### **ERROR 4: "CORS origin blocked"**
**CAUSE**: Frontend domain not in `CORS_ORIGINS`
**FIX**: After deploying frontend, update `CORS_ORIGINS` in Railway:
```bash
CORS_ORIGINS=https://your-app.web.app,https://your-app.netlify.app,http://localhost:3000
```

**Your config.py already handles this** ✅

---

### **ERROR 5: "Port already in use" / "Address already in use"**
**CAUSE**: Hardcoded port 8000
**FIX**: Your `railway.toml` uses `$PORT` which Railway provides dynamically ✅

---

### **ERROR 6: "WebSocket connection fails"**
**CAUSE**: WebSocket headers not properly configured behind proxy
**FIX**: Add this middleware to `main.py`:

```python
@app.middleware("http")
async def add_websocket_headers(request, call_next):
    response = await call_next(request)
    response.headers["Connection"] = "keep-alive"
    return response
```

**Your main.py already has CORS middleware** ✅

---

### **ERROR 7: "File upload fails - directory not found"**
**CAUSE**: Upload directory doesn't exist or has wrong permissions
**FIX**: Your `main.py` creates uploads directory:
```python
os.makedirs("uploads", exist_ok=True)
```
✅ Already fixed!

---

### **ERROR 8: "JWT token invalid"**
**CAUSE**: SECRET_KEY changed between deployments or not set
**FIX**: Always use the same SECRET_KEY in Railway environment variables

---

### **ERROR 9: "Out of memory" / "Worker timeout"**
**CAUSE**: Too many workers for Railway's free tier memory
**FIX**: Reduce workers to 2 in `railway.toml`:
```toml
startCommand = "uvicorn main:app --host 0.0.0.0 --port $PORT --workers 2"
```

---

## 🔍 MONITORING DEPLOYMENT

### **View Logs in Railway**
1. Go to your project
2. Click on backend service
3. Click **"Logs"** tab
4. Look for:
   - ✅ `Application startup complete`
   - ✅ `Uvicorn running on http://0.0.0.0:8000`
   - ❌ Any `ERROR` or `Exception` traces

### **Test Your API**
```bash
# Health check
curl https://your-project.up.railway.app/health

# Should return:
{"status":"ok","environment":"production"}
```

### **Test WebSocket Connection**
Open browser console and run:
```javascript
const ws = new WebSocket('wss://your-project.up.railway.app/api/ws/ws/location/1?token=YOUR_JWT');
ws.onopen = () => console.log('WebSocket connected!');
ws.onerror = (e) => console.error('WebSocket error:', e);
```

---

## 📊 SCALING FOR 50,000+ USERS

### **Railway Limits (Free Tier)**
- 512 MB RAM per service
- Shared CPU
- 750 hours/month

**For 50,000 users**, you need to upgrade:
1. Click **"Settings"** → **"Plan"**
2. Upgrade to **"Pro"** ($5/month per service)
3. Scale to 4 workers:
   ```toml
   startCommand = "uvicorn main:app --host 0.0.0.0 --port $PORT --workers 4"
   ```

### **Database Scaling**
PostgreSQL on Railway:
- **Hobby Tier**: Free, 1GB storage - good for development
- **Pro Tier**: $5/month, 10GB storage - good for 50K users

### **Redis Scaling**
Redis on Railway:
- **Free**: 100MB - enough for WebSocket connections
- **Pro**: $3/month - for production

### **Total Monthly Cost for 50K Users**
- Backend (Pro): $5
- PostgreSQL (Pro): $5
- Redis (Pro): $3
- **TOTAL: ~$13/month**

---

## 🔧 TROUBLESHOOTING STUCK DEPLOYMENTS

### **Build Fails**
1. Check **"Build Logs"** in Railway
2. Look for:
   - `pip install` errors → Check requirements.txt
   - `COPY . .` errors → Ensure all files exist
   - Port conflicts → Should use $PORT

### **App Crashes on Startup**
1. Check **"Logs"** tab
2. Common issues:
   - Import errors → Check Python path in main.py
   - Database connection → Verify DATABASE_URL
   - Missing environment variables → Check all required vars set

### **Deployment Stuck on "Building"**
1. Railway has a 10-minute build timeout
2. If stuck, cancel and:
   - Reduce dependencies
   - Use smaller base image: `python:3.11-slim`
   - Remove unnecessary packages

---

## 📱 STEP 2: DEPLOY FRONTEND (Flutter Web)

### **2.1 Build Flutter Web**
```bash
flutter build web --release --web-renderer canvaskit
```

### **2.2 Deploy to Firebase Hosting**

#### **Option A: Firebase Hosting (Recommended)**
```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login
firebase login

# Initialize
firebase init hosting

# Select your project
# Set public directory: build/web
# Configure as single-page app: Yes

# Deploy
firebase deploy --only hosting
```

#### **Option B: Netlify**
1. Go to https://app.netlify.com/drop
2. Drag and drop `build/web` folder
3. Get URL: `https://random-name.netlify.app`

#### **Option C: Vercel**
```bash
npm i -g vercel
vercel
```

---

## 🔗 STEP 3: CONNECT FRONTEND TO BACKEND

### **Update Flutter API Configuration**
In `lib/config/api_config.dart` (create if not exists):

```dart
class ApiConfig {
  // Change this to your Railway URL
  static const String baseUrl = 'https://your-project.up.railway.app';
  
  // WebSocket URL
  static const String wsBaseUrl = 'wss://your-project.up.railway.app';
  
  // API Endpoints
  static const String login = '$baseUrl/api/auth/login';
  static const String buses = '$baseUrl/api/buses';
  static const String tracking = '$baseUrl/api/tracking';
  // ... etc
}
```

### **Update Railway CORS Settings**
In Railway → Backend Service → Variables:
```bash
CORS_ORIGINS=https://your-project.web.app,https://your-project.netlify.app
```

---

## ✅ VERIFICATION CHECKLIST

After deployment, verify:

- [ ] Backend health check works: `https://your-railway-url.up.railway.app/health`
- [ ] Swagger docs load: `https://your-railway-url.up.railway.app/docs`
- [ ] Frontend loads without errors
- [ ] Login works from frontend
- [ ] WebSocket connection establishes
- [ ] Location tracking updates
- [ ] File uploads work
- [ ] No errors in Railway logs

---

## 🆘 STILL GETTING ERRORS?

### **Check These Files**
1. `bus_tracking_backend/railway.toml` - Fixed ✅
2. `bus_tracking_backend/Dockerfile` - Fixed ✅
3. `bus_tracking_backend/config.py` - Uses env vars ✅
4. `bus_tracking_backend/main.py` - CORS configured ✅

### **Common Issues**
| Error | Solution |
|-------|----------|
| Build fails | Check requirements.txt, remove `uvloop` |
| Port error | Ensure using `$PORT` not hardcoded |
| Database error | Set `DATABASE_URL` in Railway |
| WebSocket fails | Check CORS_ORIGINS includes frontend |
| 502 Bad Gateway | App crashed - check logs |
| Timeout | Increase timeout in Railway settings |

### **Get Help**
1. Railway Docs: https://docs.railway.app
2. Railway Discord: https://discord.gg/railway
3. Check Railway logs for exact error messages

---

## 🎯 QUICK DEPLOYMENT COMMANDS

```bash
# 1. Push code to GitHub
git add .
git commit -m "Deploy to Railway"
git push origin main

# 2. In Railway dashboard:
#    - Create PostgreSQL
#    - Add Redis
#    - Set environment variables
#    - Deploy!

# 3. Build and deploy frontend
flutter build web --release
firebase deploy

# 4. Update CORS in Railway with frontend URL
# 5. Test everything
```

---

## 🚀 AFTER SUCCESSFUL DEPLOYMENT

1. **Monitor Railway logs** for first 24 hours
2. **Set up alerts** in Railway for downtime
3. **Enable auto-scaling** if on Pro plan
4. **Add custom domain** in Railway settings
5. **Enable HTTPS** (automatic on Railway)
6. **Set up backups** for PostgreSQL
7. **Monitor performance** with Railway metrics

---

## 💡 TIPS FOR 50,000 USERS

1. **Use connection pooling** for PostgreSQL
2. **Enable Redis** for WebSocket scaling
3. **Add CDN** for static files (Cloudflare)
4. **Implement rate limiting** to prevent abuse
5. **Monitor memory usage** - upgrade if needed
6. **Use database indexes** for frequent queries
7. **Cache frequent API responses**
8. **Compress responses** with gzip
9. **Use CDN for images** (Cloudinary/Firebase Storage)
10. **Monitor WebSocket connections** and add limits

---

**Your app is almost ready! Just follow the steps above and you'll be deployed in 10-15 minutes.** 🚀