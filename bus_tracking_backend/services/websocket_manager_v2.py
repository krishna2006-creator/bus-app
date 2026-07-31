"""
Enhanced WebSocket Manager with Bus-based Rooms
Handles real-time location sharing for multiple buses with proper grouping,
last known location storage, and driver preference.
"""

from typing import Dict, List, Optional, Any, Set
from fastapi import WebSocket
from dataclasses import dataclass, field
from datetime import datetime
import json
import asyncio
import logging

logger = logging.getLogger(__name__)


@dataclass
class LocationData:
    """Represents a single location update"""
    latitude: float
    longitude: float
    speed: float = 0.0
    direction: float = 0.0
    timestamp: float = 0.0
    user_id: int = 0
    user_name: str = ""
    user_role: str = "student"  # 'driver' or 'student'
    accuracy: float = 0.0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "latitude": self.latitude,
            "longitude": self.longitude,
            "speed": self.speed,
            "direction": self.direction,
            "timestamp": self.timestamp,
            "user_id": self.user_id,
            "user_name": self.user_name,
            "user_role": self.user_role,
            "accuracy": self.accuracy,
        }


@dataclass
class UserConnection:
    """Represents a single WebSocket connection"""
    websocket: WebSocket
    user_id: Any  # Support both int and string IDs like 'stu001'
    user_name: str
    user_role: str  # 'driver' or 'student'
    bus_id: int
    connected_at: datetime = field(default_factory=datetime.now)
    last_heartbeat: datetime = field(default_factory=datetime.now)

    def is_driver(self) -> bool:
        return self.user_role.lower() == "driver"

    async def send_json(self, data: Dict[str, Any]) -> bool:
        """Send JSON to this connection. Returns False if connection is dead."""
        try:
            await self.websocket.send_json(data)
            return True
        except Exception as e:
            logger.warning(f"Failed to send to user {self.user_id}: {e}")
            return False


class BusRoom:
    """Represents all connections for a single bus"""

    def __init__(self, bus_id: int):
        self.bus_id = bus_id
        self.connections: Dict[Any, List[UserConnection]] = {}  # user_id -> list of connections
        self.last_known_location: Optional[LocationData] = None
        self.location_sender_id: Optional[int] = None  # Current active location sender (prefer driver)
        self.created_at = datetime.now()

    def add_connection(self, connection: UserConnection) -> None:
        """Add a user connection to this bus room"""
        user_id = connection.user_id
        if user_id not in self.connections:
            self.connections[user_id] = []

        self.connections[user_id].append(connection)
        logger.info(
            f"User {connection.user_id} ({connection.user_role}) added to bus {self.bus_id}. "
            f"Total connections: {self.get_connection_count()}"
        )

    def remove_connection(self, user_id: Any, websocket: Optional[WebSocket] = None) -> bool:
        """Remove a user connection from this bus room. Returns True if room is now empty."""
        if user_id not in self.connections:
            return len(self.connections) == 0

        if websocket is None:
            remaining_connections = []
        else:
            remaining_connections = [
                conn for conn in self.connections[user_id] if conn.websocket != websocket
            ]

        if remaining_connections:
            self.connections[user_id] = remaining_connections
        else:
            del self.connections[user_id]
            logger.info(
                f"User {user_id} removed from bus {self.bus_id}. "
                f"Remaining users: {len(self.connections)}"
            )

            # If this was the location sender, clear it
            if self.location_sender_id == user_id:
                self.location_sender_id = None
                self._update_location_sender()

        return len(self.connections) == 0

    def _update_location_sender(self) -> None:
        """Update the current location sender (prefer driver, then fallback to any user)"""
        if not self.connections:
            self.location_sender_id = None
            return

        # Look for a driver first
        for user_id, connections in self.connections.items():
            if any(connection.is_driver() for connection in connections):
                self.location_sender_id = user_id
                logger.info(f"Bus {self.bus_id}: Location sender set to driver {user_id}")
                return

        # If no driver, use the first connected user (oldest connection)
        oldest_connection = min(
            self.connections.values(), key=lambda connections: connections[0].connected_at
        )[0]
        self.location_sender_id = oldest_connection.user_id
        logger.info(
            f"Bus {self.bus_id}: Location sender set to {oldest_connection.user_role} {oldest_connection.user_id}"
        )

    def can_send_location(self, user_id: Any) -> bool:
        """Check if user is allowed to send location for this bus"""
        if user_id not in self.connections:
            return False

        if self.location_sender_id is None:
            # No active sender yet, set this user
            self._update_location_sender()

        # Allow if user is current sender
        if self.location_sender_id == user_id:
            return True

        # Allow if user is a driver and current sender is not
        connection = self.connections[user_id][0]
        current_sender_connections = self.connections.get(self.location_sender_id, [])
        current_sender_is_driver = any(conn.is_driver() for conn in current_sender_connections)
        if connection.is_driver() and not current_sender_is_driver:
            self.location_sender_id = user_id
            logger.info(f"Bus {self.bus_id}: Location sender switched to driver {user_id}")
            return True

        return False

    def set_last_location(self, location: LocationData) -> None:
        """Store the last known location"""
        self.last_known_location = location

    def clear_last_location(self) -> None:
        """Clear the last known location (used when sharing stops)"""
        self.last_known_location = None
        self.location_sender_id = None

    def get_last_location(self) -> Optional[Dict[str, Any]]:
        """Get the last known location as dictionary"""
        if self.last_known_location:
            return self.last_known_location.to_dict()
        return None

    async def broadcast_to_room(self, message: Dict[str, Any], exclude_user_id: Optional[int] = None) -> int:
        """
        Broadcast message to all users in this bus room.
        Args:
            message: Message to broadcast
            exclude_user_id: Optional user ID to exclude from broadcast
        Returns:
            Number of successfully sent messages
        """
        dead_connections = []
        sent_count = 0

        for user_id, connections in list(self.connections.items()):
            if exclude_user_id and user_id == exclude_user_id:
                continue

            for connection in list(connections):
                success = await connection.send_json(message)
                if success:
                    sent_count += 1
                else:
                    dead_connections.append((user_id, connection.websocket))

        # Clean up dead connections
        for user_id, websocket in dead_connections:
            self.remove_connection(user_id, websocket)

        return sent_count

    def get_connection_count(self) -> int:
        """Get number of active connections in this bus"""
        return sum(len(connections) for connections in self.connections.values())

    def get_user_count(self) -> int:
        """Get number of connected users in this bus"""
        return len(self.connections)

    def get_active_users(self) -> List[Dict[str, Any]]:
        """Get list of all active users in this bus"""
        active_users = []
        for user_id, connections in self.connections.items():
            for conn in connections:
                active_users.append(
                    {
                        "user_id": conn.user_id,
                        "user_name": conn.user_name,
                        "user_role": conn.user_role,
                        "connected_at": conn.connected_at.isoformat(),
                        "is_location_sender": conn.user_id == self.location_sender_id,
                    }
                )
        return active_users


class WebSocketManager:
    """
    Manages WebSocket connections organized by bus rooms.
    Features:
    - Bus-based room grouping (32 buses)
    - One active location sender per bus (prefers driver)
    - Last known location storage and delivery
    - Efficient broadcast to bus members only
    - Proper connection/disconnection handling
    - Multiple connections per user support
    """

    def __init__(self):
        self.buses: Dict[int, BusRoom] = {}  # bus_id -> BusRoom
        self.user_connections: Dict[Any, List[UserConnection]] = {}  # user_id -> list of connections
        self.user_to_buses: Dict[Any, Set[int]] = {}  # user_id -> set of bus_ids

    def _get_or_create_bus_room(self, bus_id: int) -> BusRoom:
        """Get or create a bus room"""
        if bus_id not in self.buses:
            self.buses[bus_id] = BusRoom(bus_id)
        return self.buses[bus_id]

    async def connect(
        self,
        websocket: WebSocket,
        user_id: Any,
        user_name: str,
        user_role: str,
        bus_id: int,
    ) -> bool:
        """
        Connect a user to a bus room. The WebSocket must be accepted by the caller first.
        Args:
            websocket: WebSocket connection
            user_id: User ID
            user_name: User name/display name
            user_role: User role (e.g., 'driver', 'student')
            bus_id: Bus ID
        Returns:
            True if successful, False otherwise
        """
        try:
            # Normalize user id to string for consistent lookups
            user_id_str = str(user_id)

            # Create user connection object
            connection = UserConnection(
                websocket=websocket,
                user_id=user_id_str,
                user_name=user_name,
                user_role=user_role,
                bus_id=bus_id,
            )

            # Add to bus room
            bus_room = self._get_or_create_bus_room(bus_id)
            bus_room.add_connection(connection)

            # Track user connections
            if user_id_str not in self.user_connections:
                self.user_connections[user_id_str] = []
                self.user_to_buses[user_id_str] = set()

            self.user_connections[user_id_str].append(connection)
            self.user_to_buses[user_id_str].add(bus_id)

            logger.info(f"User {user_id} connected to bus {bus_id}")
            return True

        except Exception as e:
            logger.error(f"Failed to connect user {user_id}: {e}")
            return False

    def disconnect(self, user_id: Any, websocket: Optional[WebSocket] = None, bus_id: Optional[int] = None) -> bool:
        """
        Disconnect a user from all or specific buses.
        Args:
            user_id: User ID
            websocket: Optional specific WebSocket to disconnect (if user has multiple)
        Returns:
            True if user was found and disconnected
        """
        user_id_str = str(user_id)
        if user_id_str not in self.user_connections:
            return False

        connections_to_remove = []

        if websocket:
            # Disconnect specific connection
            for conn in self.user_connections[user_id_str]:
                if conn.websocket == websocket:
                    connections_to_remove.append(conn)
        elif bus_id:
            # Disconnect all connections for this user to a specific bus_id
            for conn in self.user_connections[user_id_str]:
                if conn.bus_id == bus_id:
                    connections_to_remove.append(conn)
        else:
            # Disconnect all connections for this user
            connections_to_remove = self.user_connections[user_id_str].copy()

        # Remove from bus rooms and track
        buses_to_check = set()

        for connection in connections_to_remove:
            bus_id = connection.bus_id
            bus_room = self.buses.get(bus_id)

            if bus_room:
                is_empty = bus_room.remove_connection(user_id_str, connection.websocket)
                buses_to_check.add(bus_id)

                # If room is empty, remove it
                if is_empty:
                    del self.buses[bus_id]
                    logger.info(f"Bus room {bus_id} removed (no active users)")

            self.user_connections[user_id_str].remove(connection)

            # Remove bus_id from user_to_buses if no more connections for that bus
            if bus_id in self.user_to_buses[user_id_str] and not any(c.bus_id == bus_id for c in self.user_connections[user_id_str]):
                self.user_to_buses[user_id_str].remove(bus_id)

        # Clean up user tracking if no more connections
        if not self.user_connections[user_id_str]:
            del self.user_connections[user_id_str]
            del self.user_to_buses[user_id_str]
            logger.info(f"User {user_id} fully disconnected")

        return bool(connections_to_remove)

    async def broadcast_to_bus(
        self,
        bus_id: int,
        message: Dict[str, Any],
        exclude_user_id: Optional[int] = None,
    ) -> int:
        """
        Broadcast message to all users in a specific bus.
        Args:
            bus_id: Bus ID to broadcast to
            message: Message to broadcast
            exclude_user_id: Optional user ID to exclude
        Returns:
            Number of messages successfully sent
        """
        bus_room = self.buses.get(bus_id)
        if not bus_room:
            return 0

        return await bus_room.broadcast_to_room(message, exclude_user_id)

    async def broadcast(self, message: Dict[str, Any]):
        """Broadcast message to EVERYONE connected to the server, including those not in a specific bus room."""
        for user_id in list(self.user_connections.keys()):
            dead_connections = []
            for connection in self.user_connections[user_id]:
                success = await connection.send_json(message)
                if not success:
                    dead_connections.append(connection.websocket)
            
            # Clean up any dead connections found during broadcast
            for ws in dead_connections:
                self.disconnect(user_id, ws)

    async def send_personal_message(self, user_id: Any, message: Dict[str, Any]) -> int:
        """
        Send message to a specific user (all their connections).
        Args:
            user_id: User ID
            message: Message to send
        Returns:
            Number of messages successfully sent
        """
        user_id_str = str(user_id)
        if user_id_str not in self.user_connections:
            return 0

        sent_count = 0
        dead_connections = []

        for connection in self.user_connections[user_id_str]:
            success = await connection.send_json(message)
            if success:
                sent_count += 1
            else:
                dead_connections.append(connection)

        # Clean up dead connections
        for connection in dead_connections:
            self.disconnect(user_id_str, connection.websocket)

        return sent_count

    async def handle_location_update(
        self,
        bus_id: int,
        user_id: Any,
        location_data: LocationData,
    ) -> Dict[str, Any]:
        """
        Handle location update from a user.
        Validates if user can send, stores last location, broadcasts to bus.
        If no bus room exists, it creates one so the location is cached.
        Args:
            bus_id: Bus ID
            user_id: User ID sending location
            location_data: Location data
        Returns:
            Response dict with status and details
        """
        bus_room = self.buses.get(bus_id)
        if not bus_room:
            # Auto-create bus room to cache location even without WebSocket clients
            bus_room = self._get_or_create_bus_room(bus_id)
            logger.info(f"Auto-created bus room for bus {bus_id} via location update")
        
        # Store last known location regardless of sender
        bus_room.set_last_location(location_data)
        
        # Also cache for fast REST API retrieval
        try:
            from .cache import set_latest_location
            set_latest_location(f"bus:{bus_id}", location_data.to_dict())
        except Exception:
            pass

        # Check if user is authorized to update the official BUS position
        # Normalize user id for room checks
        user_id_str = str(user_id)
        is_official_sender = bus_room.can_send_location(user_id_str)
        
        # We allow students and drivers to broadcast their individual locations even if they 
        # aren't the primary sender for the bus (which is reserved for drivers/boarded students).
        is_student_sharing = location_data.user_role == "student"
        is_driver_sharing = location_data.user_role == "driver"

        # Always broadcast the location update to the bus room - do NOT reject
        # REST API location updates from drivers who aren't WebSocket-connected.
        # The post_public_location endpoint handles authentication separately.
        message = {
            "type": "LOCATION_UPDATE",
            "bus_id": bus_id,
            "payload": location_data.to_dict(),
            "timestamp": datetime.now().isoformat(),
        }

        sent_count = await bus_room.broadcast_to_room(message)

        # Also broadcast to ALL connected users so phones that aren't in this
        # specific bus room still receive the location update in real-time.
        await self.broadcast(message)

        return {
            "success": True,
            "bus_id": bus_id,
            "user_id": user_id_str,
            "broadcast_to_count": sent_count,
            "is_official_sender": is_official_sender,
            "is_student_sharing": is_student_sharing,
            "is_driver_sharing": is_driver_sharing,
        }

    async def send_last_location_to_user(
        self, bus_id: int, user_id: int
    ) -> bool:
        """
        Send the last known location of a bus to a newly connected user.
        Args:
            bus_id: Bus ID
            user_id: User ID
        Returns:
            True if location was sent, False if no last known location
        """
        bus_room = self.buses.get(bus_id)
        if not bus_room:
            return False

        last_location = bus_room.get_last_location()
        if not last_location:
            return False

        message = {
            "type": "LAST_KNOWN_LOCATION",
            "bus_id": bus_id,
            "data": last_location,
            "timestamp": datetime.now().isoformat(),
        }

        return await self.send_personal_message(user_id, message) > 0

    def get_bus_info(self, bus_id: int) -> Optional[Dict[str, Any]]:
        """Get information about a bus room"""
        bus_room = self.buses.get(bus_id)
        if not bus_room:
            return None

        return {
            "bus_id": bus_id,
            "user_count": bus_room.get_user_count(),
            "active_users": bus_room.get_active_users(),
            "location_sender_id": bus_room.location_sender_id,
            "has_last_location": bus_room.last_known_location is not None,
            "last_known_location": bus_room.last_known_location,
            "created_at": bus_room.created_at.isoformat(),
        }

    def get_all_buses_status(self) -> Dict[int, Dict[str, Any]]:
        """Get status of all active bus rooms"""
        return {bus_id: self.get_bus_info(bus_id) for bus_id in self.buses.keys()}

    def get_user_buses(self, user_id: int) -> List[int]:
        """Get all buses a user is connected to"""
        return list(self.user_to_buses.get(user_id, set()))

    def get_stats(self) -> Dict[str, Any]:
        """Get WebSocket manager statistics"""
        return {
            "total_buses": len(self.buses),
            "total_users": len(self.user_connections),
            "total_connections": sum(len(conns) for conns in self.user_connections.values()),
            "buses": self.get_all_buses_status(),
        }


# Global instance
manager = WebSocketManager()
