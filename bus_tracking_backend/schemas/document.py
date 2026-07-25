from pydantic import BaseModel
from datetime import datetime
from typing import Optional

class DocumentBase(BaseModel):
    name: str
    description: Optional[str] = None

class DocumentCreate(DocumentBase):
    pass

class DocumentResponse(DocumentBase):
    id: int
    file_path: str
    file_size: int = 0
    file_type: str = "file"
    category: str = "general"
    uploaded_by_id: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True