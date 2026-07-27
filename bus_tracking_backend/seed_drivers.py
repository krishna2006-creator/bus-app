#!/usr/bin/env python3
"""Seed driver users (1-32) for bus tracking system."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from database.database import SessionLocal
from database import models
from passlib.hash import bcrypt

PASSWORD = 'driver123'

def seed_drivers():
    db = SessionLocal()
    try:
        for i in range(1, 33):
            email = 'driver{}@busapp.com'.format(i)
            existing = db.query(models.User).filter(models.User.email == email).first()
            if existing:
                print('Driver {} exists, skipping'.format(i))
                continue
            driver = models.User(
                email=email,
                full_name='Driver {}'.format(i),
                role='driver',
                hashed_password=bcrypt.hash(PASSWORD),
                is_active=True,
                bus_id=i,
            )
            db.add(driver)
            print('Created driver {}'.format(i))
        db.commit()
        print('\nAll drivers created!')
        print('Login: driver1@busapp.com to driver32@busapp.com')
        print('Password: driver123')
    except Exception as e:
        db.rollback()
        print('Error: {}'.format(e))
    finally:
        db.close()

if __name__ == '__main__':
    seed_drivers()