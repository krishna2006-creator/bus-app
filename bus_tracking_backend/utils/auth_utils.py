import bcrypt
from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from config import settings
from database.database import get_db
from database import models


def normalize_role(role: Optional[object]) -> str:
    """Normalize role values from enums, strings, or None to a consistent lowercase string."""
    if role is None:
        return "student"
    if hasattr(role, "value"):
        role_value = role.value
    else:
        role_value = str(role)

    if isinstance(role_value, str):
        normalized = role_value.strip().lower()
        if normalized in {"admin", "staff", "student", "driver"}:
            return normalized

    return "student"

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/auth/login", auto_error=False)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))
    except Exception:
        return False

def get_password_hash(password: str) -> str:
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta if expires_delta else timedelta(minutes=15))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    """
    FastAPI dependency: Validates the token and returns the user.
    Supports both mock IDs (dev) and JWT tokens.
    """
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    # 1. Check for Development Mock IDs (stu001, admin001, etc.)
    user = db.query(models.User).filter(models.User.id == token).first()
    if user:
        return user

    # 2. Try to find by email if token is an email
    user = db.query(models.User).filter(models.User.email == token).first()
    if user:
        return user

    # 3. Try JWT Decode
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        # JWT sub could be user ID or email, try both
        sub = payload.get("sub")
        if sub:
            # First try as ID
            user = db.query(models.User).filter(models.User.id == sub).first()
            if user:
                return user
            # Then try as email
            user = db.query(models.User).filter(models.User.email == sub).first()
            if user:
                return user
    except JWTError:
        pass

    raise HTTPException(status_code=401, detail="Invalid authentication credentials")

def authenticate_user(db: Session, username: str, password: str):
    # Try finding user by email OR by ID
    user = db.query(models.User).filter((models.User.email == username) | (models.User.id == username)).first()
    if not user or not verify_password(password, user.hashed_password):
        return None
    return user
