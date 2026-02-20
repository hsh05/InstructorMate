from fastapi import APIRouter, UploadFile, File
from services.student_service import StudentService
from repositories.csv_student_repository import CsvStudentRepository
from repositories.csv_workspace_repository import CsvWorkspaceRepository

router = APIRouter()

# inject workspace repository FIRST
ws_repo = CsvWorkspaceRepository()

# pass ws_repo into student repository
repo = CsvStudentRepository(ws_repo)

service = StudentService(repo)



@router.post("/workspaces/{workspace_id}/students/import")
async def import_students(workspace_id: str, file: UploadFile = File(...)):
    content = await file.read()
    students = service.import_students(workspace_id, content)
    return {"imported": len(students)}
