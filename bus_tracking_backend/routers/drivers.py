from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel
from ..database.database import get_db
from ..schemas import user as user_schemas
from ..utils.auth_utils import get_current_user, get_password_hash
from ..database import models

router = APIRouter(prefix="/drivers", tags=["Drivers"])

# Schema for updating driver - makes password optional
class DriverUpdate(BaseModel):
    full_name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    password: Optional[str] = None
    assigned_bus_id: Optional[int] = None

@router.get("/me", response_model=user_schemas.User)
def read_driver_me(current_user: user_schemas.User = Depends(get_current_user)):
    if str(current_user.role).lower() != "driver":
        raise HTTPException(status_code=403, detail="Not a driver")
    return current_user

@router.get("/", response_model=List[user_schemas.User])
def list_drivers(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Admin/Staff: List all drivers."""
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(status_code=403, detail="Not authorized")
    return db.query(models.User).filter(models.User.role == "driver").all()

@router.get("/{driver_id}", response_model=user_schemas.User)
def get_driver(
    driver_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Admin/Staff: Get a specific driver's details."""
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(status_code=403, detail="Not authorized")
    driver = db.query(models.User).filter(models.User.id == driver_id, models.User.role == "driver").first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")
    return driver

@router.put("/{driver_id}", response_model=user_schemas.User)
def update_driver(
    driver_id: str,
    driver_update: DriverUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Admin: Update driver details (name, email, phone, password, assigned bus)."""
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")
    driver = db.query(models.User).filter(models.User.id == driver_id, models.User.role == "driver").first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    if driver_update.full_name is not None:
        driver.full_name = driver_update.full_name
    if driver_update.email is not None:
        driver.email = driver_update.email
    if driver_update.phone is not None:
        driver.phone = driver_update.phone
    if driver_update.password:
        driver.hashed_password = get_password_hash(driver_update.password)
    if driver_update.assigned_bus_id is not None:
        driver.assigned_bus_id = driver_update.assigned_bus_id
        # Also update the bus's driver_id
        bus = db.query(models.Bus).filter(models.Bus.id == driver_update.assigned_bus_id).first()
        if bus:
            bus.driver_id = driver_id

    db.commit()
    db.refresh(driver)
    return driver

@router.post("/{driver_id}/assign-bus/{bus_id}")
def assign_driver_to_bus(
    driver_id: str,
    bus_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Admin: Assign a driver to a bus."""
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")
    driver = db.query(models.User).filter(models.User.id == driver_id, models.User.role == "driver").first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")
    bus = db.query(models.Bus).filter(models.Bus.id == bus_id).first()
    if not bus:
        raise HTTPException(status_code=404, detail="Bus not found")

    bus.driver_id = driver_id
    db.commit()
    db.refresh(bus)
    return {"status": "success", "message": f"Driver {driver_id} assigned to bus {bus_id}"}

@router.get("/{driver_id}/bus", response_model=dict)
def get_driver_bus(
    driver_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Get the bus assigned to a driver."""
    if current_user.role not in ["admin", "staff", "driver"]:
        raise HTTPException(status_code=403, detail="Not authorized")
    if current_user.role == "driver" and current_user.id != driver_id:
        raise HTTPException(status_code=403, detail="Cannot view other drivers")
    bus = db.query(models.Bus).filter(models.Bus.driver_id == driver_id).first()
    if not bus:
        return {"status": "no_bus", "message": "No bus assigned to this driver"}
    return {
        "status": "success",
        "bus_id": bus.id,
        "bus_number": bus.bus_number,
        "route_name": bus.route_name,
        "status": bus.status,
    }