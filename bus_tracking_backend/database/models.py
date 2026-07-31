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
    __tablename__ = 'bus_stops'  
    id = Column(Integer, primary_key=True, index=True)  
    bus_id = Column(Integer, ForeignKey('buses.id'), nullable=True)  
    name = Column(String, nullable=False)  
    latitude = Column(Float, nullable=False)  
    longitude = Column(Float, nullable=False)  
    order = Column(Integer, default=0)  
    bus = relationship('Bus', back_populates='stops')


class LiveLocation(Base):
    __tablename__ = 'live_locations'
    id = Column(Integer, primary_key=True, index=True)
    entity_id = Column(String, nullable=False, index=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    bearing = Column(Float, nullable=True)
    speed = Column(Float, nullable=True)
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())

class DeviceToken(Base):
    __tablename__ = 'device_tokens'
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String, ForeignKey('users.id'), nullable=False)
    token = Column(String, nullable=False, unique=True)
    platform = Column(String, nullable=True)
    created_at = Column(DateTime, default=func.now())
