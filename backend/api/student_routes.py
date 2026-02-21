from fastapi import APIRouter, UploadFile, File
from services.student_service import StudentService
from repositories.csv_student_repository import CsvStudentRepository
from repositories.csv_workspace_repository import CsvWorkspaceRepository

router = APIRouter()#It lets us create API routes (URLs).              #SRP --> Import students into a workspace from a CSV file.

# inject workspace repository FIRST
ws_repo = CsvWorkspaceRepository()

# pass ws_repo into student repository
repo = CsvStudentRepository(ws_repo)

service = StudentService(repo)# So student repository needs: Workspace location, Workspace validation, Give student repository access to workspace repository.”


@router.post("/workspaces/{workspace_id}/students/import")
async def import_students(workspace_id: str, file: UploadFile = File(...)): #async allows the server to handle other requests while waiting.
    content = await file.read() #read and save info in file 
    students = service.import_students(workspace_id, content)
    return {"imported": len(students)}
