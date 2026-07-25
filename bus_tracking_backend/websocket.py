from pydantic import BaseModel
from typing import Optional, Dict, Any
from enum import Enum
from datetime import datetime

from .database import models

class MessageType(str, Enum):
    LOCATION_UPDATE = "LOCATION_UPDATE"
    PREDICTION_UPDATE = "PREDICTION_UPDATE"
    BOARDED_BUS = "BOARDED_BUS"
    ANNOUNCEMENT = "ANNOUNCEMENT"
    DOCUMENT_SHARED = "DOCUMENT_SHARED"
    BUS_STARTED = "BUS_STARTED"
    BUS_NEAR_STOP = "BUS_NEAR_STOP"

class LiveLocationUpdate(BaseModel):
    bus_id: int
    latitude: float
    longitude: float
    speed: float
    direction: float
    timestamp: float # Unix timestamp
    user_id: int # The user sending the update (driver)
    user_role: models.UserRole # Role of the user sending the update

class BoardedBusEvent(BaseModel):
    bus_id: int

class WebSocketNotificationMessage(BaseModel):
    recipient_user_id: int
    title: str
    message: str
    category: str
    data: Dict[str, Any]
    timestamp: datetime = datetime.now()