from datetime import timedelta
from fastapi import APIRouter, Depends, HTTPException, status, Request
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from ..database.database import get_db
from ..database import crud
from ..schemas import user as user_schemas
from ..schemas import token as token_schemas
from ..utils.auth_utils import authenticate_user, create_access_token, get_password_hash, get_current_user
from ..config import settings

router = APIRouter(
    prefix="/auth",
    tags=["Authentication"],
)

@router.post("/register", response_model=token_schemas.Token)
def register(user: user_schemas.UserCreate, db: Session = Depends(get_db)):
    # 1. Check if user already exists (by email or ID)
    db_user = db.query(crud.models.User).filter(
        (crud.models.User.email == user.email) | (crud.models.User.id == user.email.split('@')[0])
    ).first()

    if db_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User with this email or ID already exists"
        )

    # 2. Hash password and create
    hashed_password = get_password_hash(user.password)
    try:
        new_user = crud.create_user(db=db, user=user, hashed_password=hashed_password)
        # 3. Return token after successful registration (auto-login)
        access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
        access_token = create_access_token(
            data={"sub": new_user.id}, expires_delta=access_token_expires
        )
        return {"access_token": access_token, "token_type": "bearer"}
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Registration failed: {str(e)}"
        )

@router.post("/login", response_model=token_schemas.Token)
async def login(request: Request, db: Session = Depends(get_db)):
    """
    Login endpoint that accepts BOTH form data (OAuth2 standard) and JSON.
    This ensures compatibility with both the Flutter frontend and standard OAuth2 clients.
    """
    content_type = request.headers.get("content-type", "")

    if "application/json" in content_type:
        # Parse JSON body
        body = await request.json()
        username = body.get("username") or body.get("email") or body.get("user_id")
        password = body.get("password")
    else:
        # Parse form data (OAuth2PasswordRequestForm standard)
        form = await request.form()
        username = form.get("username")
        password = form.get("password")

    if not username or not password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username and password are required"
        )

    user = authenticate_user(db, username, password)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect ID/Email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.id}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}

@router.get("/me", response_model=user_schemas.User)
async def read_users_me(current_user: user_schemas.User = Depends(get_current_user)):
    """Returns the currently logged in user's profile info."""
    return current_user