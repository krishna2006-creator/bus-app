from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from ..database import crud, models
from ..database.database import get_db
from ..schemas import request as request_schemas
from ..schemas import user as user_schemas
from ..services.notification_service import notification_service
from ..utils.auth_utils import get_current_user

router = APIRouter(prefix="/requests", tags=["Requests"])

@router.post("/", response_model=request_schemas.Request)
async def create_request(
    request: request_schemas.RequestCreate,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    db_request = crud.create_request(db, request, current_user.id)
    
    # Notify Admins about the new request
    await notification_service.broadcast_to_role(
        db,
        "New Student Request",
        f"{current_user.full_name} has submitted a {request.request_type} request.",
        "request",
        target_role="admin"
    )
    
    # Notify the student themselves about their request confirmation
    await notification_service.send_personal_notification(
        current_user.id,
        "Request Submitted",
        f"Your {request.request_type} request has been submitted successfully.",
        "request_status",
        data={"request_id": db_request.id, "request_type": request.request_type}
    )
    
    return db_request
