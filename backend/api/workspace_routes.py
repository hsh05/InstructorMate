# backend/api/workspace_routes.py
#
# CHANGES:
# 1. Removed /reupload endpoint — no longer needed.
# 2. Fixed temp-file leak in /ask: file write is now inside the try block.
# 3. /upload now accepts .pdf and .docx (backend auto-detects by extension).


import logging
import os

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

_ALLOWED_SYLLABUS_EXTENSIONS = {".pdf", ".docx"}


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


# ── Helper ────────────────────────────────────────────────────────────────────

def _ws_dict(workspace_id, ws, section_repo, student_repo) -> dict:
    d = ws.to_dict()
    sections = section_repo.list_by_workspace(workspace_id)
    for s in sections:
        s["students_count"] = student_repo.count_by_section(workspace_id, s["section_id"])
    d["sections"] = sections
    d["students_count"] = sum(s["students_count"] for s in sections)
    # While the background LLM extraction is still running, surface a clear
    # "processing" display name so Flutter never shows "Untitled".
    fields = d.get("fields", {})
    has_name = bool(
        fields.get("course_title") or fields.get("course_name") or fields.get("course_code")
    )
    if d.get("status") == "draft" and not has_name:
        d["display_name"] = "Processing..."
    else:
        d["display_name"] = (
            fields.get("course_title")
            or fields.get("course_name")
            or fields.get("course_code")
            or "Untitled"
        )
    return d


def _mirror_course_name_fields(fields: dict) -> dict:
    """Keep course_name and course_title in sync."""
    fields = dict(fields)
    if fields.get("course_name"):
        fields["course_title"] = fields["course_name"]
    elif fields.get("course_title"):
        fields["course_name"] = fields["course_title"]
    return fields


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
    filename = file.filename or ""
    ext = ("." + filename.rsplit(".", 1)[-1].lower()) if "." in filename else ""
    if ext not in _ALLOWED_SYLLABUS_EXTENSIONS:
        raise HTTPException(
            status_code=415,
            detail=f"Unsupported file type '{ext}'. Allowed: {sorted(_ALLOWED_SYLLABUS_EXTENSIONS)}",
        )

    content = await file.read()
    result  = workspace_service.create_from_file(filename, content)
    ws      = result["workspace"]
    logger.info("Workspace uploaded id=%s already_uploaded=%s ext=%s",
                ws.workspace_id, result["already_uploaded"], ext)
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
    d = _ws_dict(workspace_id, ws, section_repo, student_repo)
    # FIX: expose whether background extraction is still running so Flutter
    # can poll until status == 'ready' and all required fields are filled.
    fields = d.get("fields", {})
    return {"workspace": d}


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
    mirrored_fields = _mirror_course_name_fields(data.fields)
    ws.update_fields(mirrored_fields)
    workspace_repo.save(ws)
    logger.info("Updated workspace id=%s", workspace_id)
    return {"workspace": _ws_dict(workspace_id, ws, section_repo, student_repo)}


@router.delete("/workspaces/{workspace_id}")
def delete_workspace(
    workspace_id: str,
    workspace_repo:    PgWorkspaceRepository = Depends(get_workspace_repo),
    workspace_service: WorkspaceService       = Depends(get_workspace_service),
):
    # Cancel any in-flight background extraction before deleting,
    # otherwise the background thread keeps writing after the DB row is gone.
    workspace_service.cancel_if_in_flight(workspace_id)
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

    chunks_from_db = workspace_repo.get_chunks_for_ask(workspace_id)
    chunks_path: str | None = None

    try:
        if chunks_from_db:
            # FIX: write temp file inside the try so cleanup is always reached
            import tempfile, csv as _csv
            tmp = tempfile.NamedTemporaryFile(
                mode="w", suffix=".csv", delete=False, newline="", encoding="utf-8"
            )
            writer = _csv.DictWriter(tmp, fieldnames=["chunk_id", "page", "text"])
            writer.writeheader()
            for c in chunks_from_db:
                writer.writerow({"chunk_id": c["chunk_id"], "page": c["page"], "text": c["content"]})
            tmp.close()
            chunks_path = tmp.name
        else:
            chunks_path_obj = workspace_repo.get_chunks_csv_path(workspace_id)
            if not chunks_path_obj.exists():
                raise HTTPException(
                    status_code=422,
                    detail="Syllabus chunks not found. Re-upload the file to regenerate them.",
                )
            chunks_path = str(chunks_path_obj)

        pipeline = AskPipeline(
            store=SyllabusCsvStore(chunks_path),
            retriever=LightweightRetriever(),
            llm=SyllabusChatGPT(),
        )
        answer = pipeline.run(req.question)

    finally:
        if chunks_from_db and chunks_path and os.path.exists(chunks_path):
            try:
                os.unlink(chunks_path)
            except OSError:
                pass

    return {"answer": answer}