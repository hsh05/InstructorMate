# backend/api/student_routes.py

import logging
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session
import hashlib

from db.database import get_db
from repositories.pg_workspace_repository import PgWorkspaceRepository
from repositories.pg_student_repository import PgStudentRepository
from services.student_service import StudentService
from repositories.pg_section_repository import PgSectionRepository

logger = logging.getLogger(__name__)
router = APIRouter()

_ALLOWED_MIME_TYPES = {
    "text/csv",
    "application/csv",
    "text/plain",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/octet-stream",
}

_ALLOWED_EXTENSIONS = {".csv", ".xlsx", ".xls"}


# ── Dependency factories ──────────────────────────────────────────────────────

def get_workspace_repo(db: Session = Depends(get_db)) -> PgWorkspaceRepository:
    return PgWorkspaceRepository(db)


def get_student_repo(
    db: Session = Depends(get_db),
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
) -> PgStudentRepository:
    return PgStudentRepository(db, workspace_repo)


def get_student_service(
    student_repo: PgStudentRepository = Depends(get_student_repo),
) -> StudentService:
    return StudentService(student_repo)

def get_section_repo(
    db: Session = Depends(get_db),
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
) -> PgSectionRepository:
    return PgSectionRepository(db, workspace_repo)


# ── Routes (unchanged) ────────────────────────────────────────────────────────

@router.post("/workspaces/{workspace_id}/students/import")
async def import_students(
    workspace_id: str,
    file: UploadFile = File(...),
    section_id: Optional[str] = Form(None),
    service: StudentService = Depends(get_student_service),
    section_repo: PgSectionRepository = Depends(get_section_repo),
):
    filename = file.filename or ""
    ext = "." + filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    if ext not in _ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=415,
            detail=f"Unsupported file type '{ext}'. Allowed: {sorted(_ALLOWED_EXTENSIONS)}",
        )

    content = await file.read()
      # Compute SHA-256 hash of uploaded file
    file_hash = hashlib.sha256(content).hexdigest()
    try:
        students = service.import_students(
            workspace_id, content, filename,
            section_id=section_id or "",
        )
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Workspace not found")
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    
      # Store hash so Flutter can detect same-file re-uploads
    if section_id:
        section_repo.update_import_hash(section_id, file_hash)

    logger.info(
        "Imported %d students into workspace=%s section=%s",
        len(students), workspace_id, section_id or "",
    )
    return {
        "workspaceId": workspace_id,
        "section_id":  section_id or "",
        "imported":    len(students),
        "file_hash":   file_hash,   # ← return it so Flutter can cache it
    }


@router.get("/workspaces/{workspace_id}/sections/{section_id}/students")
def list_section_students(
    workspace_id: str,
    section_id: str,
    repo: PgStudentRepository = Depends(get_student_repo),
):
    students = repo.list_by_section(workspace_id, section_id)
    return {"students": students, "count": len(students)}


@router.delete("/workspaces/{workspace_id}/sections/{section_id}/students")
def clear_section_students(
    workspace_id: str,
    section_id: str,
    repo: PgStudentRepository = Depends(get_student_repo),
):
    """Remove all students from a section (clears StudentSection links
    and orphaned Student rows with no other section links)."""
    count = repo.clear_section(workspace_id, section_id)
    logger.info("Cleared %d students from section=%s workspace=%s",
                count, section_id, workspace_id)
    return {"deleted": count, "section_id": section_id}


@router.delete("/workspaces/{workspace_id}/sections/{section_id}/students/{student_id}")
def delete_student(
    workspace_id: str,
    section_id: str,
    student_id: str,
    repo: PgStudentRepository = Depends(get_student_repo),
):
    deleted = repo.delete_student(workspace_id, section_id, student_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Student not found in this section")
    logger.info("Deleted student id=%s from section=%s workspace=%s",
                student_id, section_id, workspace_id)
    return {"deleted": True, "student_id": student_id}