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

from ask_syllabus import SyllabusCsvStore, LightweightRetriever, SyllabusChatGPT, AskPipeline

router = APIRouter()

workspace_repo  = CsvWorkspaceRepository()
student_repo    = CsvStudentRepository(workspace_repo)
section_repo    = CsvSectionRepository(workspace_repo)

parser           = FileParserService()
extractor        = ExtractionService()
hash_service     = PdfHashService()
workspace_service = WorkspaceService(workspace_repo, parser, extractor, hash_service)


class AskRequest(BaseModel):
    question: str

class UpdateFieldsRequest(BaseModel):
    fields: dict


def _ws_dict(workspace_id: str, ws) -> dict:
    d = ws.to_dict()
    sections = section_repo.list_by_workspace(workspace_id)
    # Inject per-section student count
    for s in sections:
        s["students_count"] = student_repo.count_by_section(workspace_id, s["section_id"])
    d["sections"] = sections
    d["students_count"] = sum(s["students_count"] for s in sections)
    return d


@router.get("/workspaces")
def list_workspaces():
    return {"workspaces": [_ws_dict(ws.workspace_id, ws) for ws in workspace_repo.list_all()]}


@router.post("/workspaces/upload")
async def import_workspace(file: UploadFile = File(...)):
    content = await file.read()
    result  = workspace_service.create_from_file(file.filename, content)
    ws      = result["workspace"]
    return {"workspace": _ws_dict(ws.workspace_id, ws), "alreadyUploaded": result["already_uploaded"]}


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


@router.delete("/workspaces/{workspace_id}")
def delete_workspace(workspace_id: str):
    deleted = workspace_repo.delete(workspace_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Workspace not found")
    return {"deleted": True}


@router.post("/workspaces/{workspace_id}/ask")
async def ask_workspace_question(workspace_id: str, req: AskRequest):
    ws = workspace_repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")
    chunks_path = workspace_repo.get_chunks_csv_path(workspace_id)
    if not chunks_path.exists():
        raise HTTPException(status_code=422,
            detail="Syllabus chunks not found. Re-upload the PDF to regenerate them.")
    pipeline = AskPipeline(
        store=SyllabusCsvStore(str(chunks_path)),
        retriever=LightweightRetriever(),
        llm=SyllabusChatGPT(),
    )
    return {"answer": pipeline.run(req.question)}


@router.post("/workspaces/{workspace_id}/reupload")
async def reupload_syllabus(workspace_id: str, file: UploadFile = File(...)):
    ws = workspace_repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")
    content = await file.read()
    try:
        workspace_service.reprocess_pdf(workspace_id, content)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to process PDF: {e}")
    return {"workspace": _ws_dict(workspace_id, workspace_repo.get_by_id(workspace_id))}


@router.delete("/workspaces/{workspace_id}/sections/{section_id}")
def delete_section(workspace_id: str, section_id: str):
    if not workspace_repo.get_by_id(workspace_id):
        raise HTTPException(status_code=404, detail="Workspace not found")
    if not section_repo.delete(workspace_id, section_id):
        raise HTTPException(status_code=404, detail="Section not found")
    ws = workspace_repo.get_by_id(workspace_id)
    return {"workspace": _ws_dict(workspace_id, ws)}