"""
Production Deployment Configuration & Security Best Practices
For Real-Time Bus Tracking System
"""

# ============================================================================
# 1. PRODUCTION CONFIGURATION
# ============================================================================

"""
ENVIRONMENT SETUP (.env file):
"""

# .env
DEBUG=False
ENVIRONMENT=production

# WebSocket Settings
WS_IDLE_TIMEOUT=120  # seconds - disconnect idle clients
WS_MAX_CONNECTIONS_PER_BUS=100  # max unique users per bus
WS_HEARTBEAT_INTERVAL=30  # server expects heartbeat every N seconds
WS_MESSAGE_QUEUE_SIZE=100  # max pending messages per connection

# Security
JWT_ALGORITHM=HS256
JWT_EXPIRATION_HOURS=24
CORS_ORIGINS=["https://yourdomain.com", "https://app.yourdomain.com"]

# Deployment
WORKERS=4  # uvicorn workers
RELOAD=False
LOG_LEVEL=info  # debug, info, warning, error

# Database
DATABASE_URL=postgresql://user:password@localhost/bus_tracking

# Optional: For scaling with multiple servers
REDIS_URL=redis://localhost:6379  # if using Redis pub/sub
MESSAGE_BROKER_URL=amqp://user:pass@rabbitmq:5672  # for RabbitMQ


# ============================================================================
# 2. UVICORN CONFIGURATION (production.py)
# ============================================================================

"""
Save as: config/uvicorn_config.py
"""

import os
from dotenv import load_dotenv

load_dotenv()


class UvicornConfig:
    """Uvicorn server configuration for production"""

    # Server
    host = os.getenv("SERVER_HOST", "0.0.0.0")
    port = int(os.getenv("SERVER_PORT", 8000))
    workers = int(os.getenv("WORKERS", 4))
    reload = os.getenv("RELOAD", "False").lower() == "true"
    loop = "uvloop"  # High-performance event loop

    # WebSocket
    lifespan = "on"
    
    # Logging
    log_level = os.getenv("LOG_LEVEL", "info")
    access_log = True

    # Performance
    limit_concurrency = None  # Let OS handle
    limit_max_requests = 10000  # Restart worker after N requests
    timeout_keep_alive = 120
    timeout_notify = 30


def get_uvicorn_config():
    """Get uvicorn configuration as dict"""
    return {
        "app": "main:app",
        "host": UvicornConfig.host,
        "port": UvicornConfig.port,
        "workers": UvicornConfig.workers,
        "reload": UvicornConfig.reload,
        "loop": UvicornConfig.loop,
        "log_level": UvicornConfig.log_level,
        "access_log": UvicornConfig.access_log,
        "lifespan": UvicornConfig.lifespan,
        "timeout_keep_alive": UvicornConfig.timeout_keep_alive,
        "timeout_notify": UvicornConfig.timeout_notify,
        "server_header": False,  # Don't expose server info
        "date_header": True,
    }


# ============================================================================
# 3. SECURITY HARDENING
# ============================================================================

"""
CORS Configuration (Updated main.py):
"""

from fastapi.middleware.cors import CORSMiddleware
import os

# In main.py, update CORS setup:
ALLOWED_ORIGINS = os.getenv(
    "CORS_ORIGINS",
    "http://192.168.29.123:3000,http://192.168.29.123:8000"
).split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST"],  # Restrict to needed methods
    allow_headers=["Authorization", "Content-Type"],
    expose_headers=["X-Process-Time"],
    max_age=600,  # Cache CORS for 10 minutes
)


"""
Rate Limiting Middleware:
Add to main.py
"""

from slowapi import Limiter
from slowapi.util import get_remote_address
from fastapi import HTTPException, status

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Apply rate limiting to REST endpoints
@api_router.post("/location/update")
@limiter.limit("100/minute")  # 100 requests per minute per IP
async def post_location_update(...):
    pass


"""
Enhanced Authentication (utils/auth_utils.py):
"""

from fastapi import HTTPException, status
import jwt
from datetime import datetime, timedelta, timezone
import os

SECRET_KEY = os.getenv("JWT_SECRET_KEY")
ALGORITHM = os.getenv("JWT_ALGORITHM", "HS256")
TOKEN_EXPIRATION = int(os.getenv("JWT_EXPIRATION_HOURS", 24))


def verify_token(token: str) -> dict:
    """Verify JWT token and return payload"""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        
        # Check token expiration
        exp = payload.get("exp")
        if exp and datetime.fromtimestamp(exp, tz=timezone.utc) < datetime.now(timezone.utc):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token expired"
            )
        
        # Verify required fields
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token payload"
            )
        
        return payload
    
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired"
        )
    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token"
        )


def create_token(user_id: int, role: str = "student") -> str:
    """Create JWT token with expiration"""
    expire = datetime.now(timezone.utc) + timedelta(hours=TOKEN_EXPIRATION)
    payload = {
        "sub": str(user_id),
        "role": role,
        "iat": datetime.now(timezone.utc).timestamp(),
        "exp": expire.timestamp(),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


# ============================================================================
# 4. NGINX REVERSE PROXY CONFIGURATION
# ============================================================================

"""
Save as: nginx.conf

This configuration:
- Handles WebSocket upgrades properly
- Proxies to multiple uvicorn workers
- Compresses responses
- Sets proper timeouts
- Adds security headers
"""

upstream bus_tracker_backend {
    least_conn;
    server localhost:8001;
    server localhost:8002;
    server localhost:8003;
    server localhost:8004;
    keepalive 32;
}

server {
    listen 80;
    server_name api.bustracker.com;
    
    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.bustracker.com;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/api.bustracker.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.bustracker.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Gzip Compression
    gzip on;
    gzip_types application/json text/plain;
    gzip_min_length 1024;
    
    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Content-Security-Policy "default-src 'self'" always;
    
    # Timeouts
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    
    location / {
        proxy_pass http://bus_tracker_backend;
        
        # Standard proxy headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Connection handling
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        
        # WebSocket support
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Buffering
        proxy_buffering off;
        proxy_request_buffering off;
    }
    
    location /ws/ {
        # Special handling for WebSocket
        proxy_pass http://bus_tracker_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Long timeout for WebSocket
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        
        # No buffering
        proxy_buffering off;
    }
}


# ============================================================================
# 5. MONITORING & LOGGING
# ============================================================================

"""
Enhanced Logging Setup (logging_config.py):
"""

import logging
import logging.handlers
import os
from datetime import datetime

LOG_DIR = "logs"
os.makedirs(LOG_DIR, exist_ok=True)


def setup_logging():
    """Setup production logging"""
    
    # Root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.DEBUG)
    
    # Console handler (INFO level)
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    console_formatter = logging.Formatter(
        "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )
    console_handler.setFormatter(console_formatter)
    
    # File handler (DEBUG level)
    file_handler = logging.handlers.RotatingFileHandler(
        f"{LOG_DIR}/app.log",
        maxBytes=10 * 1024 * 1024,  # 10 MB
        backupCount=5
    )
    file_handler.setLevel(logging.DEBUG)
    file_formatter = logging.Formatter(
        "%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s"
    )
    file_handler.setFormatter(file_formatter)
    
    # WebSocket handler (INFO level)
    ws_handler = logging.handlers.RotatingFileHandler(
        f"{LOG_DIR}/websocket.log",
        maxBytes=10 * 1024 * 1024,
        backupCount=5
    )
    ws_handler.setLevel(logging.INFO)
    
    root_logger.addHandler(console_handler)
    root_logger.addHandler(file_handler)
    
    # WebSocket logger
    ws_logger = logging.getLogger("websocket_manager")
    ws_logger.addHandler(ws_handler)
    
    return root_logger


# In main.py:
from logging_config import setup_logging
setup_logging()


# ============================================================================
# 6. METRICS & HEALTH CHECKS
# ============================================================================

"""
Health Check & Metrics Endpoint (add to routers/monitoring.py):
"""

from fastapi import APIRouter, Depends
from services.websocket_manager_v2 import manager
import psutil
import os

router = APIRouter(prefix="/health", tags=["Health"])


@router.get("/status")
async def health_check():
    """Basic health check"""
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
    }


@router.get("/metrics")
async def get_metrics():
    """Get system and WebSocket metrics"""
    
    # System metrics
    process = psutil.Process(os.getpid())
    memory = process.memory_info()
    cpu_percent = process.cpu_percent(interval=0.1)
    
    # WebSocket metrics
    ws_stats = manager.get_stats()
    
    return {
        "timestamp": datetime.now().isoformat(),
        "system": {
            "memory_mb": memory.rss / (1024 * 1024),
            "cpu_percent": cpu_percent,
            "open_files": len(process.open_files()),
        },
        "websocket": {
            "total_buses": ws_stats["total_buses"],
            "total_users": ws_stats["total_users"],
            "total_connections": ws_stats["total_connections"],
        },
    }


@router.get("/readiness")
async def readiness_check():
    """Readiness check (for K8s deployments)"""
    # Check database connection
    try:
        # Try a simple query
        # db.query(models.User).first()
        db_ok = True
    except:
        db_ok = False
    
    return {
        "ready": db_ok,
        "database": "ok" if db_ok else "error",
    }


# ============================================================================
# 7. SYSTEMD SERVICE FILE (Linux Deployment)
# ============================================================================

"""
Save as: /etc/systemd/system/bus-tracker.service

This runs the FastAPI app as a system service
"""

[Unit]
Description=Bus Tracker Backend
After=network.target

[Service]
Type=notify
User=appuser
WorkingDirectory=/opt/bus_tracking_backend
Environment="PATH=/opt/bus_tracking_backend/venv/bin"
ExecStart=/opt/bus_tracking_backend/venv/bin/uvicorn main:app --workers 4 --host 0.0.0.0 --port 8000

# Restart policy
Restart=always
RestartSec=5
StartLimitInterval=60s
StartLimitBurst=3

# Resource limits
LimitNOFILE=65535  # Max file descriptors
LimitNPROC=4096    # Max processes

[Install]
WantedBy=multi-user.target


# Usage:
# sudo systemctl start bus-tracker
# sudo systemctl stop bus-tracker
# sudo journalctl -u bus-tracker -f  # View logs


# ============================================================================
# 8. DOCKER DEPLOYMENT
# ============================================================================

"""
Save as: Dockerfile
"""

FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN apt-get update && apt-get install -y \\
    gcc \\
    postgresql-client \\
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt uvloop

COPY . .

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \\
    CMD curl -f http://localhost:8000/health/status || exit 1

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4", "--loop", "uvloop"]


# Save as: docker-compose.yml
version: '3.8'

services:
  backend:
    build: .
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://user:password@db:5432/bus_tracking
      - ENVIRONMENT=production
      - LOG_LEVEL=info
    depends_on:
      - db
      - redis
    volumes:
      - ./logs:/app/logs
    restart: always

  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=bus_tracking
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: always

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    restart: always

volumes:
  postgres_data:


# ============================================================================
# 9. SECURITY CHECKLIST FOR PRODUCTION
# ============================================================================

"""
✅ AUTHENTICATION & AUTHORIZATION
  - [ ] JWT tokens with expiration (24 hours)
  - [ ] Token validation on every WebSocket connection
  - [ ] HTTPS/WSS only (no HTTP/WS)
  - [ ] Secure secret key storage (use environment variables)
  - [ ] User role-based access control (RBAC)

✅ DATA PROTECTION
  - [ ] Encrypt sensitive data in transit (HTTPS/TLS)
  - [ ] Validate all input (JSON schema validation)
  - [ ] Sanitize error messages (no SQL/code exposure)
  - [ ] Log security events
  - [ ] Regular security audits

✅ INFRASTRUCTURE
  - [ ] Firewall rules (allow only necessary ports)
  - [ ] Rate limiting enabled
  - [ ] DDoS protection (Cloudflare, AWS Shield)
  - [ ] WAF rules configured
  - [ ] Regular backup tests

✅ DEPLOYMENT
  - [ ] Non-root user (appuser)
  - [ ] Resource limits set
  - [ ] Health checks configured
  - [ ] Monitoring alerts set up
  - [ ] Disaster recovery plan

✅ OPERATIONS
  - [ ] Centralized logging
  - [ ] Performance monitoring
  - [ ] Error tracking (Sentry)
  - [ ] Incident response plan
  - [ ] Regular updates & patches
"""

# ============================================================================
# 10. LOAD TESTING RECOMMENDATIONS
# ============================================================================

"""
Tools for load testing:
- Apache JMeter (WebSocket plugin)
- Locust (Python-based)
- K6 (Modern load testing)

Example: Load test with Locust

from locust import HttpUser, task, between
import asyncio
import websockets
import json
import random

class BusBusTrackingUser(HttpUser):
    wait_time = between(1, 5)
    
    def on_start(self):
        # Simulate login and get JWT token
        response = self.client.post("/api/login", json={
            "username": f"user{random.randint(1, 100)}",
            "password": "password"
        })
        self.token = response.json()["access_token"]
    
    @task
    def send_location(self):
        # WebSocket connection
        ws_url = f"ws://192.168.29.123:8000/api/ws/ws/location/{
            random.randint(1, 32)}?token={self.token}"
        
        async def ws_task():
            async with websockets.connect(ws_url) as ws:
                for i in range(5):  # Send 5 updates
                    await ws.send(json.dumps({
                        "type": "LOCATION_UPDATE",
                        "latitude": 28.6139 + random.random() * 0.01,
                        "longitude": 77.2090 + random.random() * 0.01,
                        "speed": random.random() * 100
                    }))
                    await asyncio.sleep(1)
        
        asyncio.run(ws_task())


TEST TARGETS:
- 50 concurrent users
- 10 location updates per user per minute
- 32 buses (distributed evenly)
- 5-minute test duration
- Monitor: Latency, CPU, Memory, Connection errors
"""
