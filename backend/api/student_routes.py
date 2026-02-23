from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from typing import Optional

from repositories.csv_workspace_repository import CsvWorkspaceRepository
from repositories.csv_student_repository import CsvStudentRepository
from services.student_service import StudentService

router = APIRouter()

workspace_repo = CsvWorkspaceRepository()
student_repo   = CsvStudentRepository(workspace_repo)
student_service = StudentService(student_repo)


@router.post("/workspaces/{workspace_id}/students/import")
async def import_students(
    workspace_id: str,
    file: UploadFile = File(...),
    section_id: Optional[str] = Form(None),
):
    content = await file.read()
    try:
        students = student_service.import_students(
            workspace_id, content, file.filename,
            section_id=section_id or ""
        )
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Workspace not found")

    return {
        "workspaceId": workspace_id,
        "section_id": section_id or "",
        "imported": len(students),
    }


@router.get("/workspaces/{workspace_id}/sections/{section_id}/students")
def list_section_students(workspace_id: str, section_id: str):
    students = student_repo.list_by_section(workspace_id, section_id)
    return {"students": students, "count": len(students)}