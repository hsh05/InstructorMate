from fastapi import FastAPI
from api.workspace_routes import router as workspace_router
from api.section_routes import router as section_router
from api.student_routes import router as student_router

app = FastAPI()

app.include_router(workspace_router)
app.include_router(section_router)
app.include_router(student_router)

from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # for development
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

from fastapi import FastAPI, UploadFile, File, HTTPException, APIRouter
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List

from repositories.csv_workspace_repository import CsvWorkspaceRepository
from repositories.csv_student_repository import CsvStudentRepository
from repositories.csv_section_repository import CsvSectionRepository

from services.workspace_service import WorkspaceService
from services.student_service import StudentService
from services.section_service import SectionService
from services.file_parser_service import FileParserService
from services.extraction_service import ExtractionService
from services.pdf_hash_service import PdfHashService

from domain.enums import WorkspaceStatus


# CORS (important for Flutter web)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# -----------------------------
# REPOSITORIES
# -----------------------------

workspace_repo = CsvWorkspaceRepository()
student_repo = CsvStudentRepository(workspace_repo)
section_repo = CsvSectionRepository(workspace_repo)

# -----------------------------
# SERVICES
# -----------------------------

workspace_service = WorkspaceService(
    repo=workspace_repo,
    parser=FileParserService(),
    extractor=ExtractionService(),
    hash_service=PdfHashService(),
)

student_service = StudentService(student_repo)
section_service = SectionService(section_repo)


# -----------------------------
# MODELS
# -----------------------------

class UpdateWorkspaceRequest(BaseModel):
    fields: dict


class AskRequest(BaseModel):
    question: str


# -----------------------------
# ROUTES
# -----------------------------

@app.post("/workspaces/upload")
async def upload_workspace(file: UploadFile = File(...)):
    content = await file.read()

    result = workspace_service.create_from_file(
        filename=file.filename,
        content=content
    )

    ws = result["workspace"]

    return {
        "workspace": ws.to_dict(),
        "already_uploaded": result["already_uploaded"]
    }


@app.get("/workspaces")
def list_workspaces():
    workspaces = workspace_repo.get_all()
    return [ws.to_summary_dict() for ws in workspaces]


@app.get("/workspaces/{workspace_id}")
def get_workspace(workspace_id: str):
    ws = workspace_repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")
    return ws.to_dict()


@app.patch("/workspaces/{workspace_id}")
def update_workspace(workspace_id: str, body: UpdateWorkspaceRequest):
    ws = workspace_service.update_workspace(workspace_id, body.fields)
    return ws.to_dict()


@app.post("/workspaces/{workspace_id}/ask")
def ask_workspace(workspace_id: str, body: AskRequest):
    ws = workspace_repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")

    # Simple AI integration (your extractor handles text)
    answer = workspace_service.extractor.answer_question(
        ws.fields,
        body.question
    )

    return {"answer": answer}


@app.post("/workspaces/{workspace_id}/sections")
def create_section(workspace_id: str, section_data: dict):
    ws = section_service.create_section(workspace_id, section_data)
    return ws.to_dict()


@app.post("/workspaces/{workspace_id}/students/import")
async def import_students(workspace_id: str, file: UploadFile = File(...)):
    content = await file.read()

    ws = student_service.import_students(workspace_id, content)
    return ws.to_dict()
