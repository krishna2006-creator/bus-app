from fastapi import APIRouter, Depends, UploadFile, File, Form
from sqlalchemy.orm import Session
from ..database.database import get_db
from ..schemas import user as user_schemas
from ..utils.auth_utils import get_current_user
import shutil
import os

router = APIRouter(prefix="/documents", tags=["Documents"])

@router.post("/upload")
async def upload_document(
    name: str = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    file_location = f"uploads/{file.filename}"
    with open(file_location, "wb+") as file_object:
        shutil.copyfileobj(file.file, file_object)
    # Add DB logic here
    return {"info": f"file '{file.filename}' saved at '{file_location}'"}