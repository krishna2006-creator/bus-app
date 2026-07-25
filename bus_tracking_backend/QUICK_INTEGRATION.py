"""
QUICK INTEGRATION GUIDE
Real-Time Bus Tracking WebSocket System

This is a step-by-step guide to integrate the new WebSocket manager
into your existing FastAPI backend.
"""

# ============================================================================
# STEP 1: BACKUP YOUR CURRENT SYSTEM
# ============================================================================

"""
1. Create a backup of your current backend:
   
   git commit -m "Backup before WebSocket migration"
   git branch backup-websocket-v1
"""

# ============================================================================
# STEP 2: ADD NEW FILES
# ============================================================================

"""
FILES CREATED:
1. services/websocket_manager_v2.py  - New enhanced WebSocket manager
2. routers/websocket_routes.py        - New WebSocket endpoints
3. WEBSOCKET_GUIDE.py                 - Complete reference guide
4. PRODUCTION_DEPLOYMENT.py           - Deployment & security config
5. QUICK_INTEGRATION.py               - This file

NO FILES REMOVED - backwards compatible!
"""

# ============================================================================
# STEP 3: UPDATE main.py
# ============================================================================

"""
Add these imports to main.py (after existing imports):
"""

# At the top with other imports:
from routers.websocket_routes import router as websocket_router

# After creating api_router:
api_router.include_router(websocket_router)

# Then mount api_router (existing code stays same):
app.include_router(api_router)


# ============================================================================
# STEP 4: VERIFY REQUIREMENTS
# ============================================================================

"""
Check requirements.txt contains:
- fastapi
- websockets  (should already be installed)
- uvicorn
- sqlalchemy
- pydantic
- python-jose      (for JWT)
- passlib          (for password hashing)

No NEW packages needed! Everything uses existing dependencies.
"""

# ============================================================================
# STEP 5: TEST LOCALLY
# ============================================================================

"""
Test your setup:

1. Start your backend:
   python -m uvicorn main:app --reload

2. Check endpoints:
   - Open http://localhost:8000/docs
   - Look for "/api/ws/..." endpoints
   - Should see multiple new WebSocket endpoints

3. Test REST endpoint:
   GET http://192.168.29.123:8000/api/ws/stats
   
   Should return something like:
   {
       "total_buses": 0,
       "total_users": 0,
       "total_connections": 0,
       "buses": {}
   }
"""

# ============================================================================
# STEP 6: CLIENT INTEGRATION (FLUTTER/DART)
# ============================================================================

"""
For your Flutter app, use this in your Dart code:

PUBSPEC.YAML:
dependencies:
  web_socket_channel: ^2.4.0
  geolocator: ^9.0.0  # For location

DART CODE EXAMPLE:
"""

// dart/lib/services/bus_tracking_service.dart

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';

class BusTrackingService {
  late WebSocketChannel _channel;
  final int busId;
  final String token;
  final String serverUrl;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  BusTrackingService({
    required this.busId,
    required this.token,
    this.serverUrl = "ws://192.168.29.123:8000",
  });

  Future<void> connect() async {
    try {
      final url = "$serverUrl/api/ws/location/$busId?token=$token";
      _channel = WebSocketChannel.connect(Uri.parse(url));

      // Listen for messages
      _channel.stream.listen(
        (message) {
          final data = jsonDecode(message);
          _messageController.add(data);
          _handleMessage(data);
        },
        onError: (error) {
          print("WebSocket error: $error");
          _messageController.addError(error);
        },
        onDone: () {
          print("WebSocket disconnected");
          reconnect();
        },
      );

      print("Connected to bus $busId");
    } catch (e) {
      print("Connection failed: $e");
      rethrow;
    }
  }

  Future<void> sendLocation(double latitude, double longitude,
      {double speed = 0.0}) async {
    try {
      final message = {
        "type": "LOCATION_UPDATE",
        "latitude": latitude,
        "longitude": longitude,
        "speed": speed,
        "direction": 0.0,
        "accuracy": 5.0,
        "timestamp": DateTime.now().millisecondsSinceEpoch / 1000,
      };
      _channel.sink.add(jsonEncode(message));
    } catch (e) {
      print("Failed to send location: $e");
    }
  }

  Future<void> sendHeartbeat() async {
    try {
      _channel.sink.add(jsonEncode({"type": "PING"}));
    } catch (e) {
      print("Failed to send heartbeat: $e");
    }
  }

  void requestBusInfo() {
    _channel.sink.add(jsonEncode({"type": "GET_BUS_INFO"}));
  }

  void _handleMessage(Map<String, dynamic> data) {
    final type = data['type'];

    switch (type) {
      case 'LOCATION_UPDATE':
        final locationData = data['payload']; // Corrected from 'data' to 'payload'
        print(
            "Bus location: ${locationData['latitude']}, ${locationData['longitude']}");
        // Update UI with location
        break;
      case 'LOCATION_CLEARED':
        print("Bus ${data['bus_id']} stopped sharing.");
        // TODO: Set busLocation to null in your UI to remove the marker
        break;
      case 'BUS_INFO':
        final users = data['active_users'];
        print("Active users: ${data['user_count']}");
        for (var user in users) {
          print("  - ${user['user_name']} (${user['user_role']})");
        }
        break;
      case 'USER_JOINED':
        print("${data['user_name']} joined the bus");
        break;
      case 'USER_LEFT':
        print("${data['user_name']} left the bus");
        break;
      case 'ERROR':
        print("Error: ${data['error']}");
        break;
    }
  }

  Future<void> reconnect() async {
    await Future.delayed(Duration(seconds: 3));
    try {
      await connect();
    } catch (e) {
      print("Reconnection failed: $e");
      await reconnect();
    }
  }

  void disconnect() {
    _channel.sink.close();
    _messageController.close();
    print("Disconnected from bus $busId");
  }
}


// USAGE IN YOUR APP:
class BusMapScreen extends StatefulWidget {
  final int busId;
  final String jwtToken;

  const BusMapScreen({
    required this.busId,
    required this.jwtToken,
  });

  @override
  State<BusMapScreen> createState() => _BusMapScreenState();
}

class _BusMapScreenState extends State<BusMapScreen> {
  late BusTrackingService _service;
  LatLng? _busLocation;
  int _activeUsers = 0;

  @override
  void initState() {
    super.initState();
    _initializeTracking();
  }

  Future<void> _initializeTracking() async {
    _service = BusTrackingService(
      busId: widget.busId,
      token: widget.jwtToken,
    );

    await _service.connect();

    // Subscribe to messages
    _service.messages.listen((message) {
      if (message['type'] == 'LOCATION_UPDATE') {
        final data = message['payload']; // Sync with backend key name
        setState(() {
          if (data['latitude'] == 0) {
            _busLocation = null; // Handle stop sharing signal
            return;
          }
          _busLocation = LatLng(data['latitude'], data['longitude']);
        });
      } else if (message['type'] == 'BUS_INFO') {
        setState(() {
          _activeUsers = message['user_count'];
        });
      }
    });

    // Send heartbeat every 30 seconds
    Timer.periodic(Duration(seconds: 30), (_) {
      _service.sendHeartbeat();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Bus ${widget.busId} Tracking"),
        subtitle: Text("Active users: $_activeUsers"),
      ),
      body: _busLocation != null
          ? GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _busLocation!,
                zoom: 15,
              ),
              markers: {
                Marker(
                  markerId: MarkerId("bus"),
                  position: _busLocation!,
                  infoWindow: InfoWindow(
                    title: "Bus #${widget.busId}",
                  ),
                ),
              },
            )
          : Center(child: CircularProgressIndicator()),
    );
  }

  @override
  void dispose() {
    _service.disconnect();
    super.dispose();
  }
}


# ============================================================================
# STEP 7: DATABASE PERSISTENCE (Optional)
# ============================================================================

"""
To persist location history to database:

1. Create a model for location history
2. In websocket_manager_v2.py, add to handle_location_update():

    # Persist to database
    location_record = models.LocationHistory(
        bus_id=bus_id,
        user_id=user_id,
        latitude=location_data.latitude,
        longitude=location_data.longitude,
        speed=location_data.speed,
        timestamp=datetime.fromtimestamp(location_data.timestamp),
    )
    db.add(location_record)
    db.commit()
"""

# ============================================================================
# STEP 8: SCALING FOR PRODUCTION (Optional)
# ============================================================================

"""
FOR SINGLE SERVER (up to 100 concurrent users):
- Use config from PRODUCTION_DEPLOYMENT.py
- Set WORKERS=4 in .env
- Use Nginx reverse proxy
- No changes to code needed

FOR MULTIPLE SERVERS (100+ users):
- Add Redis pub/sub for cross-server broadcast
- Modify broadcast_to_bus() to also publish to Redis
- All servers subscribe to Redis channels
- Connection state stays local, messages go through Redis

CODE CHANGES FOR REDIS (optional):
"""

# In websocket_manager_v2.py, add at top:
import aioredis

class WebSocketManager:
    def __init__(self, redis_url=None):
        # ... existing code ...
        self.redis = None
        if redis_url:
            self.redis = aioredis.from_url(redis_url)

    async def broadcast_to_bus(self, bus_id, message, exclude_user_id=None):
        # Local broadcast
        sent = await self.buses[bus_id].broadcast_to_room(message, exclude_user_id)
        
        # Publish to Redis for other servers
        if self.redis:
            channel = f"bus:{bus_id}"
            await self.redis.publish(channel, json.dumps(message))
        
        return sent

# ============================================================================
# COMMON ISSUES & FIXES
# ============================================================================

"""
Issue: "ModuleNotFoundError: No module named 'websocket_manager_v2'"
Fix: Check that services/websocket_manager_v2.py exists and __init__.py exists in services/

Issue: WebSocket endpoint shows 404
Fix: Check that websocket_router is imported and included in main.py:
    from routers.websocket_routes import router as websocket_router
    api_router.include_router(websocket_router)

Issue: "Token validation failed"
Fix: Ensure get_current_user in utils/auth_utils.py is working:
    - Test with: POST /api/login
    - Get token
    - Use token in WebSocket query string

Issue: Users from different buses receiving messages
Fix: Verify bus_id parameter is passed correctly:
    - URL: /ws/location/5 (bus_id=5, not user_id)
    - Check WebSocket connection parameters

Issue: High memory usage
Fix: Check /api/ws/stats endpoint
     Look for dead connections not being cleaned up
     Use limiter to prevent connection spam

Issue: WebSocket connections drop after minutes
Fix: Add heartbeat every 30 seconds from client
    Client code: _service.sendHeartbeat()
    
    Or increase nginx timeout:
    proxy_read_timeout 3600s;
"""

# ============================================================================
# VERIFICATION CHECKLIST
# ============================================================================

"""
After integration, verify:

✅ Backend starts without errors
✅ /docs page shows new WebSocket endpoints
✅ GET /api/ws/stats returns valid JSON
✅ Can connect to /api/ws/ws/location/{bus_id} with valid token
✅ Location updates broadcast to all users in same bus
✅ Users from different bus don't get messages from other bus
✅ Disconnected users are removed from manager
✅ Last known location sent to new users
✅ Heartbeat keep-alive works
✅ Error handling doesn't crash server
"""

# ============================================================================
# NEXT STEPS
# ============================================================================

"""
1. ✅ Integrate files and update main.py (Done)
2. ✅ Test locally with client code above
3. ✅ Deploy to production (see PRODUCTION_DEPLOYMENT.py)
4. ✅ Monitor with /api/ws/stats
5. ✅ Set up logging and alerts
6. ✅ Load test with multiple users
7. ✅ Implement database persistence (optional)
8. ✅ Scale with Redis if needed (optional)

Questions? Check WEBSOCKET_GUIDE.py for detailed documentation.
"""
