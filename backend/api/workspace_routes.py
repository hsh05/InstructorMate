# backend/api/workspace_routes.py

import logging
import uuid
import urllib.parse
from firebase_admin import storage

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlalchemy.orm import Session

from db.database import get_db
from repositories.pg_workspace_repository import PgWorkspaceRepository
from repositories.pg_section_repository import PgSectionRepository
from repositories.pg_student_repository import PgStudentRepository
from services.file_hash_service import FileHashService
from services.workspace_service import WorkspaceService
from ask_syllabus import AskPipeline, EmbeddingRetriever, LightweightRetriever, SyllabusChatGPT, SyllabusCsvStore, SyllabusListStore

logger = logging.getLogger(__name__)
router = APIRouter()

_ALLOWED_SYLLABUS_EXTENSIONS = {".pdf", ".docx"}


# ── Pydantic models ───────────────────────────────────────────────────────────

# Maximum number of prior conversation turns sent to the LLM.
_MAX_HISTORY_TURNS = 6


class ChatTurn(BaseModel):
    role: str      # "user" or "assistant"
    content: str


class AskRequest(BaseModel):
    question: str
    # Last N turns of conversation history, oldest first.
    history: list[ChatTurn] = []


class UpdateFieldsRequest(BaseModel):
    fields: dict


# ── Dependency factories ──────────────────────────────────────────────────────

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


# ── Helper ────────────────────────────────────────────────────────────────────

def _ws_dict(workspace_id, ws, section_repo, student_repo) -> dict:
    d = ws.to_dict()
    sections = section_repo.list_by_workspace(workspace_id)
    for s in sections:
        s["students_count"] = student_repo.count_by_section(workspace_id, s["section_id"])
    d["sections"] = sections
    d["students_count"] = sum(s["students_count"] for s in sections)
    return d


def _mirror_course_name_fields(fields: dict) -> dict:
    """Keep course_name and course_title in sync."""
    fields = dict(fields)
    if fields.get("course_name"):
        fields["course_title"] = fields["course_name"]
    elif fields.get("course_title"):
        fields["course_name"] = fields["course_title"]
    return fields


# ── Routes ────────────────────────────────────────────────────────────────────

@router.get("/workspaces")
def list_workspaces(
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:   PgSectionRepository   = Depends(get_section_repo),
    student_repo:   PgStudentRepository   = Depends(get_student_repo),
):
    return {
        "workspaces": [
            _ws_dict(ws.workspace_id, ws, section_repo, student_repo)
            for ws in workspace_repo.list_all()
        ]
    }


@router.post("/workspaces/upload")
async def import_workspace(
    file: UploadFile = File(...),
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

    content = await file.read()
    result  = workspace_service.create_from_file(filename, content)
    ws      = result["workspace"]
    
    # 👉 1. FIREBASE UPLOAD: Push the file to the Cloud!
    firebase_url = ws.workspace_id # Fallback just in case Firebase fails
    if not result["already_uploaded"]:
        try:
            bucket = storage.bucket()
            # Create a dedicated folder named after the workspace ID
            blob_path = f"workspaces/{ws.workspace_id}/{filename}"
            blob = bucket.blob(blob_path)
            
            # Upload the raw bytes to Google's servers
            blob.upload_from_string(content, content_type=file.content_type)
            
            # Generate the permanent download token
            download_token = str(uuid.uuid4())
            blob.metadata = {"firebaseStorageDownloadTokens": download_token}
            blob.patch()
            
            # Construct the official Firebase URL
            encoded_path = urllib.parse.quote(blob_path, safe='')
            firebase_url = f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{encoded_path}?alt=media&token={download_token}"
            
            logger.info(f"☁️ Firebase Success: Uploaded to {blob_path}")
        except Exception as e:
            logger.error(f"Firebase upload failed: {e}")

    # 👉 2. THE COMPLETE BRIDGE: Create Course AND Material
    if not result["already_uploaded"]:
        try:
            from models import Course, Material 
            
            # A. Create the Course
            new_course = Course(
                title=filename,
                description="Auto-generated from Workspace upload" 
            )
            db.add(new_course)
            db.commit()
            db.refresh(new_course) 
            
            # B. Create the Material with the REAL FIREBASE URL
            new_material = Material(
                course_id=new_course.id,  
                file_name=filename,
                file_path=firebase_url, # 👈 Saving the Cloud Link here!
                material_type="Syllabus"
            )
            db.add(new_material)
            db.commit()
            
            logger.info(f"🔗 Bridge Success: Created Course '{filename}' with Firebase Material")
            
        except Exception as e:
            logger.error(f"Failed to create equivalent Course/Material: {e}")
            db.rollback() 

    logger.info("Workspace uploaded id=%s already_uploaded=%s ext=%s",
                ws.workspace_id, result["already_uploaded"], ext)
    return {
        "workspace":        _ws_dict(ws.workspace_id, ws, section_repo, student_repo),
        "already_uploaded": result["already_uploaded"],
    }

@router.get("/workspaces/{workspace_id}")
def get_workspace(
    workspace_id: str,
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:   PgSectionRepository   = Depends(get_section_repo),
    student_repo:   PgStudentRepository   = Depends(get_student_repo),
):
    ws = workspace_repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")
    d = _ws_dict(workspace_id, ws, section_repo, student_repo)
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
    ws = workspace_repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")
        
    # Grab the old name before we overwrite it
    old_title = ws.fields.get("course_title") or ws.fields.get("course_name") or ""

    mirrored_fields = _mirror_course_name_fields(data.fields)
    ws.update_fields(mirrored_fields)
    workspace_repo.save(ws)
    
    # THE BRIDGE: Rename the Course so Flutter can still match them!
    new_title = mirrored_fields.get("course_title") or mirrored_fields.get("course_name")
    if new_title and old_title and new_title != old_title:
        try:
            from models import Course
            # Find the old course by its previous name and update it
            course_to_update = db.query(Course).filter(Course.title == old_title).first()
            if course_to_update:
                course_to_update.title = new_title
                db.commit()
                logger.info(f"🔗 Bridge Success: Renamed old Course to '{new_title}'")
        except Exception as e:
            logger.error(f"Failed to rename equivalent Course: {e}")

    logger.info("Updated workspace id=%s", workspace_id)
    return {"workspace": _ws_dict(workspace_id, ws, section_repo, student_repo)}


@router.delete("/workspaces/{workspace_id}")
def delete_workspace(
    workspace_id: str,
    workspace_repo:    PgWorkspaceRepository = Depends(get_workspace_repo),
    workspace_service: WorkspaceService       = Depends(get_workspace_service),
    db: Session = Depends(get_db), # 👉 1. ADD THE DATABASE CONNECTION
):
    # Cancel any in-flight background extraction first so the thread doesn't
    # try to write to a row that no longer exists (prevents cascade errors).
    workspace_service.cancel_if_in_flight(workspace_id)

    try:
        deleted = workspace_repo.delete(workspace_id)
    except Exception as exc:
        logger.error("Delete failed for workspace=%s: %s", workspace_id, exc, exc_info=True)
        raise HTTPException(status_code=500, detail=f"Delete failed: {exc}")

    if not deleted:
        raise HTTPException(status_code=404, detail="Workspace not found")

    # 👉 2. THE DELETION BRIDGE: Clean up the old database!
    try:
        from models import Course, Material
        
        # Find the material that holds this exact workspace_id 
        linked_material = db.query(Material).filter(Material.file_path == workspace_id).first()
        
        if linked_material:
            course_id_to_delete = linked_material.course_id
            
            # Step A: Delete the materials first (prevents Foreign Key crash)
            db.query(Material).filter(Material.course_id == course_id_to_delete).delete()
            
            # Step B: Delete the empty Course folder
            db.query(Course).filter(Course.id == course_id_to_delete).delete()
            
            db.commit()
            logger.info(f"🔗 Bridge Success: Deleted old Course (ID: {course_id_to_delete}) and its Materials")
    except Exception as e:
        logger.error(f"Failed to delete equivalent Course/Material: {e}")
        db.rollback() # Safety net

    logger.info("Deleted workspace id=%s", workspace_id)
    return {"deleted": True}


@router.post("/workspaces/{workspace_id}/ask")
async def ask_workspace_question(
    workspace_id: str,
    req: AskRequest,
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
):
    ws = workspace_repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")

    chunks_from_db = workspace_repo.get_chunks_for_ask(workspace_id)

    if chunks_from_db:
        # Preferred path: chunks in DB — pure memory, no disk I/O.
        store = SyllabusListStore(chunks_from_db)
        # Use semantic retrieval. EmbeddingRetriever automatically falls back
        # to LightweightRetriever for legacy chunks that have no embedding yet.
        retriever = EmbeddingRetriever(top_k=8)
    else:
        # Fallback: legacy workspace whose chunks only exist on disk.
        chunks_csv = workspace_repo.get_chunks_csv_path(workspace_id)
        if not chunks_csv.exists():
            raise HTTPException(
                status_code=422,
                detail="Syllabus chunks not found. Re-upload the file to regenerate them.",
            )
        store = SyllabusCsvStore(str(chunks_csv))
        retriever = LightweightRetriever(top_k=8)

    # Trim history to last _MAX_HISTORY_TURNS pairs to keep token usage bounded.
    raw_history = req.history[-(_MAX_HISTORY_TURNS * 2):]
    history = [{"role": t.role, "content": t.content} for t in raw_history] or None
    logger.info(">>> HISTORY LENGTH: %d", len(history) if history else 0)
    logger.info(">>> RAW QUESTION: %s", req.question)

    pipeline = AskPipeline(
        store=store,
        retriever=retriever,
        llm=SyllabusChatGPT(),
    )
    answer = pipeline.run(req.question, history=history)
    logger.info(">>> ANSWER: %s", answer[:100])
    return {"answer": answer}