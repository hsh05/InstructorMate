# backend/api/workspace_routes.py

import csv as _csv
import logging
import os
import tempfile

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlalchemy.orm import Session

from db.database import get_db
from repositories.pg_workspace_repository import PgWorkspaceRepository
from repositories.pg_section_repository import PgSectionRepository
from repositories.pg_student_repository import PgStudentRepository
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
        hash_service = PdfHashService(),
    )


# ── Helpers ───────────────────────────────────────────────────────────────────

def _ws_dict(workspace_id, ws, section_repo, student_repo) -> dict:
    d = ws.to_dict()
    sections = section_repo.list_by_workspace(workspace_id)
    for s in sections:
        s["students_count"] = student_repo.count_by_section(workspace_id, s["section_id"])
    d["sections"] = sections
    d["students_count"] = sum(s["students_count"] for s in sections)
    return d


def _validate_pdf(content: bytes, filename: str) -> None:
    """Raise HTTPException if the uploaded bytes don't look like a complete PDF."""
    if not content:
        raise HTTPException(status_code=400, detail="Empty file received.")

    if not content.startswith(b"%PDF"):
        raise HTTPException(
            status_code=400,
            detail=f"'{filename}' does not appear to be a valid PDF (missing %PDF header).",
        )

    # PDF spec requires %%EOF near the end — search last 2 KB to allow for
    # trailing whitespace/comments that some exporters add.
    if b"%%EOF" not in content[-2048:]:
        raise HTTPException(
            status_code=400,
            detail=(
                f"'{filename}' appears to be truncated or corrupted "
                "(missing %%EOF marker). Please re-export or re-upload the file."
            ),
        )

    logger.debug("PDF validation passed for '%s' (%d bytes)", filename, len(content))


# ── Routes ────────────────────────────────────────────────────────────────────

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

    # Validate PDF integrity before touching the DB or converter
    _validate_pdf(content, file.filename or "upload")

    try:
        result = workspace_service.create_from_file(file.filename, content)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

    ws = result["workspace"]
    logger.info(
        "Workspace uploaded id=%s already_uploaded=%s",
        ws.workspace_id, result["already_uploaded"],
    )
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

    # Try DB chunks first (survives Render restarts),
    # fall back to file if DB is empty (local dev or first upload before fix)
    chunks_from_db = workspace_repo.get_chunks_for_ask(workspace_id)
    chunks_path = None
    tmp_created = False

    if chunks_from_db:
        tmp = tempfile.NamedTemporaryFile(
            mode="w", suffix=".csv", delete=False, newline="", encoding="utf-8"
        )
        writer = _csv.DictWriter(tmp, fieldnames=["chunk_id", "page", "text"])
        writer.writeheader()
        for c in chunks_from_db:
            writer.writerow({"chunk_id": c["chunk_id"], "page": c["page"], "text": c["content"]})
        tmp.close()
        chunks_path = tmp.name
        tmp_created = True
    else:
        chunks_path_obj = workspace_repo.get_chunks_csv_path(workspace_id)
        if not chunks_path_obj.exists():
            raise HTTPException(
                status_code=422,
                detail="Syllabus chunks not found. Re-upload the PDF to regenerate them.",
            )
        chunks_path = str(chunks_path_obj)

    try:
        pipeline = AskPipeline(
            store=SyllabusCsvStore(chunks_path),
            retriever=LightweightRetriever(),
            llm=SyllabusChatGPT(),
        )
        answer = pipeline.run(req.question)
    finally:
        if tmp_created and chunks_path and os.path.exists(chunks_path):
            os.unlink(chunks_path)

    return {"answer": answer}


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

    # Validate PDF integrity before re-running the converter
    _validate_pdf(content, file.filename or "upload")

    try:
        workspace_service.reprocess_pdf(workspace_id, content)
    except Exception as e:
        logger.error("Reupload failed workspace=%s: %s", workspace_id, e)
        raise HTTPException(status_code=500, detail=f"Failed to process PDF: {e}")

    ws = workspace_repo.get_by_id(workspace_id)
    return {"workspace": _ws_dict(workspace_id, ws, section_repo, student_repo)}