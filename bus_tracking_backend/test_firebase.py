import os, sys, logging
logging.basicConfig(level=logging.INFO)

from pathlib import Path
env_path = Path(__file__).parent / ".env"
if env_path.exists():
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, val = line.split("=", 1)
                os.environ[key.strip()] = val.strip()

import firebase_admin
from firebase_admin import firestore, messaging
from bus_tracking_backend.utils.firebase_helper import get_firebase_credential

print("Testing Firebase Credential Loader...")
cred = get_firebase_credential()
if cred:
    print("SUCCESS: Credential object created.")
    try:
        app = firebase_admin.get_app()
        print("Reusing existing Firebase app.")
    except ValueError:
        app = firebase_admin.initialize_app(cred)
        print("Firebase app initialized successfully.")

    print("Project ID:", app.project_id)

    # Test FCM Messaging
    try:
        topic_msg = messaging.Message(
            notification=messaging.Notification(
                title="Backend Test",
                body="FCM Services initialized and active!"
            ),
            topic="test_all"
        )
        msg_id = messaging.send(topic_msg)
        print("FCM Messaging STATUS: ACTIVE! Message ID:", msg_id)
    except Exception as exc:
        print("FCM Messaging ERROR:", exc)

    # Test Firestore Client
    try:
        db = firestore.client()
        print("Firestore Client STATUS: CONNECTED!")
    except Exception as exc:
        print("Firestore Client ERROR:", exc)
else:
    print("FAILED: No valid Firebase credentials found.")

sys.stdout.flush()