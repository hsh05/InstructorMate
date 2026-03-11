# backend/api/workspace_routes.py

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
    """FIX: Keep course_name and course_title in sync.
    The PDF extractor always writes course_title; the Flutter UI always
    reads/writes course_name. Without this mirror, editing one field in the
    UI would leave the other stale, causing the header title to show
    'Untitled Course' or the Info tab to show a blank Course Name.
    """
    fields = dict(fields)  # don't mutate caller's dict
    if 'course_name' in fields and fields['course_name']:
        fields.setdefault('course_title', fields['course_name'])
        fields['course_title'] = fields['course_name']
    elif 'course_title' in fields and fields['course_title']:
        fields.setdefault('course_name', fields['course_title'])
        fields['course_name'] = fields['course_title']
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

    # FIX: mirror course_name <-> course_title so both fields stay in sync
    mirrored_fields = _mirror_course_name_fields(data.fields)

    ws.update_fields(mirrored_fields)
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

    # Try DB chunks first (survives Render restarts)
    # Fall back to file if DB is empty (local dev)
    chunks_from_db = workspace_repo.get_chunks_for_ask(workspace_id)

    if chunks_from_db:
        # Write a temp CSV for AskPipeline to read
        import tempfile, csv as _csv, os
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
        # Fallback to file
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
        # Clean up temp file if we created one
        if chunks_from_db:
            os.unlink(chunks_path)

    return {"answer": answer}