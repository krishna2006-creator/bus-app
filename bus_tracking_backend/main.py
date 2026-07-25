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
import json
import asyncio
import os

from bus_tracking_backend.database.database import engine, Base, SessionLocal, get_db
from bus_tracking_backend.database import models, crud
from bus_tracking_backend.services.websocket_manager_v2 import manager as websocket_manager
from bus_tracking_backend.services.prediction_service import prediction_service
from bus_tracking_backend.services.location_analyzer import location_analyzer
from bus_tracking_backend.utils.auth_utils import get_current_user
from bus_tracking_backend.config import settings
from bus_tracking_backend.routers import bus, students, announcements, requests, documents, drivers, stops, tracking, device_tokens, websocket_routes
from bus_tracking_backend.services import auth as auth_service

Base.metadata.create_all(bind=engine)

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

api_router = APIRouter(prefix="/api")

@api_router.websocket("/ws")
async def general_websocket(websocket: WebSocket, token: str = None):
    await websocket.accept()
    db = SessionLocal()
    user_id = None
    user_role = "student"
    bus_id = 0
    try:
        if token and token.startswith("Bearer "):
            token = token[7:]
        if not token:
            token = websocket.query_params.get("token")
        if token and token.startswith("Bearer "):
            token = token[7:]
        auth_header = websocket.headers.get("authorization") or websocket.headers.get("Authorization")
        if auth_header and auth_header.lower().startswith("bearer ") and not token:
            token = auth_header[7:]

        user = get_current_user(token, db) if token else None
        if not user or not token:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return

        user_id = user.id
        user_role = str(user.role)
        bus_id = getattr(user, 'assigned_bus_id', 0) or 0

        await websocket_manager.connect(
            websocket, user_id,
            getattr(user, 'full_name', str(user.id)),
            str(user.role),
            getattr(user, 'assigned_bus_id', 0) or 0
        )
        await websocket.send_text(json.dumps({"type": "CONNECTION_ESTABLISHED", "user": getattr(user, 'full_name', str(user.id))}))

        while True:
            data = await websocket.receive_text()
            if data == "PING":
                await websocket.send_text(json.dumps({"type": "PONG"}))
            else:
                try:
                    message = json.loads(data)
                    msg_type = message.get("type")
                    if msg_type in ["LOCATION_UPDATE", "STOP_SHARING", "LOCATION_CLEARED"]:
                        payload = message.get("payload", message)
                        if msg_type == "LOCATION_UPDATE" and bus_id and "latitude" in payload:
                            await prediction_service.update_bus_coord(int(bus_id), float(payload["latitude"]), float(payload["longitude"]))
                        await location_analyzer.process_location_update(db, user, message)
                except Exception as e:
                    print(f"Error processing WS message: {e}")
    except HTTPException as exc:
        print(f"General WS auth failed: {exc.detail}")
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason=str(exc.detail or "Unauthorized"))
        return
    except WebSocketDisconnect:
        if user_id:
            websocket_manager.disconnect(user_id, websocket)
            await location_analyzer.remove_location(user_id, bus_id, user_role)
    except Exception as e:
        print(f"General WS Error: {e}")
        if user_id:
            websocket_manager.disconnect(user_id, websocket)
            await location_analyzer.remove_location(user_id, bus_id, user_role)
    finally:
        db.close()

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
        driver = db.query(models.User).filter(models.User.id == bus.driver_id).first() if bus.driver_id else None
        result.append({
            "id": bus.id,
            "bus_number": bus.bus_number,
            "route_name": bus.route_name,
            "capacity": bus.capacity,
            "status": bus.status,
            "driver_id": bus.driver_id,
            "driver_name": driver.full_name if driver else None,
            "driver_phone": bus.driver_phone,
            "live_location": last_loc,
            "active_users": bus_info.get("user_count", 0) if bus_info else 0,
        })
    return result

@api_router.get("/admin/locations")
async def admin_get_all_locations(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(status_code=403, detail="Admin or staff access required")
    locations = []
    for u_id, loc in location_analyzer.active_locations.items():
        locations.append({
            "entity_id": str(loc.get("bus_id")) if loc.get("role") == "driver" else str(u_id),
            "entity_type": "bus" if loc.get("role") == "driver" else "student",
            "latitude": loc['lat'],
            "longitude": loc['lng'],
            "speed": loc.get('speed', 0.0),
            "bearing": loc.get('bearing', 0.0),
            "role": loc.get("role", "student"),
            "user_id": str(u_id),
            "timestamp": loc.get('timestamp', ''),
        })
    return locations

@api_router.get("/admin/stats")
async def admin_get_stats(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")
    active_tracking = db.query(models.TrackingSession).filter(models.TrackingSession.end_time.is_(None)).count()
    active_buses_count = len(websocket_manager.buses)
    return {
        "total_buses": db.query(models.Bus).count(),
        "active_buses": active_buses_count,
        "total_users": db.query(models.User).count(),
        "total_students": db.query(models.User).filter(models.User.role == "student").count(),
        "total_drivers": db.query(models.User).filter(models.User.role == "driver").count(),
        "total_staff": db.query(models.User).filter(models.User.role == "staff").count(),
        "active_tracking_sessions": active_tracking,
        "pending_requests": db.query(models.Request).filter(models.Request.status == "pending").count(),
    }

@api_router.delete("/announcements/{announcement_id}")
async def admin_delete_announcement(
    announcement_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
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

app.include_router(api_router)
app.include_router(websocket_routes.router)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)