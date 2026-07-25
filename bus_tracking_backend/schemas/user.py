from pydantic import BaseModel, EmailStr
from typing import Optional, List
from ..database.models import UserRole

class UserBase(BaseModel):
    email: EmailStr
    full_name: Optional[str] = None
    role: str

class UserCreate(UserBase):
    password: str
    phone: Optional[str] = None

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class PinnedBusSchema(BaseModel):
    bus_id: int
    bus_number: str
    route_name: str

    class Config:
        from_attributes = True

class User(UserBase):
    id: str
    boarding_stop_id: Optional[int] = None
    assigned_bus_id: Optional[int] = None
    phone: Optional[str] = None
    pinned_buses: List[PinnedBusSchema] = []

    class Config:
        from_attributes = True