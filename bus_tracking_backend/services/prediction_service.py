from sqlalchemy.orm import Session
from ..database import models
from ..utils.geo_utils import get_osrm_route, calculate_distance_km, estimate_eta_minutes
from typing import Optional, Dict
from datetime import datetime

# Agni College of Technology, Old Mahabalipuram Road, Thalambur, Chennai – 600130
# Correct Coordinates: 12.836371, 80.222332
COLLEGE_LATITUDE = 12.836371
COLLEGE_LONGITUDE = 80.222332

class PredictionService:
    def __init__(self):
        # Latest bus coordinates cached in memory: {bus_id: {lat, lon}}
        self.bus_coords = {}
        # User trip phase tracker: {user_id: phase}
        # 0 = heading to stop, 1 = heading to college (Supports Staff & Students)
        self.user_phases = {}

    async def update_bus_coord(self, bus_id: int, lat: float, lon: float):
        self.bus_coords[bus_id] = {"lat": lat, "lon": lon}

    async def get_prediction_for_user(self, db: Session, user: models.User):
        """
        Calculates prediction for a specific user (staff or student) based on
        their pinned bus and boarding stop.
        """
        user_id_str = str(user.id)
        res = await self.get_live_prediction(db, user_id_str)
        if not res or "error" in res:
            return None

        # Return an object that provides a model_dump method for the websocket sender
        class PredictionResponse:
            def __init__(self, data):
                self.data = data
            def model_dump(self):
                return {
                    "bus_id": self.data["bus_id"],
                    "distance_km": round(self.data["distance_km"], 2),
                    "eta_minutes": self.data["duration_mins"],
                    "status": self.data["status"],
                    "is_to_college": self.data["target"] == "Agni College of Technology"
                }
        return PredictionResponse(res)

    async def get_live_prediction(self, db: Session, user_id: str):
        """
        Main calculation engine.
        Combines DB state (pinned stop) with live memory (bus location).
        """
        # 1. Get student's pinned bus/stop from DB
        pinned = db.query(models.PinnedBus).filter(models.PinnedBus.user_id == user_id).first()
        if not pinned:
            return {"error": "No bus pinned"}

        # 2. Get the bus location
        bus_loc = self.bus_coords.get(pinned.bus_id)
        if not bus_loc:
            return {"error": "Bus is offline"}

        # 3. Handle the Auto-Switch logic (Distance < 100m)
        stop = pinned.boarding_stop
        if not stop:
            # Fallback: load stop manually
            if pinned.boarding_stop_id:
                stop = db.query(models.BusStop).filter(models.BusStop.id == pinned.boarding_stop_id).first()
            if not stop:
                return {"error": "No stop coordinates found"}

        # Current phase
        phase = self.user_phases.get(user_id, 0)

        # Check if we should switch to College target
        if phase == 0:
            dist_to_stop, _ = await get_osrm_route(
                bus_loc["lat"], bus_loc["lon"],
                stop.latitude, stop.longitude
            )
            # Switch phase if bus is within 250 meters of the stop
            if dist_to_stop < 0.25:
                self.user_phases[user_id] = 1
                phase = 1

        # 4. Final Calculation based on Phase
        if phase == 1:
            # Phase: Heading to Agni College of Technology
            dist, duration = await get_osrm_route(
                bus_loc["lat"], bus_loc["lon"],
                COLLEGE_LATITUDE, COLLEGE_LONGITUDE
            )
            status = "Heading to Agni College of Technology"
        else:
            # Phase: Approaching Stop
            dist, duration = await get_osrm_route(
                bus_loc["lat"], bus_loc["lon"],
                stop.latitude, stop.longitude
            )
            status = "Approaching Stop"

        return {
            "bus_id": pinned.bus_id,
            "distance_km": dist,
            "duration_mins": duration,
            "status": status,
            "target": "Agni College of Technology" if phase == 1 else "Your Stop",
            "timestamp": datetime.now().isoformat()
        }

    async def get_predictions_for_stop(self, db: Session, stop_id: int):
        """
        Get all bus predictions for buses passing through a specific stop.
        Returns a list of predictions with ETA and distance for all buses at that stop.
        """
        predictions = []

        try:
            # 1. Get the stop coordinates
            stop = db.query(models.BusStop).filter(models.BusStop.id == stop_id).first()
            if not stop:
                return []

            # 2. Find all buses whose route passes through this stop (by bus_id)
            buses = db.query(models.Bus).join(
                models.BusStop,
                models.Bus.id == models.BusStop.bus_id
            ).filter(
                models.BusStop.id == stop_id
            ).all()

            # For each bus at the stop, calculate prediction
            for bus in buses:
                bus_loc = self.bus_coords.get(bus.id)

                if not bus_loc:
                    # Bus is offline, skip
                    continue

                # Calculate distance and ETA
                try:
                    distance_km, duration_mins = await get_osrm_route(
                        bus_loc["lat"], bus_loc["lon"],
                        stop.latitude, stop.longitude
                    )
                except Exception:
                    # Fallback to haversine distance
                    distance_km = calculate_distance_km(
                        bus_loc["lat"], bus_loc["lon"],
                        stop.latitude, stop.longitude
                    )
                    duration_mins = estimate_eta_minutes(distance_km, 20.0)

                # Create prediction response
                predictions.append({
                    "bus_id": bus.id,
                    "bus_number": bus.bus_number,
                    "route_name": bus.route_name,
                    "eta_minutes": int(duration_mins),
                    "distance_km": round(distance_km, 2),
                    "traffic_level": "normal",
                    "is_to_college": False,
                    "arrival_time": datetime.now().isoformat()
                })

            # Sort by ETA
            predictions.sort(key=lambda x: x["eta_minutes"])
            return predictions
        except Exception as e:
            print(f"Error getting predictions for stop: {e}")
            return []

prediction_service = PredictionService()
