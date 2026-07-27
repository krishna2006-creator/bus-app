#!/usr/bin/env python3
"""Database optimization: indexes, connection pooling."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))

OPTIMIZATIONS = [
    "CREATE INDEX IF NOT EXISTS idx_bus_locations_bus_number ON bus_locations(bus_number);",
    "CREATE INDEX IF NOT EXISTS idx_bus_locations_timestamp ON bus_locations(timestamp DESC);",
    "CREATE INDEX IF NOT EXISTS idx_bus_locations_bus_ts ON bus_locations(bus_number, timestamp DESC);",
    "CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);",
    "CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);",
    "CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, created_at DESC);",
    "CREATE INDEX IF NOT EXISTS idx_requests_user ON requests(user_id);",
    "CREATE INDEX IF NOT EXISTS idx_requests_status ON requests(status);",
    "CREATE INDEX IF NOT EXISTS idx_buses_number ON buses(bus_number);",
    "CREATE INDEX IF NOT EXISTS idx_feedback_user ON feedback(user_id);",
    "CREATE INDEX IF NOT EXISTS idx_documents_uploaded ON documents(uploaded_by_id);",
    "CREATE INDEX IF NOT EXISTS idx_announcements_target ON announcements(target_role);",
]

def optimize():
    from sqlalchemy import text
    from database.database import SessionLocal
    db = SessionLocal()
    try:
        for sql in OPTIMIZATIONS:
            try:
                db.execute(text(sql))
                print('Applied: {}...'.format(sql[:60]))
            except Exception as e:
                print('Error: {}'.format(e))
        db.commit()
        print('All database optimizations applied!')
    except Exception as e:
        db.rollback()
        print('Error: {}'.format(e))
    finally:
        db.close()

if __name__ == '__main__':
    optimize()