from fastapi import APIRouter, Depends, HTTPException, Body
from sqlalchemy.orm import Session
from typing import List
from datetime import datetime

from bus_tracking_backend.database.database import get_db
from bus_tracking_backend.database import models
from bus_tracking_backend.utils.auth_utils import get_current_user
from bus_tracking_backend.services.notification_service import notification_service

router = APIRouter(prefix="/feedback", tags=["feedback"])

@router.get("", include_in_schema=False)
@router.get("/", include_in_schema=False)
async def get_all_feedback(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Admin: Get all feedback. Users: Get their own feedback."""
    if current_user.role == "admin":
        feedbacks = db.query(models.Feedback).order_by(models.Feedback.created_at.desc()).all()
    else:
        feedbacks = db.query(models.Feedback).filter(
            models.Feedback.user_id == current_user.id
        ).order_by(models.Feedback.created_at.desc()).all()
    
    result = []
    for f in feedbacks:
        result.append({
            "id": f.id,
            "userId": str(f.user_id),
            "userName": f.user_name,
            "userRole": f.user_role,
            "subject": f.subject,
            "message": f.message,
            "reply": f.reply,
            "replied": f.replied,
            "created_at": f.created_at.isoformat() if f.created_at else None,
            "repliedAt": f.replied_at.isoformat() if f.replied_at else None,
        })
    return result

@router.post("", include_in_schema=False)
@router.post("/", include_in_schema=False)
async def submit_feedback(
    data: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Submit feedback or complaint."""
    feedback = models.Feedback(
        user_id=current_user.id,
        user_name=current_user.full_name or "Anonymous",
        user_role=current_user.role,
        subject=data.get("subject", ""),
        message=data.get("message", ""),
        replied=False,
        created_at=datetime.utcnow(),
    )
    db.add(feedback)
    db.commit()
    db.refresh(feedback)
    
    # Notify admins about new feedback
    await notification_service.broadcast_to_role(
        db,
        "New Feedback Received",
        f"{current_user.full_name or 'User'} has submitted feedback: {data.get('subject', '')}",
        "feedback",
        target_role="admin",
        data={"feedback_id": feedback.id, "subject": data.get("subject", "")}
    )
    
    return {
        "status": "success",
        "id": feedback.id,
        "message": "Feedback submitted successfully"
    }

@router.delete("/{feedback_id}", include_in_schema=False)
async def delete_feedback(
    feedback_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Admin: Delete feedback."""
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")
    
    feedback = db.query(models.Feedback).filter(models.Feedback.id == feedback_id).first()
    if not feedback:
        raise HTTPException(status_code=404, detail="Feedback not found")
    
    db.delete(feedback)
    db.commit()
    
    return {"status": "success", "message": "Feedback deleted successfully"}

@router.post("/{feedback_id}/reply", include_in_schema=False)
@router.post("/{feedback_id}/reply/", include_in_schema=False)
async def reply_to_feedback(
    feedback_id: int,
    data: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Admin: Reply to feedback."""
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")
    
    feedback = db.query(models.Feedback).filter(models.Feedback.id == feedback_id).first()
    if not feedback:
        raise HTTPException(status_code=404, detail="Feedback not found")
    
    feedback.reply = data.get("reply", "")
    feedback.replied = True
    feedback.replied_at = datetime.utcnow()
    db.commit()
    
    # Notify the student about the admin reply
    await notification_service.send_personal_notification(
        feedback.user_id,
        "Feedback Reply Received",
        f"Admin has replied to your feedback: {feedback.subject}",
        "feedback_reply",
        data={"feedback_id": feedback.id, "reply": feedback.reply}
    )
    
    return {"status": "success", "message": "Reply sent successfully"}