from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from typing import List
from ..database import crud
from ..database.database import get_db
from ..schemas import stop as stop_schemas, bus as bus_schemas
from ..services.prediction_service import prediction_service

router = APIRouter(prefix="/stops", tags=["Stops"])

@router.get("", response_model=List[stop_schemas.Stop])
def list_all_stops(db: Session = Depends(get_db)):
    """Get all available bus stops"""
    return crud.get_all_stops(db)

@router.get("/search", response_model=List[stop_schemas.Stop])
def search_stops(query: str, db: Session = Depends(get_db)):
    return crud.search_stops(db, query)

@router.get("/{stop_id}", response_model=stop_schemas.Stop)
def get_stop(stop_id: int, db: Session = Depends(get_db)):
    """Get a specific bus stop by ID"""
    return crud.get_stop_by_id(db, stop_id)

@router.get("/{stop_id}/predictions", response_model=List[bus_schemas.PredictionResponse])
async def get_stop_predictions(stop_id: int, db: Session = Depends(get_db)):
    """Get all bus predictions for buses passing through a specific stop"""
    return await prediction_service.get_predictions_for_stop(db, stop_id)
