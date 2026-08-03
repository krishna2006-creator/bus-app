"""
WebSocket Endpoints for Real-Time Bus Tracking
Handles location sharing with bus-based room grouping
"""

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, status, Query, HTTPException
from sqlalchemy.orm import Session
import json
import asyncio
import logging
from datetime import datetime

from ..database.database import SessionLocal, get_db
from ..database import models
from ..services.websocket_manager_v2 import manager, LocationData
from ..services.location_analyzer import location_analyzer
from ..services.prediction_service import prediction_service
from ..services.notification_service import notification_service
from ..utils.auth_utils import get_current_user

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["WebSocket"])


async def _verify_token(token: str):
    """Verify a WebSocket token and return user info without holding a DB session."""
    if not token:
        return None
    try:
        db = SessionLocal()
        try:
            user = get_current_user(token, db)
            return user
        finally:
            db.close()
    except Exception:
        return None


# ============================================================================
# LOCATION SHARING (Main Real-Time Location Endpoint)
# ============================================================================


@router.websocket("/ws/location/{bus_id}")
async def websocket_location_tracking(
    websocket: WebSocket,
    bus_id: int,
    token: str = Query(None),
):
    """
    Primary WebSocket endpoint for bus location tracking.
    """
    user = None
    user_id = None
    user_name = None
    user_role = None

    try:
        await websocket.accept()

        if token and token.startswith("Bearer "):
            token = token[7:]
        if not token:
            token = websocket.query_params.get("token")
        if token and token.startswith("Bearer "):
            token = token[7:]

        user = await _verify_token(token)
        if not user:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Unauthorized")
            return

        user_id = user.id
        user_name = user.full_name or f"User {user_id}"
        user_role = user.role or "student"

        # Connect user to the bus room (after accept)
        success = await manager.connect(
            websocket=websocket,
            user_id=user_id,
            user_name=user_name,
            user_role=user_role,
            bus_id=bus_id,
        )
        if not success:
            await websocket.close(code=status.WS_1011_SERVER_ERROR, reason="Failed to connect")
            return

        logger.info(f"User {user_id} ({user_name}) connected to bus {bus_id}")

        # Send last known location if available
        await manager.send_last_location_to_user(bus_id, user_id)

        # Notify other users in the bus about new user
        await manager.broadcast_to_bus(
            bus_id,
            {
                "type": "USER_JOINED",
                "bus_id": bus_id,
                "user_id": user_id,
                "user_name": user_name,
                "user_role": user_role,
                "timestamp": datetime.now().isoformat(),
            },
            exclude_user_id=str(user_id),
        )

        # Main WebSocket loop - receive and process messages
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            message_type = message.get("type", "").upper()

            if message_type == "LOCATION_UPDATE":
                # Create a short-lived db session for processing
                try:
                    db = SessionLocal()
                    try:
                        result = await location_analyzer.process_location_update(db, user, message)
                    finally:
                        db.close()
                except Exception as e:
                    logger.error(f"Location update error: {e}")
                    result = {}

                if result.get("status") == "ignored":
                    await manager.send_personal_message(
                        user_id,
                        {
                            "type": "ERROR",
                            "error": result.get("reason", "Location update ignored"),
                            "bus_id": bus_id,
                            "timestamp": datetime.now().isoformat(),
                        },
                    )

            elif message_type in ("STOP_SHARING", "LOCATION_CLEARED"):
                try:
                    db = SessionLocal()
                    try:
                        result = await location_analyzer.process_location_update(db, user, message)
                    finally:
                        db.close()
                except Exception as e:
                    logger.error(f"Stop sharing error: {e}")

            elif message_type == "PING":
                await manager.send_personal_message(
                    user_id, {"type": "PONG", "timestamp": datetime.now().isoformat()},
                )

            elif message_type == "GET_BUS_INFO":
                bus_info = manager.get_bus_info(bus_id)
                if bus_info:
                    await manager.send_personal_message(
                        user_id,
                        {
                            "type": "BUS_INFO",
                            "bus_id": bus_id,
                            "user_count": bus_info["user_count"],
                            "active_users": bus_info["active_users"],
                            "timestamp": datetime.now().isoformat(),
                        },
                    )

    except HTTPException as exc:
        logger.warning(f"WebSocket auth failed for bus {bus_id}: {exc.detail}")
        try:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason=str(exc.detail or "Unauthorized"))
        except Exception:
            pass
        return

    except WebSocketDisconnect:
        logger.info(f"User {user_id} disconnected from bus {bus_id}")
        if user_id:
            try:
                db = SessionLocal()
                try:
                    await location_analyzer.remove_location(user_id, bus_id, user_role)
                finally:
                    db.close()
            except Exception:
                pass
            await manager.broadcast_to_bus(
                bus_id,
                {
                    "type": "USER_LEFT",
                    "bus_id": bus_id,
                    "user_id": user_id,
                    "user_name": user_name,
                    "timestamp": datetime.now().isoformat(),
                },
            )

    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON from user {user_id}: {e}")

    except Exception as e:
        logger.error(f"WebSocket error for user {user_id} on bus {bus_id}: {e}")
        if user_id:
            try:
                db = SessionLocal()
                try:
                    await location_analyzer.remove_location(user_id, bus_id, user_role)
                finally:
                    db.close()
            except Exception:
                pass


# ============================================================================
# STOP PREDICTION LIVE WEBSOCKET (Real-time bus ETA & phase tracking)
# ============================================================================


@router.websocket("/ws/stop-prediction-live")
async def websocket_stop_prediction_live(
    websocket: WebSocket,
    token: str = Query(None),
):
    user = None
    user_id = None
    last_phase = 0
    update_task = None

    try:
        await websocket.accept()

        if token and token.startswith("Bearer "):
            token = token[7:]
        if not token:
            token = websocket.query_params.get("token")
        if token and token.startswith("Bearer "):
            token = token[7:]

        user = await _verify_token(token)
        if not user:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Unauthorized")
            return

        user_id = str(user.id)
        user_name = user.full_name or f"User {user_id}"
        user_role = user.role or "student"

        success = await manager.connect(
            websocket=websocket,
            user_id=user_id,
            user_name=user_name,
            user_role=user_role,
            bus_id=0,
        )
        if not success:
            await websocket.close(code=status.WS_1011_SERVER_ERROR, reason="Failed to connect")
            return

        logger.info(f"Stop prediction WS connected for user {user_id} ({user_name})")

        await websocket.send_json({
            "type": "CONNECTED",
            "message": "Stop prediction live updates connected",
            "user_id": user_id,
            "timestamp": datetime.now().isoformat(),
        })

        async def send_prediction_updates():
            nonlocal last_phase
            while True:
                try:
                    db = SessionLocal()
                    try:
                        pred = await prediction_service.get_live_prediction(db, user_id)
                    finally:
                        db.close()

                    if pred and "error" not in pred:
                        current_phase = prediction_service.user_phases.get(user_id, 0)

                        if current_phase != last_phase:
                            last_phase = current_phase
                            if current_phase == 1:
                                await websocket.send_json({
                                    "type": "NOTIFICATION",
                                    "title": "Bus Left Your Stop!",
                                    "message": "Your bus has passed your boarding point and is now heading to Agni College of Technology",
                                    "notification_type": "left_stop",
                                    "timestamp": datetime.now().isoformat(),
                                })
                            else:
                                await websocket.send_json({
                                    "type": "NOTIFICATION",
                                    "title": "Bus Approaching Your Stop",
                                    "message": f"Bus is {pred.get('duration_mins', 0)} min away from your stop",
                                    "notification_type": "bus_arriving",
                                    "timestamp": datetime.now().isoformat(),
                                })

                        await websocket.send_json({
                            "type": "PREDICTION_UPDATE",
                            "payload": {
                                "bus_id": pred["bus_id"],
                                "distance_km": round(pred["distance_km"], 2),
                                "eta_minutes": pred["duration_mins"],
                                "status": pred["status"],
                                "target": pred["target"],
                                "is_to_college": pred["target"] == "Agni College of Technology",
                            },
                            "timestamp": datetime.now().isoformat(),
                        })

                        # ALSO send bus location so the map marker (dog.png) shows
                        # Works for BOTH driver and student shared locations
                        bus_loc = prediction_service.bus_coords.get(pred["bus_id"])
                        if bus_loc:
                            await websocket.send_json({
                                "type": "LOCATION_UPDATE",
                                "payload": {
                                    "bus_id": pred["bus_id"],
                                    "latitude": bus_loc["lat"],
                                    "longitude": bus_loc["lon"],
                                    "speed": bus_loc.get("speed", 0.0),
                                },
                                "timestamp": datetime.now().isoformat(),
                            })

                        if current_phase == 1 and pred.get("distance_km", 0) < 2.0:
                            await websocket.send_json({
                                "type": "NOTIFICATION",
                                "title": "Approaching College!",
                                "message": f"Bus is {pred.get('duration_mins', 0)} min away from Agni College of Technology",
                                "notification_type": "approaching_college",
                                "timestamp": datetime.now().isoformat(),
                            })

                    await asyncio.sleep(3)
                except asyncio.CancelledError:
                    break
                except Exception as e:
                    logger.error(f"Prediction update error for user {user_id}: {e}")
                    await asyncio.sleep(5)

        update_task = asyncio.create_task(send_prediction_updates())

        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            msg_type = message.get("type", "").upper()

            if msg_type == "PING":
                await websocket.send_json({
                    "type": "PONG",
                    "timestamp": datetime.now().isoformat(),
                })
            elif msg_type == "GET_PREDICTION":
                db = SessionLocal()
                try:
                    pred = await prediction_service.get_live_prediction(db, user_id)
                finally:
                    db.close()
                if pred and "error" not in pred:
                    await websocket.send_json({
                        "type": "PREDICTION_UPDATE",
                        "payload": {
                            "bus_id": pred["bus_id"],
                            "distance_km": round(pred["distance_km"], 2),
                            "eta_minutes": pred["duration_mins"],
                            "status": pred["status"],
                            "target": pred["target"],
                            "is_to_college": pred["target"] == "Agni College of Technology",
                        },
                        "timestamp": datetime.now().isoformat(),
                    })

    except WebSocketDisconnect:
        logger.info(f"Stop prediction WS disconnected for user {user_id}")
        if user_id:
            manager.disconnect(user_id, bus_id=0)
            if user_id in prediction_service.user_phases:
                del prediction_service.user_phases[user_id]

    except Exception as e:
        logger.error(f"Stop prediction WS error for user {user_id}: {e}")
        if update_task is not None:
            update_task.cancel()
        if user_id:
            manager.disconnect(user_id, bus_id=0)


# ============================================================================
# NOTIFICATION WEBSOCKET (General purpose for notifications)
# ============================================================================


@router.websocket("/ws")
async def websocket_notifications(
    websocket: WebSocket,
    token: str = Query(None),
):
    user = None
    user_id = None
    try:
        await websocket.accept()

        if token and token.startswith("Bearer "):
            token = token[7:]
        if not token:
            token = websocket.query_params.get("token")

        user = await _verify_token(token)
        if not user:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Unauthorized")
            return

        user_id = user.id
        user_name = user.full_name or f"User {user_id}"
        user_role = user.role or "student"

        logger.info(f"Notification WebSocket connected for user {user_id} ({user_name})")

        # Connect to manager for notifications
        success = await manager.connect(
            websocket=websocket,
            user_id=user_id,
            user_name=user_name,
            user_role=user_role,
            bus_id=0,
        )
        if not success:
            await websocket.close(code=status.WS_1011_SERVER_ERROR, reason="Failed to connect")
            return

        # Send welcome message
        await websocket.send_json({
            "type": "CONNECTED",
            "message": "Notification WebSocket connected",
            "user_id": user_id,
            "timestamp": datetime.now().isoformat(),
        })

        # Keep connection alive and handle messages
        while True:
            try:
                data = await websocket.receive_text()
                message = json.loads(data)
                msg_type = message.get("type", "").upper()

                if msg_type == "PING":
                    await websocket.send_json({
                        "type": "PONG",
                        "timestamp": datetime.now().isoformat(),
                    })
                elif msg_type == "LOCATION_UPDATE":
                    bus_id = message.get("bus_id") or message.get("busId")
                    if bus_id:
                        db = SessionLocal()
                        try:
                            result = await location_analyzer.process_location_update(db, user, message)
                        finally:
                            db.close()
                        if result.get("status") == "ignored":
                            await websocket.send_json({
                                "type": "ERROR",
                                "error": result.get("reason", "Location update ignored"),
                                "timestamp": datetime.now().isoformat(),
                            })
                else:
                    await websocket.send_json({
                        "type": "ERROR",
                        "error": "Unknown message type. Use PING to keep alive.",
                        "timestamp": datetime.now().isoformat(),
                    })
            except json.JSONDecodeError:
                await websocket.send_json({
                    "type": "ERROR",
                    "error": "Invalid JSON",
                    "timestamp": datetime.now().isoformat(),
                })

    except WebSocketDisconnect:
        logger.info(f"Notification WebSocket disconnected for user {user_id}")
        if user_id:
            manager.disconnect(user_id, bus_id=0)

    except Exception as e:
        logger.error(f"Notification WebSocket error for user {user_id}: {e}")
        if user_id:
            manager.disconnect(user_id, bus_id=0)


# ============================================================================
# REST ENDPOINT FOR LOCATION UPDATES (Alternative/Fallback)
# ============================================================================


@router.post("/ws/location/update")
async def post_location_update(
    bus_id: int = Query(...),
    token: str = Query(None),
    location_data: dict = None,
    db: Session = Depends(get_db),
):
    user = get_current_user(token, db)
    if not user:
        return {"success": False, "error": "Unauthorized"}

    user_id = user.id
    user_name = user.full_name or f"User {user_id}"
    user_role = user.role or "student"

    try:
        location = LocationData(
            latitude=location_data.get("latitude", 0.0),
            longitude=location_data.get("longitude", 0.0),
            speed=location_data.get("speed", 0.0),
            direction=location_data.get("direction", 0.0),
            accuracy=location_data.get("accuracy", 0.0),
            timestamp=location_data.get("timestamp", datetime.now().timestamp()),
            user_id=user_id,
            user_name=user_name,
            user_role=user_role,
        )

        result = await manager.handle_location_update(bus_id, user_id, location)

        if result["success"]:
            return {
                "success": True,
                "bus_id": bus_id,
                "user_id": user_id,
                "broadcast_to_count": result.get("broadcast_to_count", 0),
                "message": f"Location broadcast to {result.get('broadcast_to_count')} users",
            }
        else:
            return {"success": False, "error": result.get("error", "Unknown error")}

    except Exception as e:
        logger.error(f"Error handling location update: {e}")
        return {"success": False, "error": str(e)}


# ============================================================================
# MANAGEMENT ENDPOINTS
# ============================================================================


@router.get("/ws/stats")
async def get_websocket_stats():
    """Get WebSocket manager statistics."""
    return manager.get_stats()


@router.get("/ws/bus/{bus_id}/info")
async def get_bus_info(bus_id: int):
    """Get information about a specific bus room"""
    bus_info = manager.get_bus_info(bus_id)
    if not bus_info:
        return {"success": False, "error": f"Bus {bus_id} not found"}

    return {
        "success": True,
        "bus_id": bus_id,
        "data": bus_info,
    }


@router.get("/ws/user/{user_id}/buses")
async def get_user_buses(user_id: int):
    """Get all buses a user is currently connected to"""
    buses = manager.get_user_buses(user_id)
    return {"success": True, "user_id": user_id, "buses": buses}