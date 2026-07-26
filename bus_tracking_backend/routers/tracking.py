"""
Tracking Router - Handles real-time bus tracking, boarding points, and student location tracking
"""
from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks
from sqlalchemy.orm import Session
from datetime import datetime
from typing import List, Optional
from ..database.database import get_db, SessionLocal
from ..database import models
from ..schemas.tracking import (
    TrackingSessionCreate,
    TrackingSessionUpdate,
    TrackingSessionResponse,
    LiveLocationCreate,
    LiveLocationResponse,
    BusRouteResponse,
)
from ..utils.auth_utils import get_current_user
from ..services.websocket_manager_v2 import manager as websocket_manager
from ..services.location_analyzer import location_analyzer
import json
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/tracking", tags=["tracking"])

# ==================== TRACKING SESSIONS ====================

@router.post("/sessions", response_model=TrackingSessionResponse)
async def create_tracking_session(
    session_data: TrackingSessionCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Create a new tracking session for a student"""
    try:
        # Verify user is student
        if current_user.role != "student":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only students can create tracking sessions"
            )
        
        # Create tracking session
        tracking_session = models.TrackingSession(
            id=session_data.id,
            student_id=current_user.id,
            bus_id=session_data.bus_id,
            boarding_point_id=session_data.boarding_point_id,
            start_time=datetime.now(),
            status="tracking_to_boarding",
        )
        
        db.add(tracking_session)
        db.commit()
        db.refresh(tracking_session)
        
        return tracking_session
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Error creating tracking session: {str(e)}"
        )

@router.get("/sessions/{session_id}", response_model=TrackingSessionResponse)
async def get_tracking_session(
    session_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Get a specific tracking session"""
    session = db.query(models.TrackingSession).filter(
        models.TrackingSession.id == session_id
    ).first()
    
    if not session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tracking session not found"
        )
    
    # Verify ownership (student or admin)
    if current_user.role == "student" and session.student_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot access other student's tracking session"
        )
    
    return session

@router.get("/sessions/student/{student_id}", response_model=List[TrackingSessionResponse])
async def get_student_sessions(
    student_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Get all tracking sessions for a student"""
    # Verify permission
    if current_user.role == "student" and current_user.id != student_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot access other student's sessions"
        )
    
    sessions = db.query(models.TrackingSession).filter(
        models.TrackingSession.student_id == student_id,
        models.TrackingSession.end_time.is_(None)
    ).all()
    
    return sessions

@router.get("/sessions/bus/{bus_id}", response_model=List[TrackingSessionResponse])
async def get_bus_sessions(
    bus_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Get all active tracking sessions for a bus"""
    # Only admin and drivers can view this
    if current_user.role not in ["admin", "driver"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only admin and drivers can view bus tracking sessions"
        )
    
    sessions = db.query(models.TrackingSession).filter(
        models.TrackingSession.bus_id == bus_id,
        models.TrackingSession.end_time.is_(None)
    ).all()
    
    return sessions

@router.put("/sessions/{session_id}", response_model=TrackingSessionResponse)
async def update_tracking_session(
    session_id: str,
    session_data: TrackingSessionUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Update a tracking session with current distances and status"""
    session = db.query(models.TrackingSession).filter(
        models.TrackingSession.id == session_id
    ).first()
    
    if not session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tracking session not found"
        )
    
    # Update fields
    if session_data.status:
        session.status = session_data.status
    if session_data.distance_to_bus is not None:
        session.distance_to_bus = session_data.distance_to_bus
    if session_data.total_distance_to_college is not None:
        session.total_distance_to_college = session_data.total_distance_to_college
    if session_data.estimated_minutes_to_bus is not None:
        session.estimated_minutes_to_bus = session_data.estimated_minutes_to_bus
    if session_data.estimated_minutes_to_college is not None:
        session.estimated_minutes_to_college = session_data.estimated_minutes_to_college
    
    db.commit()
    db.refresh(session)
    
    return session

@router.post("/sessions/{session_id}/complete")
async def complete_tracking_session(
    session_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Mark a tracking session as completed"""
    session = db.query(models.TrackingSession).filter(
        models.TrackingSession.id == session_id
    ).first()
    
    if not session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tracking session not found"
        )
    
    session.status = "completed"
    session.end_time = datetime.now()
    
    db.commit()
    db.refresh(session)
    
    return {"message": "Session completed", "session": session}

# ==================== LIVE LOCATIONS ====================

@router.post("/locations", response_model=LiveLocationResponse)
async def record_live_location(
    location_data: LiveLocationCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Record a live location for a bus or student and broadcast to WebSocket clients"""
    # 1. FAST SHARING: Broadcast immediately for sub-second real-time tracking
    try:
        await location_analyzer.process_location_update(db, current_user, location_data.model_dump())
    except Exception as ws_err:
        logger.error(f"Fast broadcast failed: {ws_err}")

    # 2. BACKGROUND PERSISTENCE: Offload DB write to keep the response time ultra-low for high-frequency updates
    background_tasks.add_task(async_save_location, location_data.model_dump())

    # 3. IMMEDIATE RESPONSE: Return input data immediately to the client
    return LiveLocationResponse(
        id=int(datetime.now().timestamp()),
        entity_id=location_data.entity_id,
        entity_type=location_data.entity_type,
        latitude=location_data.latitude,
        longitude=location_data.longitude,
        speed=location_data.speed,
        bearing=location_data.bearing,
        timestamp=datetime.now(),
        accuracy=location_data.accuracy,
    )

def async_save_location(data: dict):
    """Persists location record in the background to ensure high-frequency refresh is smooth."""
    db = SessionLocal()
    try:
        live_location = models.LiveLocation(
            entity_id=data.get("entity_id"),
            entity_type=data.get("entity_type"),
            latitude=data.get("latitude"),
            longitude=data.get("longitude"),
            speed=data.get("speed"),
            bearing=data.get("bearing"),
            timestamp=datetime.now(),
            accuracy=data.get("accuracy"),
        )
        db.add(live_location)
        db.commit()
    except Exception as e:
        db.rollback()
        logger.error(f"Background location persistence failed: {e}")
    finally:
        db.close()

@router.get("/locations/latest/{entity_id}", response_model=Optional[LiveLocationResponse])
async def get_latest_location(
    entity_id: str,
    db: Session = Depends(get_db),
):
    """Get the latest recorded location for an entity"""
    # Try Redis cache first for fast path
    try:
        from ..services.cache import get_latest_location as get_cached
        cached = get_cached(f"entity:{entity_id}") or get_cached(f"bus:{entity_id}")
        if cached:
            return cached
    except Exception:
        pass

    location = db.query(models.LiveLocation).filter(
        models.LiveLocation.entity_id == entity_id
    ).order_by(
        models.LiveLocation.timestamp.desc()
    ).first()
    
    return location

@router.get("/locations/all-latest", response_model=List[LiveLocationResponse])
async def get_all_latest_locations(
    db: Session = Depends(get_db),
):
    """Get the latest location for all buses and students"""
    # Get latest location for each unique entity_id
    from sqlalchemy import func, desc
    latest_locations = db.query(
        models.LiveLocation.entity_id,
        func.max(models.LiveLocation.timestamp).label('max_timestamp')
    ).group_by(
        models.LiveLocation.entity_id
    ).subquery()
    
    locations = db.query(models.LiveLocation).join(
        latest_locations,
        (models.LiveLocation.entity_id == latest_locations.c.entity_id) &
        (models.LiveLocation.timestamp == latest_locations.c.max_timestamp)
    ).all()
    
    return locations

@router.get("/locations/active", response_model=List[LiveLocationResponse])
async def get_all_active_locations_from_cache(
    current_user: models.User = Depends(get_current_user),
):
    """Get all currently active locations from the in-memory cache."""
    active_locs = []
    user_role = str(current_user.role).lower()
    
    for u_id, loc in location_analyzer.active_locations.items():
        loc_role = loc.get("user_role", "student")
        
        # Students only see buses (driver role)
        if user_role == "student" and loc_role != "driver":
            continue
            
        entity_type = "bus" if loc_role == "driver" else "student"
        entity_id = str(loc.get("bus_id")) if loc_role == "driver" else str(u_id)

        active_locs.append(LiveLocationResponse(
            id=0, # Keep ID consistent with broadcast updates
            entity_id=entity_id,
            entity_type=entity_type,
            latitude=loc['lat'],
            longitude=loc['lng'],
            speed=loc['speed'],
            bearing=loc.get('bearing', loc.get('direction', 0.0)),
            timestamp=datetime.fromtimestamp(loc['timestamp']) if 'timestamp' in loc else datetime.now(),
            accuracy=loc.get('accuracy', 0.0)
        ))
    return active_locs

@router.get("/locations/history/{entity_id}", response_model=List[LiveLocationResponse])
async def get_location_history(
    entity_id: str,
    limit: int = 100,
    db: Session = Depends(get_db),
):
    """Get location history for an entity"""
    locations = db.query(models.LiveLocation).filter(
        models.LiveLocation.entity_id == entity_id
    ).order_by(
        models.LiveLocation.timestamp.desc()
    ).limit(limit).all()
    
    return locations[::-1]  # Reverse to get chronological order

# ==================== BUS ROUTES ====================

@router.get("/routes/{bus_id}", response_model=BusRouteResponse)
async def get_bus_route(
    bus_id: int,
    db: Session = Depends(get_db),
):
    """Get route information for a bus including boarding points"""
    bus_route = db.query(models.BusRoute).filter(
        models.BusRoute.bus_id == bus_id
    ).first()
    
    if not bus_route:
        # Return default route if not found
        bus = db.query(models.Bus).filter(models.Bus.id == bus_id).first()
        if not bus:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Bus not found"
            )
        
        # Get boarding points from bus stops
        boarding_points = db.query(models.BusStop).filter(
            models.BusStop.bus_id == bus_id
        ).order_by(models.BusStop.stop_order).all()
        
        return BusRouteResponse(
            bus_id=bus_id,
            boarding_points=boarding_points,
            total_distance_km=0.0,
            total_duration_minutes=0,
        )
    
    boarding_points = db.query(models.BusStop).filter(
        models.BusStop.bus_id == bus_id
    ).order_by(models.BusStop.stop_order).all()
    
    return BusRouteResponse(
        bus_id=bus_id,
        boarding_points=boarding_points,
        total_distance_km=bus_route.total_distance_km,
        total_duration_minutes=bus_route.total_duration_minutes,
    )

# ==================== STATS ====================

@router.get("/stats/bus/{bus_id}")
async def get_bus_tracking_stats(
    bus_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Get tracking statistics for a bus"""
    if current_user.role not in ["admin", "driver"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only admin and drivers can view tracking stats"
        )
    
    # Get active sessions
    active_sessions = db.query(models.TrackingSession).filter(
        models.TrackingSession.bus_id == bus_id,
        models.TrackingSession.end_time.is_(None)
    ).all()
    
    # Count by status
    to_boarding = len([s for s in active_sessions if s.status == "tracking_to_boarding"])
    at_boarding = len([s for s in active_sessions if s.status == "at_boarding"])
    to_college = len([s for s in active_sessions if s.status == "tracking_to_college"])
    
    return {
        "total_active_students": len(active_sessions),
        "tracking_to_boarding": to_boarding,
        "at_boarding": at_boarding,
        "tracking_to_college": to_college,
        "boarding_points": len(db.query(models.BusStop).filter(
            models.BusStop.bus_id == bus_id
        ).all()),
    }
