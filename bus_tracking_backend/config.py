import os
from pydantic_settings import BaseSettings
from pathlib import Path


class Settings(BaseSettings):
    DATABASE_URL: str = os.getenv("DATABASE_URL", "sqlite:///./bus_tracking.db")
    USE_SQLITE: bool = "DATABASE_URL" not in os.environ or "sqlite" in os.getenv("DATABASE_URL", "")
    SECRET_KEY: str = os.getenv("SECRET_KEY", "your-secret-key-for-jwt-change-this-in-production")
    ALGORITHM: str = os.getenv("ALGORITHM", "HS256")
    ACCESS_TOKEN_EXPIRE_MINUTES: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "30"))
    FCM_SERVER_KEY: str = os.getenv("FCM_SERVER_KEY", "")
    FCM_PROJECT_ID: str = os.getenv("FCM_PROJECT_ID", "bustracker-afb3c")
    FCM_SENDER_ID: str = os.getenv("FCM_SENDER_ID", "851331446616")
    FCM_API_URL: str = os.getenv("FCM_API_URL", "https://fcm.googleapis.com/fcm/send")
    # Firebase service account credentials — paste full JSON content here
    FIREBASE_KEY: str = os.getenv("FIREBASE_KEY", "")
    # Fallback: path to a service-account JSON file (used if FIREBASE_KEY is not set)
    FIREBASE_CREDENTIALS_PATH: str = os.getenv("FIREBASE_CREDENTIALS_PATH", str(Path(__file__).parent / "firebase-key.json"))
    MINIO_BUCKET_DOCUMENTS: str = os.getenv("MINIO_BUCKET_DOCUMENTS", "documents")
    MINIO_BUCKET_ANNOUNCEMENTS: str = os.getenv("MINIO_BUCKET_ANNOUNCEMENTS", "announcements")
    CORS_ORIGINS: str = os.getenv(
        "CORS_ORIGINS",
        "http://localhost:3000,http://127.0.0.1:8000,http://10.0.2.2:8000,http://10.0.2.2:3000,http://192.168.29.123:8000,http://192.168.1.100:8000,https://bus-tracking-Uios.up.railway.app"
    )
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")

    class Config:
        env_file = str(Path(__file__).parent / ".env")
        extra = "ignore"


settings = Settings()