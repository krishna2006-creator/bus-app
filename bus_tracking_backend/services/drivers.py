from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from ..database.database import get_db
from ..schemas import user as user_schemas
from ..utils.auth_utils import get_current_user
from ..database import models

router = APIRouter(prefix="/drivers", tags=["Drivers"])

@router.get("/me", response_model=user_schemas.User)
def read_driver_me(current_user: user_schemas.User = Depends(get_current_user)):
    if current_user.role != models.UserRole.DRIVER:
        raise HTTPException(status_code=403, detail="Not a driver")
    return current_user