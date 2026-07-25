from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class AnnouncementBase(BaseModel):
    title: str
    message: str
    target_role: str = "all"
    priority: str = "normal"
    expires_at: Optional[datetime] = None

class AnnouncementCreate(AnnouncementBase):
    pass

class Announcement(AnnouncementBase):
    id: int
    created_by_user_id: Optional[str] = None
    created_at: datetime = datetime.now()

    class Config:
        from_attributes = True