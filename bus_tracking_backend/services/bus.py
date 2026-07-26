from fastapi import APIRouter, Depends, HTTPException, status, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session
from typing import List, Optional

from ..database import crud, models
from ..database.database import get_db
from ..schemas import bus as bus_schemas
from ..schemas import user as user_schemas
from ..schemas import websocket as ws_schemas
from .location_analyzer import location_analyzer
from .notification_service import notification_service
from .websocket_manager_v2 import manager as websocket_manager
from ..utils.auth_utils import get_current_user

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
    # Retrieve the bus's last known location from the WebSocket manager
    bus_info = websocket_manager.get_bus_info(bus_id)
    if bus_info and bus_info.get("has_last_location"):
        last_location = bus_info["last_known_location"] # This is a LocationData object
        return bus_schemas.LiveLocationResponse(
            id=last_location.user_id, # The ID of the user sending the location
            bus_id=bus_id,
            latitude=last_location.latitude,
            longitude=last_location.longitude,
            speed=last_location.speed,
            timestamp=datetime.fromtimestamp(last_location.timestamp)
        )
    return None

@router.post("/{bus_id}/start_tracking", status_code=status.HTTP_200_OK)
async def start_bus_tracking(
    bus_id: int,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    if current_user.role != models.UserRole.DRIVER or current_user.assigned_bus_id != bus_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to start tracking this bus")
    
    # Send notification that bus has started (exclude the driver who started it)
    await notification_service.broadcast_to_role(
        db,
        title="Bus Service Started",
        message=f"Bus {bus_id} has started sharing its live location.",
        category="BUS_STARTED",
        target_role="all",
        exclude_user_id=current_user.id
    )
    return {"message": f"Bus {bus_id} tracking started and notifications sent."}

# WebSocket for driver to send live location updates
@router.websocket("/{bus_id}/live_location")
async def driver_live_location_websocket(websocket: WebSocket, bus_id: int, token: str):
    db: Session = next(get_db())
    user = get_current_user(db, token)
    if not user:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    await websocket.accept()
    # Extract role string correctly (handling Enums) so manager can recognize it
    role_str = user.role.value if hasattr(user.role, 'value') else str(user.role).lower().split('.')[-1]
    await websocket_manager.connect(
        websocket=websocket, 
        user_id=user.id, 
        user_name=user.full_name, 
        user_role=role_str, 
        bus_id=bus_id
    )

    try:
        while True:
            data = await websocket.receive_json()
            try:
                message_type = data.get("type", "").upper()
                if message_type == ws_schemas.MessageType.LOCATION_UPDATE.value:
                    # Wrap the payload in a format process_location_update expects
                    update_packet = {
                        # Ensure bus_id is in payload for location_analyzer
                        "payload": {
                            **data.get("payload", {}),
                            "bus_id": bus_id,
                            "user_id": user.id,
                            "user_role": role_str,
                            "is_shared_by_student": False # Explicitly false for driver
                        },
                        "type": message_type,
                    }
                    
                    # Use the unified analyzer instead of old location_service
                    await location_analyzer.process_location_update(db, user, update_packet)
                    
                    # Notify students on the same route or who have pinned this bus
                    bus = db.query(models.Bus).filter(models.Bus.id == bus_id).first()
                    # The prediction logic is now handled within location_analyzer.process_location_update
                    # and its _update_subscribers method.
                    # This block can be removed as location_analyzer will handle the notifications.
                    # if bus and bus.route_id:
                    #     # Find students on the same route
                    #     students_on_route = db.query(models.User).join(models.BusStop, models.User.boarding_stop_id == models.BusStop.id).join(models.RouteStopAssociation).filter(
                    #         models.RouteStopAssociation.route_id == bus.route_id
                    #     ).all()
                        
                    #     # Find students who pinned this bus
                    #     pinned_bus_users = db.query(models.User).join(models.PinnedBus).filter(
                    #         models.PinnedBus.bus_id == bus_id
                    #     ).all()

                    #     # Combine and deduplicate students
                    #     all_relevant_students = list(set(students_on_route + pinned_bus_users))
                        
                    #     for student in all_relevant_students:
                    #         # Get current bus stats for prediction
                    #         bus_stats = location_analyzer.active_locations.get(str(user.id))
                    #         if not bus_stats: continue
                            
                    #         prediction = await location_analyzer.get_prediction_for_user(
                    #             db, 
                    #             student, 
                    #             bus_id, 
                    #             bus_stats['lat'], 
                    #             bus_stats['lng'], 
                    #             bus_stats['speed']
                    #         )
                            
                    #         if prediction:
                    #             await websocket_manager.send_personal_message(
                    #                 user_id=student.id,
                    #                 message={"type": "PREDICTION_UPDATE", "payload": prediction}
                    #             )

            except Exception as e:
                print(f"Error processing driver location message: {e}")
    except WebSocketDisconnect:
        if user:
            role_str = user.role.value if hasattr(user.role, 'value') else str(user.role).lower().split('.')[-1]
            # Centralize removal logic through location_analyzer to ensure clear signal is sent
            await location_analyzer.remove_location(user.id, bus_id, role_str)
    finally:
        db.close()