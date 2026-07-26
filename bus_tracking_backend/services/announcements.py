from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List

from ..database import crud, models
from ..database.database import get_db
from ..schemas import announcement as announcement_schemas
from ..schemas import user as user_schemas
from .notification_service import notification_service
from ..utils.auth_utils import get_current_user

router = APIRouter(
    prefix="/announcements",
    tags=["Announcements"],
    responses={404: {"description": "Not found"}},
)

@router.get("/", response_model=List[announcement_schemas.Announcement])
def read_announcements(
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    # Get announcements relevant to the user's role
    announcements = crud.get_announcements(db, target_role=current_user.role.value)
    return announcements

@router.post("/", response_model=announcement_schemas.Announcement)
async def create_announcement(
    announcement: announcement_schemas.AnnouncementCreate,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    if current_user.role not in [models.UserRole.ADMIN, models.UserRole.STAFF]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to create announcements")
    
    db_announcement = crud.create_announcement(db=db, announcement=announcement, user_id=current_user.id)
    
    # Send real-time notification for the new announcement (exclude the creator)
    await notification_service.broadcast_to_role(
        db,
        title=db_announcement.title,
        message=db_announcement.message,
        category="ANNOUNCEMENT",
        target_role=db_announcement.target_role,
        exclude_user_id=current_user.id
    )
    
    return db_announcement

@router.delete("/{announcement_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_announcement(
    announcement_id: int,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    if current_user.role not in [models.UserRole.ADMIN, models.UserRole.STAFF]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to delete announcements")
    
    crud.delete_announcement(db, announcement_id=announcement_id) # Assuming crud.delete_announcement exists
    return {"message": "Announcement deleted successfully"}