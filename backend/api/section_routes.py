# backend/api/section_routes.py

import logging
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from db.database import get_db
from repositories.pg_workspace_repository import PgWorkspaceRepository
from repositories.pg_section_repository import PgSectionRepository
from repositories.pg_student_repository import PgStudentRepository
from services.section_service import SectionService

logger = logging.getLogger(__name__)
router = APIRouter()


class ScheduleRequest(BaseModel):
    days: List[str] = Field(default_factory=list)
    start_time: str = ""
    end_time: str = ""
    timezone: str = "UTC"
    reminder_minutes: int = 10


class SectionCreateRequest(BaseModel):
    name: str = Field(..., min_length=1)
    location: str = ""
    schedule: ScheduleRequest = Field(default_factory=ScheduleRequest)


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


def get_section_service(
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:   PgSectionRepository   = Depends(get_section_repo),
) -> SectionService:
    return SectionService(section_repo, workspace_repo)


def _ws_dict(workspace_id, ws, section_repo, student_repo) -> dict:
    d = ws.to_dict()
    sections = section_repo.list_by_workspace(workspace_id)
    for s in sections:
        s["students_count"] = student_repo.count_by_section(workspace_id, s["section_id"])
    d["sections"] = sections
    d["students_count"] = sum(s["students_count"] for s in sections)
    return d


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/workspaces/{workspace_id}/sections", status_code=201)
def create_section(
    workspace_id: str,
    body: SectionCreateRequest,
    service:        SectionService        = Depends(get_section_service),
    section_repo:   PgSectionRepository   = Depends(get_section_repo),
    student_repo:   PgStudentRepository   = Depends(get_student_repo),
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
):
    try:
        section = service.create_section(workspace_id, body.model_dump())
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Workspace not found")
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

    ws = workspace_repo.get_by_id(workspace_id)
    logger.info("Created section in workspace=%s", workspace_id)
    return {"section": section, "workspace": _ws_dict(workspace_id, ws, section_repo, student_repo)}


@router.patch("/workspaces/{workspace_id}/sections/{section_id}")
def update_section(
    workspace_id: str,
    section_id:   str,
    body: SectionCreateRequest,
    section_repo:   PgSectionRepository   = Depends(get_section_repo),
    student_repo:   PgStudentRepository   = Depends(get_student_repo),
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
):
    """
    Update a section in-place, preserving section_id.
    All students linked to this section remain intact.
    """
    if not workspace_repo.get_by_id(workspace_id):
        raise HTTPException(status_code=404, detail="Workspace not found")

    updated = section_repo.update(workspace_id, section_id, body.model_dump())
    if not updated:
        raise HTTPException(status_code=404, detail="Section not found")

    ws = workspace_repo.get_by_id(workspace_id)
    logger.info("Updated section=%s in workspace=%s", section_id, workspace_id)
    return {"workspace": _ws_dict(workspace_id, ws, section_repo, student_repo)}


@router.delete("/workspaces/{workspace_id}/sections/{section_id}")
def delete_section(
    workspace_id: str,
    section_id:   str,
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:   PgSectionRepository   = Depends(get_section_repo),
    student_repo:   PgStudentRepository   = Depends(get_student_repo),
):
    if not workspace_repo.get_by_id(workspace_id):
        raise HTTPException(status_code=404, detail="Workspace not found")
    if not section_repo.delete(workspace_id, section_id):
        raise HTTPException(status_code=404, detail="Section not found")
    ws = workspace_repo.get_by_id(workspace_id)
    logger.info("Deleted section=%s from workspace=%s", section_id, workspace_id)
    return {"workspace": _ws_dict(workspace_id, ws, section_repo, student_repo)}