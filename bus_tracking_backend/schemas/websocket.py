from pydantic import BaseModel
from typing import Optional, Dict, Any
from enum import Enum
from datetime import datetime

class MessageType(str, Enum):
    LOCATION_UPDATE = "LOCATION_UPDATE"
    PREDICTION_UPDATE = "PREDICTION_UPDATE"
    BOARDED_BUS = "BOARDED_BUS"
    ANNOUNCEMENT = "ANNOUNCEMENT"
    DOCUMENT_SHARED = "DOCUMENT_SHARED"
    BUS_STARTED = "BUS_STARTED"
    BUS_NEAR_STOP = "BUS_NEAR_STOP"

class BoardedBusEvent(BaseModel):
    bus_id: int

class WebSocketNotificationMessage(BaseModel):
    recipient_user_id: int
    title: str
    message: str
    category: str
    data: Dict[str, Any]
    timestamp: datetime = datetime.now()