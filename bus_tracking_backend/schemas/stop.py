from pydantic import BaseModel, Field
from typing import Optional

class StopBase(BaseModel):
    name: str = Field(..., alias="stop_name")
    latitude: float
    longitude: float

class StopCreate(StopBase):
    pass

class Stop(StopBase):
    id: int
    class Config:
        from_attributes = True
        populate_by_name = True