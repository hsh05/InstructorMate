# backend/api/workspace_routes.py

from fastapi import APIRouter, UploadFile, File, HTTPException
from pydantic import BaseModel

from services.workspace_service import WorkspaceService
from services.pdf_hash_service import PdfHashService
from services.file_parser_service import FileParserService
from services.extraction_service import ExtractionService
from repositories.csv_workspace_repository import CsvWorkspaceRepository
from repositories.csv_student_repository import CsvStudentRepository
from repositories.csv_section_repository import CsvSectionRepository

from ask_syllabus import (
    SyllabusCsvStore,
    LightweightRetriever,
    SyllabusChatGPT,
    AskPipeline,
)

router = APIRouter()

# ---- Shared Repositories ----
workspace_repo = CsvWorkspaceRepository()
student_repo   = CsvStudentRepository(workspace_repo)
section_repo   = CsvSectionRepository(workspace_repo)

# ---- Services ----
parser           = FileParserService()
extractor        = ExtractionService()
hash_service     = PdfHashService()
workspace_service = WorkspaceService(workspace_repo, parser, extractor, hash_service)

# -----------------------------
# Request Models
# -----------------------------

class AskRequest(BaseModel):
    question: str

class UpdateFieldsRequest(BaseModel):
    fields: dict

# -----------------------------
# Helper: full workspace dict with real sections + student count
# -----------------------------

def _ws_dict(workspace_id: str, ws) -> dict:
    d = ws.to_dict()
    # FIX BUG 1: inject real sections from CSV (to_dict() always returned [])
    d["sections"]       = section_repo.list_by_workspace(workspace_id)
    # inject real student count too
    d["students_count"] = len(student_repo.list_by_workspace(workspace_id))
    return d

# -----------------------------
# Workspace CRUD
# -----------------------------

@router.get("/workspaces")
def list_workspaces():
    workspaces = workspace_repo.list_all()
    return {"workspaces": [_ws_dict(ws.workspace_id, ws) for ws in workspaces]}


@router.post("/workspaces/upload")
async def import_workspace(file: UploadFile = File(...)):
    content = await file.read()
    result  = workspace_service.create_from_file(file.filename, content)
    ws      = result["workspace"]
    return {
        "workspace":     _ws_dict(ws.workspace_id, ws),
        "alreadyUploaded": result["already_uploaded"],
    }


@router.get("/workspaces/{workspace_id}")
def get_workspace(workspace_id: str):
    ws = workspace_repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")
    return {"workspace": _ws_dict(workspace_id, ws)}


@router.patch("/workspaces/{workspace_id}")
def update_workspace(workspace_id: str, data: UpdateFieldsRequest):
    ws = workspace_repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")
    ws.update_fields(data.fields)
    workspace_repo.save(ws)
    return {"workspace": _ws_dict(workspace_id, ws)}


# -----------------------------
# Ask Question
# -----------------------------

@router.post("/workspaces/{workspace_id}/ask")
async def ask_workspace_question(workspace_id: str, req: AskRequest):
    ws = workspace_repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")

    chunks_path = workspace_repo.get_chunks_csv_path(workspace_id)

    # FIX BUG 2: give a clear error if chunks.csv doesn't exist yet
    # (means workspace was created before converter ran, or converter failed)
    if not chunks_path.exists():
        raise HTTPException(
            status_code=422,
            detail="Syllabus chunks not found. Re-upload the PDF to regenerate them."
        )

    pipeline = AskPipeline(
        store=SyllabusCsvStore(str(chunks_path)),
        retriever=LightweightRetriever(),
        llm=SyllabusChatGPT(),
    )

    answer = pipeline.run(req.question)
    return {"answer": answer}