from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional

from ..database import crud, models
from ..database.database import get_db
from ..schemas import user as user_schemas
from ..schemas import bus as bus_schemas
from ..schemas import websocket as ws_schemas
from ..services.location_analyzer import location_analyzer # Already imported
from ..services.websocket_manager_v2 import manager as websocket_manager
from ..utils.auth_utils import get_current_user

router = APIRouter(
    prefix="/students",
    tags=["Students"],
    responses={404: {"description": "Not found"}},
)

def _is_student_user(current_user: models.User) -> bool:
    return str(getattr(current_user, "role", "")).lower() == "student"

@router.get("/me", response_model=user_schemas.User)
def read_student_me(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """
    Returns the profile of the currently logged in student.
    Includes pinned_buses with details for Swagger visibility.
    """
    if not _is_student_user(current_user):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a student user")

    # Eagerly load pinned buses and their associated bus details
    user = db.query(models.User).filter(models.User.id == current_user.id).options(
        joinedload(models.User.pinned_buses).joinedload(models.PinnedBus.bus)
    ).first()

    # Flatten the result for the schema
    response_data = {
        "id": user.id,
        "email": user.email,
        "full_name": user.full_name,
        "role": user.role,
        "boarding_stop_id": user.boarding_stop_id,
        "pinned_buses": [
            {
                "bus_id": p.bus.id,
                "bus_number": p.bus.bus_number,
                "route_name": p.bus.route_name
            } for p in user.pinned_buses
        ]
    }
    return response_data

def _update_boarding_stop_for_user(db: Session, current_user: models.User, stop_id: int):
    db_user = crud.update_user_boarding_stop(db, user_id=current_user.id, stop_id=stop_id)
    if db_user is None:
        raise HTTPException(status_code=404, detail="User or stop not found")
    return db_user

@router.get("/me/boarding_stop", response_model=Optional[bus_schemas.StopResponse])
def get_student_boarding_stop(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Returns the student's currently selected boarding stop."""
    stop = crud.get_user_boarding_stop(db, user_id=current_user.id)
    return stop

@router.put("/me/boarding_stop", response_model=user_schemas.User)
def update_student_boarding_stop_query(
    stop_id: int = Query(..., description="Boarding stop id"),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Updates the persistent boarding stop for the student using a query parameter."""
    if not _is_student_user(current_user):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a student user")
    return _update_boarding_stop_for_user(db, current_user, stop_id)

@router.put("/me/boarding_stop/{stop_id}", response_model=user_schemas.User)
def update_student_boarding_stop(
    stop_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Updates the persistent boarding stop for the student."""
    if not _is_student_user(current_user):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a student user")
    return _update_boarding_stop_for_user(db, current_user, stop_id)

@router.get("/me/predictions", response_model=Optional[bus_schemas.PredictionResponse])
async def get_student_predictions(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """
    Manually triggers a prediction calculation for the dashboard.
    """
    pinned = db.query(models.PinnedBus).filter(models.PinnedBus.user_id == current_user.id).first()
    if not pinned:
        return None

    # Get current bus stats from active_locations cache
    # Get the bus's official live location from the analyzer
    bus_loc = location_analyzer.get_bus_location_by_bus_id(pinned.bus_id)
    if not bus_loc:
        return None # Bus not currently active
    prediction = await location_analyzer.get_prediction_for_user(
        db, current_user, pinned.bus_id, bus_loc['lat'], bus_loc['lng'], bus_loc['speed']
    )
    if prediction:
        return bus_schemas.PredictionResponse(**prediction["payload"]) # prediction is a dict with "payload" key
    
    return None
