from pydantic import BaseModel
from typing import Optional

class RequestBase(BaseModel):
    bus_id: Optional[int] = None
    request_type: str
    description: str

class RequestCreate(RequestBase):
    pass

class Request(RequestBase):
    id: int
    user_id: int
    status: str = "pending"

    class Config:
        from_attributes = True