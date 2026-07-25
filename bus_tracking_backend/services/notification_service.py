"""
Notification Service - Handles all real-time notifications
Supports WebSocket + FCM push notifications for:
- Pinned bus live tracking started
- Pinned bus location updates
- Pinned bus approaching stop (2km, 1km, 500m geofences)
- Pinned bus reached stop
- Pinned bus completed trip
- Driver live location started
- Student shared location update
"""
from sqlalchemy.orm import Session
from ..database import models
from .websocket_manager_v2 import manager
from .firebase_service import firebase_service
from datetime import datetime
import logging
import requests
from typing import Optional, List

from ..config import settings
from ..utils.auth_utils import normalize_role

logger = logging.getLogger(__name__)


class NotificationService:
    async def send_personal_notification(self, user_id, title: str, message: str, category: str, data: dict = None, priority: str = "high", sound: str = "default"):
        """Sends a real-time notification to a specific user session."""
        u_id_str = str(user_id)

        notification = {
            "type": "NOTIFICATION",
            "payload": {
                "id": datetime.now().strftime("%Y%m%d%H%M%S%f"),
                "title": title,
                "message": message,
                "category": category,
                "priority": priority,
                "sound": sound,
                "data": data or {}
            }
        }

        sent_count = await manager.send_personal_message(u_id_str, notification)

        try:
            from ..database.database import SessionLocal
            db = SessionLocal()
            try:
                tokens = db.query(models.DeviceToken).filter(models.DeviceToken.user_id == u_id_str).all()
                if tokens:
                    self._send_fcm_notifications([t.token for t in tokens], title, message, data or {})
            finally:
                db.close()
        except Exception as exc:
            logger.warning(f"FCM dispatch failed for {u_id_str}: {exc}")

        if sent_count == 0:
            logger.debug(f"User {u_id_str} is offline. Notification '{category}' not delivered via WebSocket.")
        return sent_count > 0

    def _send_fcm_notifications(self, tokens: list, title: str, message: str, data: dict):
        """Send FCM notifications using Firebase Admin SDK."""
        if not tokens:
            return
        try:
            firebase_service.send_multicast(tokens, title, message, data)
        except Exception as exc:
            logger.warning(f"FCM send failed: {exc}")
            if settings.FCM_SERVER_KEY:
                headers = {
                    "Authorization": f"key={settings.FCM_SERVER_KEY}",
                    "Content-Type": "application/json",
                }
                payload = {
                    "to": tokens[0] if len(tokens) == 1 else None,
                    "registration_ids": tokens if len(tokens) > 1 else None,
                    "priority": "high",
                    "notification": {"title": title, "body": message},
                    "data": data,
                }
                try:
                    requests.post(settings.FCM_API_URL, headers=headers, json=payload, timeout=10)
                except Exception as exc2:
                    logger.warning(f"FCM REST fallback failed: {exc2}")

    async def broadcast_to_role(self, db: Session, title: str, message: str, category: str, target_role: str = "all", data: dict = None):
        """Broadcasts a notification to ALL users of a specific role (WebSocket + FCM).
        Sends to ALL users in the database with that role, not just WebSocket-connected ones.
        This ensures offline users still get FCM push notifications."""
        role_norm = target_role.lower() if target_role else "all"
        query = db.query(models.User)
        if role_norm != 'all':
            normalized_role = normalize_role(role_norm)
            query = query.filter(models.User.role == normalized_role)
        
        all_users = query.all()
        
        for user in all_users:
            await self.send_personal_notification(user.id, title, message, category, data=data)
        
        logger.info(f"Broadcast '{category}' sent to {len(all_users)} {target_role} users (WebSocket + FCM).")

    async def notify_pinned_users(self, db: Session, bus_id: int, title: str, message: str, category: str = "pinned_bus", data: dict = None):
        """
        Notify ALL users who have pinned a specific bus.
        Works for both online and offline users (sends FCM to all).
        """
        user_id_str = str(bus_id)
        pinned_records = db.query(models.PinnedBus).filter(
            models.PinnedBus.bus_id == bus_id
        ).all()

        for record in pinned_records:
            await self.send_personal_notification(
                record.user_id,
                title,
                message,
                category,
                data=data
            )
        logger.info(f"Pinned bus notification '{category}' sent to {len(pinned_records)} users for bus {bus_id}")
        return len(pinned_records)

    async def notify_pinned_bus_tracking_started(self, db: Session, bus_id: int, bus_number: str, driver_name: str = "Driver"):
        """Notify when a driver starts live tracking for a pinned bus."""
        await self.notify_pinned_users(
            db, bus_id,
            title="Live Tracking Started",
            message=f"Your pinned bus {bus_number} has started live location sharing.",
            category="PINNED_BUS_LIVE_STARTED",
            data={"bus_id": bus_id, "bus_number": bus_number}
        )

    async def notify_pinned_bus_location_updated(self, db: Session, bus_id: int, bus_number: str):
        """Notify pinned users when bus location is updated."""
        await self.notify_pinned_users(
            db, bus_id,
            title=f"Bus {bus_number} Location Updated",
            message=f"Your pinned bus {bus_number} location has been updated.",
            category="PINNED_BUS_LOCATION_UPDATE",
            data={"bus_id": bus_id, "bus_number": bus_number}
        )

    async def notify_pinned_bus_approaching_stop(self, db: Session, bus_id: int, bus_number: str, stop_name: str, distance_km: float):
        """Notify pinned users when bus is approaching their selected stop."""
        if distance_km <= 0.5:
            message = f"Your pinned bus {bus_number} is arriving soon at {stop_name}."
        elif distance_km <= 1.0:
            message = f"Your pinned bus {bus_number} is 1 km away from {stop_name}."
        elif distance_km <= 2.0:
            message = f"Your pinned bus {bus_number} is 2 km away from {stop_name}."
        else:
            return  # Don't notify beyond 2km

        data = {"bus_id": bus_id, "bus_number": bus_number, "stop_name": stop_name, "distance_km": distance_km}

        if distance_km <= 0.5:
            await self.notify_pinned_users(
                db, bus_id,
                title=f"Bus {bus_number} Arriving Soon!",
                message=message,
                category="PINNED_BUS_ARRIVING",
                data=data
            )
        else:
            await self.notify_pinned_users(
                db, bus_id,
                title=f"Bus {bus_number} Approaching",
                message=message,
                category="PINNED_BUS_APPROACHING",
                data=data
            )

    async def notify_pinned_bus_reached_stop(self, db: Session, bus_id: int, bus_number: str, stop_name: str):
        """Notify pinned users when bus has reached their stop."""
        await self.notify_pinned_users(
            db, bus_id,
            title=f"Bus {bus_number} Has Reached!",
            message=f"Your pinned bus {bus_number} has reached {stop_name}.",
            category="PINNED_BUS_REACHED",
            data={"bus_id": bus_id, "bus_number": bus_number, "stop_name": stop_name}
        )

    async def notify_pinned_bus_trip_completed(self, db: Session, bus_id: int, bus_number: str):
        """Notify pinned users when bus completes its trip (stops sharing)."""
        await self.notify_pinned_users(
            db, bus_id,
            title=f"Bus {bus_number} Trip Completed",
            message=f"Your pinned bus {bus_number} has completed its trip.",
            category="PINNED_BUS_TRIP_COMPLETED",
            data={"bus_id": bus_id, "bus_number": bus_number}
        )

    async def notify_student_shared_location(self, db: Session, bus_id: int, bus_number: str):
        """Notify pinned users when a student shares location for their pinned bus."""
        await self.notify_pinned_users(
            db, bus_id,
            title="Live Location Updated",
            message=f"Your pinned bus {bus_number} location has been updated by a community contributor.",
            category="COMMUNITY_LOCATION_UPDATE",
            data={"bus_id": bus_id, "bus_number": bus_number, "shared_by": "student"}
        )


notification_service = NotificationService()