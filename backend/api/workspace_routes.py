from fastapi import APIRouter, UploadFile, File, HTTPException
from pydantic import BaseModel

from services.workspace_service import WorkspaceService
from services.pdf_hash_service import PdfHashService
from services.file_parser_service import FileParserService
from services.extraction_service import ExtractionService
from repositories.csv_workspace_repository import CsvWorkspaceRepository

from ask_syllabus import (
    SyllabusCsvStore,
    LightweightRetriever,
    SyllabusChatGPT,
    AskPipeline,
)

router = APIRouter()

repo = CsvWorkspaceRepository()
parser = FileParserService()
extractor = ExtractionService()
hash_service = PdfHashService()
service = WorkspaceService(repo, parser, extractor, hash_service)


# -----------------------------
# Models
# -----------------------------

class AskRequest(BaseModel):
    question: str


class UpdateFieldsRequest(BaseModel):
    fields: dict


# -----------------------------
# Workspace CRUD
# -----------------------------

@router.get("/workspaces")
def list_workspaces():
    workspaces = repo.list_all()
    return [ws.to_dict() for ws in workspaces]


@router.get("/workspaces/{workspace_id}")
def get_workspace(workspace_id: str):
    ws = repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")
    return ws


@router.patch("/workspaces/{workspace_id}")
def update_workspace(workspace_id: str, data: UpdateFieldsRequest):
    ws = repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")

    ws.update_fields(data.fields)
    repo.save(ws)
    return ws


# -----------------------------
# Import Syllabus (MATCHES FLUTTER)
# -----------------------------

@router.post("/workspaces/import")
async def import_workspace(file: UploadFile = File(...)):
    content = await file.read()

    result = service.create_from_file(file.filename, content)
    ws = result["workspace"]

    return {
        "workspace": ws,
        "alreadyUploaded": result["already_uploaded"],
    }


# -----------------------------
# Ask Question
# -----------------------------

@router.post("/workspaces/{workspace_id}/ask")
async def ask_workspace_question(workspace_id: str, req: AskRequest):
    ws = repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")

    chunks_path = repo.get_chunks_csv_path(workspace_id)

    pipeline = AskPipeline(
        store=SyllabusCsvStore(chunks_path),
        retriever=LightweightRetriever(),
        llm=SyllabusChatGPT(),
    )

    answer = pipeline.run(req.question)

    return {"answer": answer}
