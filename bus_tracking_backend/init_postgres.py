"""
PostgreSQL Database Initialization Script
Creates all tables and optionally seeds initial data.
"""
import os
import sys

# Ensure UTF-8 output for Unicode characters on Windows
sys.stdout.reconfigure(encoding='utf-8')

# Ensure the package is importable
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from bus_tracking_backend.database.database import engine, Base, SessionLocal
from bus_tracking_backend.database import models
from dotenv import load_dotenv

load_dotenv()

def create_tables():
    """Create all tables in PostgreSQL."""
    print("Creating PostgreSQL tables...")
    try:
        Base.metadata.create_all(bind=engine)
        print("✅ All tables created successfully!")
        return True
    except Exception as e:
        print(f"❌ Error creating tables: {e}")
        return False

def show_tables():
    """List all tables in PostgreSQL."""
    from sqlalchemy import inspect
    inspector = inspect(engine)
    tables = inspector.get_table_names()
    print("\n📋 Tables in database:")
    for table in tables:
        print(f"  - {table}")
    return tables

def show_indexes():
    """Show indexes for performance verification."""
    from sqlalchemy import inspect
    inspector = inspect(engine)
    tables = inspector.get_table_names()
    
    print("\n🔍 Indexes:")
    for table in tables:
        indexes = inspector.get_indexes(table)
        if indexes:
            print(f"\n  {table}:")
            for idx in indexes:
                print(f"    - {idx['name']}: {idx['column_names']}")

def seed_data():
    """Seed initial data into PostgreSQL database."""
    from bus_tracking_backend.utils.auth_utils import get_password_hash
    from bus_tracking_backend.database import models
    
    db = SessionLocal()
    try:
        # Check if data already exists
        existing_users = db.query(models.User).count()
        if existing_users > 0:
            print(f"\n📊 Database already has {existing_users} users. Skipping seed.")
            return True
        
        print("\n🌱 Seeding initial data...")
        
        # Seed users
        users = [
            models.User(
                id="admin001", email="admin@gmail.com", full_name="Admin User",
                hashed_password=get_password_hash("admin@123"), role="admin"
            ),
            models.User(
                id="stu001", email="student@gmail.com", full_name="Student User",
                hashed_password=get_password_hash("stu@123"), role="student"
            ),
            models.User(
                id="staff001", email="staff@gmail.com", full_name="Staff User",
                hashed_password=get_password_hash("staff@123"), role="staff"
            ),
            models.User(
                id="driver001", email="driver001@gmail.com", full_name="Driver One",
                hashed_password=get_password_hash("driver@123"), role="driver",
                phone="9940140579"
            ),
            models.User(
                id="driver002", email="driver002@gmail.com", full_name="Driver Two",
                hashed_password=get_password_hash("driver@123"), role="driver",
                phone="8098587815"
            ),
        ]
        db.add_all(users)
        
        # Seed buses with stops
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
        
        coordinates = {
            "Thiruvanmiyur": (12.9896, 80.2744),
            "Adyar": (13.0056, 80.2644),
            "Agni College of Technology": (12.8482, 80.1943),
            "Mylapore": (13.0329, 80.2644),
            "Mandaveli": (13.0396, 80.2526),
            "Perambur": (13.1445, 80.1705),
            "Redhills": (13.1854, 80.1269),
            "Central": (13.0827, 80.2798),
            "Velachery": (12.9696, 80.2126),
            "Tambaram": (12.9142, 79.9608),
        }
        
        for bus_id, route_name, stop_names in bus_data:
            new_bus = models.Bus(
                bus_number=str(bus_id),
                route_name=route_name,
                capacity=50,
                status="active"
            )
            db.add(new_bus)
            db.flush()
            
            stops = []
            for order, stop_name in enumerate(stop_names, 1):
                lat, lng = coordinates.get(stop_name, (12.8482, 80.1943))
                stops.append(
                    models.BusStop(
                        bus_id=new_bus.id,
                        stop_name=stop_name,
                        latitude=lat,
                        longitude=lng,
                        stop_order=order
                    )
                )
            db.add_all(stops)
        
        # Assign drivers to buses
        bus1 = db.query(models.Bus).filter(models.Bus.id == 1).first()
        bus1.driver_id = "driver001"
        bus1.driver_phone = "9940140579"
        bus2 = db.query(models.Bus).filter(models.Bus.id == 2).first()
        bus2.driver_id = "driver002"
        bus2.driver_phone = "8098587815"
        
        # Create notification settings for all users
        for user in users:
            db.add(models.NotificationSetting(user_id=user.id))
        
        db.commit()
        print(f"✅ Seeded {len(users)} users and {len(bus_data)} buses with stops!")
        return True
    except Exception as e:
        print(f"❌ Error seeding data: {e}")
        db.rollback()
        return False
    finally:
        db.close()

if __name__ == "__main__":
    print("=" * 60)
    print("PostgreSQL Database Initialization")
    print("=" * 60)
    
    # Show current database URL
    db_url = os.getenv("DATABASE_URL")
    print(f"\nDatabase URL: {db_url}")
    
    if "postgresql" not in db_url:
        print("\n⚠️  WARNING: DATABASE_URL is not PostgreSQL!")
        print("   Current URL:", db_url)
        print("   Please update your .env file to use PostgreSQL.")
        exit(1)
    
    # Create tables
    if create_tables():
        show_tables()
        show_indexes()
        # Seed data
        seed_data()
        print("\n✅ PostgreSQL initialization complete!")
    else:
        print("\n❌ PostgreSQL initialization failed!")
        exit(1)
