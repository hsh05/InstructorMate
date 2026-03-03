# backend/api/workspace_routes.py

import logging

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlalchemy.orm import Session

from db.database import get_db
from repositories.pg_workspace_repository import PgWorkspaceRepository
from repositories.pg_section_repository import PgSectionRepository
from repositories.pg_student_repository import PgStudentRepository
from services.extraction_service import ExtractionService
from services.file_parser_service import FileParserService
from services.pdf_hash_service import PdfHashService
from services.workspace_service import WorkspaceService
from ask_syllabus import AskPipeline, LightweightRetriever, SyllabusChatGPT, SyllabusCsvStore

logger = logging.getLogger(__name__)
router = APIRouter()


# ── Pydantic models ───────────────────────────────────────────────────────────

class AskRequest(BaseModel):
    question: str


class UpdateFieldsRequest(BaseModel):
    fields: dict


# ── Dependency factories ──────────────────────────────────────────────────────

def get_workspace_repo(db: Session = Depends(get_db)) -> PgWorkspaceRepository:
    return PgWorkspaceRepository(db)


def get_section_repo(
    db: Session = Depends(get_db),
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
) -> PgSectionRepository:
    return PgSectionRepository(db, workspace_repo)


def get_student_repo(
    db: Session = Depends(get_db),
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
) -> PgStudentRepository:
    return PgStudentRepository(db, workspace_repo)


def get_workspace_service(
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
) -> WorkspaceService:
    return WorkspaceService(
        repo         = workspace_repo,
        parser       = FileParserService(),
        extractor    = ExtractionService(),
        hash_service = PdfHashService(),
    )


# ── Helper ────────────────────────────────────────────────────────────────────

def _ws_dict(workspace_id, ws, section_repo, student_repo) -> dict:
    d = ws.to_dict()
    sections = section_repo.list_by_workspace(workspace_id)
    for s in sections:
        s["students_count"] = student_repo.count_by_section(workspace_id, s["section_id"])
    d["sections"] = sections
    d["students_count"] = sum(s["students_count"] for s in sections)
    return d


# ── Routes (unchanged) ────────────────────────────────────────────────────────

@router.get("/workspaces")
def list_workspaces(
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:   PgSectionRepository   = Depends(get_section_repo),
    student_repo:   PgStudentRepository   = Depends(get_student_repo),
):
    return {
        "workspaces": [
            _ws_dict(ws.workspace_id, ws, section_repo, student_repo)
            for ws in workspace_repo.list_all()
        ]
    }


@router.post("/workspaces/upload")
async def import_workspace(
    file: UploadFile = File(...),
    workspace_repo:    PgWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:      PgSectionRepository   = Depends(get_section_repo),
    student_repo:      PgStudentRepository   = Depends(get_student_repo),
    workspace_service: WorkspaceService       = Depends(get_workspace_service),
):
    content = await file.read()
    result  = workspace_service.create_from_file(file.filename, content)
    ws      = result["workspace"]
    logger.info("Workspace uploaded id=%s already_uploaded=%s",
                ws.workspace_id, result["already_uploaded"])
    return {
        "workspace":        _ws_dict(ws.workspace_id, ws, section_repo, student_repo),
        "already_uploaded": result["already_uploaded"],
    }


@router.get("/workspaces/{workspace_id}")
def get_workspace(
    workspace_id: str,
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:   PgSectionRepository   = Depends(get_section_repo),
    student_repo:   PgStudentRepository   = Depends(get_student_repo),
):
    ws = workspace_repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")
    return {"workspace": _ws_dict(workspace_id, ws, section_repo, student_repo)}


@router.patch("/workspaces/{workspace_id}")
def update_workspace(
    workspace_id: str,
    data: UpdateFieldsRequest,
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:   PgSectionRepository   = Depends(get_section_repo),
    student_repo:   PgStudentRepository   = Depends(get_student_repo),
):
    ws = workspace_repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")
    ws.update_fields(data.fields)
    workspace_repo.save(ws)
    logger.info("Updated workspace id=%s", workspace_id)
    return {"workspace": _ws_dict(workspace_id, ws, section_repo, student_repo)}


@router.delete("/workspaces/{workspace_id}")
def delete_workspace(
    workspace_id: str,
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
):
    if not workspace_repo.delete(workspace_id):
        raise HTTPException(status_code=404, detail="Workspace not found")
    logger.info("Deleted workspace id=%s", workspace_id)
    return {"deleted": True}


@router.post("/workspaces/{workspace_id}/ask")
async def ask_workspace_question(
    workspace_id: str,
    req: AskRequest,
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
):
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
async def reupload_syllabus(
    workspace_id: str,
    file: UploadFile = File(...),
    workspace_repo:    PgWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:      PgSectionRepository   = Depends(get_section_repo),
    student_repo:      PgStudentRepository   = Depends(get_student_repo),
    workspace_service: WorkspaceService       = Depends(get_workspace_service),
):
    ws = workspace_repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")
    content = await file.read()
    try:
        workspace_service.reprocess_pdf(workspace_id, content)
    except Exception as e:
        logger.error("Reupload failed workspace=%s: %s", workspace_id, e)
        raise HTTPException(status_code=500, detail=f"Failed to process PDF: {e}")
    ws = workspace_repo.get_by_id(workspace_id)
    return {"workspace": _ws_dict(workspace_id, ws, section_repo, student_repo)}