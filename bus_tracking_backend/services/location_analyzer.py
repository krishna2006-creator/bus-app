"""
Location Analyzer - Processes location updates and triggers pinned bus notifications
- Geofence notifications at 2km, 1km, 500m
- Duplicate prevention per stop and trip
- Notifies only users who pinned that specific bus
"""
from sqlalchemy.orm import Session, joinedload
from ..database import models
from .websocket_manager_v2 import manager
from .websocket_manager_v2 import LocationData as WSLocationData
from .notification_service import notification_service
from ..utils.geo_utils import calculate_distance_km, estimate_eta_minutes
from datetime import datetime
from typing import Any, Optional

# Agni College Location
COLLEGE_LATITUDE = 12.8482
COLLEGE_LONGITUDE = 80.1943


class LocationAnalyzer:
    def __init__(self):
        self.active_locations = {}
        self.user_trip_phases = {}
        self.notified_users = set()  # Tracks dispatched notifications to prevent duplicates
        # Track whether we've sent "tracking started" notification per bus_id
        self._tracking_started_notified = set()
        # Track last distance bracket notified per (bus_id, user_id)
        self._last_distance_bracket = {}

    def _make_geofence_key(self, bus_id: int, stop_id: int, bracket: str) -> str:
        """Create a unique notification key to prevent duplicate geofence alerts."""
        return f"{bus_id}_{stop_id}_{bracket}"

    async def process_location_update(self, db: Session, user: Any, data: dict):
        """Processes location and broadcasts with pinned bus notifications."""
        payload = data.get("payload", data)
        msg_type = data.get("type") or payload.get("type")

        bus_id = payload.get("bus_id") or payload.get("busId") or getattr(user, 'assigned_bus_id', None)

        # Handle stop sharing / cleared
        if msg_type in ["STOP_SHARING", "LOCATION_CLEARED"]:
            u_id = user.id if user and hasattr(user, 'id') else f'system_{bus_id}'
            role = (user.role.value if hasattr(user.role, 'value') else str(user.role).lower().split('.')[-1]) if user and hasattr(user, 'role') else 'driver'
            return await self._handle_stop_sharing(db, u_id, bus_id, role)

        u_id = user.id if user and hasattr(user, 'id') else f'system_{bus_id}'
        role = (user.role.value if hasattr(user.role, 'value') else str(user.role).lower().split('.')[-1]) if user and hasattr(user, 'role') else 'student'
        is_student_sharing = payload.get("is_shared_by_student", role == "student")

        lat = float(payload.get("latitude") or payload.get("lat", 0))
        lng = float(payload.get("longitude") or payload.get("lng", 0))
        speed = float(payload.get("speed") or payload.get("speed", 0))
        bearing = float(payload.get("bearing") or payload.get("direction", 0.0))
        accuracy = float(payload.get("accuracy") or 0.0)

        if not bus_id or lat == 0 or lng == 0:
            return {"status": "ignored", "reason": "invalid_coords"}

        ws_location_data = WSLocationData(
            latitude=lat, longitude=lng, speed=speed, direction=bearing,
            timestamp=datetime.now().timestamp(),
            user_id=u_id, user_name=getattr(user, 'full_name', str(u_id)),
            user_role=role, accuracy=accuracy
        )

        ws_response = await manager.handle_location_update(bus_id, u_id, ws_location_data)
        if not ws_response.get("success"):
            return {"status": "ignored", "reason": ws_response.get("error")}

        location_dict = ws_location_data.to_dict()
        location_dict["bus_id"] = bus_id
        location_dict["lat"] = lat
        location_dict["lng"] = lng
        self.active_locations[str(u_id)] = location_dict

        # Update prediction service with latest bus coordinates for distance calculations
        from .prediction_service import prediction_service
        await prediction_service.update_bus_coord(bus_id, lat, lng)

        # --- PINNED BUS NOTIFICATIONS ---

        # Get bus info
        bus = db.query(models.Bus).filter(models.Bus.id == bus_id).first()
        bus_number = bus.bus_number if bus else str(bus_id)

        # 1. NOTIFY: Tracking Started (First time this bus sends location)
        if role == "driver" and bus_id not in self._tracking_started_notified:
            self._tracking_started_notified.add(bus_id)
            driver_name = getattr(user, 'full_name', 'Driver') if user else 'Driver'
            await notification_service.notify_pinned_bus_tracking_started(
                db, bus_id, bus_number, driver_name
            )

        # 2. NOTIFY: Student shared location
        if is_student_sharing:
            await notification_service.notify_student_shared_location(db, bus_id, bus_number)

        # 3. NOTIFY: Geofence distance-based alerts for ALL stops this bus serves
        bus_stops = db.query(models.BusStop).filter(
            models.BusStop.bus_id == bus_id
        ).order_by(models.BusStop.stop_order).all()

        for stop in bus_stops:
            await self._check_geofence_and_notify(db, bus_id, bus_number, stop, lat, lng)

        # 4. Trigger predictions for subscribers
        await self._update_subscribers(db, bus_id, lat, lng, speed)

        return {"status": "broadcasted", "ws_manager_status": ws_response}

    async def _check_geofence_and_notify(self, db: Session, bus_id: int, bus_number: str, stop, b_lat: float, b_lng: float):
        """Check if bus is within geofence radii of a stop and notify pinned users."""
        dist_km = calculate_distance_km(b_lat, b_lng, stop.latitude, stop.longitude)
        stop_name = stop.stop_name or f"Stop {stop.stop_order}"
        stop_id = stop.id

        # Determine distance bracket (2km, 1km, 500m)
        if dist_km <= 0.1:
            # Bus has reached the stop
            key = self._make_geofence_key(bus_id, stop_id, "reached")
            if key not in self.notified_users:
                await notification_service.notify_pinned_bus_reached_stop(
                    db, bus_id, bus_number, stop_name
                )
                self.notified_users.add(key)
        elif dist_km <= 0.5:
            key = self._make_geofence_key(bus_id, stop_id, "500m")
            if key not in self.notified_users:
                await notification_service.notify_pinned_bus_approaching_stop(
                    db, bus_id, bus_number, stop_name, dist_km
                )
                self.notified_users.add(key)
        elif dist_km <= 1.0:
            key = self._make_geofence_key(bus_id, stop_id, "1km")
            if key not in self.notified_users:
                await notification_service.notify_pinned_bus_approaching_stop(
                    db, bus_id, bus_number, stop_name, dist_km
                )
                self.notified_users.add(key)
        elif dist_km <= 2.0:
            key = self._make_geofence_key(bus_id, stop_id, "2km")
            if key not in self.notified_users:
                await notification_service.notify_pinned_bus_approaching_stop(
                    db, bus_id, bus_number, stop_name, dist_km
                )
                self.notified_users.add(key)

    async def _handle_stop_sharing(self, db: Session, u_id: str, bus_id: Optional[int], role: str):
        """Handle when a driver/student stops sharing location."""
        # Notify pinned users that trip completed (only for drivers)
        if role == "driver" and bus_id:
            bus = db.query(models.Bus).filter(models.Bus.id == bus_id).first()
            bus_number = bus.bus_number if bus else str(bus_id)
            await notification_service.notify_pinned_bus_trip_completed(db, bus_id, bus_number)

            # Clean up tracking state
            self._tracking_started_notified.discard(bus_id)

        return await self.remove_location(u_id, bus_id, role)

    def get_bus_location_by_bus_id(self, bus_id: int) -> Optional[dict]:
        """Retrieves the last known location of a bus by its bus_id."""
        bus_info = manager.get_bus_info(bus_id)
        if not bus_info or not bus_info.get("has_last_location"):
            return None
        last_location = bus_info.get("last_known_location")
        if not last_location:
            return None
        if hasattr(last_location, "to_dict"):
            return last_location.to_dict()
        return last_location

    async def remove_location(self, u_id: Any, bus_id: Optional[int] = None, role: str = "student"):
        """Explicitly removes a location from cache and signals all clients."""
        u_id_str = str(u_id)

        if u_id_str in self.active_locations:
            del self.active_locations[u_id_str]

        clear_signal = {
            "type": "LOCATION_CLEARED",
            "payload": {
                "id": u_id, "role": role, "bus_id": bus_id,
                "latitude": 0, "longitude": 0,
                "timestamp": datetime.now().timestamp()
            },
            "bus_id": bus_id, "id": u_id, "role": role,
            "latitude": 0, "longitude": 0,
            "timestamp": datetime.now().timestamp()
        }

        if bus_id:
            manager.disconnect(u_id, bus_id=bus_id)
            await manager.broadcast_to_bus(bus_id, clear_signal)
        else:
            manager.disconnect(u_id)
            await manager.broadcast(clear_signal)

        # Clear notification state for this bus
        if bus_id:
            self.notified_users = {k for k in self.notified_users if not str(bus_id) in k}
        return {"status": "broadcasted"}

    def update_student_state(self, user_id: Any, boarded: bool, bus_id: int = None):
        """Updates the tracking phase for a student."""
        self.user_trip_phases[user_id] = "on_board" if boarded else "waiting"
        if bus_id and str(user_id) in self.active_locations:
            self.active_locations[str(user_id)]["bus_id"] = bus_id

    async def analyze_buses_for_student(self, db: Session, lat: float, lon: float, user_id: Any):
        """Analyzes nearby buses and provides ETAs."""
        results = []
        for sender_id, loc in self.active_locations.items():
            if loc.get("role") == "driver" and loc.get("bus_id"):
                bus_id = loc["bus_id"]
                dist = calculate_distance_km(lat, lon, loc["lat"], loc["lng"])
                if dist < 10.0:
                    results.append({
                        "bus_id": bus_id,
                        "distance_km": round(dist, 2),
                        "eta_minutes": estimate_eta_minutes(dist, loc["speed"]),
                        "latitude": loc["lat"],
                        "longitude": loc["lng"],
                        "status": "Running"
                    })
        return sorted(results, key=lambda x: x['distance_km'])

    async def _update_subscribers(self, db: Session, bus_id: int, b_lat: float, b_lng: float, speed: float):
        """Update subscribers with predictions."""
        subscribers = db.query(models.PinnedBus).filter(models.PinnedBus.bus_id == bus_id).options(
            joinedload(models.PinnedBus.boarding_stop)
        ).all()

        for sub in subscribers:
            if str(sub.user_id) in manager.user_connections:
                stop = sub.boarding_stop
                if not stop and sub.boarding_stop_id:
                    stop = db.query(models.BusStop).filter(models.BusStop.id == sub.boarding_stop_id).first()
                if stop:
                    prediction = await self._calculate_prediction(
                        sub.user_id, bus_id, b_lat, b_lng, speed,
                        stop.latitude, stop.longitude
                    )
                    await manager.send_personal_message(str(sub.user_id), prediction)

    async def get_prediction_for_user(self, db: Session, user: models.User, bus_id: int, b_lat: float, b_lng: float, b_speed: float):
        """Helper to calculate prediction for a user on demand."""
        db_user = db.query(models.User).filter(models.User.id == user.id).options(
            joinedload(models.User.boarding_stop),
            joinedload(models.User.pinned_buses).joinedload(models.PinnedBus.boarding_stop)
        ).first()
        if not db_user:
            return None

        stop = db_user.boarding_stop
        if not stop and bus_id:
            pinned = next((p for p in db_user.pinned_buses if p.bus_id == bus_id), None)
            stop = pinned.boarding_stop if pinned and pinned.boarding_stop else None

        if not stop:
            return None

        if b_lat == 0 and b_lng == 0 and b_speed == 0:
            bus_loc = self.get_bus_location_by_bus_id(bus_id)
            if bus_loc:
                b_lat, b_lng, b_speed = bus_loc['latitude'], bus_loc['longitude'], bus_loc['speed']

        return await self._calculate_prediction(user.id, bus_id, b_lat, b_lng, b_speed, stop.latitude, stop.longitude)

    async def _calculate_prediction(self, user_id, bus_id, b_lat, b_lng, b_speed, s_lat, s_lng):
        dist_to_stop = calculate_distance_km(b_lat, b_lng, s_lat, s_lng)
        phase = self.user_trip_phases.get(user_id, "waiting")
        prev_dist = getattr(self, f"_prev_dist_{user_id}", dist_to_stop)
        setattr(self, f"_prev_dist_{user_id}", dist_to_stop)

        if phase == "waiting" and (dist_to_stop < 0.25 or (dist_to_stop < 0.5 and dist_to_stop > prev_dist)):
            self.user_trip_phases[user_id] = "on_board"
            phase = "on_board"

        target_lat, target_lng = (COLLEGE_LATITUDE, COLLEGE_LONGITUDE) if phase == "on_board" else (s_lat, s_lng)
        final_dist = calculate_distance_km(b_lat, b_lng, target_lat, target_lng)
        status_text = "Approaching Stop" if phase == "waiting" else "Heading to Agni College of Technology"

        effective_speed = b_speed if b_speed > 5.0 else 20.0
        final_eta = estimate_eta_minutes(final_dist, effective_speed)

        return {
            "type": "PREDICTION_UPDATE",
            "payload": {
                "bus_id": bus_id,
                "distance_km": round(final_dist, 2),
                "eta_minutes": final_eta,
                "status": status_text,
                "is_to_college": phase == "on_board"
            }
        }


location_analyzer = LocationAnalyzer()