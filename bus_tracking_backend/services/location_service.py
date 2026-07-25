from sqlalchemy.orm import Session
from ..database import models
from ..schemas import bus as bus_schemas
from datetime import datetime
from typing import Optional, Dict, List

class LocationService:
    def __init__(self):
        self.active_bus_locations: Dict[int, Dict] = {}
        self.student_states = {}

    async def process_driver_location(self, db: Session, location_data: bus_schemas.LiveLocationUpdate):
        location_timestamp = datetime.fromtimestamp(location_data.timestamp)
        db_location = models.LiveLocation(
            bus_id=location_data.bus_id,
            user_id=location_data.user_id,
            latitude=location_data.latitude,
            longitude=location_data.longitude,
            speed=location_data.speed,
            timestamp=location_timestamp
        )
        db.add(db_location)
        db.commit()
        db.refresh(db_location)
        
        if location_data.user_role == models.UserRole.DRIVER and location_data.bus_id:
            self.active_bus_locations[location_data.bus_id] = {
                "location": bus_schemas.LiveLocationResponse.model_validate(db_location),
                "timestamp": location_timestamp
            }
        
        return bus_schemas.LiveLocationResponse.model_validate(db_location)

    def get_active_bus_location(self, bus_id: int) -> Optional[bus_schemas.LiveLocationResponse]:
        active_data = self.active_bus_locations.get(bus_id)
        if active_data:
            return active_data["location"]
        return None

    def update_location(self, bus_id: int, latitude: float, longitude: float):
        """Update the current location of a bus."""
        if bus_id not in self.active_bus_locations:
            self.active_bus_locations[bus_id] = {}
        
        self.active_bus_locations[bus_id].update({
            "bus_id": bus_id,
            "latitude": latitude,
            "longitude": longitude,
            "timestamp": datetime.now()
        })
        return self.active_bus_locations[bus_id]

    def clear_location(self, bus_id: int):
        """Clear/remove the location for a bus."""
        if bus_id in self.active_bus_locations:
            del self.active_bus_locations[bus_id]
        return {"status": "cleared"}

    def update_student_state(self, user_id: int, boarded: bool, bus_id: Optional[int] = None):
        self.student_states[user_id] = {"boarded": boarded, "bus_id": bus_id}

    async def analyze_buses_for_student(self, db: Session, lat: float, lon: float, user_id: int) -> List[bus_schemas.BusAnalysisResult]:
        # Placeholder for complex analysis logic
        # In a real implementation, this would calculate ETA for nearby buses to the student's location
        return []

location_service = LocationService()