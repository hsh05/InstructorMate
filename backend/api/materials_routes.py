# backend/api/materials_routes.py

import uuid
import urllib.parse
import logging
from firebase_admin import storage

from fastapi import APIRouter, Depends, File, UploadFile, HTTPException
from sqlalchemy.orm import Session

from db.database import get_db
from db import models
import schemas

logger = logging.getLogger(__name__)

# Initialize the router
router = APIRouter(tags=["Materials"])

@router.post("/workspaces/{workspace_id}/materials/", response_model=schemas.MaterialResponse)
async def upload_material(
    workspace_id: int,
    file: UploadFile = File(...),   
    db: Session = Depends(get_db)
):
    workspace = db.query(models.Workspace).filter(models.Workspace.workspace_id == workspace_id).first()
    if not workspace:
        raise HTTPException(status_code=404, detail="Workspace not found")

    try:
        bucket = storage.bucket()
        unique_filename = f"workspaces/{workspace_id}/{uuid.uuid4()}_{file.filename}"
        blob = bucket.blob(unique_filename)
        
        contents = await file.read()
        blob.upload_from_string(contents, content_type=file.content_type)
        
        download_token = str(uuid.uuid4())
        blob.metadata = {"firebaseStorageDownloadTokens": download_token}
        blob.patch() 
        
        encoded_path = urllib.parse.quote(unique_filename, safe='')
        file_url = f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{encoded_path}?alt=media&token={download_token}"

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to upload to Firebase: {str(e)}")

    ext = file.filename.split('.')[-1].lower() if '.' in file.filename else "unknown"

    db_material = models.Material(
        workspace_id=workspace_id,
        file_name=file.filename,
        file_path=file_url,
        material_type=ext
    )
    db.add(db_material)
    db.commit()
    
    return db_material


@router.delete("/materials/{material_id}")
async def delete_workspace_material(material_id: int, db: Session = Depends(get_db)):
    material = db.query(models.Material).filter(models.Material.material_id == material_id).first()
    if not material:
        raise HTTPException(status_code=404, detail="Material not found")

    try:
        blob_name_encoded = material.file_path.split('/o/')[1].split('?')[0]
        blob_name = urllib.parse.unquote(blob_name_encoded)
        
        bucket = storage.bucket()
        blob = bucket.blob(blob_name)
        if blob.exists():
            blob.delete()
    except Exception as e:
        logger.warning(f"Failed to delete file from Firebase (might already be missing): {e}")

    db.delete(material)
    db.commit()

    return {"message": "Material deleted successfully"}