# backend/api/workspace_routes.py

import logging
import uuid
import urllib.parse
from firebase_admin import storage

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime

from db.database import get_db
from db.models import Workspace as DBWorkspace
from db import models

# 👉 THE FIX: Pointing all repositories to our new unified pg_repository!
from repositories.pg_repository import (
    PgWorkspaceRepository, 
    PgSectionRepository, 
    PgStudentRepository
)

# 👉 THE FIX: Pointing to the new unified service files!
from services.file_service import FileHashService
from services.app_service import WorkspaceService
from services.ai_service import (
    AskPipeline, 
    EmbeddingRetriever, 
    LightweightRetriever, 
    SyllabusChatGPT, 
    SyllabusCsvStore, 
    SyllabusListStore
)

logger = logging.getLogger(__name__)
router = APIRouter()

_ALLOWED_SYLLABUS_EXTENSIONS = {".pdf", ".docx"}
_MAX_HISTORY_TURNS = 6


class ChatTurn(BaseModel):
    role: str      
    content: str

class AskRequest(BaseModel):
    question: str
    history: list[ChatTurn] = []

class UpdateFieldsRequest(BaseModel):
    fields: dict


def get_workspace_repo(db: Session = Depends(get_db)) -> PgWorkspaceRepository:
    return PgWorkspaceRepository(db)

def get_section_repo(
    db: Session = Depends(get_db),
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
) -> PgSectionRepository:
    return PgSectionRepository(db, workspace_repo)

def get_student_repo(
    db: Session = Depends(get_db),
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
) -> PgStudentRepository:
    return PgStudentRepository(db, workspace_repo)

def get_workspace_service(
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
) -> WorkspaceService:
    return WorkspaceService(
        repo         = workspace_repo,
        hash_service = FileHashService(),
    )


def _ws_dict(workspace_id, ws, section_repo, student_repo, db: Session) -> dict:
    d = ws.to_dict()
    
    # 👉 THE FIX: Safely convert string ID to int for DB operations
    ws_id_int = int(workspace_id)
    
    sections = section_repo.list_by_workspace(ws_id_int)
    for s in sections:
        s["students_count"] = student_repo.count_by_section(ws_id_int, s["section_id"])
    d["sections"] = sections
    d["students_count"] = sum(s["students_count"] for s in sections)
    
    try:
        db_ws = db.query(models.Workspace).filter(models.Workspace.workspace_id == ws_id_int).first()
        if db_ws:
            d["start_date"] = str(db_ws.start_date) if db_ws.start_date else ""
            d["end_date"] = str(db_ws.end_date) if db_ws.end_date else ""
        else:
            d["start_date"] = ""
            d["end_date"] = ""

        # Fetch Materials for this workspace and attach them!
        materials = db.query(models.Material).filter(models.Material.workspace_id == ws_id_int).all()
        d["materials"] = [
            {
                "material_id": m.material_id,
                "workspace_id": m.workspace_id,
                "file_name": m.file_name,
                "file_path": m.file_path,
                "material_type": m.material_type
            } for m in materials
        ]
    except ValueError:
        d["materials"] = []
        d["start_date"] = ""
        d["end_date"] = ""
        
    return d

def _mirror_workspace_name_fields(fields: dict) -> dict:
    fields = dict(fields)
    if fields.get("workspace_name"):
        fields["workspace_title"] = fields["workspace_name"]
    elif fields.get("workspace_title"):
        fields["workspace_name"] = fields["workspace_title"]
    return fields


@router.get("/workspaces")
def list_workspaces(
    instructor_id: str,
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:   PgSectionRepository   = Depends(get_section_repo),
    student_repo:   PgStudentRepository   = Depends(get_student_repo),
    db: Session = Depends(get_db), 
):
    # 👉 1. Ask the database ONLY for the workspace IDs belonging to this instructor
    db_workspaces = db.query(models.Workspace.workspace_id).filter(
        models.Workspace.instructor_id == instructor_id
    ).all()
    
    # 👉 2. Use your repository to fetch the proper domain objects (which DO have .to_dict!)
    valid_workspaces = []
    for (wid,) in db_workspaces:
        domain_ws = workspace_repo.get_by_id(wid)
        if domain_ws:
            valid_workspaces.append(domain_ws)

    # 👉 3. Return them safely without crashing!
    return {
        "workspaces": [
            _ws_dict(ws.workspace_id, ws, section_repo, student_repo, db)
            for ws in valid_workspaces
        ]
    }


@router.post("/workspaces/upload")
async def import_workspace(
    file: UploadFile = File(...),
    instructor_id: str = Form(...),
    start_date: Optional[str] = Form(None),
    end_date: Optional[str] = Form(None),
    workspace_repo:    PgWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:      PgSectionRepository   = Depends(get_section_repo),
    student_repo:      PgStudentRepository   = Depends(get_student_repo),
    workspace_service: WorkspaceService      = Depends(get_workspace_service),
    db: Session = Depends(get_db), 
):
    filename = file.filename or ""
    ext = ("." + filename.rsplit(".", 1)[-1].lower()) if "." in filename else ""
    if ext not in _ALLOWED_SYLLABUS_EXTENSIONS:
        raise HTTPException(
            status_code=415,
            detail=f"Unsupported file type '{ext}'. Allowed: {sorted(_ALLOWED_SYLLABUS_EXTENSIONS)}",
        )

    # 1. Read the file and let the service do the initial creation
    content     = await file.read()
    result      = workspace_service.create_from_file(filename, content)
    domain_ws   = result["workspace"]

    ws_id_int = int(domain_ws.workspace_id)
    db_ws = db.query(DBWorkspace).filter(DBWorkspace.workspace_id == ws_id_int).first()

    # 3. Safely parse and assign the dates to the DB record
    if db_ws:
        try:
            db_ws.instructor_id = instructor_id

            if start_date and start_date.strip():
                db_ws.start_date = datetime.strptime(start_date.split('T')[0], "%Y-%m-%d").date()
            if end_date and end_date.strip():
                db_ws.end_date = datetime.strptime(end_date.split('T')[0], "%Y-%m-%d").date()
            
            db.commit() 
            db.refresh(db_ws)
        except Exception as e:
            logger.error(f"Date parsing failed: {e}")
    else:
        logger.warning(f"Could not find DB record to update dates for workspace {ws_id_int}")
    
    # 4. FIREBASE UPLOAD ONLY 
    if not result["already_uploaded"]:
        try:
            bucket = storage.bucket()
            blob_path = f"workspaces/{ws_id_int}/{filename}"
            blob = bucket.blob(blob_path)
            
            blob.upload_from_string(content, content_type=file.content_type)
            
            download_token = str(uuid.uuid4())
            blob.metadata = {"firebaseStorageDownloadTokens": download_token}
            blob.patch()
            
            logger.info(f"☁️ Firebase Success: Uploaded to {blob_path}")
        except Exception as e:
            logger.error(f"Firebase upload failed: {e}")

    logger.info("Workspace uploaded id=%s already_uploaded=%s ext=%s",
                ws_id_int, result["already_uploaded"], ext)
    
    return {
        "workspace":        _ws_dict(domain_ws.workspace_id, domain_ws, section_repo, student_repo, db), 
        "already_uploaded": result["already_uploaded"],
    }


@router.get("/workspaces/{workspace_id}")
def get_workspace(
    workspace_id: str,
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:   PgSectionRepository   = Depends(get_section_repo),
    student_repo:   PgStudentRepository   = Depends(get_student_repo),
    db: Session = Depends(get_db), 
):
    # 👉 THE FIX: Parse as int for repository
    ws = workspace_repo.get_by_id(int(workspace_id))
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")
    d = _ws_dict(workspace_id, ws, section_repo, student_repo, db) 
    return {"workspace": d}


@router.patch("/workspaces/{workspace_id}")
def update_workspace(
    workspace_id: str,
    data: UpdateFieldsRequest,
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:   PgSectionRepository   = Depends(get_section_repo),
    student_repo:   PgStudentRepository   = Depends(get_student_repo),
    db: Session = Depends(get_db), 
):
    ws_id_int = int(workspace_id)
    ws = workspace_repo.get_by_id(ws_id_int)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")

    incoming_fields = dict(data.fields)
    db_ws = db.query(DBWorkspace).filter(DBWorkspace.workspace_id == ws_id_int).first()
    
    if db_ws:
        try:
            if "start_date" in incoming_fields:
                start_str = incoming_fields.pop("start_date") 
                if start_str and start_str.strip():
                    db_ws.start_date = datetime.strptime(start_str.split('T')[0], "%Y-%m-%d").date()
                else:
                    db_ws.start_date = None
                    
            if "end_date" in incoming_fields:
                end_str = incoming_fields.pop("end_date")
                if end_str and end_str.strip():
                    db_ws.end_date = datetime.strptime(end_str.split('T')[0], "%Y-%m-%d").date()
                else:
                    db_ws.end_date = None
            
            db.commit()
            db.refresh(db_ws)
        except Exception as e:
            logger.error(f"Date parsing failed during update: {e}")

    mirrored_fields = _mirror_workspace_name_fields(incoming_fields)
    ws.update_fields(mirrored_fields)
    workspace_repo.save(ws)
    
    logger.info("Updated workspace id=%s", workspace_id)
    return {"workspace": _ws_dict(workspace_id, ws, section_repo, student_repo, db)}


@router.delete("/workspaces/{workspace_id}")
def delete_workspace(
    workspace_id: str,
    workspace_repo:    PgWorkspaceRepository = Depends(get_workspace_repo),
    workspace_service: WorkspaceService       = Depends(get_workspace_service),
    db: Session = Depends(get_db), 
):
    workspace_service.cancel_if_in_flight(workspace_id)

    try:
        # 👉 THE FIX: Parse as int
        deleted = workspace_repo.delete(int(workspace_id))
    except Exception as exc:
        logger.error("Delete failed for workspace=%s: %s", workspace_id, exc, exc_info=True)
        raise HTTPException(status_code=500, detail=f"Delete failed: {exc}")

    if not deleted:
        raise HTTPException(status_code=404, detail="Workspace not found")

    try:
        bucket = storage.bucket()
        blobs = bucket.list_blobs(prefix=f"workspaces/{workspace_id}/")
        
        deleted_count = 0
        for blob in blobs:
            blob.delete()
            deleted_count += 1
            
        if deleted_count > 0:
            logger.info(f"🗑️ Firebase Success: Purged {deleted_count} files from workspaces/{workspace_id}/")
    except Exception as e:
        logger.error(f"Firebase deletion failed for workspace {workspace_id}: {e}")

    logger.info("Deleted workspace id=%s", workspace_id)
    return {"deleted": True}


@router.post("/workspaces/{workspace_id}/ask")
async def ask_workspace_question(
    workspace_id: str,
    req: AskRequest,
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
):
    ws_id_int = int(workspace_id)
    ws = workspace_repo.get_by_id(ws_id_int)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")

    chunks_from_db = workspace_repo.get_chunks_for_ask(ws_id_int)

    if chunks_from_db:
        store = SyllabusListStore(chunks_from_db)
        retriever = EmbeddingRetriever(top_k=15)
    else:
        chunks_csv = workspace_repo.get_chunks_csv_path(ws_id_int)
        if not chunks_csv.exists():
            raise HTTPException(
                status_code=422,
                detail="Syllabus chunks not found. Re-upload the file to regenerate them.",
            )
        store = SyllabusCsvStore(str(chunks_csv))
        retriever = LightweightRetriever(top_k=15)

    raw_history = req.history[-(_MAX_HISTORY_TURNS * 2):]
    history = [{"role": t.role, "content": t.content} for t in raw_history] or None
    
    pipeline = AskPipeline(
        store=store,
        retriever=retriever,
        llm=SyllabusChatGPT(),
    )
    answer = pipeline.run(req.question, history=history)
    return {"answer": answer}