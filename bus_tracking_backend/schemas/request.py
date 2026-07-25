from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class RequestBase(BaseModel):
    bus_id: Optional[int] = None
    request_type: str
    description: str

class RequestCreate(RequestBase):
    pass

class Request(RequestBase):
    id: int
    user_id: str
    status: str = "pending"
    created_at: datetime = datetime.now()

    class Config:
        from_attributes = True