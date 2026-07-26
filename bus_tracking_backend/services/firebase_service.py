"""
Firebase Integration Service
Handles Firestore documents, announcements, and FCM push notifications
"""
import firebase_admin
from firebase_admin import credentials, firestore, messaging
from ..config import settings
import logging
from datetime import datetime
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)

class FirebaseService:
    _instance = None
    _db = None
    _app = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self._initialized = True
        self._init_firebase()

    def _init_firebase(self):
        """Initialize Firebase Admin SDK"""
        try:
            creds_path = settings.FIREBASE_CREDENTIALS_PATH
            if not creds_path:
                logger.warning("FIREBASE_CREDENTIALS_PATH not set. Firebase disabled.")
                return

            from pathlib import Path
            if not Path(creds_path).exists():
                logger.warning("Firebase credentials not found at %s. Firebase disabled.", creds_path)
                return

            cred = credentials.Certificate(creds_path)
            self._app = firebase_admin.initialize_app(cred)
            self._db = firestore.client()
            logger.info("Firebase initialized successfully")
        except Exception as e:
            logger.error("Firebase initialization failed: %s", e)
            self._db = None

    @staticmethod
    def get_db():
        """Get Firestore client"""
        service = FirebaseService()
        return service._db

    async def save_announcement(self, title: str, body: str, target_role: str, attachments: List[str] = None, priority: str = "normal"):
        """Save announcement to Firestore"""
        if not self._db:
            logger.warning("Firebase not initialized. Announcement not saved.")
            return None

        try:
            announcement = {
                "title": title,
                "body": body,
                "target_role": target_role,
                "attachments": attachments or [],
                "priority": priority,
                "created_at": datetime.now(),
                "read_by": [],
            }
            doc_ref = self._db.collection("announcements").document()
            doc_ref.set(announcement)
            logger.info(f"Announcement saved: {doc_ref.id}")
            return doc_ref.id
        except Exception as e:
            logger.error(f"Failed to save announcement: {e}")
            return None

    async def get_announcements(self, target_role: str = None, limit: int = 50):
        """Fetch announcements from Firestore"""
        if not self._db:
            return []

        try:
            query = self._db.collection("announcements").order_by("created_at", direction=firestore.Query.DESCENDING)
            
            if target_role and target_role.lower() != "all":
                query = query.where("target_role", "==", target_role)
            
            docs = query.limit(limit).stream()
            announcements = []
            for doc in docs:
                data = doc.to_dict()
                data["id"] = doc.id
                announcements.append(data)
            return announcements
        except Exception as e:
            logger.error(f"Failed to fetch announcements: {e}")
            return []

    async def mark_announcement_read(self, announcement_id: str, user_id: str):
        """Mark announcement as read by user"""
        if not self._db:
            return False

        try:
            doc_ref = self._db.collection("announcements").document(announcement_id)
            doc_ref.update({"read_by": firestore.ArrayUnion([user_id])})
            return True
        except Exception as e:
            logger.error(f"Failed to mark announcement as read: {e}")
            return False

    async def save_document(self, file_name: str, file_path: str, uploaded_by: str, size: int, mime_type: str, category: str = "general"):
        """Save document metadata to Firestore"""
        if not self._db:
            return None

        try:
            document = {
                "file_name": file_name,
                "file_path": file_path,
                "uploaded_by": uploaded_by,
                "size": size,
                "mime_type": mime_type,
                "category": category,
                "created_at": datetime.now(),
                "downloads": 0,
                "access_count": 0,
            }
            doc_ref = self._db.collection("documents").document()
            doc_ref.set(document)
            logger.info(f"Document metadata saved: {doc_ref.id}")
            return doc_ref.id
        except Exception as e:
            logger.error(f"Failed to save document metadata: {e}")
            return None

    async def get_documents(self, category: str = None, limit: int = 100):
        """Fetch documents from Firestore"""
        if not self._db:
            return []

        try:
            query = self._db.collection("documents").order_by("created_at", direction=firestore.Query.DESCENDING)
            
            if category and category.lower() != "all":
                query = query.where("category", "==", category)
            
            docs = query.limit(limit).stream()
            documents = []
            for doc in docs:
                data = doc.to_dict()
                data["id"] = doc.id
                documents.append(data)
            return documents
        except Exception as e:
            logger.error(f"Failed to fetch documents: {e}")
            return []

    async def increment_document_access(self, document_id: str):
        """Increment document access count"""
        if not self._db:
            return False

        try:
            doc_ref = self._db.collection("documents").document(document_id)
            doc_ref.update({"access_count": firestore.Increment(1)})
            return True
        except Exception as e:
            logger.error(f"Failed to increment document access: {e}")
            return False

    @staticmethod
    def send_multicast(tokens: List[str], title: str, body: str, data: Dict = None):
        """Send multicast FCM notification using Firebase Admin SDK.
        Uses the service account credentials - NO server key needed.
        Uses MulticastMessage for newer Firebase Admin SDK compatibility."""
        if not tokens:
            logger.warning("No tokens provided. Skipping multicast.")
            return

        try:
            multicast_message = messaging.MulticastMessage(
                notification=messaging.Notification(title=title, body=body),
                data=data or {},
                tokens=tokens,
            )
            response = messaging.send_each_for_multicast(multicast_message)
            logger.info(f"Multicast sent to {response.success_count}/{len(tokens)} devices")
            return response
        except Exception as e:
            logger.error(f"Multicast FCM failed: {e}")
            return None

    @staticmethod
    def send_topic_notification(topic: str, title: str, body: str, data: Dict = None):
        """Send topic-based FCM notification"""
        try:
            message = messaging.Message(
                notification=messaging.Notification(title=title, body=body),
                data=data or {},
                topic=topic,
            )
            response = messaging.send(message)
            logger.info(f"Topic notification sent to topic '{topic}': {response}")
            return response
        except Exception as e:
            logger.error(f"Topic FCM failed: {e}")
            return None


# Singleton instance
firebase_service = FirebaseService()
