# backend/api/workspace_routes.py
#
# CHANGES:
# 1. Removed /reupload endpoint — no longer needed.
# 2. Fixed temp-file leak in /ask: file write is now inside the try block.
# 3. /upload now accepts .pdf and .docx (backend auto-detects by extension).


import logging

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlalchemy.orm import Session

from db.database import get_db
from repositories.pg_workspace_repository import PgWorkspaceRepository
from repositories.pg_section_repository import PgSectionRepository
from repositories.pg_student_repository import PgStudentRepository
from services.pdf_hash_service import PdfHashService
from services.workspace_service import WorkspaceService
from ask_syllabus import AskPipeline, LightweightRetriever, SyllabusChatGPT, SyllabusCsvStore, SyllabusListStore

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
    # Cancel any in-flight background extraction first so the thread doesn't
    # try to write to a row that no longer exists (prevents cascade errors).
    workspace_service.cancel_if_in_flight(workspace_id)

    try:
        deleted = workspace_repo.delete(workspace_id)
    except Exception as exc:
        logger.error("Delete failed for workspace=%s: %s", workspace_id, exc, exc_info=True)
        raise HTTPException(status_code=500, detail=f"Delete failed: {exc}")

    if not deleted:
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

    if chunks_from_db:
        # Preferred path: chunks are in the DB — pass them directly as a list.
        # No disk I/O, no temp files, no cleanup needed.
        store = SyllabusListStore(chunks_from_db)
    else:
        # Fallback path: chunks not yet in DB (legacy workspace before migration).
        # Read from the on-disk CSV that was saved at upload time.
        chunks_csv = workspace_repo.get_chunks_csv_path(workspace_id)
        if not chunks_csv.exists():
            raise HTTPException(
                status_code=422,
                detail="Syllabus chunks not found. Re-upload the file to regenerate them.",
            )
        store = SyllabusCsvStore(str(chunks_csv))

    pipeline = AskPipeline(
        store=store,
        retriever=LightweightRetriever(),
        llm=SyllabusChatGPT(),
    )
    answer = pipeline.run(req.question)
    return {"answer": answer}