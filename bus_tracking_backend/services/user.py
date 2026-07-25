from pydantic import BaseModel, EmailStr
from typing import Optional
from enum import Enum

class UserRole(str, Enum):
    STUDENT = "student"
    DRIVER = "driver"
    STAFF = "staff"
    ADMIN = "admin"

class UserBase(BaseModel):
    email: EmailStr
    full_name: str
    role: UserRole

class UserCreate(UserBase):
    password: str

class User(UserBase):
    id: str
    boarding_stop_id: Optional[int] = None
    
    class Config:
        from_attributes = True