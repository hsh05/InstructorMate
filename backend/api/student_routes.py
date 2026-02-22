# backend/api/student_routes.py

from fastapi import APIRouter, UploadFile, File, HTTPException

from repositories.csv_workspace_repository import CsvWorkspaceRepository
from repositories.csv_student_repository import CsvStudentRepository
from services.student_service import StudentService

router = APIRouter()

# ---- Shared Workspace Repository ----
workspace_repo = CsvWorkspaceRepository()

# ---- Student Layer ----
student_repo = CsvStudentRepository(workspace_repo)
student_service = StudentService(student_repo)


@router.post("/workspaces/{workspace_id}/students/import")
async def import_students(workspace_id: str, file: UploadFile = File(...)):
    content = await file.read()

    try:
        students = student_service.import_students(workspace_id, content)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Workspace not found")

    return {
        "workspaceId": workspace_id,
        "imported": len(students),
    }