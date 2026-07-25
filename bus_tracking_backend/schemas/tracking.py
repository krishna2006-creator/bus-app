from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime

class BoardingPointSchema(BaseModel):
    id: int
    stop_name: str
    latitude: float
    longitude: float
    stop_order: int

    class Config:
        from_attributes = True

class TrackingSessionCreate(BaseModel):
    id: str
    bus_id: int
    boarding_point_id: int

class TrackingSessionUpdate(BaseModel):
    status: Optional[str] = None
    distance_to_bus: Optional[float] = None
    distance_to_boarding: Optional[float] = None
    total_distance_to_college: Optional[float] = None
    estimated_minutes_to_bus: Optional[int] = None
    estimated_minutes_to_college: Optional[int] = None

class TrackingSessionResponse(BaseModel):
    id: str
    student_id: str
    bus_id: int
    boarding_point_id: Optional[int]
    start_time: datetime
    end_time: Optional[datetime]
    status: str
    distance_to_bus: float
    distance_to_boarding: float
    total_distance_to_college: float
    estimated_minutes_to_bus: int
    estimated_minutes_to_college: int

    class Config:
        from_attributes = True

class LiveLocationCreate(BaseModel):
    entity_id: str
    entity_type: str  # "bus" or "student"
    latitude: float
    longitude: float
    speed: float = 0.0
    bearing: float = 0.0
    accuracy: float = 0.0

class LiveLocationResponse(BaseModel):
    id: int
    entity_id: str
    entity_type: str
    latitude: float
    longitude: float
    speed: float
    bearing: float
    timestamp: datetime
    accuracy: float

    class Config:
        from_attributes = True

class BusRouteResponse(BaseModel):
    bus_id: int
    boarding_points: List[BoardingPointSchema]
    total_distance_km: float
    total_duration_minutes: int

    class Config:
        from_attributes = True
