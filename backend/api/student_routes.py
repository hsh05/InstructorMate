# backend/api/student_routes.py

import io
import logging
import uuid
import hashlib
from typing import Optional

import pandas as pd
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import text

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


# ==============================================================================
# ── GLOBAL STUDENT ROUTES (Added from main.py merge) ──────────────────────────
# ==============================================================================

@router.post("/students/upload")
async def upload_global_students(file: UploadFile = File(...), db: Session = Depends(get_db)):
    """
    Upload a global master list of students to the university database.
    Replaces the old dbconn.py logic.
    """
    try:
        contents = await file.read()

        if file.filename.endswith(".csv"):
            df = pd.read_csv(io.BytesIO(contents))
        elif file.filename.endswith(".xlsx"):
            df = pd.read_excel(io.BytesIO(contents))
        else:
            raise HTTPException(status_code=400, detail="Unsupported file type")

        df.columns = [c.strip().lower() for c in df.columns]
        required_columns = ["student_id", "student_name", "campus_code"]

        for col in required_columns:
            if col not in df.columns:
                raise HTTPException(status_code=400, detail=f"Missing required column: {col}")

        inserted = 0

        for _, row in df.iterrows():
            student_id = str(row["student_id"]).strip()
            student_name = str(row["student_name"]).strip()
            # Note: We aren't currently storing campus_code in the ERD, but we can safely ignore it or add it later!

            if not student_id or not student_name:
                continue

            db.execute(
                text("""
                INSERT INTO students (student_id, name)
                VALUES (:id, :name)
                ON CONFLICT (student_id) DO NOTHING
                """),
                {"id": student_id, "name": student_name}
            )
            inserted += 1
            
        db.commit()

        return {
            "ok": True,
            "inserted": inserted,
            "columns_detected": {
                "student_id": "student_id",
                "student_name": "student_name",
                "campus_code": "campus_code",
            },
        }

    except Exception as e:
        db.rollback() 
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/students/")
def fetch_all_students(db: Session = Depends(get_db)):
    """
    Returns a list of all students in the global database.
    """
    try:
        result = db.execute(
            text("""
            SELECT student_id, name, encoding_json
            FROM students
            ORDER BY student_id
            """)
        )
        return [
            {"student_id": row.student_id, "name": row.name, "encoding_json": row.encoding_json}
            for row in result
        ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ==============================================================================
# ── SECTION-SPECIFIC ROUTES (Unchanged teammates logic) ───────────────────────
# ==============================================================================

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
        "file_hash":   file_hash, 
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

class AddStudentRequest(BaseModel):
    name:       str = ""
    email:      str = ""
    student_no: str = ""

@router.post("/workspaces/{workspace_id}/sections/{section_id}/students")
def add_student(
    workspace_id: str,
    section_id:   str,
    req:          AddStudentRequest,
    repo:         PgStudentRepository = Depends(get_student_repo),
):
    from domain.student import Student as DomainStudent
    if not req.name.strip() and not req.email.strip() and not req.student_no.strip():
        raise HTTPException(
            status_code=422,
            detail="At least one of name, email, or student number is required.",
        )

    # TODO FOR TEAMMATE: Update DomainStudent to match the new ERD! 
    # `student_id` should equal `req.student_no`, and `workspace_id` should be removed.
    student = DomainStudent(
        student_id   = req.student_no.strip() or str(uuid.uuid4()), # Patched to use their ID if provided
        workspace_id = workspace_id, 
        name         = req.name.strip(),
        email        = req.email.strip(),
        student_no   = req.student_no.strip(),
    )
    repo.save(student, section_id=section_id)
    
    logger.info(
        "Added student name=%s to workspace=%s section=%s",
        req.name, workspace_id, section_id,
    )
    students = repo.list_by_section(workspace_id, section_id)
    return {
        "student_id":  student.student_id,
        "section_id":  section_id,
        "count":       len(students),
    }