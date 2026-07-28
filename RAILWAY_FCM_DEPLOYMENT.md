# Railway FCM Deployment Guide

## Server Key vs Service Account

Google Console may warn about a missing **Server Key**. This project uses the **HTTP v1 API via `firebase-admin` SDK**, which authenticates using the **service account JSON** — NOT the server key. The server key is only needed for the legacy HTTP API. You do **not** need a server key.

The `firebase-admin` SDK automatically obtains OAuth 2.0 tokens from the service account JSON and calls the FCM HTTP v1 API. This is the modern, secure approach.

## Deploy Firebase Credentials on Railway

Since `firebase-key.json` is in `.gitignore`, provide credentials via a base64 environment variable.

### Step 1: Base64-encode your key

```bash
# Linux/macOS:
base64 -w 0 bus_tracking_backend/firebase-key.json

# Windows PowerShell:
[Convert]::ToBase64String([IO.File]::ReadAllBytes("bus_tracking_backend/firebase-key.json"))
```

### Step 2: Add to Railway

1. Go to [Railway Dashboard](https://railway.app) → your project → **Settings** → **Variables**
2. Add variable: `FIREBASE_CREDENTIALS_BASE64` (type: Secret) with the base64 string

### Step 3: Deploy

```bash
git add .
git commit -m "FCM integration with bustracker-afb3c"
git push railway main
```

### Step 4: Verify

Check Railway logs for: `Firebase Admin SDK initialized successfully for FCM.`

Test:
```bash
curl -X POST https://your-app.up.railway.app/api/send-notification \
  -H "Content-Type: application/json" \
  -d '{"token":"YOUR_TOKEN","title":"Test","body":"Hello!"}'
```

## All Notification Features Working

All existing features use the same `firebase-admin` SDK (HTTP v1 API):

- **Announcements** → `firebase_service.save_announcement()`
- **Documents** → `firebase_service.save_document()`
- **Pinned Bus Tracking** → `notification_service.notify_pinned_bus_tracking_started()`
- **Pinned Bus Location Updates** → `notification_service.notify_pinned_bus_location_updated()`
- **Pinned Bus Approaching** → `notification_service.notify_pinned_bus_approaching_stop()`
- **Pinned Bus Reached Stop** → `notification_service.notify_pinned_bus_reached_stop()`
- **Pinned Bus Trip Completed** → `notification_service.notify_pinned_bus_trip_completed()`
- **Student Shared Location** → `notification_service.notify_student_shared_location()`
- **Admin Announcements** → `notification_service.notify_admin_announcement()`
- **Feedback Requests** → `notification_service.notify_admin_announcement()`
- **Device Token Registration** → `POST /api/notifications/device-token`

## Firebase Console Setup

1. Go to [Firebase Console](https://console.firebase.google.com/) → project **bustracker-afb3c**
2. **Project Settings** → **Service Accounts** → verify `firebase-adminsdk-fbsvc@bustracker-afb3c.iam.gserviceaccount.com` has admin role
3. **Cloud Messaging** tab → verify Sender ID `851331446616` is listed
4. Android app (`google-services.json`) is already configured — no changes needed

## Troubleshooting

| Issue | Solution |
|---|---|
| "Firebase credentials not found" | Set `FIREBASE_CREDENTIALS_BASE64` as Secret on Railway |
| "Firebase initialization failed" | Re-download key from Firebase Console, re-encode as base64 |
| Notifications not received | Check device registered token via `POST /api/notifications/device-token` |
| Firestore not working | `firebase_service.py` now reuses initialized app — check Firestore is enabled in Firebase Console |
</arg_value>
<task_progress>
- [x] Analyze project structure and existing code
- [x] Update backend serviceAccountKey.json with bustracker-afb3c credentials
- [x] Update backend config.py with correct FCM project ID and sender ID
- [x] Create FastAPI /send-notification endpoint using firebase-admin SDK (HTTP v1)
- [x] Create Android Kotlin MyFirebaseMessagingService class
- [x] Update AndroidManifest.xml with notification service registration
- [x] Verify google-services.json and gradle dependencies
- [x] Update .env.example and .env.railway with correct project IDs
- [x] Create comprehensive FCM integration guide
- [x] Final verification: config.py default path, requirements.txt, .gitignore
- [x] Fix firebase_service.py double-initialization bug
- [x] Create Railway deployment guide for Firebase credentials</task_progress></tool_call>