# Firebase Integration Guide

Complete step-by-step guide to set up Firebase Cloud Messaging (FCM) and Firestore for the Bus Tracking App.

## Prerequisites

- Google/Firebase account
- A Flutter app with Firebase configured (or create a new one)
- Backend running (or ready to start)

---

## Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **"Create a project"** → Name: `BusTracking` → Continue
3. Enable Google Analytics (optional) → Create
4. Wait for project creation to complete

---

## Step 2: Get Firebase Credentials

### For FCM (Server Key):

1. In Firebase Console, go to **Project Settings** (⚙️ icon)
2. Click **"Service Accounts"** tab
3. Scroll to **"Firebase Admin SDK"** → Click **"Generate new private key"**
4. Save the JSON file as `serviceAccountKey.json` in the `bus_tracking_backend` folder
5. Extract these from the JSON:
   - `project_id` → `FCM_PROJECT_ID`
   - Use the entire JSON file → `FIREBASE_CREDENTIALS_PATH`

### For Cloud Messaging:

1. Go to **Project Settings** → **Cloud Messaging** tab
2. Copy:
   - **Server API Key** → `FCM_SERVER_KEY`
   - **Sender ID** → `FCM_SENDER_ID`

---

## Step 3: Enable Firestore

1. In Firebase Console, go to **Firestore Database**
2. Click **"Create Database"**
3. Select **Start in Test Mode** (for development)
4. Choose region closest to you
5. Click **Enable**

---

## Step 4: Configure Backend

### Update `.env` file:

```bash
# Copy from Firebase credentials
FCM_SERVER_KEY=YOUR_FCM_SERVER_KEY_HERE
FCM_PROJECT_ID=your-firebase-project-id
FCM_SENDER_ID=your-fcm-sender-id

# Path to the serviceAccountKey.json
FIREBASE_CREDENTIALS_PATH=/app/serviceAccountKey.json

# Or locally:
FIREBASE_CREDENTIALS_PATH=./serviceAccountKey.json

# Storage buckets
MINIO_BUCKET_DOCUMENTS=documents
MINIO_BUCKET_ANNOUNCEMENTS=announcements
```

### Place `serviceAccountKey.json`:

```bash
cp /path/to/serviceAccountKey.json ./bus_tracking_backend/serviceAccountKey.json
```

### Install dependencies:

```bash
pip install -r bus_tracking_backend/requirements.txt
```

---

## Step 5: Setup Flutter App

### Add Firebase to Flutter:

```bash
cd flutter_app_directory

# Install Firebase packages
flutter pub add firebase_core
flutter pub add firebase_messaging
flutter pub add google_maps_flutter

# Run build
flutter pub get
```

### Initialize Firebase in Flutter:

**File: `lib/main.dart`**

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // Auto-generated

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}
```

### Get Device Token and Register with Backend:

**File: `lib/services/notification_service.dart`**

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  late FirebaseMessaging _firebaseMessaging;

  factory NotificationService() => _instance;

  NotificationService._internal();

  Future<void> init() async {
    _firebaseMessaging = FirebaseMessaging.instance;

    // Request permission
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission');

      // Get FCM token
      String? token = await _firebaseMessaging.getToken();
      print('FCM Token: $token');

      // Register token with backend
      if (token != null) {
        await registerDeviceToken(token);
      }

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        registerDeviceToken(newToken);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Got a message whilst in the foreground!');
        print('Message data: ${message.data}');

        if (message.notification != null) {
          print('Message also contained a notification: ${message.notification}');
          // Show local notification or update UI
        }
      });
    }
  }

  Future<void> registerDeviceToken(String token) async {
    try {
      final response = await http.post(
        Uri.parse('http://192.168.29.123:8000/api/notifications/device-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer YOUR_JWT_TOKEN_HERE',
        },
        body: jsonEncode({
          'token': token,
          'platform': 'android', // or 'ios'
        }),
      );

      if (response.statusCode == 200) {
        print('Device token registered successfully');
      } else {
        print('Failed to register device token');
      }
    } catch (e) {
      print('Error registering device token: $e');
    }
  }
}
```

### Initialize in main.dart:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // Initialize notification service
  await NotificationService().init();
  
  runApp(const MyApp());
}
```

---

## Step 6: Test Firebase Notifications

### Test from Backend:

```bash
# Start backend server
python -m uvicorn bus_tracking_backend.main:app --host 0.0.0.0 --port 8000

# Test device token registration
curl -X POST http://localhost:8000/api/notifications/device-token \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{"token":"YOUR_DEVICE_TOKEN_HERE","platform":"android"}'

# Test announcement with notification
curl -X POST http://localhost:8000/api/announcements \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{"title":"Bus Alert","body":"Bus 1 is 1km away","target_role":"student"}'
```

### Test Firestore:

1. Open Firebase Console → Firestore Database
2. Create collection `announcements` with sample document
3. Verify data appears in the console

---

## Step 7: Deployment

### Docker Setup:

Update `docker-compose.yml`:

```yaml
services:
  backend:
    build:
      context: ./bus_tracking_backend
      dockerfile: Dockerfile
    environment:
      FCM_SERVER_KEY: ${FCM_SERVER_KEY}
      FCM_PROJECT_ID: ${FCM_PROJECT_ID}
      FCM_SENDER_ID: ${FCM_SENDER_ID}
      FIREBASE_CREDENTIALS_PATH: /app/serviceAccountKey.json
    volumes:
      - ./bus_tracking_backend/serviceAccountKey.json:/app/serviceAccountKey.json:ro
```

---

## API Endpoints for Notifications

### Register Device Token

```
POST /api/notifications/device-token
Authorization: Bearer {jwt_token}

Body:
{
  "token": "fcm_device_token_here",
  "platform": "android"
}

Response:
{
  "status": "ok",
  "message": "Device token registered"
}
```

### Send Announcement with Notification

```
POST /api/announcements
Authorization: Bearer {jwt_token}

Body:
{
  "title": "Important Update",
  "body": "Your bus is on the way",
  "target_role": "student",
  "priority": "high"
}

Response:
{
  "id": "announcement_id",
  "message": "Announcement created and notification sent"
}
```

### Get Active Announcements

```
GET /api/announcements
Authorization: Bearer {jwt_token}

Response:
[
  {
    "id": "ann_123",
    "title": "Bus Alert",
    "body": "Bus 1 approaching",
    "created_at": "2026-07-22T10:30:00",
    "read_by": ["user1", "user2"]
  }
]
```

---

## Firestore Collections Structure

### `announcements` collection:

```json
{
  "title": "Bus Update",
  "body": "Bus 1 is running 5 minutes late",
  "target_role": "student",
  "priority": "normal",
  "created_at": "2026-07-22T10:30:00",
  "read_by": ["user1", "user2"],
  "attachments": []
}
```

### `documents` collection:

```json
{
  "file_name": "bus_schedule.pdf",
  "file_path": "s3://documents/bus_schedule.pdf",
  "uploaded_by": "admin001",
  "size": 245000,
  "mime_type": "application/pdf",
  "category": "schedules",
  "created_at": "2026-07-22T10:30:00",
  "downloads": 12,
  "access_count": 45
}
```

---

## Troubleshooting

### FCM Notifications Not Arriving

1. Check `FCM_SERVER_KEY` is correct
2. Verify device token is registered: `GET /api/notifications/device-tokens`
3. Check Firebase Console → Cloud Messaging → Send test message
4. Ensure app has notification permissions

### Firestore Not Saving Data

1. Verify `FIREBASE_CREDENTIALS_PATH` points to valid `serviceAccountKey.json`
2. Check Firestore is enabled in Firebase Console
3. Review backend logs for errors: `docker logs container_id`
4. Ensure Firestore rules allow writes (Test Mode or custom rules)

### Device Token Registration Fails

1. Verify JWT token is valid and user is authenticated
2. Check endpoint: `curl http://localhost:8000/api/notifications/device-token`
3. Ensure POST body contains `token` and `platform` fields

---

## Next Steps

1. ✅ Create Firebase project
2. ✅ Get credentials and set in `.env`
3. ✅ Configure Flutter app
4. ✅ Register device tokens from mobile
5. ✅ Test announcements with FCM
6. ✅ Deploy to production with Docker
7. ✅ Monitor in Firebase Console

---

## Support

For issues, check:
- Backend logs: `docker logs bus_tracking_backend`
- Firebase Console Cloud Messaging tab
- Flutter debug console for FCM token registration
- Firestore Database Rules (ensure test mode or custom rules allow reads/writes)
