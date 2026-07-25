from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException, status
from sqlalchemy.orm import Session
from ..database.database import get_db
from ..database import models
from ..schemas import user as user_schemas
from ..services.notification_service import notification_service
from ..utils.auth_utils import get_current_user
import shutil
import os
from pydantic import BaseModel
from typing import List
from datetime import datetime

router = APIRouter(prefix="/documents", tags=["Documents"])

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
    db_docs = db.query(models.Document).all()
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
    uploads_dir = "uploads"
    documents = []

    if os.path.exists(uploads_dir):
        for filename in os.listdir(uploads_dir):
            file_path = os.path.join(uploads_dir, filename)
            if os.path.isfile(file_path):
                file_ext = os.path.splitext(filename)[1].lower()
                file_type = "pdf" if file_ext == ".pdf" else ("image" if file_ext in [".jpg", ".jpeg", ".png"] else "file")

                documents.append(DocumentResponse(
                    id=filename,
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

    os.makedirs("uploads", exist_ok=True)
    file_location = f"uploads/{file.filename}"
    with open(file_location, "wb+") as file_object:
        shutil.copyfileobj(file.file, file_object)

    file_size = os.path.getsize(file_location)
    file_ext = os.path.splitext(file.filename)[1].lower()
    file_type = "pdf" if file_ext == ".pdf" else ("image" if file_ext in [".jpg", ".jpeg", ".png"] else "file")

    # Save document metadata to DB
    db_document = models.Document(
        name=name,
        description=description,
        file_path=file.filename,
        file_size=file_size,
        file_type=file_type,
        category=category,
        uploaded_by_id=current_user.id,
    )
    db.add(db_document)
    db.commit()
    db.refresh(db_document)

    # Construct the file URL so the frontend can open it directly
    file_url = f"/uploads/{file.filename}"

    # Notify students and staff about the new document
    await notification_service.broadcast_to_role(
        db,
        title="New Document Available",
        message=f"A new document '{name}' has been uploaded.",
        category="DOCUMENT_SHARED",
        target_role="all",
        data={"file_name": name, "url": file_url, "document_id": db_document.id}
    )

    return {
        "info": f"file '{file.filename}' saved and notification sent",
        "document_id": db_document.id,
        "url": file_url
    }

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
    file_path = os.path.join("uploads", doc.file_path)
    if os.path.exists(file_path):
        os.remove(file_path)
    
    # Delete from database
    db.delete(doc)
    db.commit()
    
    return {"status": "success", "message": f"Document '{doc.name}' deleted"}
