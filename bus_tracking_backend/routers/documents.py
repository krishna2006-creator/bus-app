from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from ..database.database import get_db
from ..database import models
from ..schemas import user as user_schemas
from ..services.notification_service import notification_service
from ..utils.auth_utils import get_current_user
import shutil
import os
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
import asyncio

router = APIRouter(prefix="/documents", tags=["Documents"])

# Use absolute path for uploads directory to work consistently across deployments
UPLOADS_DIR = os.path.join(os.getcwd(), "uploads")
os.makedirs(UPLOADS_DIR, exist_ok=True)

class DocumentResponse(BaseModel):
    id: int
    name: str
    url: str
    file_type: str
    uploaded_at: str
    description: Optional[str] = None
    category: str = "general"

    class Config:
        from_attributes = True

@router.get("", response_model=List[DocumentResponse])
@router.get("/", response_model=List[DocumentResponse])
async def list_documents(
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    """Get all available documents for the current user."""
    # First try DB-stored documents
    db_docs = db.query(models.Document).order_by(models.Document.created_at.desc()).all()
    if db_docs:
        documents = []
        for doc in db_docs:
            file_ext = os.path.splitext(doc.file_path)[1].lower()
            file_type = "pdf" if file_ext == ".pdf" else ("image" if file_ext in [".jpg", ".jpeg", ".png"] else "file")
            documents.append(DocumentResponse(
                id=doc.id,
                name=doc.name,
                url=f"/uploads/{doc.file_path}",
                file_type=file_type,
                uploaded_at=doc.created_at.isoformat() if doc.created_at else "",
                description=doc.description,
                category=doc.category
            ))
        return documents

    # Fallback: List all files in uploads directory
    documents = []

    if os.path.exists(UPLOADS_DIR):
        for filename in os.listdir(UPLOADS_DIR):
            file_path = os.path.join(UPLOADS_DIR, filename)
            if os.path.isfile(file_path):
                file_ext = os.path.splitext(filename)[1].lower()
                file_type = "pdf" if file_ext == ".pdf" else ("image" if file_ext in [".jpg", ".jpeg", ".png"] else "file")

                documents.append(DocumentResponse(
                    id=abs(hash(filename)) % 1000000,
                    name=filename,
                    url=f"/uploads/{filename}",
                    file_type=file_type,
                    uploaded_at=str(datetime.fromtimestamp(os.path.getmtime(file_path)))
                ))

    return documents

@router.post("/upload")
async def upload_document(
    name: str = Form(...),
    file: UploadFile = File(...),
    description: str = Form(None),
    category: str = Form("general"),
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")

    os.makedirs(UPLOADS_DIR, exist_ok=True)
    
    # Sanitize filename to prevent path traversal
    safe_filename = os.path.basename(file.filename or "document")
    file_location = os.path.join(UPLOADS_DIR, safe_filename)
    
    # If file already exists, add timestamp to avoid overwrite
    if os.path.exists(file_location):
        name_part, ext_part = os.path.splitext(safe_filename)
        safe_filename = f"{name_part}_{datetime.now().strftime('%Y%m%d%H%M%S')}{ext_part}"
        file_location = os.path.join(UPLOADS_DIR, safe_filename)
    
    with open(file_location, "wb+") as file_object:
        shutil.copyfileobj(file.file, file_object)

    file_size = os.path.getsize(file_location)
    file_ext = os.path.splitext(safe_filename)[1].lower()
    file_type = "pdf" if file_ext == ".pdf" else ("image" if file_ext in [".jpg", ".jpeg", ".png"] else "file")

    # Save document metadata to DB
    db_document = models.Document(
        name=name,
        description=description,
        file_path=safe_filename,
        file_size=file_size,
        file_type=file_type,
        category=category,
        uploaded_by_id=current_user.id,
    )
    db.add(db_document)
    db.commit()
    db.refresh(db_document)

    # Construct the file URL so the frontend can open it directly
    file_url = f"/uploads/{safe_filename}"

    # Notify students and staff about the new document (exclude the uploader)
    # Use asyncio.create_task to send notifications in background - don't block upload response
    # Create a new DB session for the background task since the request session will be closed
    async def _send_document_notification():
        from ..database.database import SessionLocal
        bg_db = SessionLocal()
        try:
            await notification_service.broadcast_to_role(
                bg_db,
                title="New Document Available",
                message=f"A new document '{name}' has been uploaded.",
                category="DOCUMENT_SHARED",
                target_role="all",
                data={"file_name": name, "url": file_url, "document_id": db_document.id},
                exclude_user_id=current_user.id
            )
        finally:
            bg_db.close()
    
    asyncio.create_task(_send_document_notification())

    return {
        "info": f"file '{safe_filename}' saved and notification sent",
        "document_id": db_document.id,
        "url": file_url
    }

@router.get("/{document_id}/download")
@router.get("/{document_id}/file")
async def download_document(
    document_id: int,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    """Download/Stream document file by ID for any authenticated user."""
    doc = db.query(models.Document).filter(models.Document.id == document_id).first()
    if not doc:
        raise HTTPException(status_code=404, detail="Document metadata not found")

    file_path = os.path.join(UPLOADS_DIR, doc.file_path)
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="Document file not found on server")

    file_ext = os.path.splitext(doc.file_path)[1].lower()
    media_type = "application/pdf" if file_ext == ".pdf" else (
        "image/png" if file_ext == ".png" else (
            "image/jpeg" if file_ext in [".jpg", ".jpeg"] else "application/octet-stream"
        )
    )

    return FileResponse(
        path=file_path,
        filename=doc.name,
        media_type=media_type
    )

@router.get("/{document_id}")
async def get_document(
    document_id: int,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    """Get a specific document by ID."""
    doc = db.query(models.Document).filter(models.Document.id == document_id).first()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")
    file_ext = os.path.splitext(doc.file_path)[1].lower()
    file_type = "pdf" if file_ext == ".pdf" else ("image" if file_ext in [".jpg", ".jpeg", ".png"] else "file")
    return DocumentResponse(
        id=doc.id,
        name=doc.name,
        url=f"/uploads/{doc.file_path}",
        file_type=file_type,
        uploaded_at=doc.created_at.isoformat() if doc.created_at else "",
        description=doc.description,
        category=doc.category
    )

@router.delete("/{document_id}")
async def delete_document(
    document_id: int,
    db: Session = Depends(get_db),
    current_user: user_schemas.User = Depends(get_current_user)
):
    """Admin/Staff: Delete a document."""
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")
    
    doc = db.query(models.Document).filter(models.Document.id == document_id).first()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")
    
    # Delete the physical file
    file_path = os.path.join(UPLOADS_DIR, doc.file_path)
    if os.path.exists(file_path):
        os.remove(file_path)
    
    # Delete from database
    db.delete(doc)
    db.commit()
    
    return {"status": "success", "message": f"Document '{doc.name}' deleted"}