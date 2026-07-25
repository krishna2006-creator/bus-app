from fastapi import APIRouter, Depends, HTTPException, status, List
from sqlalchemy.orm import Session
from ..database import crud, models
from ..database.database import get_db
from ..schemas import request as request_schemas
from ..schemas import user as user_schemas
from ..utils.auth_utils import get_current_user

router = APIRouter(prefix="/requests", tags=["Requests"])

@router.post("/", response_model=request_schemas.Request)
def create_request(
    request: request_schemas.RequestCreate,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    return crud.create_request(db, request, current_user.id)

@router.get("/", response_model=List[request_schemas.Request])
def read_requests(
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    # Only Admin and Staff should see all requests
    if current_user.role not in [models.UserRole.ADMIN, models.UserRole.STAFF]:
        return crud.get_user_requests(db, user_id=current_user.id)
    return crud.get_requests(db)