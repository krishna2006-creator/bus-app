from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List

from ..database import crud, models
from ..database.database import get_db
from ..schemas import announcement as announcement_schemas
from ..schemas import user as user_schemas
from ..services.notification_service import notification_service
from ..utils.auth_utils import get_current_user, normalize_role

router = APIRouter(
    prefix="/announcements",
    tags=["Announcements"],
    responses={404: {"description": "Not found"}},
)

@router.get("", response_model=List[announcement_schemas.Announcement])
@router.get("/", response_model=List[announcement_schemas.Announcement])
def read_announcements(
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    raw_announcements = crud.get_announcements(db, target_role=normalize_role(current_user.role))
    # Filter out items dismissed by this user (personal delete memory)
    dismissed_ids = set(crud.get_dismissed_item_ids(db, current_user.id, "announcement"))
    return [a for a in raw_announcements if a.id not in dismissed_ids]

@router.delete("/{announcement_id}/dismiss", status_code=status.HTTP_200_OK)
def dismiss_announcement(
    announcement_id: int,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    """Student/Staff: Dismiss (hide) an announcement from your personal view only.
    Does NOT delete it globally - admin/staff can still see it. Your dismissal persists."""
    crud.dismiss_item(db, current_user.id, "announcement", announcement_id)
    return {"status": "dismissed", "message": "Announcement dismissed from your view"}

@router.post("", response_model=announcement_schemas.Announcement)
@router.post("/", response_model=announcement_schemas.Announcement)
async def create_announcement(
    announcement: announcement_schemas.AnnouncementCreate,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")
    
    db_announcement = crud.create_announcement(db=db, announcement=announcement, user_id=current_user.id)
    
    # Send real-time notification (exclude the creator so admin doesn't get their own notification)
    await notification_service.broadcast_to_role(
        db,
        title=f"Announcement: {db_announcement.title}",
        message=db_announcement.message,
        category="announcement",
        target_role=db_announcement.target_role,
        data={
            "id": db_announcement.id,
            "priority": "high"
        },
        exclude_user_id=current_user.id
    )
    
    return db_announcement
