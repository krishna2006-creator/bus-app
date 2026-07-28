import sys
from pathlib import Path

# Add parent directory to sys.path so Railway can import this package
parent_dir = Path(__file__).resolve().parent.parent
if str(parent_dir) not in sys.path:
    sys.path.insert(0, str(parent_dir))

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, status, APIRouter, Body, Depends
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any
import json
import asyncio
import os
import logging

# Firebase Admin SDK for FCM push notifications (HTTP v1)
import firebase_admin
from firebase_admin import credentials, messaging

from bus_tracking_backend.database.database import engine, Base, SessionLocal, get_db
from bus_tracking_backend.database import models, crud
from bus_tracking_backend.services.websocket_manager_v2 import manager as websocket_manager
from bus_tracking_backend.services.prediction_service import prediction_service
from bus_tracking_backend.services.location_analyzer import location_analyzer
from bus_tracking_backend.utils.auth_utils import get_current_user
from bus_tracking_backend.config import settings
from bus_tracking_backend.routers import bus, students, announcements, requests, documents, drivers, stops, tracking, device_tokens, feedback, websocket_routes
from bus_tracking_backend.services import auth as auth_service
from bus_tracking_backend.init_db import init_database

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Firebase Admin SDK initialization for FCM push notifications (HTTP v1)
# ---------------------------------------------------------------------------
def _init_firebase():
    """Initialize Firebase Admin SDK with the service account credentials."""
    try:
        firebase_admin.get_app()
        logger.info("Firebase app already initialized.")
        return
    except ValueError:
        pass

    creds_path = settings.FIREBASE_CREDENTIALS_PATH
    cred = None

    if creds_path and Path(creds_path).exists():
        try:
            cred = credentials.Certificate(creds_path)
            logger.info("Firebase credentials loaded from file: %s", creds_path)
        except Exception as exc:
            logger.error("Failed to load Firebase credentials from file: %s", exc)

    if cred is None:
        import base64
        creds_b64 = os.getenv("FIREBASE_CREDENTIALS_BASE64")
        if creds_b64:
            try:
                creds_json = json.loads(base64.b64decode(creds_b64))
                cred = credentials.Certificate(creds_json)
                logger.info("Firebase credentials loaded from env var.")
            except Exception as exc:
                logger.error("Failed to load Firebase credentials from base64: %s", exc)

    if cred is None:
        logger.warning("Firebase credentials not found. FCM will be disabled.")
        return

    try:
        firebase_admin.initialize_app(cred)
        logger.info("Firebase Admin SDK initialized successfully for FCM.")
    except Exception as exc:
        logger.error("Failed to initialize Firebase Admin SDK: %s", exc)

_init_firebase()

# Database init
Base.metadata.create_all(bind=engine)
init_database()

app = FastAPI(title="Agni Bus Tracking API")

@app.get("/health")
async def health_check():
    return {"status": "ok", "environment": settings.ENVIRONMENT}

@app.get("/", response_class=HTMLResponse)
async def read_root():
    return """
    <!DOCTYPE html>
    <html>
        <head>
            <title>Bus Tracking Backend</title>
            <style>
                body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
                .container { max-width: 600px; margin: auto; padding: 20px; border: 1px solid #ccc; border-radius: 10px; box-shadow: 2px 2px 10px rgba(0,0,0,0.1); }
                h1 { color: #333; }
                p { color: #666; }
                .btn { display: inline-block; padding: 10px 20px; background-color: #007bff; color: white; text-decoration: none; border-radius: 5px; margin-top: 20px; }
                .btn:hover { background-color: #0056b3; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Agni College of Technology Bus Tracker</h1>
                <p>The Backend Server is running successfully.</p>
                <p>Status: <strong>Online</strong></p>
                <br>
                <a href="/docs" class="btn">View API Documentation (Swagger)</a>
            </div>
        </body>
    </html>
    """

allowed_origins = [origin.strip() for origin in settings.CORS_ORIGINS.split(",") if origin.strip()]
if not allowed_origins or allowed_origins == ["*"]:
    allowed_origins = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

os.makedirs("uploads", exist_ok=True)
from fastapi.staticfiles import StaticFiles
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

# ===========================================================================
# Pydantic models for the /api/send-notification endpoint
# ===========================================================================
class NotificationRequest(BaseModel):
    """Request body for sending an FCM push notification to a single device."""
    token: str = Field(..., description="FCM registration token of the target device")
    title: str = Field(..., min_length=1, max_length=200, description="Notification title")
    body: str = Field(..., min_length=1, max_length=2000, description="Notification body text")
    data: Optional[Dict[str, str]] = Field(default=None, description="Optional custom key-value pairs")
    priority: str = Field(default="high", description="Message priority: 'high' or 'normal'")
    sound: str = Field(default="default", description="Notification sound")


class NotificationResponse(BaseModel):
    """Response returned after attempting to send a notification."""
    success: bool
    message_id: Optional[str] = None
    error: Optional[str] = None


api_router = APIRouter(prefix="/api")


# ---------------------------------------------------------------------------
# FCM push notification endpoint (HTTP v1 via Firebase Admin SDK)
# ---------------------------------------------------------------------------
@api_router.post("/send-notification", response_model=NotificationResponse)
async def send_notification(payload: NotificationRequest):
    """Send an FCM push notification (HTTP v1) to a specific Android device."""
    try:
        message = messaging.Message(
            token=payload.token,
            notification=messaging.Notification(
                title=payload.title, body=payload.body, sound=payload.sound,
            ),
            data=payload.data or {},
            android=messaging.AndroidConfig(
                priority=payload.priority,
                notification=messaging.AndroidNotification(
                    sound=payload.sound, click_action="FLUTTER_NOTIFICATION_CLICK",
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound=payload.sound, content_available=True),
                ),
            ),
        )
        message_id = messaging.send(message)
        logger.info("FCM sent to token ...%s (msg: %s)", payload.token[-8:], message_id)
        return NotificationResponse(success=True, message_id=message_id)
    except firebase_admin.exceptions.FirebaseError as exc:
        logger.error("FCM FirebaseError: %s", exc)
        return NotificationResponse(success=False, error=f"Firebase error: {exc}")
    except Exception as exc:
        logger.error("FCM error: %s", exc)
        return NotificationResponse(success=False, error=f"Error: {exc}")


# ===========================================================================
# Existing API endpoints
# ===========================================================================

@api_router.post("/public-location")
async def receive_public_location(data: dict = Body(...), db: Session = Depends(get_db)):
    await location_analyzer.process_location_update(db, None, data)
    return {"status": "success"}

@api_router.get("/predictions")
async def get_predictions(stop_id: int = None, db: Session = Depends(get_db)):
    if stop_id:
        return await prediction_service.get_predictions_for_stop(db, stop_id)
    return []

@api_router.post("/tracking/sync")
async def sync_tracking_data(data: dict = Body(...), db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    sessions = data.get("sessions", [])
    for session_data in sessions:
        session = db.query(models.TrackingSession).filter(models.TrackingSession.id == session_data.get("id")).first()
        if session:
            if session_data.get("status"):
                session.status = session_data["status"]
            if session_data.get("distance_to_bus") is not None:
                session.distance_to_bus = session_data["distance_to_bus"]
            if session_data.get("total_distance_to_college") is not None:
                session.total_distance_to_college = session_data["total_distance_to_college"]
            if session_data.get("estimated_minutes_to_bus") is not None:
                session.estimated_minutes_to_bus = session_data["estimated_minutes_to_bus"]
            if session_data.get("estimated_minutes_to_college") is not None:
                session.estimated_minutes_to_college = session_data["estimated_minutes_to_college"]
    db.commit()
    return {"status": "success", "message": f"Synced {len(sessions)} sessions"}

@api_router.get("/admin/buses")
async def admin_get_all_buses(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")
    buses = db.query(models.Bus).all()
    result = []
    for bus in buses:
        bus_info = websocket_manager.get_bus_info(bus.id)
        last_loc = bus_info.get("last_known_location") if bus_info else None
        if not last_loc:
            live_loc = db.query(models.LiveLocation).filter(
                models.LiveLocation.entity_id == str(bus.id),
                models.LiveLocation.entity_type == "bus"
            ).order_by(models.LiveLocation.timestamp.desc()).first()
            if live_loc:
                last_loc = {
                    "latitude": live_loc.latitude, "longitude": live_loc.longitude,
                    "speed": live_loc.speed, "direction": live_loc.bearing,
                    "timestamp": live_loc.timestamp.isoformat() if live_loc.timestamp else None,
                }
        if not last_loc:
            cached_loc = location_analyzer.active_locations.get(str(bus.id))
            if cached_loc:
                last_loc = {
                    "latitude": cached_loc.get("lat"), "longitude": cached_loc.get("lng"),
                    "speed": cached_loc.get("speed", 0.0),
                    "direction": cached_loc.get("bearing", cached_loc.get("direction", 0.0)),
                    "timestamp": cached_loc.get("timestamp", None),
                }
        is_active = bus.location_sharing_active if hasattr(bus, 'location_sharing_active') else False
        if bus_info and bus_info.get("has_last_location"):
            is_active = True
        driver = db.query(models.User).filter(models.User.id == bus.driver_id).first() if bus.driver_id else None
        result.append({
            "id": bus.id, "bus_number": bus.bus_number, "route_name": bus.route_name,
            "capacity": bus.capacity, "status": bus.status, "driver_id": bus.driver_id,
            "driver_name": driver.full_name if driver else None, "driver_phone": bus.driver_phone,
            "live_location": last_loc, "active_users": bus_info.get("user_count", 0) if bus_info else 0,
            "location_sharing_active": is_active,
        })
    return result

@api_router.get("/admin/locations")
async def admin_get_all_locations(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(status_code=403, detail="Admin or staff access required")
    locations = []
    for u_id, loc in location_analyzer.active_locations.items():
        locations.append({
            "entity_id": str(loc.get("bus_id")) if loc.get("user_role") == "driver" else str(u_id),
            "entity_type": "bus" if loc.get("user_role") == "driver" else "student",
            "latitude": loc['lat'], "longitude": loc['lng'],
            "speed": loc.get('speed', 0.0), "bearing": loc.get('bearing', loc.get('direction', 0.0)),
            "role": loc.get("user_role", "student"), "user_id": str(u_id),
            "timestamp": loc.get('timestamp', ''),
        })
    return locations

@api_router.get("/admin/stats")
async def admin_get_stats(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")
    return {
        "total_buses": db.query(models.Bus).count(),
        "active_buses": len(websocket_manager.buses),
        "total_users": db.query(models.User).count(),
        "total_students": db.query(models.User).filter(models.User.role == "student").count(),
        "total_drivers": db.query(models.User).filter(models.User.role == "driver").count(),
        "total_staff": db.query(models.User).filter(models.User.role == "staff").count(),
        "active_tracking_sessions": db.query(models.TrackingSession).filter(models.TrackingSession.end_time.is_(None)).count(),
        "pending_requests": db.query(models.Request).filter(models.Request.status == "pending").count(),
    }

@api_router.delete("/announcements/{announcement_id}")
async def admin_delete_announcement(announcement_id: int, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(status_code=403, detail="Not authorized")
    success = crud.delete_announcement(db, announcement_id)
    if not success:
        raise HTTPException(status_code=404, detail="Announcement not found")
    return {"status": "success", "message": "Announcement deleted"}

api_router.include_router(auth_service.router)
api_router.include_router(bus.router)
api_router.include_router(students.router)
api_router.include_router(announcements.router)
api_router.include_router(requests.router)
api_router.include_router(documents.router)
api_router.include_router(drivers.router)
api_router.include_router(stops.router)
api_router.include_router(tracking.router)
api_router.include_router(device_tokens.router)
api_router.include_router(feedback.router)

app.include_router(api_router)
app.include_router(websocket_routes.router)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)