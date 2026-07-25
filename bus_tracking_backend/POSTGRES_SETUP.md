# PostgreSQL Setup for Bus Tracking Backend

## Why PostgreSQL?

Your app will have **100,000 users**. SQLite is NOT suitable for this scale because:
- ❌ SQLite handles ~1 concurrent writer (PostgreSQL: 100+)
- ❌ SQLite has no connection pooling (PostgreSQL: built-in pooling)
- ❌ SQLite locks the entire database on writes (PostgreSQL: row-level locking)
- ❌ SQLite is file-based (PostgreSQL: client-server, network-accessible)

## Prerequisites

1. **Install PostgreSQL** on your server/machine:
   ```bash
   # Windows: Download from https://www.postgresql.org/download/windows/
   # Mac: brew install postgresql
   # Linux: sudo apt-get install postgresql postgresql-contrib
   ```

2. **Start PostgreSQL service**:
   ```bash
   # Windows: Services → PostgreSQL → Start
   # Mac: brew services start postgresql
   # Linux: sudo systemctl start postgresql
   ```

3. **Create database**:
   ```bash
   # Login to PostgreSQL
   psql -U postgres

   # Create database
   CREATE DATABASE bus_tracking;

   # Create user (optional, default is postgres/postgres)
   CREATE USER busapp WITH PASSWORD 'your_secure_password';
   GRANT ALL PRIVILEGES ON DATABASE bus_tracking TO busapp;
   ```

## Configuration

Your `.env` file is already configured:
```
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/bus_tracking
```

**For production**, change to:
```
DATABASE_URL=postgresql://busapp:your_secure_password@localhost:5432/bus_tracking
```

## Install Dependencies

```bash
cd c:\busappvictory\bus_tracking_backend
pip install -r requirements.txt
```

Key packages added:
- `psycopg2-binary` - PostgreSQL adapter for Python
- `tenacity` - Retry logic for database connections
- `redis` - Caching for 100k user scale

## Run Database Migrations

```bash
# Option 1: Auto-create tables (for development)
python -c "from bus_tracking_backend.database.database import engine, Base; Base.metadata.create_all(bind=engine)"

# Option 2: Use init script
python bus_tracking_backend/init_db.py
```

## Verify Connection

```bash
# Test PostgreSQL connection
python -c "from bus_tracking_backend.database.database import engine; print('PostgreSQL connected:', engine.url)"

# Start backend
python bus_tracking_backend\main.py
```

Expected output:
```
INFO:     Started server process [12345]
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000
```

## Database Schema Features for 100k Users

### Indexes Added (Critical for Performance)
```python
# Composite indexes for fast queries
Index('idx_pinned_user_bus', 'user_id', 'bus_id')  # Fast pinned bus lookup
Index('idx_tracking_bus_time', 'bus_id', 'start_time')  # Fast tracking history
Index('idx_live_entity_time', 'entity_id', 'timestamp')  # Fast location lookups
```

### Connection Pooling Configuration
```python
pool_size=10           # 10 persistent connections
max_overflow=20        # +20 during spikes (total 30)
pool_pre_ping=True     # Verify connections before use
pool_recycle=3600      # Recycle after 1 hour
pool_timeout=30        # Wait 30s for available connection
```

### Retry Logic
```python
@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=1, max=10),
    retry=retry_if_exception_type(OperationalError),
)
def get_db():
    # Automatically retries on transient connection errors
```

## Production Recommendations

1. **Use connection pooler (PgBouncer)**:
   ```bash
   # Install PgBouncer
   sudo apt-get install pgbouncer

   # Configure for 100k users
   pool_mode = transaction
   max_client_conn = 10000
   default_pool_size = 50
   ```

2. **Enable PostgreSQL tuning**:
   ```sql
   ALTER SYSTEM SET shared_buffers = '256MB';
   ALTER SYSTEM SET effective_cache_size = '1GB';
   ALTER SYSTEM SET maintenance_work_mem = '64MB';
   ALTER SYSTEM SET checkpoint_completion_target = 0.9;
   ALTER SYSTEM SET wal_buffers = '16MB';
   ALTER SYSTEM SET default_statistics_target = 100;
   SELECT pg_reload_conf();
   ```

3. **Add Redis for caching** (already in requirements.txt):
   ```python
   # Cache active locations, user sessions, pinned buses
   # Reduces DB queries by 90%
   ```

4. **Use read replicas** for reporting:
   ```python
   # Route admin dashboard queries to read replica
   # Keeps main DB fast for write operations
   ```

## Troubleshooting

**Error: `psycopg2` not found**
```bash
pip install psycopg2-binary
```

**Error: `could not connect to server`**
```bash
# Check PostgreSQL is running
# Windows: services.msc → PostgreSQL
# Mac: brew services list
# Linux: sudo systemctl status postgresql
```

**Error: `database "bus_tracking" does not exist`**
```bash
psql -U postgres -c "CREATE DATABASE bus_tracking;"
```

**Error: `password authentication failed`**
```bash
# Check credentials in .env match PostgreSQL user
# Default: postgres/postgres