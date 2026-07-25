from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..database.database import get_db
from ..database import models
from ..utils.auth_utils import get_current_user

router = APIRouter(prefix="/notifications", tags=["Notifications"])


class DeviceTokenRequest(BaseModel):
    token: str
    platform: str = "android"


@router.post("/device-token")
def register_device_token(
    payload: DeviceTokenRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if not payload.token:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Device token is required")

    existing = (
        db.query(models.DeviceToken)
        .filter(models.DeviceToken.token == payload.token)
        .first()
    )

    if existing:
        existing.user_id = current_user.id
        existing.platform = payload.platform
        db.commit()
        return {"status": "ok", "message": "Device token updated"}

    device_token = models.DeviceToken(
        user_id=current_user.id,
        token=payload.token,
        platform=payload.platform,
    )
    db.add(device_token)
    db.commit()
    return {"status": "ok", "message": "Device token registered"}
