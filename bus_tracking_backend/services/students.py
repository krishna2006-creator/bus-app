from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional

from ..database import crud, models
from ..database.database import get_db
from ..schemas import user as user_schemas
from ..schemas import bus as bus_schemas
from ..schemas import websocket as ws_schemas
from ..services.location_analyzer import location_analyzer
from ..services.websocket_manager_v2 import manager as websocket_manager
from ..utils.auth_utils import get_current_user

router = APIRouter(
    prefix="/students",
    tags=["Students"],
    responses={404: {"description": "Not found"}},
)

@router.get("/me", response_model=user_schemas.User)
def read_student_me(current_user: user_schemas.User = Depends(get_current_user)):
    if current_user.role != models.UserRole.STUDENT:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a student user")
    return current_user

@router.put("/me/boarding_stop/{stop_id}", response_model=user_schemas.User)
def update_student_boarding_stop(
    stop_id: int,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    if current_user.role != models.UserRole.STUDENT:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a student user")
    
    db_user = crud.update_user_boarding_stop(db, user_id=current_user.id, stop_id=stop_id)
    if db_user is None:
        raise HTTPException(status_code=404, detail="User or stop not found")
    return db_user

@router.get("/me/predictions", response_model=Optional[bus_schemas.PredictionResponse])
async def get_student_predictions(
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    if current_user.role != models.UserRole.STUDENT:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a student user")
    
    # Find the active bus this student is interested in
    # Get the bus's official live location from the analyzer
    pinned_bus = db.query(models.PinnedBus).filter(models.PinnedBus.user_id == current_user.id).first()
    if not pinned_bus: return None
    bus_loc = location_analyzer.get_bus_location_by_bus_id(pinned_bus.bus_id)
    if not bus_loc: return None

    prediction = await location_analyzer.get_prediction_for_user(
        db, current_user, pinned.bus_id, bus_loc['lat'], bus_loc['lng'], bus_loc['speed']
    )
    return prediction

@router.post("/me/boarded_bus", status_code=status.HTTP_200_OK)
async def student_boarded_bus(
    boarded_event: ws_schemas.BoardedBusEvent,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    if current_user.role != models.UserRole.STUDENT:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a student user")
    
    # Update student state in location_analyzer (e.g., for ETA calculation logic)
    location_analyzer.update_student_state(current_user.id, boarded=True, bus_id=boarded_event.bus_id)
    
    # Immediately send an updated prediction for the journey to college
    bus_loc = location_analyzer.get_bus_location_by_bus_id(boarded_event.bus_id) # Use the official bus location
    if not bus_loc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bus location not found for prediction")

    prediction = await location_analyzer.get_prediction_for_user(db, current_user, boarded_event.bus_id, bus_loc['latitude'], bus_loc['longitude'], bus_loc['speed'])
    
    if prediction:
        # Manager V2 expects a dict, prediction is already a dict from _calculate_prediction
        await websocket_manager.send_personal_message(
            current_user.id,
            prediction
        )
    
    return {"message": "Student boarding status updated and prediction sent."}

@router.get("/nearby_buses", response_model=List[bus_schemas.BusAnalysisResult])
async def get_nearby_buses_for_student(
    student_lat: float,
    student_lon: float,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    if current_user.role != models.UserRole.STUDENT:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a student user")
    
    # This method in location_analyzer will find buses near the given coordinates
    # and provide ETA to boarding points.
    return await location_analyzer.analyze_buses_for_student(db, student_lat, student_lon, current_user.id)