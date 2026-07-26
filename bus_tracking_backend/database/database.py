import logging
from sqlalchemy import create_engine, Index
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from bus_tracking_backend.config import settings
from sqlalchemy.pool import QueuePool
from sqlalchemy.exc import OperationalError
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type

logger = logging.getLogger(__name__)

# Use SQLite unless DATABASE_URL explicitly points to Postgres
if settings.USE_SQLITE:
    SQLALCHEMY_DATABASE_URL = "sqlite:///./bus_tracking.db"
else:
    SQLALCHEMY_DATABASE_URL = settings.DATABASE_URL

logger.info(f"Database URL: {SQLALCHEMY_DATABASE_URL}")

def _create_engine(url: str):
    if url.startswith("sqlite"):
        return create_engine(url, connect_args={"check_same_thread": False})
    # PostgreSQL with connection pooling - increased pool size for WebSocket connections
    return create_engine(
        url,
        poolclass=QueuePool,
        pool_size=20,        # Increased from 5 to 20
        max_overflow=30,     # Increased from 10 to 30
        pool_pre_ping=True,
        pool_recycle=300,    # Recycle connections after 5 min instead of 30
        pool_timeout=60,     # Increased timeout from 30 to 60 sec
    )

try:
    engine = _create_engine(SQLALCHEMY_DATABASE_URL)
except Exception as exc:
    logger.error(f"Failed to create database engine: {exc}")
    raise

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=1, max=10),
    retry=retry_if_exception_type(OperationalError),
)
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()