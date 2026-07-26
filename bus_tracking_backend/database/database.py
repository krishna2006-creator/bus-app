import logging
import os
from sqlalchemy import create_engine, Index
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from bus_tracking_backend.config import settings
from sqlalchemy.pool import QueuePool, NullPool
from sqlalchemy.exc import OperationalError
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type

logger = logging.getLogger(__name__)

# Use SQLite unless DATABASE_URL explicitly points to Postgres
if settings.USE_SQLITE:
    SQLALCHEMY_DATABASE_URL = "sqlite:///./bus_tracking.db"
else:
    SQLALCHEMY_DATABASE_URL = settings.DATABASE_URL

logger.info(f"Database URL: {SQLALCHEMY_DATABASE_URL}")

# Estimate max concurrent users from environment or default to 100k
MAX_CONCURRENT_USERS = int(os.getenv("MAX_CONCURRENT_USERS", "100000"))
# For high-traffic WebSocket apps, use NullPool so connections are created/destroyed per operation
# This avoids pool exhaustion with thousands of concurrent WebSocket connections
# Railway PostgreSQL handles connection pooling at the infrastructure level
USE_NULL_POOL = os.getenv("USE_NULL_POOL", "true").lower() == "true"

def _create_engine(url: str):
    if url.startswith("sqlite"):
        return create_engine(url, connect_args={"check_same_thread": False})
    
    if USE_NULL_POOL:
        # NullPool: No persistent connections - each session creates/releases its own connection.
        # Required for WebSocket-heavy apps to avoid pool exhaustion.
        # Railway PostgreSQL can handle 100+ concurrent connections natively.
        logger.info("Using NullPool - no persistent connection pool")
        return create_engine(
            url,
            poolclass=NullPool,
            pool_pre_ping=True,
            connect_args={
                "connect_timeout": 10,
                "keepalives": 1,
                "keepalives_idle": 30,
                "keepalives_interval": 10,
                "keepalives_count": 5,
            },
        )
    else:
        # QueuePool with large limits for traditional request-response workloads
        pool_size = min(100, max(20, MAX_CONCURRENT_USERS // 1000))
        overflow = min(200, max(30, MAX_CONCURRENT_USERS // 500))
        logger.info(f"Using QueuePool: pool_size={pool_size}, max_overflow={overflow}")
        return create_engine(
            url,
            poolclass=QueuePool,
            pool_size=pool_size,
            max_overflow=overflow,
            pool_pre_ping=True,
            pool_recycle=120,    # Recycle connections every 2 minutes
            pool_timeout=30,
            connect_args={
                "connect_timeout": 10,
                "keepalives": 1,
                "keepalives_idle": 30,
                "keepalives_interval": 10,
                "keepalives_count": 5,
            },
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