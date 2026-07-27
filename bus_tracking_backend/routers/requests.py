from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from ..database import crud, models
from ..database.database import get_db
from ..schemas import request as request_schemas
from ..schemas import user as user_schemas
from ..services.notification_service import notification_service
from ..utils.auth_utils import get_current_user
from typing import List

router = APIRouter(prefix="/requests", tags=["Requests"])

@router.get("", include_in_schema=False)
@router.get("/", include_in_schema=False)
async def read_requests(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Admin: Get all requests. Users: Get their own requests."""
    if current_user.role == "admin":
        requests = db.query(models.Request).order_by(models.Request.id.desc()).all()
    else:
        requests = db.query(models.Request).filter(
            models.Request.user_id == current_user.id
        ).order_by(models.Request.id.desc()).all()
    
    result = []
    for r in requests:
        user = db.query(models.User).filter(models.User.id == r.user_id).first()
        bus = db.query(models.Bus).filter(models.Bus.id == r.bus_id).first() if r.bus_id else None
        result.append({
            "id": str(r.id),
            "user_id": r.user_id,
            "user_name": user.full_name if user else "Unknown",
            "bus_number": bus.bus_number if bus else "N/A",
            "bus_id": r.bus_id,
            "request_type": r.request_type,
            "description": r.description,
            "status": r.status,
            "created_at": r.created_at.isoformat() if r.created_at else None,
            "resolved_at": r.resolved_at.isoformat() if r.resolved_at else None,
        })
    return result

@router.post("", include_in_schema=False)
@router.post("/", include_in_schema=False)
async def create_request(
    data: dict,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    db_request = models.Request(
        user_id=current_user.id,
        bus_id=data.get("bus_id"),
        request_type=data.get("request_type", "general"),
        description=data.get("description", ""),
        status="pending",
    )
    db.add(db_request)
    db.commit()
    db.refresh(db_request)
    
    # Get user name for notification
    user_name = current_user.full_name or current_user.email
    
    # Notify Admins about the new request
    await notification_service.broadcast_to_role(
        db,
        "New Student Request",
        f"{user_name} has submitted a {data.get('request_type', 'general')} request.",
        "request",
        target_role="admin",
        data={"request_id": db_request.id, "request_type": data.get('request_type', '')}
    )
    
    # Notify the student themselves about their request confirmation
    await notification_service.send_personal_notification(
        current_user.id,
        "Request Submitted",
        f"Your {data.get('request_type', 'general')} request has been submitted successfully.",
        "request_status",
        data={"request_id": db_request.id, "request_type": data.get('request_type', '')}
    )
    
    return {
        "status": "success",
        "id": db_request.id,
        "message": "Request submitted successfully"
    }

@router.delete("/{request_id}", include_in_schema=False)
async def delete_request(
    request_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Admin: Delete request."""
    if current_user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")
    
    db_request = db.query(models.Request).filter(models.Request.id == request_id).first()
    if not db_request:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")
    
    db.delete(db_request)
    db.commit()
    
    return {"status": "success", "message": "Request deleted successfully"}

@router.post("/{request_id}/status", include_in_schema=False)
@router.post("/{request_id}/status/", include_in_schema=False)
async def update_request_status(
    request_id: int,
    data: dict,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Admin: Update request status."""
    if current_user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")
    
    db_request = db.query(models.Request).filter(models.Request.id == request_id).first()
    if not db_request:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")
    
    new_status = data.get("status", "pending")
    db_request.status = new_status
    if new_status in ["approved", "resolved", "rejected"]:
        from datetime import datetime
        db_request.resolved_at = datetime.utcnow()
    db.commit()
    
    # Notify the student about status update
    await notification_service.send_personal_notification(
        db_request.user_id,
        "Request Status Updated",
        f"Your request has been {new_status}.",
        "request_status",
        data={"request_id": db_request.id, "status": new_status}
    )
    
    return {"status": "success", "message": f"Request {new_status}"}