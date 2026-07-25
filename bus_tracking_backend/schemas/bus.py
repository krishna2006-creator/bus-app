from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
from ..database.models import UserRole

class StopBase(BaseModel):
    stop_name: str
    latitude: float
    longitude: float
    scheduled_time: Optional[str] = None
    stop_order: int

class StopCreate(StopBase):
    pass

class StopResponse(StopBase):
    id: int
    bus_id: int
    class Config:
        from_attributes = True

class BusBase(BaseModel):
    bus_number: str
    route_name: str
    capacity: int
    driver_id: Optional[str] = None
    status: str = "active"
    driver_phone: Optional[str] = None

class BusCreate(BusBase):
    stops: List[StopCreate] = []

class BusResponse(BusBase):
    id: int
    stops: List[StopResponse] = []
    class Config:
        from_attributes = True

class LiveLocationUpdate(BaseModel):
    bus_id: Optional[int] = None
    user_role: str
    user_id: str
    latitude: float
    longitude: float
    speed: float = 0.0
    direction: float = 0.0
    timestamp: float

class LiveLocationResponse(BaseModel):
    id: int
    bus_id: Optional[int] = None
    user_id: str
    latitude: float
    longitude: float
    speed: float
    direction: float
    source_type: str = "live"
    timestamp: datetime
    class Config:
        from_attributes = True

class PinnedBusCreate(BaseModel):
    bus_id: int
    boarding_stop_id: Optional[int] = None

class PinnedBusResponse(PinnedBusCreate):
    id: int
    user_id: str
    class Config:
        from_attributes = True

class BusAnalysisResult(BaseModel):
    bus_id: int
    bus_number: str
    route_name: str
    boarding_point_id: int
    boarding_point_name: str
    distance_to_student_km: float
    eta_to_boarding_point_minutes: int
    traffic_level: str
    estimated_arrival_at_boarding_point: datetime
    estimated_arrival_at_college: datetime

class PredictionResponse(BaseModel):
    bus_id: int
    bus_number: str
    route_name: str
    eta_minutes: int
    distance_km: float
    traffic_level: str
    arrival_time: datetime
    is_to_college: bool = False