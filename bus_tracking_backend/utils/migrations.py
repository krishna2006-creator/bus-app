"""
Schema migration utility – ensures all columns defined by the SQLAlchemy models
actually exist in the live database.

This is critical for production deployments (Railway / Docker) where the database
may have been created by an older version of the code and `Base.metadata.create_all()`
only creates *new* tables — it never adds missing columns to existing tables.

The functions here are designed to be **idempotent** and **safe to call from
multiple worker processes** (e.g. gunicorn with 4 workers).  Each worker will
attempt the migration; `ALTER TABLE ... IF NOT EXISTS` ensures no conflicts.
"""
import logging
import time
from typing import Dict, List, Set

from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Column specifications: (table_name, [(column_name, sql_type), ...])
# ---------------------------------------------------------------------------
SCHEMA_MIGRATIONS: Dict[str, List[tuple]] = {
    "users": [
        ("custom_boarding_lat", "FLOAT"),
        ("custom_boarding_lng", "FLOAT"),
        ("bus_room_id", "INTEGER"),
        ("phone", "VARCHAR"),
    ],
    "buses": [
        ("is_active", "BOOLEAN"),
        ("location_sharing_active", "BOOLEAN"),
        ("driver_phone", "VARCHAR"),
    ],
    "notification_settings": [
        ("push_enabled", "BOOLEAN"),
        ("email_enabled", "BOOLEAN"),
        ("sms_enabled", "BOOLEAN"),
    ],
    "buses_stops": [],  # placeholder – table name handled elsewhere if needed
}


def _get_existing_columns(inspector: "inspect", table_name: str) -> Set[str]:
    """Safely retrieve the set of column names for *table_name*.

    Returns an empty set if the table does not exist yet (this is normal
    during first boot when ``create_all`` has just run).
    """
    try:
        return {col["name"] for col in inspector.get_columns(table_name)}
    except Exception:
        return set()


def ensure_schema_columns(engine: Engine, max_retries: int = 3, retry_delay: float = 2.0) -> bool:
    """Ensure that every column defined in *SCHEMA_MIGRATIONS* exists in the
    database, adding any that are missing.

    Parameters
    ----------
    engine
        SQLAlchemy engine connected to the target database.
    max_retries
        How many times to retry the entire migration if a connection-level
        error (e.g. database not ready) is encountered.
    retry_delay
        Seconds to wait between retries.

    Returns
    -------
    bool
        ``True`` if the schema is ensured (or already up-to-date), ``False``
        if all retries were exhausted.
    """
    for attempt in range(1, max_retries + 1):
        try:
            inspector = inspect(engine)
            existing_tables: Set[str] = set(inspector.get_table_names())

            # ``users`` is the critical table – it must exist.
            # If it doesn't, Base.metadata.create_all() should be called first.
            if "users" not in existing_tables:
                logger.warning(
                    "ensure_schema_columns: 'users' table does not exist yet; "
                    "skipping column migration (table will be created by metadata)."
                )
                return True  # create_all will handle it

            with engine.begin() as conn:
                # --- users table ---
                cols = _get_existing_columns(inspector, "users")
                _add_missing_column(conn, "users", cols, "custom_boarding_lat", "FLOAT")
                _add_missing_column(conn, "users", cols, "custom_boarding_lng", "FLOAT")
                _add_missing_column(conn, "users", cols, "bus_room_id", "INTEGER")
                _add_missing_column(conn, "users", cols, "phone", "VARCHAR")
                # Refresh column set after additions
                cols = _get_existing_columns(inspector, "users")

                # --- buses table ---
                if "buses" in existing_tables:
                    cols = _get_existing_columns(inspector, "buses")
                    _add_missing_column(conn, "buses", cols, "is_active", "BOOLEAN")
                    _add_missing_column(conn, "buses", cols, "location_sharing_active", "BOOLEAN")
                    _add_missing_column(conn, "buses", cols, "driver_phone", "VARCHAR")

                # --- notification_settings table ---
                if "notification_settings" in existing_tables:
                    cols = _get_existing_columns(inspector, "notification_settings")
                    _add_missing_column(conn, "notification_settings", cols, "push_enabled", "BOOLEAN")
                    _add_missing_column(conn, "notification_settings", cols, "email_enabled", "BOOLEAN")
                    _add_missing_column(conn, "notification_settings", cols, "sms_enabled", "BOOLEAN")

            logger.info("Schema migration completed successfully.")
            return True

        except Exception as exc:
            logger.warning(
                "Schema migration attempt %d/%d failed: %s",
                attempt, max_retries, exc,
            )
            if attempt < max_retries:
                time.sleep(retry_delay)
            else:
                logger.error("Schema migration FAILED after %d attempts: %s", max_retries, exc)
                return False

    return False


def _add_missing_column(conn, table_name: str, existing_cols: Set[str], col_name: str, sql_type: str):
    """Add a single column if it is not already present.

    Uses ``ADD COLUMN IF NOT EXISTS`` so the operation is idempotent and safe
    to run concurrently from multiple worker processes.
    """
    if col_name not in existing_cols:
        try:
            col_type = sql_type
            if sql_type == "BOOLEAN":
                # Provide a default so existing rows get a sensible value
                conn.execute(text(
                    f"ALTER TABLE {table_name} ADD COLUMN IF NOT EXISTS {col_name} {col_type} DEFAULT FALSE"
                ))
            elif sql_type == "INTEGER" or sql_type == "FLOAT":
                conn.execute(text(
                    f"ALTER TABLE {table_name} ADD COLUMN IF NOT EXISTS {col_name} {col_type}"
                ))
            else:
                conn.execute(text(
                    f"ALTER TABLE {table_name} ADD COLUMN IF NOT EXISTS {col_name} {col_type}"
                ))
            logger.info("Added column %s.%s (%s)", table_name, col_name, sql_type)
        except Exception as exc:
            logger.warning("Failed to add %s.%s: %s", table_name, col_name, exc)


def ensure_user_columns_safe(db_session) -> bool:
    """Lightweight helper called right before a User query in auth flows.

    Uses the *session's* bind (engine) to run a minimal ALTER TABLE for just
    the two columns that the User model requires and that are most commonly
    missing in legacy databases: ``custom_boarding_lat`` and
    ``custom_boarding_lng``.

    This acts as a last-resort self-heal: if the startup migration failed
    silently, this function gives subsequent requests a chance to recover
    instead of returning a 500.

    Returns ``True`` if the columns are confirmed present, ``False`` otherwise.
    """
    try:
        engine = db_session.bind
        if engine is None:
            return False

        inspector = inspect(engine)
        if "users" not in inspector.get_table_names():
            return False

        cols = _get_existing_columns(inspector, "users")
        needed = {"custom_boarding_lat", "custom_boarding_lng"} - cols
        if not needed:
            return True  # already present

        with engine.begin() as conn:
            for col_name in needed:
                col_type = "FLOAT"
                conn.execute(text(
                    f"ALTER TABLE users ADD COLUMN IF NOT EXISTS {col_name} {col_type}"
                ))
        logger.info("Self-healed missing user columns: %s", needed)
        return True
    except Exception as exc:
        logger.warning("ensure_user_columns_safe failed: %s", exc)
        return False
