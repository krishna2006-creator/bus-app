from fastapi import APIRouter, Depends, HTTPException, status, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session
from typing import List, Optional

from .database import crud, models
from .database.database import get_db
from .schemas import bus as bus_schemas
from .schemas import user as user_schemas
from .schemas import websocket as ws_schemas
from .services.location_service import location_service
from .services.prediction_service import prediction_service
from .services.notification_service import notification_service
from .services.websocket_manager_v2 import manager as websocket_manager
from .utils.auth_utils import get_current_user

router = APIRouter(
    prefix="/buses",
    tags=["Buses"],
    responses={404: {"description": "Not found"}},
)

@router.get("/", response_model=List[bus_schemas.BusResponse])
def read_buses(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    buses = crud.get_buses(db, skip=skip, limit=limit)
    return buses

@router.post("/", response_model=bus_schemas.BusResponse)
def create_bus(
    bus: bus_schemas.BusCreate,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    if current_user.role not in [models.UserRole.ADMIN, models.UserRole.STAFF]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to create buses")
    return crud.create_bus_with_stops(db=db, bus=bus)

@router.get("/{bus_id}", response_model=bus_schemas.BusResponse)
def read_bus(bus_id: int, db: Session = Depends(get_db)):
    db_bus = crud.get_bus(db, bus_id=bus_id)
    if db_bus is None:
        raise HTTPException(status_code=404, detail="Bus not found")
    return db_bus

@router.put("/{bus_id}", response_model=bus_schemas.BusResponse)
def update_bus(
    bus_id: int,
    bus: bus_schemas.BusCreate, # Using BusCreate for simplicity, could be BusUpdate
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    if current_user.role not in [models.UserRole.ADMIN, models.UserRole.STAFF]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to update buses")
    db_bus = crud.update_bus(db, bus_id=bus_id, bus=bus)
    if db_bus is None:
        raise HTTPException(status_code=404, detail="Bus not found")
    return db_bus

@router.delete("/{bus_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_bus(
    bus_id: int,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    if current_user.role not in [models.UserRole.ADMIN, models.UserRole.STAFF]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to delete buses")
    crud.delete_bus(db, bus_id=bus_id)
    return {"message": "Bus deleted successfully"}

@router.get("/{bus_id}/location", response_model=Optional[bus_schemas.LiveLocationResponse])
def get_bus_live_location(bus_id: int):
    return location_service.get_active_bus_location(bus_id)

@router.post("/{bus_id}/start_tracking", status_code=status.HTTP_200_OK)
async def start_bus_tracking(
    bus_id: int,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    if current_user.role != models.UserRole.DRIVER or current_user.assigned_bus_id != bus_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to start tracking this bus")
    
    # Send notification that bus has started
    await notification_service.broadcast_to_role(
        db,
        title="Bus Service Started",
        message=f"Bus {bus_id} has started sharing its live location.",
        category="BUS_STARTED",
        target_role="all"
    )
    return {"message": f"Bus {bus_id} tracking started and notifications sent."}

# WebSocket for driver to send live location updates
@router.websocket("/{bus_id}/live_location")
async def driver_live_location_websocket(websocket: WebSocket, bus_id: int, token: str):
    user = get_current_user(token) # Authenticate driver
    if not user or user.role != models.UserRole.DRIVER or user.assigned_bus_id != bus_id:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    await websocket.accept()
    await websocket_manager.connect(
        websocket, 
        user.id, 
        getattr(user, 'full_name', 'Driver'), 
        str(user.role), 
        bus_id
    )
    db: Session = next(get_db())

    try:
        while True:
            data = await websocket.receive_json()
            try:
                message_type = data.get("type")
                if message_type == ws_schemas.MessageType.LOCATION_UPDATE:
                    loc_data = bus_schemas.LiveLocationUpdate(**data['payload'], user_id=user.id, bus_id=bus_id, user_role=user.role)
                    
                    # Process driver location
                    active_loc_response = await location_service.process_driver_location(db, loc_data)
                    
                    # Update prediction engine with new coordinates
                    await prediction_service.update_bus_coord(bus_id, loc_data.latitude, loc_data.longitude)
                    
                    # Notify users (students & staff) on the same route or who have pinned this bus
                    bus = db.query(models.Bus).filter(models.Bus.id == bus_id).first()
                    if bus and bus.route_id:
                        # Find all users (Students & Staff) on the same route via their boarding stop
                        users_on_route = db.query(models.User).filter(models.User.boarding_stop_id.isnot(None)).join(models.BusStop).join(models.RouteStopAssociation).filter(
                            models.RouteStopAssociation.route_id == bus.route_id
                        ).all()
                        
                        # Find all users who explicitly pinned this bus (Students & Staff)
                        pinned_bus_users = db.query(models.User).join(models.PinnedBus, models.User.id == models.PinnedBus.user_id).filter(
                            models.PinnedBus.bus_id == bus_id
                        ).all()

                        # Combine and deduplicate relevant users
                        all_relevant_users = list(set(users_on_route + pinned_bus_users))
                        
                        for user_to_notify in all_relevant_users:
                            prediction = await prediction_service.get_prediction_for_user(db, user_to_notify)
                            if prediction:
                                await websocket_manager.send_personal_message(
                                    user_to_notify.id,
                                    {"type": ws_schemas.MessageType.PREDICTION_UPDATE, "payload": prediction.model_dump()}
                                )
                    
                    # Also check for pinned bus notifications (e.g., bus near stop)
                    await notification_service.check_and_send_pinned_bus_notifications(db, bus_id, active_loc_response)

            except Exception as e:
                print(f"Error processing driver location message: {e}")
    except WebSocketDisconnect:
        websocket_manager.disconnect(user.id, websocket)
    finally:
        db.close()