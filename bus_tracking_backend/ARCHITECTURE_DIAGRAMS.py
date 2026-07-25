"""
VISUAL ARCHITECTURE & DATA FLOW DIAGRAMS
Real-Time Bus Tracking WebSocket System

ASCII diagrams and visual representations for quick understanding.
"""

# ============================================================================
# DIAGRAM 1: System Architecture
# ============================================================================

"""
┌──────────────────────────────────────────────────────────────────┐
│                          CLIENTS (Web/Mobile)                     │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐ │
│  │  Student 1 │  │  Driver 1  │  │  Student 2 │  │  Student 3 │ │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘ │
└────────┼───────────────┼───────────────┼───────────────┼─────────┘
         │ WS: /ws/location/1             │               │
         │                                │               │
         ├────────────────────────────────┼───────────────┤
         │                                │               │
┌────────▼────────────────────────────────▼───────────────▼─────────┐
│               FASTAPI BACKEND (main.py)                           │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─── Authentication (JWT Validation) ───┐                     │
│  │ - Verify token                        │                     │
│  │ - Extract user_id, role               │                     │
│  │ - Check authorization                 │                     │
│  └────────────────────────────────────────┘                     │
│                    │                                             │
│                    ▼                                             │
│  ┌──────────────────────────────────────────┐                  │
│  │   WebSocketManager (Global Instance)     │                  │
│  ├──────────────────────────────────────────┤                  │
│  │                                          │                  │
│  │  ┌─ BusRoom(1) ─────────────────────┐  │                  │
│  │  │ connections = {                  │  │                  │
│  │  │   1: UserConnection(Student 1)   │  │                  │
│  │  │   2: UserConnection(Driver 1)    │  │  ◄─ Location     │
│  │  │   3: UserConnection(Student 2)   │  │     broadcast    │
│  │  │   4: UserConnection(Student 3)   │  │     happens here │
│  │  │ }                                 │  │                  │
│  │  │ location_sender_id = 2 (driver)  │  │                  │
│  │  │ last_known_location = {...}      │  │                  │
│  │  └──────────────────────────────────┘  │                  │
│  │                                         │                  │
│  │  ┌─ BusRoom(2) ─────────────────────┐  │                  │
│  │  │ connections = { ... }            │  │                  │
│  │  │ location_sender_id = 5           │  │                  │
│  │  │ last_known_location = None       │  │                  │
│  │  └──────────────────────────────────┘  │                  │
│  │                                         │                  │
│  │  ... (up to 32 buses)                   │                  │
│  │                                         │                  │
│  └─────────────────────────────────────────┘                  │
│                                                                 │
│  ┌─── Health Check Endpoints ───┐                            │
│  │ GET /health/status           │                            │
│  │ GET /ws/stats                │ ◄─ Metrics                │
│  │ GET /ws/bus/{id}/info        │                            │
│  │ GET /ws/user/{id}/buses      │                            │
│  └──────────────────────────────┘                            │
│                                                                 │
└──────────────────────────────────────────────────────────────────┘
         │                                             │
         │ HTTP/HTTPS/WSS                             │ HTTP/HTTPS
         │                                             │
┌────────▼─────────────────────────────────────────────▼─────────┐
│            NGINX Reverse Proxy (Production)                      │
│   - SSL/TLS Termination                                        │
│   - Load Balancing (4-8 worker processes)                      │
│   - WebSocket upgrade handling                                 │
│   - Compression (gzip)                                         │
│   - Security headers                                           │
└──────────────────────────────────────────────────────────────────┘
         │
         │
┌────────▼────────────────────────────────┐
│        Optional: Database (PostgreSQL)   │
│   ┌─────────────────────────────────┐   │
│   │ LocationHistory (if needed)     │   │
│   │ - For historical analytics      │   │
│   │ - Not used for real-time        │   │
│   │ - Can be added later            │   │
│   └─────────────────────────────────┘   │
└─────────────────────────────────────────┘


KEY POINTS:
===========
1. Each bus is a separate "room" (BusRoom object)
2. Users connected to bus are in that room's connections
3. Location updates broadcast only within the room
4. No inter-bus communication
5. Manager is in-memory (fast, no DB queries for messages)
"""


# ============================================================================
# DIAGRAM 2: Message Flow - Location Update
# ============================================================================

"""
┌─────────────────────────────────────────────────────────────────┐
│                    Location Update Flow                          │
└─────────────────────────────────────────────────────────────────┘


TIMELINE:
=========

t=0ms: Driver sends location update
       ┌──────────────────────────┐
       │ {                        │
       │   "type": "LOCATION...", │
       │   "latitude": 28.6139,   │
       │   "longitude": 77.2090   │
       │ }                        │
       └────────────┬─────────────┘
                    │
                    ▼
t=5ms:  Server receives & parses JSON
        ├─ Validates JSON format
        ├─ Extracts latitude, longitude, speed
        └─ Checks timestamp
                    │
                    ▼
t=10ms: Authentication check
        ├─ Is user authenticated? ✓
        ├─ Is user in bus 1? ✓
        └─ Is user allowed to send? ✓ (driver)
                    │
                    ▼
t=15ms: Authorization check (handle_location_update)
        ├─ Is this user the location sender? ✓
        ├─ If no: reject with error
        └─ If yes: proceed
                    │
                    ▼
t=20ms: Store last known location
        ├─ Create LocationData object
        ├─ Save to BusRoom(1).last_known_location
        └─ Now new users see it when connecting
                    │
                    ▼
t=25ms: Broadcast to bus room
        ├─ Get BusRoom(1).connections
        ├─ Create broadcast message
        │  {
        │    "type": "LOCATION_UPDATE",
        │    "bus_id": 1,
        │    "data": { latitude, longitude, ... }
        │  }
        │
        ├─ Send to Student 1
        │    ├─ Serialized: 512 bytes
        │    ├─ Transmitted: ~5ms
        │    ├─ Client receives: 515 bytes total
        │    └─ Time: t=27ms
        │
        ├─ Send to Student 2
        │    ├─ Transmitted: ~5ms
        │    └─ Time: t=29ms
        │
        ├─ Send to Student 3
        │    ├─ Transmitted: ~5ms
        │    └─ Time: t=31ms
        │
        └─ Exclude driver (sender)
                    │
                    ▼
t=35ms: Clients receive location
        ├─ Parse JSON
        ├─ Extract latitude, longitude
        ├─ Update map marker
        └─ Show on screen (rendered in next frame)


MESSAGE SIZE:
=============
Request:  ~200 bytes (location data only)
Response: ~350 bytes (with metadata)
Total bandwidth per location: ~550 bytes × 32 buses × 1 update/sec
                           = ~17.6 KB/sec typical usage


LATENCY BREAKDOWN:
==================
Parsing:       1-2 ms
Auth check:    1-3 ms
DB lookup:     0 ms (in-memory)
Broadcast:     2-5 ms per user (async)
Total:         5-15 ms typical (< 100ms worst case)
"""


# ============================================================================
# DIAGRAM 3: Connection States & Transitions
# ============================================================================

"""
Connection State Machine:
==========================

                    [DISCONNECTED]
                           △
                           │
                           │ (websocket close)
                           │
        (websocket accept)  │
              │             │
              ▼             │
        ┌──────────────────────────┐
        │   AUTHENTICATING         │
        │ (verify JWT token)       │
        └─────────────┬────────────┘
                      │
            (token valid?) ─────No──────► [REJECTED]
                      │
                     Yes
                      │
                      ▼
        ┌──────────────────────────┐
        │   CONNECTING TO ROOM     │
        │ (add to BusRoom)         │
        └─────────────┬────────────┘
                      │
            (success?)─ No ──────► [ERROR]
                      │
                     Yes
                      │
                      ▼
        ┌──────────────────────────┐
        │   SENDING LAST LOCATION  │
        │ (if available)           │
        └─────────────┬────────────┘
                      │
                      ▼
        ┌──────────────────────────┐
        │   NOTIFYING OTHERS       │
        │ (send USER_JOINED)       │
        └─────────────┬────────────┘
                      │
                      ▼
        ┌──────────────────────────┐
        │      ACTIVE              │◄────┐
        │ Can receive/send          │     │ (location updates)
        │ Can receive notifications │─────┘
        └─────────────┬────────────┘
                      │
                      │ (WebSocketDisconnect or timeout)
                      ▼
        ┌──────────────────────────┐
        │   CLEANING UP            │
        │ (remove from room)       │
        │ (notify others)          │
        └─────────────┬────────────┘
                      │
                      ▼
                 [DISCONNECTED]


EVENTS AT EACH STATE:
====================
DISCONNECTED     → User hasn't connected yet
AUTHENTICATING   → Token validation in progress
CONNECTING       → Adding to bus room
SENDING_LOCATION → First location message sent
NOTIFYING        → Broadcast user joined
ACTIVE           → Normal operation ◄─ 99% time spent here
CLEANING_UP      → Removal from room on disconnect
REJECTED         → Bad token or auth failure
ERROR            → Connection failed

TRANSITION RULES:
=================
✓ Only valid transitions shown above
✓ Invalid transitions rejected with error
✓ If any step fails: go to DISCONNECTED
✓ Timeout if stuck for 120+ seconds
✓ Multiple reconnections supported (exponential backoff)
"""


# ============================================================================
# DIAGRAM 4: Bus Room Structure (In-Memory)
# ============================================================================

"""
BusRoom (In-Memory):
===================

BusRoom(bus_id=5):
│
├── bus_id: 5
│
├── connections: Dict[int, UserConnection]
│   ├─ 12 (Student Abdul)
│   │   ├─ websocket: <WebSocket object>
│   │   ├─ user_id: 12
│   │   ├─ user_name: "Abdul Khan"
│   │   ├─ user_role: "student"
│   │   ├─ bus_id: 5
│   │   ├─ connected_at: 2024-01-15 10:15:30
│   │   └─ last_heartbeat: 2024-01-15 10:30:45
│   │
│   ├─ 45 (Driver Raj)
│   │   ├─ websocket: <WebSocket object>
│   │   ├─ user_id: 45
│   │   ├─ user_name: "Raj Kumar"
│   │   ├─ user_role: "driver"
│   │   ├─ bus_id: 5
│   │   ├─ connected_at: 2024-01-15 10:20:00
│   │   └─ last_heartbeat: 2024-01-15 10:30:50
│   │
│   └─ 78 (Student Priya)
│       ├─ websocket: <WebSocket object>
│       ├─ user_id: 78
│       ├─ user_name: "Priya Singh"
│       ├─ user_role: "student"
│       ├─ bus_id: 5
│       ├─ connected_at: 2024-01-15 10:25:15
│       └─ last_heartbeat: 2024-01-15 10:30:48
│
├── location_sender_id: 45 (driver Raj)
│   └─ Only Raj can send location for this bus
│   └─ If Raj disconnects, switches to Abdul or Priya
│
├── last_known_location: LocationData
│   ├─ latitude: 28.6139
│   ├─ longitude: 77.2090
│   ├─ speed: 45.5 km/h
│   ├─ direction: 180.0 degrees
│   ├─ accuracy: 5.0 meters
│   ├─ user_id: 45 (who sent it)
│   ├─ user_name: "Raj Kumar"
│   ├─ user_role: "driver"
│   └─ timestamp: 2024-01-15 10:30:50
│
├── created_at: 2024-01-15 10:15:30
└── get_active_users() → [
    {
        "user_id": 12,
        "user_name": "Abdul Khan",
        "user_role": "student",
        "connected_at": "2024-01-15T10:15:30",
        "is_location_sender": false
    },
    {
        "user_id": 45,
        "user_name": "Raj Kumar",
        "user_role": "driver",
        "connected_at": "2024-01-15T10:20:00",
        "is_location_sender": true  ◄─ Only one sender
    },
    {
        "user_id": 78,
        "user_name": "Priya Singh",
        "user_role": "student",
        "connected_at": "2024-01-15T10:25:15",
        "is_location_sender": false
    }
]


MEMORY USAGE:
=============
Per BusRoom:           ~5 KB (shared)
Per UserConnection:    ~2-3 KB
Per LocationData:      ~500 B
Per 32 buses × 10 users: ~1-2 MB
Per 32 buses × 100 users: ~6-8 MB

CLEANUP:
========
✓ Dead connections removed automatically
✓ Empty rooms deleted when last user leaves
✓ Memory reclaimed immediately (Python GC)
✓ No memory leaks (connections properly cleaned)
"""


# ============================================================================
# DIAGRAM 5: Multi-Bus Broadcasting (No Inter-Bus Leakage)
# ============================================================================

"""
Broadcasting Isolation:
=======================

              Bus 1 Room           Bus 2 Room           Bus 3 Room
         ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
         │                 │  │                 │  │                 │
   User1 │  Student (📱)   │  │  Student (🚗)   │  │  Driver (🚌)    │
         │  User2          │  │  User5          │  │  User8          │
         │  Student (🚗)   │  │  Student (📱)   │  │  Student (📍)   │
         │                 │  │  User6          │  │  User9          │
         │                 │  │  Driver (📞)    │  │  Student (📍)   │
         │                 │  │  User7          │  │  User10         │
         │                 │  │                 │  │                 │
         └────────┬────────┘  └────────┬────────┘  └────────┬────────┘
                  │                    │                    │
                  │ (Broadcast)        │ (Broadcast)        │ (Broadcast)
                  │ ONLY within        │ ONLY within        │ ONLY within
                  │ Bus 1 room         │ Bus 2 room         │ Bus 3 room
                  │                    │                    │
                  ├────────┬───────────┼────┬───────────────┼────┬─────
                  │        │           │    │               │    │
            User1 ↓   User2 ↓      User5 ↓   User6 ↓       User8 ↓   User9 ↓
            📱    📱        🚗       🚗      📱   📱       🚌    📍    📍
            
User1 location: VISIBLE to User2 only (Bus 1)
            ❌ NOT visible to User5, User6, User8, User9, User10
            
User7 location: VISIBLE to User5, User6 only (Bus 2)
            ❌ NOT visible to User1, User2, User8, User9, User10


CODE IMPLEMENTATION:
====================
# When User1 sends location in Bus 1:
room = manager.buses[1]  # Get Bus 1 room
room.broadcast_to_room(message)  # Only broadcasts to connections in Bus 1

# This is isolated from:
manager.buses[2].broadcast_to_room(message)  # Bus 2 - separate room
manager.buses[3].broadcast_to_room(message)  # Bus 3 - separate room


KEY GUARANTEE:
==============
✓ NO location data leaks across buses
✓ Each bus is completely isolated
✓ No way to send to multiple buses at once
✓ Wrong bus_id? Message goes nowhere
✓ Maximum 32 buses × N students = N locations total
"""


# ============================================================================
# DIAGRAM 6: Scaling Architecture (Optional Redis)
# ============================================================================

"""
SINGLE SERVER (Development/Small Scale):
==========================================

        Driver 1     Student 1    Student 2
           │             │            │
           └─────────┬────┴────┬──────┘
                     │         │
                     ▼         ▼
        ┌────────────────────────────┐
        │   SINGLE FASTAPI SERVER    │
        │   + WebSocketManager       │
        │   - All connections        │
        │   - All rooms in memory    │
        │   - Single process         │
        └────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────────┐
        │   DATABASE (Optional)      │
        │   Location history         │
        └────────────────────────────┘

Capacity: ~500-1000 concurrent users
Latency:  ~50-100ms (local memory)


MULTI-SERVER WITH REDIS (Enterprise Scale):
==============================================

    ┌─────────────────────┬──────────────────┬──────────────────┐
    │                     │                  │                  │
  Driver 1            Driver 2            Driver 3          Driver N
    │                     │                  │                  │
    └──┬──────────────────┴──────────────────┴──────────────────┘
       │
       │ Requests distributed by Load Balancer (Round-robin)
       │
    ┌──┴──────────────────┬────────────┬──────────────────┐
    │                     │            │                  │
    ▼                     ▼            ▼                  ▼
┌────────────────┐  ┌─────────────┐  ┌────────────────┐ ┌────────────┐
│ FASTAPI #1     │  │ FASTAPI #2  │  │ FASTAPI #3     │ │ FASTAPI N  │
│ Worker 1 (8000)│  │ Worker 2    │  │ Worker 3       │ │ Worker N   │
├────────────────┤  ├─────────────┤  ├────────────────┤ ├────────────┤
│ Manager (Bus 1)│  │ Manager     │  │ Manager        │ │ Manager    │
│ Users: 1,2,3   │  │ (Bus 2)     │  │ (Bus 3)        │ │ (Other)    │
│ Local memory   │  │ Users: 4,5  │  │ Users: 6,7,8   │ │ Users...   │
│               │  │ Local memory│  │                │  │            │
└─────┬──────────┘  └──────┬─────┘  └────────┬───────┘  └────────┬───┘
      │                    │                 │                   │
      └────────────────────┼─────────────────┼───────────────────┘
                           │                 │
                           ▼                 ▼
                     ┌─────────────────────┐
                     │    REDIS PUB/SUB    │
                     ├─────────────────────┤
                     │ Channels:           │
                     │ - bus:1 (location)  │
                     │ - bus:2 (location)  │
                     │ - bus:3 (location)  │
                     │ - ...               │
                     └─────────────────────┘

Flow:
1. Driver sends location to Server #1 (Bus 1)
2. Server #1 broadcasts to local users (Bus 1)
3. Server #1 publishes to Redis channel "bus:1"
4. All servers listen to "bus:1" channel
5. Server #2, #3, etc. receive if they have Bus 1 users
6. BUT: Each user only connects to one server

Result:
- No duplicate messages
- Real-time sync across servers
- Scales to 1000+ concurrent users
- Can add/remove servers dynamically


IMPORTANT: Because each user connects to ONLY ONE server,
Redis is only needed for analytics/logging, not for message delivery.
Current single-server implementation is sufficient for most use cases!
"""


# ============================================================================
# DIAGRAM 7: Authentication & JWT Flow
# ============================================================================

"""
User Login & WebSocket Connection:
===================================

STEP 1: LOGIN (REST API)
┌──────────────┐
│  Client      │
│  /login      │
└──────┬───────┘
       │ POST /api/login
       │ {"username": "raj", "password": "..."}
       │
       ▼
┌─────────────────────────────────────┐
│  FastAPI Authentication Endpoint    │
│  - Hash password check              │
│  - Create JWT token                 │
│  - Token expires in 24 hours        │
└──────┬────────────────────────────────┘
       │
       │ Response: 200 OK
       │ {"access_token": "eyJhbGc...", "token_type": "bearer"}
       │
       ▼
┌──────────────┐
│  Client      │
│  Saves token │
│  in memory   │
└──────────────┘


STEP 2: WEBSOCKET CONNECTION
┌──────────────────────────────────┐
│  Client                          │
│  WS /ws/location/5?token=JWT ... │
└──────┬───────────────────────────┘
       │ WebSocket upgrade request
       │ Query param: token=eyJhbGc...
       │
       ▼
┌─────────────────────────────────────┐
│  FastAPI WebSocket Endpoint        │
│  - Extract token from query param  │
│  - Call get_current_user(token)   │
│  ├─ Decode JWT                     │
│  ├─ Verify signature               │
│  ├─ Check expiration               │
│  └─ Load user from database        │
│  - If successful: accept WS        │
│  - If failed: close with 401       │
└──────┬───────────────────────────────┘
       │
       ├─ Token valid? ───No──► WebSocket close (401)
       │
       Yes
       │
       ▼
┌──────────────────────────────────┐
│  WebSocket connection accepted   │
│  - User authenticated            │
│  - Added to bus room             │
│  - Can receive/send locations    │
└──────────────────────────────────┘


JWT TOKEN STRUCTURE:
====================
Header:  {
    "alg": "HS256",
    "typ": "JWT"
}

Payload: {
    "sub": "12",           # user_id
    "role": "driver",      # user role
    "iat": 1705330245,     # issued at
    "exp": 1705416645      # expires in 24h
}

Signature: HMACSHA256(base64(header) + "." + base64(payload), SECRET_KEY)

Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdW..." 


SECURITY FEATURES:
==================
✓ Token signature verification prevents tampering
✓ Expiration prevents replay attacks
✓ User_id tied to token
✓ Role stored in token for authorization
✓ Can't send location if not driver/authenticated
✓ HTTPS/WSS only in production
"""


# ============================================================================
# DIAGRAM 8: Flow of Last Location
# ============================================================================

"""
Scenario: Student joins bus but hasn't seen location yet

TIMELINE:
=========

t=0:  Driver connected (location not sent yet)
      Bus 1 room: [Driver]
      last_known_location: None

t=5:  Driver sends location
      Bus 1 broadcasts to all (no one else connected)
      last_known_location: {lat: 28.6139, lon: 77.2090, ...}

t=10: Student connects to same bus
      │
      └─ Server receives connection request
         └─ Validates token ✓
         └─ Adds student to Bus 1 room
         │
         └─ Checks if last_known_location exists
            │
            └─ YES! Send immediately:
               {
                   "type": "LAST_KNOWN_LOCATION",
                   "bus_id": 1,
                   "data": {
                       "latitude": 28.6139,
                       "longitude": 77.2090,
                       "speed": 45.5,
                       ...
                   }
               }

t=12: Student receives last location
      └─ Sees bus on map at previous location
      └─ Knows bus is running (not frozen)

t=15: Student sends heartbeat (PING)
t=20: Student sends another heartbeat
t=25: Driver sends new location
      │
      └─ Bus 1 broadcasts to [Driver, Student]
      └─ Student receives NEW location
      └─ Updates map marker


BENEFITS:
=========
✓ New users see bus immediately (even if no update yet)
✓ Removes "waiting for location" blank period
✓ Improves user experience
✓ Shows that tracking is active
✓ Works even if driver hasn't sent location in minutes


SCENARIOS:
===========
1. No location sent yet   → Send None (user waits)
2. Location sent          → Send it (user sees position)
3. Old location (30+ min) → Send it (better than nothing)
4. Bus offline            → Send it (shows last known)

Memory: ~500 bytes per bus for 32 buses = 16 KB total
"""

print("\n".join([
    "",
    "╔═════════════════════════════════════════════════════════════╗",
    "║  WEBSOCKET ARCHITECTURE - ALL DIAGRAMS ABOVE               ║",
    "║                                                             ║",
    "║  1. System Architecture          - Overall structure       ║",
    "║  2. Message Flow                 - Latency breakdown       ║",
    "║  3. Connection States            - State machine           ║",
    "║  4. Bus Room Structure           - In-memory data          ║",
    "║  5. Broadcasting Isolation       - No inter-bus leakage    ║",
    "║  6. Scaling with Redis           - Enterprise scale        ║",
    "║  7. Authentication Flow          - JWT validation          ║",
    "║  8. Last Location Logic          - New user experience     ║",
    "║                                                             ║",
    "║  For detailed implementation: See code files              ║",
    "║  - websocket_manager_v2.py                                ║",
    "║  - websocket_routes.py                                    ║",
    "║                                                             ║",
    "╚═════════════════════════════════════════════════════════════╝",
    ""
]))