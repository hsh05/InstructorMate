# backend/api/student_routes.py

import logging
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from db.database import get_db
from repositories.pg_workspace_repository import PgWorkspaceRepository
from repositories.pg_student_repository import PgStudentRepository
from services.student_service import StudentService

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


# ── Routes (unchanged) ────────────────────────────────────────────────────────

@router.post("/workspaces/{workspace_id}/students/import")
async def import_students(
    workspace_id: str,
    file: UploadFile = File(...),
    section_id: Optional[str] = Form(None),
    service: StudentService = Depends(get_student_service),
):
    filename = file.filename or ""
    ext = "." + filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    if ext not in _ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=415,
            detail=f"Unsupported file type '{ext}'. Allowed: {sorted(_ALLOWED_EXTENSIONS)}",
        )

    content = await file.read()
    try:
        students = service.import_students(
            workspace_id, content, filename,
            section_id=section_id or "",
        )
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Workspace not found")
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

    logger.info(
        "Imported %d students into workspace=%s section=%s",
        len(students), workspace_id, section_id or "",
    )
    return {
        "workspaceId": workspace_id,
        "section_id":  section_id or "",
        "imported":    len(students),
    }


@router.get("/workspaces/{workspace_id}/sections/{section_id}/students")
def list_section_students(
    workspace_id: str,
    section_id: str,
    repo: PgStudentRepository = Depends(get_student_repo),
):
    students = repo.list_by_section(workspace_id, section_id)
    return {"students": students, "count": len(students)}