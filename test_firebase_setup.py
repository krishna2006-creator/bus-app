#!/usr/bin/env python
"""
Firebase Integration Test Script
Tests FCM notifications and Firestore connectivity
Run this to verify Firebase setup is correct
"""

import os
import sys
import json
import requests
from datetime import datetime

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from bus_tracking_backend.config import settings
from bus_tracking_backend.services.firebase_service import firebase_service
from bus_tracking_backend.database.database import SessionLocal
from bus_tracking_backend.database import models

def test_firebase_config():
    """Test if Firebase configuration is properly set"""
    print("\n" + "="*60)
    print("Testing Firebase Configuration")
    print("="*60)
    
    print(f"✓ FCM_SERVER_KEY set: {'Yes' if settings.FCM_SERVER_KEY else 'No'}")
    print(f"✓ FCM_PROJECT_ID: {settings.FCM_PROJECT_ID or 'Not set'}")
    print(f"✓ FCM_SENDER_ID: {settings.FCM_SENDER_ID or 'Not set'}")
    print(f"✓ FIREBASE_CREDENTIALS_PATH: {settings.FIREBASE_CREDENTIALS_PATH or 'Not set'}")
    
    if settings.FIREBASE_CREDENTIALS_PATH and os.path.exists(settings.FIREBASE_CREDENTIALS_PATH):
        print(f"✓ Service account key file exists: Yes")
        try:
            with open(settings.FIREBASE_CREDENTIALS_PATH) as f:
                creds = json.load(f)
                print(f"  Project ID from file: {creds.get('project_id')}")
                print(f"  Service account email: {creds.get('client_email')}")
        except Exception as e:
            print(f"✗ Error reading service account key: {e}")
    else:
        print(f"✗ Service account key file not found")
    
    return bool(settings.FCM_SERVER_KEY and settings.FCM_PROJECT_ID)

def test_firestore_connection():
    """Test Firestore connectivity"""
    print("\n" + "="*60)
    print("Testing Firestore Connection")
    print("="*60)
    
    db = firebase_service.get_db()
    if not db:
        print("✗ Firestore client not initialized")
        return False
    
    try:
        # Try to read from a test collection
        test_collection = db.collection("_test").document("test")
        test_collection.set({"timestamp": datetime.now(), "test": True})
        print("✓ Firestore write successful")
        
        # Read it back
        doc = test_collection.get()
        if doc.exists:
            print("✓ Firestore read successful")
            test_collection.delete()  # Clean up
            print("✓ Firestore delete successful")
            return True
        else:
            print("✗ Firestore read failed")
            return False
    except Exception as e:
        print(f"✗ Firestore connection error: {e}")
        return False

def test_announcements_firestore():
    """Test saving and retrieving announcements from Firestore"""
    print("\n" + "="*60)
    print("Testing Announcements (Firestore)")
    print("="*60)
    
    db = firebase_service.get_db()
    if not db:
        print("✗ Firestore not initialized")
        return False
    
    try:
        # Save test announcement
        import asyncio
        announcement_id = asyncio.run(firebase_service.save_announcement(
            title="Test Announcement",
            body="This is a test notification",
            target_role="student",
            priority="high"
        ))
        
        if announcement_id:
            print(f"✓ Announcement saved: {announcement_id}")
            
            # Retrieve announcements
            announcements = asyncio.run(firebase_service.get_announcements(target_role="student", limit=10))
            print(f"✓ Retrieved {len(announcements)} announcements")
            return True
        else:
            print("✗ Failed to save announcement")
            return False
    except Exception as e:
        print(f"✗ Announcements test error: {e}")
        return False

def test_device_tokens():
    """Test device token storage and retrieval"""
    print("\n" + "="*60)
    print("Testing Device Tokens (Database)")
    print("="*60)
    
    db = SessionLocal()
    try:
        # Create test user
        test_user = models.User(
            id="test_user_" + str(datetime.now().timestamp()),
            email=f"test_{datetime.now().timestamp()}@test.com",
            full_name="Test User",
            hashed_password="hashed_test_pwd",
            role="student"
        )
        db.add(test_user)
        db.commit()
        print(f"✓ Test user created: {test_user.id}")
        
        # Add device token
        device_token = models.DeviceToken(
            user_id=test_user.id,
            token="test_device_token_12345",
            platform="android"
        )
        db.add(device_token)
        db.commit()
        print(f"✓ Device token saved")
        
        # Retrieve device tokens
        tokens = db.query(models.DeviceToken).filter(
            models.DeviceToken.user_id == test_user.id
        ).all()
        print(f"✓ Retrieved {len(tokens)} device token(s)")
        
        # Clean up
        db.query(models.DeviceToken).filter(models.DeviceToken.user_id == test_user.id).delete()
        db.query(models.User).filter(models.User.id == test_user.id).delete()
        db.commit()
        print("✓ Test data cleaned up")
        
        return True
    except Exception as e:
        db.rollback()
        print(f"✗ Device tokens test error: {e}")
        return False
    finally:
        db.close()

def test_health_endpoint():
    """Test backend health endpoint"""
    print("\n" + "="*60)
    print("Testing Backend Health")
    print("="*60)
    
    try:
        response = requests.get("http://localhost:8000/health", timeout=5)
        if response.status_code == 200:
            print(f"✓ Health endpoint OK: {response.json()}")
            return True
        else:
            print(f"✗ Health endpoint returned {response.status_code}")
            return False
    except Exception as e:
        print(f"✗ Backend not running or unreachable: {e}")
        print("  Start backend with: python -m uvicorn bus_tracking_backend.main:app --host 0.0.0.0 --port 8000")
        return False

def test_fcm_send(device_token=None):
    """Test sending FCM notification"""
    print("\n" + "="*60)
    print("Testing FCM Send")
    print("="*60)
    
    if not device_token:
        print("⚠ No device token provided for FCM test")
        print("  To test FCM: python test_firebase_setup.py --device-token YOUR_DEVICE_TOKEN")
        return None
    
    try:
        firebase_service.send_multicast(
            tokens=[device_token],
            title="Test Notification",
            body="This is a test FCM notification",
            data={"test": "true", "timestamp": str(datetime.now())}
        )
        print("✓ FCM notification sent (check your device)")
        return True
    except Exception as e:
        print(f"✗ FCM send error: {e}")
        return False

def run_all_tests():
    """Run all tests"""
    print("\n" + "█"*60)
    print("Firebase Integration Test Suite")
    print("█"*60)
    print(f"Started at: {datetime.now()}")
    
    results = {
        "Config": test_firebase_config(),
        "Firestore": test_firestore_connection(),
        "Announcements": test_announcements_firestore(),
        "DeviceTokens": test_device_tokens(),
        "Backend Health": test_health_endpoint(),
    }
    
    print("\n" + "="*60)
    print("Test Results Summary")
    print("="*60)
    
    for test_name, result in results.items():
        status = "✓ PASSED" if result else "✗ FAILED"
        print(f"{test_name:.<40} {status}")
    
    passed = sum(1 for r in results.values() if r)
    total = len(results)
    
    print("\n" + "="*60)
    print(f"Overall: {passed}/{total} tests passed")
    print("="*60 + "\n")
    
    return all(results.values())

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Firebase Integration Tests")
    parser.add_argument("--device-token", help="Device token for FCM test")
    args = parser.parse_args()
    
    success = run_all_tests()
    
    if args.device_token:
        test_fcm_send(args.device_token)
    
    sys.exit(0 if success else 1)
