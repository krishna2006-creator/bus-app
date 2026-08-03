from sqlalchemy.orm import Session
from bus_tracking_backend.database import models
from bus_tracking_backend.schemas import user as user_schemas
from bus_tracking_backend.schemas import bus as bus_schemas
from bus_tracking_backend.schemas import announcement as announcement_schemas
from bus_tracking_backend.schemas import request as request_schemas
from datetime import datetime

# --- User CRUD ---
def get_user(db: Session, user_id: str):
    return db.query(models.User).filter(models.User.id == user_id).first()

def get_user_by_email(db: Session, email: str):
    return db.query(models.User).filter(models.User.email == email).first()

def create_user(db: Session, user: user_schemas.UserCreate, hashed_password: str):
    db_user = models.User(
        id=user.email.split('@')[0],
        email=user.email,
        hashed_password=hashed_password,
        full_name=user.full_name,
        role=user.role,
        phone=getattr(user, 'phone', None),
    )
    db.add(db_user)
    db.flush()

    db_settings = models.NotificationSetting(user_id=db_user.id)
    db.add(db_settings)

    db.commit()
    db.refresh(db_user)
    return db_user

# --- Bus CRUD ---
def get_bus(db: Session, bus_id: int):
    return db.query(models.Bus).filter(models.Bus.id == bus_id).first()

def get_buses(db: Session, skip: int = 0, limit: int = 100):
    return db.query(models.Bus).offset(skip).limit(limit).all()

def create_bus_with_stops(db: Session, bus: bus_schemas.BusCreate):
    db_bus = models.Bus(
        bus_number=bus.bus_number,
        route_name=bus.route_name,
        capacity=bus.capacity,
        driver_id=bus.driver_id,
        status=bus.status,
        driver_phone=getattr(bus, 'driver_phone', None),
    )
    db.add(db_bus)
    db.flush()

    for stop_data in bus.stops:
        db_stop = models.BusStop(
            bus_id=db_bus.id,
            stop_name=stop_data.stop_name,
            latitude=stop_data.latitude,
            longitude=stop_data.longitude,
            stop_order=stop_data.stop_order,
            scheduled_time=getattr(stop_data, 'scheduled_time', None),
        )
        db.add(db_stop)

    db.commit()
    db.refresh(db_bus)
    return db_bus

def update_bus(db: Session, bus_id: int, bus: bus_schemas.BusCreate):
    db_bus = db.query(models.Bus).filter(models.Bus.id == bus_id).first()
    if db_bus:
        db_bus.bus_number = bus.bus_number
        db_bus.route_name = bus.route_name
        db_bus.capacity = bus.capacity
        db_bus.driver_id = bus.driver_id
        db_bus.status = bus.status
        db_bus.driver_phone = getattr(bus, 'driver_phone', None)

        # Simple stop update: remove old, add new
        db.query(models.BusStop).filter(models.BusStop.bus_id == bus_id).delete()
        for stop_data in bus.stops:
            db_stop = models.BusStop(
                bus_id=db_bus.id,
                stop_name=stop_data.stop_name,
                latitude=stop_data.latitude,
                longitude=stop_data.longitude,
                stop_order=stop_data.stop_order,
                scheduled_time=getattr(stop_data, 'scheduled_time', None),
            )
            db.add(db_stop)

        db.commit()
        db.refresh(db_bus)
    return db_bus

def delete_bus(db: Session, bus_id: int):
    db_bus = db.query(models.Bus).filter(models.Bus.id == bus_id).first()
    if db_bus:
        db.delete(db_bus)
        db.commit()
        return True
    return False

# --- Stop CRUD ---
def get_all_stops(db: Session):
    return db.query(models.BusStop).all()

def get_stop_by_id(db: Session, stop_id: int):
    return db.query(models.BusStop).filter(models.BusStop.id == stop_id).first()

def search_stops(db: Session, query: str):
    """Search for bus stops by name"""
    return db.query(models.BusStop).filter(
        models.BusStop.stop_name.ilike(f"%{query}%")
    ).all()

# --- Announcement CRUD ---
def create_announcement(db: Session, announcement: announcement_schemas.AnnouncementCreate, user_id: str):
    db_announcement = models.Announcement(
        title=announcement.title,
        message=announcement.message,
        target_role=announcement.target_role,
        priority=getattr(announcement, 'priority', 'normal'),
        expires_at=announcement.expires_at,
        created_by_user_id=user_id
    )
    db.add(db_announcement)
    db.commit()
    db.refresh(db_announcement)
    return db_announcement

def get_announcements(db: Session, target_role: str):
    return db.query(models.Announcement).filter(
        (models.Announcement.target_role == target_role) | (models.Announcement.target_role == "all")
    ).all()

def delete_announcement(db: Session, announcement_id: int):
    db_announcement = db.query(models.Announcement).filter(models.Announcement.id == announcement_id).first()
    if db_announcement:
        db.delete(db_announcement)
        db.commit()
        return True
    return False

# --- Request CRUD ---
def create_request(db: Session, request: request_schemas.RequestCreate, user_id: str):
    db_request = models.Request(
        user_id=user_id,
        bus_id=request.bus_id,
        request_type=request.request_type,
        description=request.description
    )
    db.add(db_request)
    db.commit()
    db.refresh(db_request)
    return db_request

def get_requests(db: Session, skip: int = 0, limit: int = 100):
    return db.query(models.Request).order_by(models.Request.id.desc()).offset(skip).limit(limit).all()

def get_user_requests(db: Session, user_id: str):
    return db.query(models.Request).filter(models.Request.user_id == user_id).all()

# --- User Boarding Stop ---
def update_user_boarding_stop(db: Session, user_id: str, stop_id: int):
    """
    Updates the boarding_stop_id for a specific user.
    Validates that the stop_id exists in the bus_stops table first.
    Returns None if the user or stop is not found.
    """
    # Validate stop_id is a positive integer (negative values like -2 are invalid)
    if stop_id <= 0:
        return None
    
    # Verify the stop exists in the database
    db_stop = db.query(models.BusStop).filter(models.BusStop.id == stop_id).first()
    if not db_stop:
        return None
    
    db_user = db.query(models.User).filter(models.User.id == user_id).first()
    if db_user:
        db_user.boarding_stop_id = stop_id
        db.commit()
        db.refresh(db_user)
        return db_user
    return None

def get_user_boarding_stop(db: Session, user_id: str):
    """
    Retrieves the boarding stop for a given user.
    """
    db_user = db.query(models.User).filter(models.User.id == user_id).first()
    if db_user and db_user.boarding_stop_id:
        return db.query(models.BusStop).filter(models.BusStop.id == db_user.boarding_stop_id).first()
    return None

# --- Custom Boarding Point (any location on map) ---
def set_user_boarding_coords(db: Session, user_id: str, lat: float, lng: float):
    """
    Sets a custom boarding point by GPS coordinates (not tied to a system stop).
    Clears boarding_stop_id so the custom coords are used as the boarding point.
    """
    db_user = db.query(models.User).filter(models.User.id == user_id).first()
    if db_user:
        db_user.boarding_stop_id = None
        db_user.custom_boarding_lat = lat
        db_user.custom_boarding_lng = lng
        db.commit()
        db.refresh(db_user)
        return db_user
    return None

def get_user_boarding_coords(db: Session, user_id: str):
    """
    Returns the user's boarding point location — either from the system stop
    or from custom coordinates.
    """
    db_user = db.query(models.User).filter(models.User.id == user_id).first()
    if not db_user:
        return None
    # Prefer custom coordinates if set
    if db_user.custom_boarding_lat is not None and db_user.custom_boarding_lng is not None:
        return {
            "id": -1,
            "name": "Custom Location",
            "latitude": db_user.custom_boarding_lat,
            "longitude": db_user.custom_boarding_lng,
            "stop_order": 0,
            "scheduled_time": None,
        }
    # Fallback to system stop
    if db_user.boarding_stop_id:
        stop = db.query(models.BusStop).filter(models.BusStop.id == db_user.boarding_stop_id).first()
        if stop:
            return {
                "id": stop.id,
                "name": stop.stop_name,
                "latitude": stop.latitude,
                "longitude": stop.longitude,
                "stop_order": stop.stop_order,
                "scheduled_time": stop.scheduled_time,
            }
    return None

# --- User Dismissed Items (personal delete memory) ---
def dismiss_item(db: Session, user_id: str, item_type: str, item_id: int):
    """Records that a user has dismissed (hidden) an announcement or document."""
    existing = db.query(models.UserDismissedItem).filter(
        models.UserDismissedItem.user_id == user_id,
        models.UserDismissedItem.item_type == item_type,
        models.UserDismissedItem.item_id == item_id,
    ).first()
    if not existing:
        dismissed = models.UserDismissedItem(
            user_id=user_id, item_type=item_type, item_id=item_id
        )
        db.add(dismissed)
        db.commit()
    return True

def get_dismissed_item_ids(db: Session, user_id: str, item_type: str):
    """Returns a list of item IDs that the user has dismissed for a given type."""
    records = db.query(models.UserDismissedItem).filter(
        models.UserDismissedItem.user_id == user_id,
        models.UserDismissedItem.item_type == item_type,
    ).all()
    return [r.item_id for r in records]
