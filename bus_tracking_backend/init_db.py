import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from bus_tracking_backend.database.database import engine, SessionLocal
from bus_tracking_backend.database import models
from bus_tracking_backend.utils.auth_utils import get_password_hash
from sqlalchemy import inspect, text

COLLEGE_LATITUDE = 12.8489
COLLEGE_LONGITUDE = 80.1939

def get_stop_coordinates(stop_name):
    coordinates = {
        "Thiruvanmiyur": (12.9896, 80.2744),
        "Adyar": (13.0056, 80.2644),
        "Agni College of Technology": (COLLEGE_LATITUDE, COLLEGE_LONGITUDE),
        "Mylapore": (13.0329, 80.2644),
        "Mandaveli": (13.0396, 80.2526),
        "Perambur": (13.1445, 80.1705),
        "Redhills": (13.1854, 80.1269),
        "Central": (13.0827, 80.2798),
        "Velachery": (12.9696, 80.2126),
        "Tambaram": (12.9142, 79.9608),
        "Airport Road": (13.0733, 80.1699),
        "Meenambakkam": (13.0339, 80.2154),
        "Nungambakkam": (13.0827, 80.2798),
        "Kilpauk": (13.0740, 80.2110),
        "Kodambakkam": (13.0733, 80.2154),
        "Valasaravakkam": (13.0833, 80.2075),
        "Teynampet": (13.0375, 80.2619),
        "Nandanam": (13.0375, 80.2619),
        "K.K. Nagar": (13.0833, 80.2075),
        "Karpagam": (13.0833, 80.2075),
        "Ashok Nagar": (13.0733, 80.2154),
        "Alwarpet": (13.0375, 80.2619),
        "Thalankuppam": (12.8233, 80.2250),
        "Kelambakkam": (12.7950, 80.2250),
        "Velappachavadi": (13.0833, 80.2075),
        "Ambattur": (13.0733, 80.2154),
        "Baby Nagar": (13.0650, 80.2075),
        "Perungudi": (13.0650, 80.2075),
        "Sriperumbudur": (12.9933, 79.9733),
        "Oragadam": (12.9933, 79.9733),
        "Chrompet": (13.0569, 80.1699),
        "Pallavaram": (13.0650, 80.2075),
        "Little Mount": (13.0650, 80.2075),
        "Guindy": (13.0650, 80.2075),
        "Saidapet": (13.0650, 80.2075),
        "St. Thomas Mount": (13.0650, 80.2075),
        "Adambakkam": (13.0650, 80.2075),
        "Tirupati": (13.0650, 80.2075),
        "Vellore": (13.0650, 80.2075),
        "Bangalore": (13.0650, 80.2075),
        "Chikballapur": (13.0650, 80.2075),
        "Hosur": (12.8950, 78.0233),
        "Krishnagiri": (12.8950, 78.0233),
        "Ranipet": (13.0650, 80.2075),
        "Kanchipuram": (13.0650, 80.2075),
        "Uttarpalli": (13.0650, 80.2075),
        "Uthandi": (13.0650, 80.2075),
        "Mahabalipuram": (12.8233, 80.2250),
        "Chengalpattu": (12.8233, 80.2250),
        "Kovalam": (12.8233, 80.2250),
        "Muttukadu": (12.8233, 80.2250),
        "Vedanthangal": (12.8233, 80.2250),
        "Ekanapuram": (12.8233, 80.2250),
        "Srirangam": (13.0650, 80.2075),
        "Trichy": (13.0650, 80.2075),
        "Kumbakonam": (13.0650, 80.2075),
        "Thanjavur": (13.0650, 80.2075),
        "Cuddalore": (13.0650, 80.2075),
        "Villupuram": (13.0650, 80.2075),
        "Pondicherry": (12.8233, 80.2250),
        "Karaikal": (12.8233, 80.2250),
        "Puducherry": (12.8233, 80.2250),
        "Yanam": (12.8233, 80.2250),
    }
    return coordinates.get(stop_name, (COLLEGE_LATITUDE, COLLEGE_LONGITUDE))

def _migrate_columns():
    try:
        inspector = inspect(engine)
        if 'users' in inspector.get_table_names():
            columns = {col['name'] for col in inspector.get_columns('users')}
            if 'bus_room_id' not in columns:
                try:
                    with engine.begin() as conn:
                        conn.execute(text("ALTER TABLE users ADD COLUMN bus_room_id INTEGER"))
                    print("Added bus_room_id column to users table")
                except Exception as exc:
                    print(f"bus_room_id migration skipped/failed: {exc}")
        if 'buses' in inspector.get_table_names():
            columns = {col['name'] for col in inspector.get_columns('buses')}
            if 'is_active' not in columns:
                try:
                    with engine.begin() as conn:
                        conn.execute(text("ALTER TABLE buses ADD COLUMN is_active BOOLEAN DEFAULT TRUE"))
                    print("Added is_active column to buses table")
                except Exception as exc:
                    print(f"is_active migration skipped/failed: {exc}")
            if 'location_sharing_active' not in columns:
                try:
                    with engine.begin() as conn:
                        conn.execute(text("ALTER TABLE buses ADD COLUMN location_sharing_active BOOLEAN DEFAULT FALSE"))
                    print("Added location_sharing_active column to buses table")
                except Exception as exc:
                    print(f"location_sharing_active migration skipped/failed: {exc}")
        # CRITICAL: notification_settings table in older deployments only has (id, user_id).
        # The NotificationSetting model requires push_enabled/email_enabled/sms_enabled columns,
        # so registration would otherwise fail with "column push_enabled does not exist".
        if 'notification_settings' in inspector.get_table_names():
            columns = {col['name'] for col in inspector.get_columns('notification_settings')}
            if 'push_enabled' not in columns:
                try:
                    with engine.begin() as conn:
                        conn.execute(text("ALTER TABLE notification_settings ADD COLUMN push_enabled BOOLEAN DEFAULT TRUE"))
                    print("Added push_enabled column to notification_settings table")
                except Exception as exc:
                    print(f"push_enabled migration skipped/failed: {exc}")
            if 'email_enabled' not in columns:
                try:
                    with engine.begin() as conn:
                        conn.execute(text("ALTER TABLE notification_settings ADD COLUMN email_enabled BOOLEAN DEFAULT FALSE"))
                    print("Added email_enabled column to notification_settings table")
                except Exception as exc:
                    print(f"email_enabled migration skipped/failed: {exc}")
            if 'sms_enabled' not in columns:
                try:
                    with engine.begin() as conn:
                        conn.execute(text("ALTER TABLE notification_settings ADD COLUMN sms_enabled BOOLEAN DEFAULT FALSE"))
                    print("Added sms_enabled column to notification_settings table")
                except Exception as exc:
                    print(f"sms_enabled migration skipped/failed: {exc}")
    except Exception as exc:
        print(f"Migration column check warning (non-fatal): {exc}")

def reinitialize_database():
    models.Base.metadata.create_all(bind=engine)
    try:
        inspector = inspect(engine)
        columns = {col['name'] for col in inspector.get_columns('users')}
        if 'bus_room_id' not in columns:
            try:
                with engine.begin() as conn:
                    conn.execute(text("ALTER TABLE users ADD COLUMN bus_room_id INTEGER"))
            except Exception:
                pass
        columns = {col['name'] for col in inspector.get_columns('buses')}
        if 'is_active' not in columns:
            try:
                with engine.begin() as conn:
                    conn.execute(text("ALTER TABLE buses ADD COLUMN is_active BOOLEAN DEFAULT TRUE"))
            except Exception:
                pass
        if 'location_sharing_active' not in columns:
            try:
                with engine.begin() as conn:
                    conn.execute(text("ALTER TABLE buses ADD COLUMN location_sharing_active BOOLEAN DEFAULT FALSE"))
            except Exception:
                pass
    except Exception as exc:
        print(f"Reinit migration check warning (non-fatal): {exc}")
    db = SessionLocal()
    try:
        print("Seeding all user roles...")
        users = [
            models.User(id="admin001", email="admin@gmail.com", full_name="Admin User", hashed_password=get_password_hash("admin@123"), role="admin"),
            models.User(id="stu001", email="student@gmail.com", full_name="Student User", hashed_password=get_password_hash("stu@123"), role="student", bus_room_id=1),
            models.User(id="staff001", email="staff@gmail.com", full_name="Staff User", hashed_password=get_password_hash("staff@123"), role="staff"),
            models.User(id="driver001", email="driver001@gmail.com", full_name="Driver One", hashed_password=get_password_hash("driver@123"), role="driver", phone="9940140579"),
            models.User(id="driver002", email="driver002@gmail.com", full_name="Driver Two", hashed_password=get_password_hash("driver@123"), role="driver", phone="8098587815"),
        ]
        db.add_all(users)
        print("Seeding buses with stops...")
        bus_data = [
            (1, "Airport Road", ["Airport Road", "Meenambakkam", "Agni College of Technology"]),
            (2, "Perambur", ["Perambur", "Redhills", "Agni College of Technology"]),
            (3, "Nungambakkam", ["Nungambakkam", "Kilpauk", "Agni College of Technology"]),
            (4, "Kodambakkam", ["Kodambakkam", "Valasaravakkam", "Agni College of Technology"]),
            (5, "Velachery", ["Velachery", "Tambaram", "Agni College of Technology"]),
            (6, "Mylapore", ["Mylapore", "Mandaveli", "Agni College of Technology"]),
            (7, "Teynampet", ["Teynampet", "Nandanam", "Agni College of Technology"]),
            (8, "K.K. Nagar", ["K.K. Nagar", "Karpagam", "Agni College of Technology"]),
            (9, "Ashok Nagar", ["Ashok Nagar", "Alwarpet", "Agni College of Technology"]),
            (10, "Perambur", ["Perambur", "Central", "Agni College of Technology"]),
            (11, "Thalankuppam", ["Thalankuppam", "Kelambakkam", "Agni College of Technology"]),
            (12, "Velappachavadi", ["Velappachavadi", "Ambattur", "Agni College of Technology"]),
            (13, "Thiruvanmiyur", ["Thiruvanmiyur", "Adyar", "Agni College of Technology"]),
            (14, "Baby Nagar", ["Baby Nagar", "Perungudi", "Agni College of Technology"]),
            (15, "Sriperumbudur", ["Sriperumbudur", "Oragadam", "Agni College of Technology"]),
            (16, "Chrompet", ["Chrompet", "Pallavaram", "Agni College of Technology"]),
            (17, "Little Mount", ["Little Mount", "Guindy", "Agni College of Technology"]),
            (18, "Saidapet", ["Saidapet", "Guindy", "Agni College of Technology"]),
            (19, "St. Thomas Mount", ["St. Thomas Mount", "Adambakkam", "Agni College of Technology"]),
            (20, "Tirupati", ["Tirupati", "Vellore", "Agni College of Technology"]),
            (21, "Bangalore", ["Bangalore", "Chikballapur", "Agni College of Technology"]),
            (22, "Hosur", ["Hosur", "Krishnagiri", "Agni College of Technology"]),
            (23, "Ranipet", ["Ranipet", "Kanchipuram", "Agni College of Technology"]),
            (24, "Uttarpalli", ["Uttarpalli", "Uthandi", "Agni College of Technology"]),
            (25, "Mahabalipuram", ["Mahabalipuram", "Chengalpattu", "Agni College of Technology"]),
            (26, "Kovalam", ["Kovalam", "Muttukadu", "Agni College of Technology"]),
            (27, "Vedanthangal", ["Vedanthangal", "Ekanapuram", "Agni College of Technology"]),
            (28, "Srirangam", ["Srirangam", "Trichy", "Agni College of Technology"]),
            (29, "Kumbakonam", ["Kumbakonam", "Thanjavur", "Agni College of Technology"]),
            (30, "Cuddalore", ["Cuddalore", "Villupuram", "Agni College of Technology"]),
            (31, "Pondicherry", ["Pondicherry", "Karaikal", "Agni College of Technology"]),
            (32, "Puducherry", ["Puducherry", "Yanam", "Agni College of Technology"]),
        ]
        for bus_id, route_name, stop_names in bus_data:
            bus = models.Bus(bus_number=str(bus_id), route_name=route_name, capacity=50, status="active", location_sharing_active=False)
            db.add(bus)
            db.flush()
            for order, stop_name in enumerate(stop_names, 1):
                lat, lng = get_stop_coordinates(stop_name)
                db.add(models.BusStop(bus_id=bus.id, stop_name=stop_name, latitude=lat, longitude=lng, stop_order=order))
        bus1 = db.query(models.Bus).filter(models.Bus.id == 1).first()
        bus1.driver_id = "driver001"
        bus1.driver_phone = "9940140579"
        bus2 = db.query(models.Bus).filter(models.Bus.id == 2).first()
        bus2.driver_id = "driver002"
        bus2.driver_phone = "8098587815"
        for user in users:
            db.add(models.NotificationSetting(user_id=user.id))
        db.commit()
        print("Database initialized successfully with all roles!")
    except Exception as e:
        print(f"Error: {e}")
        db.rollback()
    finally:
        db.close()

def init_database():
    models.Base.metadata.create_all(bind=engine)
    _migrate_columns()
    db = SessionLocal()
    try:
        user_count = db.query(models.User).count()
        if user_count == 0:
            print("Database empty. Seeding initial data...")
            reinitialize_database()
        else:
            print(f"Database already has {user_count} users. Skipping seed.")
            models.Base.metadata.create_all(bind=engine)
    except Exception as e:
        print(f"Database initialization error: {e}")
        db.rollback()
    finally:
        db.close()

if __name__ == "__main__":
    reinitialize_database()