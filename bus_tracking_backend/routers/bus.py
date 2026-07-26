from fastapi import APIRouter, Depends, HTTPException, status, WebSocket, WebSocketDisconnect, Header
from sqlalchemy.orm import Session
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel
import json

from ..database import crud, models
from ..database.database import get_db, SessionLocal
from ..schemas import bus as bus_schemas
from ..schemas import user as user_schemas
from ..schemas import websocket as ws_schemas
from ..services.location_analyzer import location_analyzer
from ..services.websocket_manager_v2 import manager as websocket_manager
from ..utils.auth_utils import get_current_user

router = APIRouter(
    prefix="/buses",
    tags=["Buses"],
    responses={404: {"description": "Not found"}},
)

# --- Public/Student Access Endpoints ---

@router.get("/", response_model=List[bus_schemas.BusResponse])
def read_buses(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    return crud.get_buses(db, skip=skip, limit=limit)

@router.get("/{bus_id_or_number}", response_model=bus_schemas.BusResponse)
def read_bus(bus_id_or_number: str, db: Session = Depends(get_db)):
    # Flexible lookup by database ID OR by bus number
    db_bus = None
    if bus_id_or_number.isdigit():
        db_bus = crud.get_bus(db, bus_id=int(bus_id_or_number))

    if not db_bus:
        db_bus = db.query(models.Bus).filter(models.Bus.bus_number == bus_id_or_number).first()

    if db_bus is None:
        raise HTTPException(status_code=404, detail="Bus not found")
    return db_bus

@router.get("/{bus_id}/location", response_model=Optional[bus_schemas.LiveLocationResponse])
def get_bus_live_location(bus_id: int, db: Session = Depends(get_db)):
    # Retrieve the bus's last known location from the WebSocket manager
    bus_info = websocket_manager.get_bus_info(bus_id)
    if bus_info and bus_info.get("has_last_location"):
        last_location = bus_info["last_known_location"]
        return bus_schemas.LiveLocationResponse(
            id=bus_id,
            bus_id=bus_id,
            user_id=str(last_location.user_id),
            latitude=last_location.latitude,
            longitude=last_location.longitude,
            speed=last_location.speed,
            direction=last_location.direction,
            source_type="live",
            timestamp=datetime.fromtimestamp(last_location.timestamp)
        )
    return None

@router.get("/student/pinned-buses", response_model=List[bus_schemas.BusResponse])
def get_student_pinned_buses(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Get all pinned buses for current student with real-time location"""
    if current_user.role != "student":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only students can view pinned buses")

    # Get pinned buses
    pinned_buses = db.query(models.Bus).join(models.PinnedBus).filter(
        models.PinnedBus.user_id == current_user.id
    ).all()

    return pinned_buses

# --- Bus Pinning Endpoints (Student feature) ---

@router.get("/{bus_id}/pin", response_model=bus_schemas.PinnedBusResponse)
def get_bus_pin(
    bus_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Get the pinned bus info for the current user."""
    pin = db.query(models.PinnedBus).filter(
        models.PinnedBus.bus_id == bus_id,
        models.PinnedBus.user_id == current_user.id
    ).first()
    if not pin:
        raise HTTPException(status_code=404, detail="Bus not pinned")
    return pin

@router.post("/{bus_id}/pin", response_model=bus_schemas.PinnedBusResponse)
def pin_bus(
    bus_id: int,
    pin_data: bus_schemas.PinnedBusCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Pin a bus for tracking."""
    # Verify bus exists
    bus = db.query(models.Bus).filter(models.Bus.id == bus_id).first()
    if not bus:
        raise HTTPException(status_code=404, detail="Bus not found")

    # Check if already pinned
    existing = db.query(models.PinnedBus).filter(
        models.PinnedBus.bus_id == bus_id,
        models.PinnedBus.user_id == current_user.id
    ).first()
    if existing:
        return existing

    pin = models.PinnedBus(
        user_id=current_user.id,
        bus_id=bus_id,
        boarding_stop_id=pin_data.boarding_stop_id
    )
    db.add(pin)
    db.commit()
    db.refresh(pin)
    return pin

@router.delete("/{bus_id}/pin")
def unpin_bus(
    bus_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Unpin a bus."""
    pin = db.query(models.PinnedBus).filter(
        models.PinnedBus.bus_id == bus_id,
        models.PinnedBus.user_id == current_user.id
    ).first()
    if not pin:
        raise HTTPException(status_code=404, detail="Bus not pinned")
    db.delete(pin)
    db.commit()
    return {"status": "success", "message": "Bus unpinned"}

# --- Admin Only Management Endpoints ---

@router.post("/", response_model=bus_schemas.BusResponse)
def create_bus(
    bus: bus_schemas.BusCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    if current_user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only Admins can create buses")
    return crud.create_bus_with_stops(db=db, bus=bus)

@router.put("/{bus_id}", response_model=bus_schemas.BusResponse)
def update_bus(
    bus_id: int,
    bus: bus_schemas.BusCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    if current_user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only Admins can update buses")
    db_bus = crud.update_bus(db, bus_id=bus_id, bus=bus)
    if db_bus is None:
        raise HTTPException(status_code=404, detail="Bus not found")
    return db_bus

@router.delete("/{bus_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_bus(
    bus_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    if current_user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only Admins can delete buses")
    success = crud.delete_bus(db, bus_id=bus_id)
    if not success:
        raise HTTPException(status_code=404, detail="Bus not found")
    return None

# --- Real-Time Tracking ---

@router.websocket("/{bus_id}/live_location")
async def bus_live_location_websocket(websocket: WebSocket, bus_id: int, token: str = None):
    db = SessionLocal()
    user = None
    role_str = "student"
    try:
        user = get_current_user(token, db)
        if not user:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return

        # Correct the connect call to provide all required 5 arguments
        role_str = user.role.value if hasattr(user.role, 'value') else str(user.role).lower().split('.')[-1]
        await websocket_manager.connect(
            websocket=websocket,
            user_id=user.id,
            user_name=user.full_name,
            user_role=role_str,
            bus_id=bus_id
        )

        while True:
            data = await websocket.receive_text()
            try:
                msg = json.loads(data)
                if msg.get("type") in ["LOCATION_UPDATE", "STOP_SHARING", "LOCATION_CLEARED"]:
                    # Trigger the analyzer so students see the movement and ETA updates
                    await location_analyzer.process_location_update(db, user, msg)
            except:
                pass

            await websocket.send_text(json.dumps({"type": "PONG"}))

    except WebSocketDisconnect:
        if user:
            await location_analyzer.remove_location(user.id, bus_id, role_str)
    except Exception as e:
        print(f"Bus WebSocket Error: {e}")
        if user:
            await location_analyzer.remove_location(user.id, bus_id, role_str)
    finally:
        db.close()


# --- Location Sharing Endpoints ---

class PublicLocationUpdate(BaseModel):
    bus_id: int
    latitude: float
    longitude: float
    speed: float = 0.0
    direction: float = 0.0
    is_public: bool = True

@router.post("/public-location")
async def post_public_location(
    location: PublicLocationUpdate,
    db: Session = Depends(get_db),
    authorization: str = Header(None),
):
    """
    Post current location for a bus/student/driver.
    Used for real-time location sharing.
    Authentication is optional - allows public location sharing.
    """
    try:
        # Extract token from Authorization header
        token = None
        if authorization:
            if authorization.startswith("Bearer "):
                token = authorization[7:]
            else:
                token = authorization

        # Try to authenticate user if token is provided
        current_user = None
        if token:
            try:
                user = db.query(models.User).filter(models.User.id == token).first()
                if not user:
                    user = db.query(models.User).filter(models.User.email == token).first()
                if not user:
                    from jose import jwt
                    from ..config import settings
                    payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
                    email = payload.get("sub")
                    if email:
                        user = db.query(models.User).filter(models.User.email == email).first()
                current_user = user
            except Exception as e:
                print(f"Token validation error (non-critical): {e}")

        # Use the unified analyzer to process and broadcast GLOBALLY.
        await location_analyzer.process_location_update(
            db,
            current_user,
            {
                "latitude": location.latitude,
                "longitude": location.longitude,
                "speed": location.speed,
                "bus_id": location.bus_id,
                "is_shared_by_student": True if (current_user and current_user.role == "student") else False
            }
        )

        # Persist location to LiveLocation table so REST API clients
        # (e.g. LocationService.fetchAllLatestLocations) can retrieve it
        # even when WebSocket is not connected.
        # CRITICAL FIX: Update existing record instead of creating new ones,
        # so the table doesn't grow unbounded with thousands of students.
        try:
            existing = db.query(models.LiveLocation).filter(
                models.LiveLocation.entity_id == str(location.bus_id),
                models.LiveLocation.entity_type == "bus"
            ).first()
            if existing:
                existing.latitude = location.latitude
                existing.longitude = location.longitude
                existing.speed = location.speed
                existing.bearing = location.direction
                existing.timestamp = datetime.now()
                existing.accuracy = 0.0
            else:
                live_loc = models.LiveLocation(
                    entity_id=str(location.bus_id),
                    entity_type="bus",
                    latitude=location.latitude,
                    longitude=location.longitude,
                    speed=location.speed,
                    bearing=location.direction,
                    timestamp=datetime.now(),
                    accuracy=0.0,
                )
                db.add(live_loc)
            db.commit()
        except Exception as persist_err:
            db.rollback()
            print(f"Location persistence failed (non-critical): {persist_err}")

        return {
            "status": "success",
            "message": "Location updated",
            "data": location
        }
    except Exception as e:
        print(f"Error posting location: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to post location: {str(e)}"
        )

@router.delete("/public-location/{bus_id}")
async def clear_public_location(
    bus_id: int,
    db: Session = Depends(get_db),
    authorization: str = Header(None),
):
    """
    Stops sharing and signals all clients to remove the marker immediately.
    Authentication is optional - allows public location clearing (same as post_public_location).
    """
    try:
        # Extract token from Authorization header
        token = None
        if authorization:
            if authorization.startswith("Bearer "):
                token = authorization[7:]
            else:
                token = authorization

        # Try to authenticate user if token is provided
        current_user = None
        if token:
            try:
                user = db.query(models.User).filter(models.User.id == token).first()
                if not user:
                    user = db.query(models.User).filter(models.User.email == token).first()
                if not user:
                    from jose import jwt
                    from ..config import settings
                    payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
                    email = payload.get("sub")
                    if email:
                        user = db.query(models.User).filter(models.User.email == email).first()
                current_user = user
            except Exception as e:
                print(f"Token validation error (non-critical): {e}")

        # Determine u_id and role - use bus_id for anonymous users to match post_public_location
        u_id = current_user.id if current_user and hasattr(current_user, 'id') else f'system_{bus_id}'
        role = (current_user.role.value if hasattr(current_user.role, 'value') else str(current_user.role).lower().split('.')[-1]) if current_user and hasattr(current_user, 'role') else 'student'

        await location_analyzer.remove_location(
            u_id=u_id,
            bus_id=bus_id,
            role=role
        )

        # Also clear from LiveLocation table
        try:
            db.query(models.LiveLocation).filter(
                models.LiveLocation.entity_id == str(bus_id),
                models.LiveLocation.entity_type == "bus"
            ).delete()
            db.commit()
        except Exception as persist_err:
            db.rollback()
            print(f"LiveLocation cleanup failed (non-critical): {persist_err}")

        return {"status": "success", "message": "Location cleared"}
    except Exception as e:
        print(f"Error clearing location: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to clear location: {str(e)}"
        )
