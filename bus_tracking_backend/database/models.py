from sqlalchemy import Column, Integer, String, Float, DateTime, Boolean, ForeignKey, Enum, Text, Index
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from bus_tracking_backend.database.database import Base
import enum
from typing import Optional

class UserRole(str, enum.Enum):
    ADMIN = "admin"
    STAFF = "staff"
    STUDENT = "student"
    DRIVER = "driver"

class User(Base):
    __tablename__ = "users"
    id = Column(String, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    full_name = Column(String)
    role = Column(String, default="student")
    is_active = Column(Boolean, default=True)
    boarding_stop_id = Column(Integer, ForeignKey("bus_stops.id"), nullable=True)
    phone = Column(String, nullable=True)
    assigned_bus_id = Column(Integer, ForeignKey("buses.id"), nullable=True)
    # Student login: individual login mapped to bus room ID
    bus_room_id = Column(Integer, ForeignKey("buses.id"), nullable=True)

    boarding_stop = relationship("BusStop", foreign_keys=[boarding_stop_id])
    pinned_buses = relationship("PinnedBus", back_populates="user")
    notification_settings = relationship("NotificationSetting", back_populates="user", uselist=False)
    assigned_bus = relationship("Bus", foreign_keys=[assigned_bus_id])
    bus_room = relationship("Bus", foreign_keys=[bus_room_id])
    # Custom boarding point coordinates (for "any location" boarding point selection)
    custom_boarding_lat = Column(Float, nullable=True)
    custom_boarding_lng = Column(Float, nullable=True)

    @property
    def assigned_bus_number(self) -> Optional[str]:
        """Get the bus number from the assigned bus relationship.
        This property is used by the Pydantic schema to serialize the bus number
        in the /auth/me response, so the Flutter app can display it correctly."""
        if self.assigned_bus:
            return self.assigned_bus.bus_number
        return None

class Bus(Base):
    __tablename__ = "buses"
    id = Column(Integer, primary_key=True, index=True)
    bus_number = Column(String, unique=True, index=True)
    route_name = Column(String)
    capacity = Column(Integer)
    driver_id = Column(String, ForeignKey("users.id"), nullable=True)
    status = Column(String, default="active")  # active, inactive, maintenance
    is_active = Column(Boolean, default=True)  # True if bus is ON and sharing location
    driver_phone = Column(String, nullable=True)
    # Bus location active state: if bus is ON, show active status correctly in dashboard
    location_sharing_active = Column(Boolean, default=False)

    stops = relationship("BusStop", back_populates="bus")
    pinned_by_users = relationship("PinnedBus", back_populates="bus")
    driver = relationship("User", foreign_keys=[driver_id])

class BusStop(Base):
    __tablename__ = "bus_stops"
    id = Column(Integer, primary_key=True, index=True)
    bus_id = Column(Integer, ForeignKey("buses.id"))
    stop_name = Column(String)
    latitude = Column(Float)
    longitude = Column(Float)
    stop_order = Column(Integer)
    scheduled_time = Column(String, nullable=True)

    bus = relationship("Bus", back_populates="stops")

class PinnedBus(Base):
    __tablename__ = "pinned_buses"
    __table_args__ = (
        Index('idx_pinned_user_bus', 'user_id', 'bus_id'),
    )
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String, ForeignKey("users.id"), index=True)
    bus_id = Column(Integer, ForeignKey("buses.id"), nullable=True)
    bus_number = Column(String, nullable=True)
    boarding_stop_id = Column(Integer, ForeignKey("bus_stops.id"), nullable=True)
    pinned_at = Column(DateTime, default=func.now())

    user = relationship("User", back_populates="pinned_buses")
    bus = relationship("Bus", back_populates="pinned_by_users")
    boarding_stop = relationship("BusStop")

    @property
    def effective_bus_number(self) -> Optional[str]:
        """Return bus_number from DB column if available, otherwise from the Bus relationship."""
        if self.bus_number:
            return self.bus_number
        if self.bus:
            return self.bus.bus_number
        return None

    @property
    def effective_route_name(self) -> Optional[str]:
        """Return route_name from the Bus relationship if available."""
        if self.bus:
            return self.bus.route_name
        return None

class NotificationSetting(Base):
    __tablename__ = "notification_settings"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String, ForeignKey("users.id"), unique=True, nullable=False)
    # These columns are added to existing databases via ALTER TABLE in init_db._migrate_columns()
    push_enabled = Column(Boolean, default=True)
    email_enabled = Column(Boolean, default=False)
    sms_enabled = Column(Boolean, default=False)
    user = relationship("User", back_populates="notification_settings")

class DeviceToken(Base):
    __tablename__ = "device_tokens"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String, ForeignKey("users.id"), index=True)
    token = Column(String, unique=True, index=True, nullable=False)
    platform = Column(String, default="android")
    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())

class TrackingSession(Base):
    """Represents a student's tracking session for a bus"""
    __tablename__ = "tracking_sessions"
    __table_args__ = (
        Index('idx_tracking_bus_time', 'bus_id', 'start_time'),
    )
    id = Column(String, primary_key=True, index=True)
    student_id = Column(String, ForeignKey("users.id"), index=True)
    bus_id = Column(Integer, ForeignKey("buses.id"), index=True)
    boarding_point_id = Column(Integer, ForeignKey("bus_stops.id"), nullable=True)
    start_time = Column(DateTime, default=func.now(), index=True)
    end_time = Column(DateTime, nullable=True)
    status = Column(String, default="tracking_to_boarding")  # tracking_to_boarding, at_boarding, tracking_to_college, completed
    distance_to_bus = Column(Float, default=0.0)
    distance_to_boarding = Column(Float, default=0.0)
    total_distance_to_college = Column(Float, default=0.0)
    estimated_minutes_to_bus = Column(Integer, default=0)
    estimated_minutes_to_college = Column(Integer, default=0)

    student = relationship("User")
    bus = relationship("Bus")
    boarding_point = relationship("BusStop")

class LiveLocation(Base):
    """Real-time location data for buses and students"""
    __tablename__ = "live_locations"
    __table_args__ = (
        Index('idx_live_entity_time', 'entity_id', 'timestamp'),
    )
    id = Column(Integer, primary_key=True, index=True)
    entity_id = Column(String, index=True)  # bus_id or student_id
    entity_type = Column(String)  # "bus" or "student"
    latitude = Column(Float)
    longitude = Column(Float)
    speed = Column(Float, default=0.0)
    bearing = Column(Float, default=0.0)
    timestamp = Column(DateTime, default=func.now(), index=True)
    accuracy = Column(Float, default=0.0)
    created_at = Column(DateTime, default=func.now())

class BusRoute(Base):
    """Bus route configuration with boarding points"""
    __tablename__ = "bus_routes"
    id = Column(Integer, primary_key=True, index=True)
    bus_id = Column(Integer, ForeignKey("buses.id"), unique=True, index=True)
    total_distance_km = Column(Float, default=0.0)
    total_duration_minutes = Column(Integer, default=0)
    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())

    bus = relationship("Bus")

class Announcement(Base):
    """Announcements created by admin/staff for users"""
    __tablename__ = "announcements"
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, nullable=False)
    message = Column(Text, nullable=False)
    target_role = Column(String, default="all")  # admin, staff, student, driver, all
    priority = Column(String, default="normal")
    expires_at = Column(DateTime, nullable=True)
    created_by_user_id = Column(String, ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime, default=func.now())

    created_by = relationship("User")

class Request(Base):
    """Requests submitted by students (e.g., bus change, issue report)"""
    __tablename__ = "requests"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    bus_id = Column(Integer, ForeignKey("buses.id"), nullable=True)
    request_type = Column(String, nullable=False)
    description = Column(Text, nullable=False)
    status = Column(String, default="pending")
    created_at = Column(DateTime, default=func.now())
    resolved_at = Column(DateTime, nullable=True)

    user = relationship("User")
    bus = relationship("Bus")

class Document(Base):
    """Documents uploaded by admin/staff for students"""
    __tablename__ = "documents"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    file_path = Column(String, nullable=False)
    file_size = Column(Integer, default=0)
    file_type = Column(String, default="file")
    category = Column(String, default="general")
    uploaded_by_id = Column(String, ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime, default=func.now())

    uploaded_by = relationship("User")

class Feedback(Base):
    """Feedback and complaints submitted by users"""
    __tablename__ = "feedback"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    user_name = Column(String, nullable=True)
    user_role = Column(String, nullable=True)
    subject = Column(String, nullable=False)
    message = Column(Text, nullable=False)
    reply = Column(Text, nullable=True)
    replied = Column(Boolean, default=False)
    created_at = Column(DateTime, default=func.now())
    replied_at = Column(DateTime, nullable=True)

    user = relationship("User")

class UserDismissedItem(Base):
    """Tracks items dismissed by individual users (personal delete memory).
    Does NOT delete the item globally — only hides it from that user's view."""
    __tablename__ = "user_dismissed_items"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    item_type = Column(String, nullable=False, index=True)  # "announcement" or "document"
    item_id = Column(Integer, nullable=False, index=True)
    dismissed_at = Column(DateTime, default=func.now())
