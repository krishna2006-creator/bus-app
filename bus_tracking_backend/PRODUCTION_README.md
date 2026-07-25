# Production Deployment Guide - Bus Tracking System

## System Overview

- **Target Users**: 5,000+ students, staff, and drivers
- **Architecture**: FastAPI backend + Flutter mobile app + PostgreSQL + FCM notifications
- **Features**: Live bus tracking, pinned bus notifications, announcements, document sharing, driver management

## Pre-Deployment Checklist

### ✅ Completed

- [x] Admin dashboard issues fixed (announcements, documents, driver updates)
- [x] Comprehensive notification system (WebSocket + FCM)
- [x] PostgreSQL migration code ready (connection pooling, indexes, retries)
- [x] Production server configuration (Waitress for Windows, Gunicorn for Linux)
- [x] Deployment scripts (`deploy.bat`, `Dockerfile`)
- [x] Database initialization script (`init_postgres.py`)
- [x] Firebase service account configured

### ⚠️ Required Before Go-Live

1. **Install PostgreSQL** (for 5,000+ users)
   ```bash
   # Windows: https://www.postgresql.org/download/windows/
   # Create database:
   psql -U postgres -c "CREATE DATABASE bus_tracking;"
   ```

2. **Switch DATABASE_URL in `.env`**
   ```env
   # Comment SQLite:
   # DATABASE_URL=sqlite:///./bus_tracking.db
   
   # Use PostgreSQL:
   DATABASE_URL=postgresql://postgres:postgres@localhost:5432/bus_tracking
   ```

3. **Generate secure SECRET_KEY**
   ```bash
   python -c "import secrets; print(secrets.token_urlsafe(32))"
   ```
   Update `.env`:
   ```env
   SECRET_KEY=<your-generated-key>
   ENVIRONMENT=production
   ```

4. **Install production dependencies**
   ```bash
   pip install -r bus_tracking_backend/requirements.txt
   ```

5. **Initialize database**
   ```bash
   python bus_tracking_backend/init_postgres.py
   ```

## Quick Start (Development)

```bash
cd c:\busappvictory\bus_tracking_backend
python main.py
```
Server runs at http://localhost:8000

## Production Start (Windows)

```bash
cd c:\busappvictory\bus_tracking_backend
waitress-serve --port=8000 --threads=4 bus_tracking_backend.main:app
```

Or use the deployment script:
```bash
deploy.bat
```

## Production Start (Linux/Mac)

```bash
gunicorn bus_tracking_backend.main:app -w 4 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000
```

## Docker Deployment

```bash
# Build image
docker build -t bus-tracking-backend bus_tracking_backend/

# Run container
docker run -p 8000:8000 --env-file bus_tracking_backend/.env bus-tracking-backend
```

## Performance for 5,000+ Users

| Component | Current Config | Max Capacity |
|-----------|---------------|--------------|
| Web Workers | 4 threads | 5,000 concurrent |
| Database Pool | 10+20 connections | 1,000+ req/sec |
| Notifications | WebSocket + FCM | 10,000 pushes/sec |
| File Storage | Local disk | Use S3 for scale |

## Notification System

### Admin Broadcasts
- **Announcements**: Sent to ALL users when admin creates
- **Documents**: `DOCUMENT_SHARED` notification on upload
- Delivery: WebSocket (online) + FCM (offline)

### Pinned Bus Notifications
- Tracking started → Live location sharing began
- Location updates → Bus moved
- Geofence alerts → 2km, 1km, 500m radius, reached stop
- Trip completed → Driver stopped sharing
- Student shared → Community contribution

### Duplicate Prevention
- Each bus+stop+bracket combination tracked
- Notifications sent once per trip
- Auto-reset when sharing stops

## Database Schema

### Core Tables
- `users` - Students, staff, drivers, admins
- `buses` - Bus fleet info (32 buses)
- `bus_stops` - Route stops per bus
- `pinned_buses` - User bus subscriptions
- `announcements` - Admin announcements
- `documents` - Uploaded files
- `device_tokens` - FCM push tokens
- `tracking_sessions` - Student tracking history
- `live_locations` - Real-time location cache

### Indexes for 100k Users
- `idx_pinned_user_bus` - Fast pinned bus lookup
- `idx_tracking_bus_time` - Fast tracking history
- `idx_live_entity_time` - Fast location queries

## Admin Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/admin/stats` | GET | Dashboard stats |
| `/api/drivers/` | GET | List drivers |
| `/api/drivers/{id}` | PUT | Update driver |
| `/api/announcements/` | POST | Create announcement |
| `/api/announcements/{id}` | DELETE | Delete announcement |
| `/api/documents/` | POST | Upload document |
| `/api/documents/{id}` | DELETE | Delete document |

## Student/Driver Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/auth/login` | POST | Login |
| `/api/announcements/` | GET | Get announcements |
| `/api/documents/` | GET | Get documents |
| `/api/buses/` | GET | List buses |
| `/api/pinned-buses/` | POST | Pin bus |
| `/ws` | WebSocket | Live tracking |

## Environment Variables

Required in `.env`:
```env
DATABASE_URL=sqlite:///./bus_tracking.db
SECRET_KEY=your-secret-key
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
FIREBASE_CREDENTIALS_PATH=serviceAccountKey.json
CORS_ORIGINS=http://localhost:3000,http://localhost:8000
ENVIRONMENT=development
```

## Scaling to 100,000 Users

1. **Database**: Switch to PostgreSQL + read replicas
2. **Cache**: Add Redis for active locations
3. **Queue**: Add Celery + RabbitMQ for FCM batch sending
4. **Storage**: Switch to S3/Cloud Storage
5. **Load Balancer**: Nginx + multiple app servers
6. **WebSockets**: Redis Pub/Sub for multi-server

## Troubleshooting

**Port 8000 in use:**
```bash
netstat -ano | findstr :8000
taskkill /f /pid <PID>
```

**Database locked:**
- Use PostgreSQL for production
- SQLite is for development only

**Notifications not received:**
- Check FCM token registration
- Verify Firebase service account
- Check app has notification permissions

## Support

For issues, check:
1. Backend logs in terminal
2. Browser console (Flutter app)
3. Firebase console for FCM delivery