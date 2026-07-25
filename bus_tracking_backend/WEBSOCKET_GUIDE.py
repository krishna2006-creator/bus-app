"""
WEBSOCKET INTEGRATION GUIDE
Real-Time Bus Tracking System - Installation & Usage

AUTHOR: Bus Tracking Backend Team
DATE: January 2024
VERSION: 2.0 (Production Ready)
"""

# ============================================================================
# 1. INSTALLATION & SETUP
# ============================================================================

"""
STEP 1: Add new files to your backend
- services/websocket_manager_v2.py  (comprehensive bus room manager)
- routers/websocket_routes.py       (WebSocket endpoints)

STEP 2: Update main.py to import and mount the new router
"""

# Add to main.py after other imports:
from routers.websocket_routes import router as websocket_router

# Mount the router:
api_router.include_router(websocket_router)

# STEP 3: Update requirements.txt (already included in FastAPI)
# No new dependencies needed - uses only FastAPI, asyncio, logging

# STEP 4: (Optional) Update auth_utils if needed
# The implementation uses get_current_user from utils.auth_utils
# Make sure it returns a user object with: id, name, role


# ============================================================================
# 2. DATA FLOW ARCHITECTURE
# ============================================================================

"""
ARCHITECTURE OVERVIEW:

┌─────────────────────────────────────────────────────────────┐
│                     32 BUSES (Fixed)                        │
└─────────────────────────────────────────────────────────────┘
         │              │              │
    BUS 1         BUS 2         ...   BUS 32
    (Room)        (Room)         (Room)
         │              │              │
    ┌────────┐      ┌────────┐    ┌────────┐
    │User1   │      │User5   │    │User50  │
    │(Driver)│▬───▶ │Display │    │Student │
    └────────┘      └────────┘    └────────┘
    ┌────────┐      ┌────────┐
    │User2   │      │User6   │
    │Student │      │Student │
    └────────┘      └────────┘


DATA FLOW - Location Update:
1. Driver sends LOCATION_UPDATE to /ws/location/1?token=JWT
2. Server authenticates via JWT token
3. Server checks if driver is the location sender for Bus 1
4. If yes: Server stores last location in BusRoom cache
5. Server broadcasts to ALL users in Bus 1 room
6. New users connecting get LAST_KNOWN_LOCATION automatically

DATABASE LESS - Everything is in-memory:
- No database calls for location messages (ultra-fast)
- Last location stored in memory (not persistent)
- Persisting? Save to DB in handle_location_update() if needed


ROOM MANAGEMENT:
- Room created automatically on first user connection
- Room deleted automatically when last user disconnects
- No manual room management needed
- Supports 32 concurrent buses easily
"""


# ============================================================================
# 3. JSON MESSAGE FORMATS
# ============================================================================

"""
CLIENT SENDS TO SERVER:
========================

### Location Update (Driver or Student)
{
    "type": "LOCATION_UPDATE",
    "latitude": 28.6139,        # Required
    "longitude": 77.2090,       # Required
    "speed": 45.5,              # Optional (default: 0.0)
    "direction": 180.0,         # Optional (default: 0.0) - 0-360 degrees
    "accuracy": 5.0,            # Optional (default: 0.0) - radius in meters
    "timestamp": 1629783600.0   # Optional (default: current time)
}

### Heartbeat/Keep-Alive
{
    "type": "PING"
}

### Request Bus Info
{
    "type": "GET_BUS_INFO"
}

SERVER SENDS TO CLIENT:
=======================

### Location Broadcast to All Users in Bus
{
    "type": "LOCATION_UPDATE",
    "bus_id": 5,
    "data": {
        "latitude": 28.6139,
        "longitude": 77.2090,
        "speed": 45.5,
        "direction": 180.0,
        "accuracy": 5.0,
        "user_id": 12,
        "user_name": "Raj Kumar",
        "user_role": "driver",
        "timestamp": 1629783600.0
    },
    "timestamp": "2024-01-15T10:30:45.123456Z"
}

### Last Known Location on Connect
{
    "type": "LAST_KNOWN_LOCATION",
    "bus_id": 5,
    "data": {
        ...location data...
    },
    "timestamp": "2024-01-15T10:25:00.123456Z"
}

### Heartbeat Response
{
    "type": "PONG",
    "timestamp": "2024-01-15T10:30:45.123456Z"
}

### Bus Info (Active Users)
{
    "type": "BUS_INFO",
    "bus_id": 5,
    "user_count": 8,
    "active_users": [
        {
            "user_id": 12,
            "user_name": "Raj Kumar",
            "user_role": "driver",
            "is_location_sender": true,
            "connected_at": "2024-01-15T10:15:00Z"
        },
        {
            "user_id": 45,
            "user_name": "Priya Singh",
            "user_role": "student",
            "is_location_sender": false,
            "connected_at": "2024-01-15T10:20:00Z"
        }
    ],
    "timestamp": "2024-01-15T10:30:45.123456Z"
}

### Notification - User Joined Bus
{
    "type": "USER_JOINED",
    "bus_id": 5,
    "user_id": 45,
    "user_name": "Priya Singh",
    "user_role": "student",
    "timestamp": "2024-01-15T10:30:45.123456Z"
}

### Notification - User Left Bus
{
    "type": "USER_LEFT",
    "bus_id": 5,
    "user_id": 45,
    "user_name": "Priya Singh",
    "timestamp": "2024-01-15T10:30:45.123456Z"
}

### Error Response
{
    "type": "ERROR",
    "error": "User not authorized to send location",
    "bus_id": 5,
    "timestamp": "2024-01-15T10:30:45.123456Z"
}
"""


# ============================================================================
# 4. EXAMPLE IMPLEMENTATIONS
# ============================================================================

"""
PYTHON CLIENT (Async)
=====================
"""

import asyncio
import websockets
import json
from datetime import datetime
import time

class BusTrackingClient:
    def __init__(self, bus_id: int, user_id: int, token: str, server_url: str = "ws://localhost:8000"):
        self.bus_id = bus_id
        self.user_id = user_id
        self.token = token
        self.server_url = server_url
        self.websocket = None
        self.running = False

    async def connect(self) -> bool:
        """Connect to WebSocket"""
        try:
            ws_url = f"{self.server_url}/api/ws/ws/location/{self.bus_id}?token={self.token}"
            self.websocket = await websockets.connect(ws_url)
            self.running = True
            print(f"Connected to bus {self.bus_id}")
            return True
        except Exception as e:
            print(f"Connection failed: {e}")
            return False

    async def send_location(self, latitude: float, longitude: float, speed: float = 0.0):
        """Send location update"""
        if not self.websocket:
            return False

        message = {
            "type": "LOCATION_UPDATE",
            "latitude": latitude,
            "longitude": longitude,
            "speed": speed,
            "direction": 180.0,
            "accuracy": 5.0,
            "timestamp": time.time()
        }

        try:
            await self.websocket.send(json.dumps(message))
            print(f"Sent: {latitude}, {longitude}")
            return True
        except Exception as e:
            print(f"Send failed: {e}")
            return False

    async def send_heartbeat(self):
        """Send PING to keep connection alive"""
        if not self.websocket:
            return False

        try:
            await self.websocket.send(json.dumps({"type": "PING"}))
            return True
        except Exception as e:
            print(f"Heartbeat failed: {e}")
            return False

    async def receive_messages(self):
        """Receive and process messages"""
        if not self.websocket:
            return

        try:
            async for message in self.websocket:
                data = json.loads(message)
                message_type = data.get("type")
                print(f"Received [{message_type}]: {data}")

                if message_type == "LOCATION_UPDATE":
                    location = data.get("data")
                    print(f"  Bus location: {location['latitude']}, {location['longitude']}")

                elif message_type == "BUS_INFO":
                    print(f"  Active users: {data.get('user_count')}")
                    for user in data.get("active_users", []):
                        sender = "📍 (sender)" if user.get("is_location_sender") else ""
                        print(f"    - {user['user_name']} ({user['user_role']}) {sender}")

                elif message_type == "ERROR":
                    print(f"  Error: {data.get('error')}")

        except Exception as e:
            print(f"Receive error: {e}")

    async def disconnect(self):
        """Disconnect from WebSocket"""
        if self.websocket:
            await self.websocket.close()
            self.websocket = None
            self.running = False
            print(f"Disconnected from bus {self.bus_id}")

    async def run(self, duration: int = 60):
        """Run client for specified duration"""
        if not await self.connect():
            return

        # Start receive loop in background
        receive_task = asyncio.create_task(self.receive_messages())

        # Send heartbeat every 30 seconds
        start_time = time.time()
        heartbeat_interval = 30

        try:
            while time.time() - start_time < duration:
                current_time = time.time()

                # Send heartbeat
                if (current_time - start_time) % heartbeat_interval < 1:
                    await self.send_heartbeat()

                await asyncio.sleep(1)

        finally:
            receive_task.cancel()
            await self.disconnect()


# USAGE EXAMPLE:
async def example_client():
    """Example: Driver sending location"""
    client = BusTrackingClient(
        bus_id=5,
        user_id=12,
        token="your_jwt_token_here"
    )

    if await client.connect():
        # Start receiving in background
        receive_task = asyncio.create_task(client.receive_messages())

        # Send location updates every 5 seconds
        for i in range(12):  # Run for 1 minute
            await client.send_location(
                latitude=28.6139 + i * 0.001,
                longitude=77.2090 + i * 0.001,
                speed=45.0
            )
            await asyncio.sleep(5)

        receive_task.cancel()
        await client.disconnect()


if __name__ == "__main__":
    asyncio.run(example_client())


# ============================================================================
# JAVASCRIPT CLIENT (Browser - with Reconnection)
# ============================================================================

"""
// File: public/js/bus-tracking.js

class BusTrackingWebSocket {
    constructor(busId, token, serverUrl = 'ws://localhost:8000') {
        this.busId = busId;
        this.token = token;
        this.serverUrl = serverUrl;
        this.ws = null;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 10;
        this.reconnectInterval = 3000;
        this.messageHandlers = {};
    }

    connect() {
        const wsUrl = `${this.serverUrl}/api/ws/ws/location/${this.busId}?token=${this.token}`;
        
        this.ws = new WebSocket(wsUrl);
        
        this.ws.onopen = () => {
            console.log(`Connected to bus ${this.busId}`);
            this.reconnectAttempts = 0;
            this.emit('connected');
        };

        this.ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            console.log(`[${data.type}]`, data);
            this.emit(data.type, data);
        };

        this.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
            this.emit('error', error);
        };

        this.ws.onclose = () => {
            console.log('WebSocket closed');
            this.attemptReconnect();
        };
    }

    send(message) {
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify(message));
        } else {
            console.warn('WebSocket not connected');
        }
    }

    sendLocation(latitude, longitude, speed = 0, direction = 0, accuracy = 5) {
        this.send({
            type: 'LOCATION_UPDATE',
            latitude,
            longitude,
            speed,
            direction,
            accuracy,
            timestamp: Date.now() / 1000
        });
    }

    sendHeartbeat() {
        this.send({ type: 'PING' });
    }

    requestBusInfo() {
        this.send({ type: 'GET_BUS_INFO' });
    }

    attemptReconnect() {
        if (this.reconnectAttempts < this.maxReconnectAttempts) {
            this.reconnectAttempts++;
            const delay = this.reconnectInterval * this.reconnectAttempts;
            console.log(`Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts})`);
            
            setTimeout(() => this.connect(), delay);
        } else {
            console.error('Max reconnection attempts reached');
            this.emit('reconnect_failed');
        }
    }

    on(event, callback) {
        if (!this.messageHandlers[event]) {
            this.messageHandlers[event] = [];
        }
        this.messageHandlers[event].push(callback);
    }

    emit(event, data) {
        if (this.messageHandlers[event]) {
            this.messageHandlers[event].forEach(callback => callback(data));
        }
    }

    disconnect() {
        if (this.ws) {
            this.ws.close();
            this.ws = null;
        }
    }
}

// USAGE EXAMPLE:
const tracking = new BusTrackingWebSocket(
    busId = 5,
    token = 'your_jwt_token'
);

tracking.on('LOCATION_UPDATE', (data) => {
    const location = data.data;
    console.log(`Bus at: ${location.latitude}, ${location.longitude}`);
    // Update map with new location
    updateMapMarker(location.latitude, location.longitude);
});

tracking.on('BUS_INFO', (data) => {
    console.log(`Active users: ${data.user_count}`);
    updateUserList(data.active_users);
});

tracking.on('USER_JOINED', (data) => {
    showNotification(`${data.user_name} joined the bus`);
});

tracking.on('error', (error) => {
    showAlert('Connection error, reconnecting...');
});

tracking.connect();

// Send location every 10 seconds (if user is driver)
setInterval(() => {
    navigator.geolocation.getCurrentPosition(pos => {
        tracking.sendLocation(
            pos.coords.latitude,
            pos.coords.longitude,
            pos.coords.speed || 0
        );
    });
}, 10000);

// Heartbeat every 30 seconds to keep connection alive
setInterval(() => tracking.sendHeartbeat(), 30000);
"""


# ============================================================================
# 5. PRODUCTION DEPLOYMENT CHECKLIST
# ============================================================================

"""
PRE-DEPLOYMENT CHECKLIST:
✅ 1. Authentication
   - Ensure JWT tokens are properly validated
   - Token should come from query parameter or header
   - Set token expiration to reasonable value (e.g., 24 hours)
   - Use HTTPS/WSS in production

✅ 2. Security
   - Enable CORS only for trusted domains
   - Implement rate limiting on REST endpoints
   - Add request validation
   - Log all connection/disconnection events

✅ 3. Monitoring
   - Add metrics for WebSocket connections
   - Monitor memory usage (cached locations)
   - Track failed broadcasts
   - Alert on unusual patterns

✅ 4. Resource Management
   - Set connection timeout (60-120 seconds recommended)
   - Clear dead connections automatically
   - Implement max connections per bus
   - Monitor CPU and memory usage

✅ 5. Testing
   - Load test with 32 buses × 10 users = 320 connections
   - Test with 90+ users per bus for stress test
   - Verify message delivery reliability
   - Test reconnection scenarios

✅ 6. Deployment
   - Use multiple uvicorn workers (4-8 for production)
   - Deploy behind load balancer
   - Use reverse proxy (Nginx) with WebSocket support
   - Enable gzip compression
   - Set up health checks

✅ 7. Configuration
   - Set environment-specific settings
   - Configure logging levels
   - Enable access logs
   - Set proper timeouts
"""

# ============================================================================
# 6. PERFORMANCE CHARACTERISTICS
# ============================================================================

"""
PERFORMANCE METRICS (Expected):
===============================

Latency:
- Message send-to-receive: < 100ms (local network)
- Broadcast to 10 users: < 50ms
- Broadcast to 100 users: < 200ms

Memory Usage:
- Per connection: ~2-3 KB
- Per bus room: ~5 KB (shared)
- Last location storage: ~500 B per bus
- Total for 320 connections: ~1-2 MB

Throughput:
- Single bus: 10-50 location updates per second
- 32 buses × 10 updates/sec: 320 updates/sec
- ~64 KB/sec data transmission (typical)

Scaling Limits (Single Server):
- CPU: Limited by number of concurrent connections
- Memory: ~1-2 MB for 10,000 concurrent connections
- Network: Limited by bandwidth (typical: 100 Mbps → 12.5 MB/s)

RECOMMENDATIONS FOR SCALING:
- 50-100 users: Single server, 2-4 workers
- 100-500 users: Single server, 4-8 workers or Redis pub/sub
- 500+ users: Redis pub/sub + multiple servers
- 1000+ users: Message queue (RabbitMQ) + multiple servers
"""

# ============================================================================
# 7. TROUBLESHOOTING & DEBUGGING
# ============================================================================

"""
COMMON ISSUES & SOLUTIONS:
==========================

Issue #1: Users not receiving location updates
Solution:
- Check user's role (must be driver or first connected student)
- Verify user is in manager.buses[bus_id].connections
- Check WebSocket connection status (open/closed)
- Verify no authentication errors in logs

Issue #2: Last location not sent on connect
Solution:
- Check if location has been sent before connection
- Verify manager.send_last_location_to_user() was called
- Check logs for broadcast failures

Issue #3: Connection drops after 60 seconds
Solution:
- Add heartbeat/keep-alive mechanism
- Increase idle connection timeout on server/reverse proxy
- Check firewall rules blocking idle connections

Issue #4: High memory usage
Solution:
- Check if connections are properly cleaned up
- Verify disconnect() is called on WebSocketDisconnect
- Monitor for connection leaks using get_stats()
- Implement max connection limit per bus

Issue #5: Users from one bus receiving messages from another
Solution:
- Verify bus_id is correctly passed to manager.connect()
- Check broadcast_to_bus() only targets correct bus_id
- Verify no global broadcast() calls are used

DEBUGGING TIPS:
- Enable debug logging: logger.setLevel(logging.DEBUG)
- Use /api/ws/stats endpoint to check current state
- Monitor /api/ws/bus/{bus_id}/info for specific bus
- Check logs for connection/disconnection events
"""

# ============================================================================
# 8. MIGRATION FROM OLD WEBSOCKET_MANAGER
# ============================================================================

"""
If you're upgrading from old websocket_manager.py:

OLD CODE (Don't use):
    from services.websocket_manager import manager
    await manager.connect(websocket, user_id)
    await manager.broadcast(message)

NEW CODE (Use this):
    from services.websocket_manager_v2 import manager
    await manager.connect(websocket, user_id, user_name, user_role, bus_id)
    await manager.broadcast_to_bus(bus_id, message)

BREAKING CHANGES:
- connect() now requires: user_name, user_role, bus_id
- broadcast() renamed to broadcast_to_bus() and requires bus_id
- New method: handle_location_update() for location-specific logic
- New method: send_last_location_to_user()
- New method: get_bus_info(), get_stats()

MIGRATION STEPS:
1. Replace websocket_manager.py with websocket_manager_v2.py
2. Update all endpoint handlers to use new manager API
3. Update client code to send location inside bus room
4. Test with single bus first, then all 32 buses
5. Monitor /api/ws/stats to verify correctness
"""
