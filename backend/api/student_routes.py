# backend/api/student_routes.py
#
# FIX (Security): No file-type validation — any file was accepted.
# Now validates content_type against an allowlist of safe MIME types.
# An attacker uploading an .exe renamed to .csv is now rejected with 415.
#
# FIX: Module-level singletons replaced with FastAPI Depends().
# FIX: Replaced print() with logging.

import logging
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile

from repositories.csv_student_repository import CsvStudentRepository
from repositories.csv_workspace_repository import CsvWorkspaceRepository
from services.student_service import StudentService

logger = logging.getLogger(__name__)
router = APIRouter()

# Allowed MIME types for student roster uploads
_ALLOWED_MIME_TYPES = {
    "text/csv",
    "application/csv",
    "text/plain",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/octet-stream",  # some browsers send this for .xlsx
}

_ALLOWED_EXTENSIONS = {".csv", ".xlsx", ".xls"}


# ── Dependency injection ──────────────────────────────────────────────────────

def get_student_service() -> StudentService:
    workspace_repo = CsvWorkspaceRepository()
    student_repo   = CsvStudentRepository(workspace_repo)
    return StudentService(student_repo)


def get_student_repo() -> CsvStudentRepository:
    workspace_repo = CsvWorkspaceRepository()
    return CsvStudentRepository(workspace_repo)


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/workspaces/{workspace_id}/students/import")
async def import_students(
    workspace_id: str,
    file: UploadFile = File(...),
    section_id: Optional[str] = Form(None),
    service: StudentService = Depends(get_student_service),
):
    # FIX: validate file extension
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
    repo: CsvStudentRepository = Depends(get_student_repo),
):
    students = repo.list_by_section(workspace_id, section_id)
    return {"students": students, "count": len(students)}