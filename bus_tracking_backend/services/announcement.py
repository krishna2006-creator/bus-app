from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class AnnouncementBase(BaseModel):
    title: str
    message: str
    target_role: str = "all"
    expires_at: Optional[datetime] = None

class AnnouncementCreate(AnnouncementBase):
    pass

class Announcement(AnnouncementBase):
    id: int
    created_by_user_id: str
    created_at: datetime

    class Config:
        from_attributes = True