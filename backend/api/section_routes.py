# backend/api/section_routes.py
#
# FIX (DRY / SRP): delete_section was incorrectly placed in workspace_routes.py.
# All section concerns now live here.
#
# FIX (Security): body was `dict` with no validation — now a Pydantic model.
# FIX: Module-level singletons → FastAPI Depends().
# FIX: workspace existence guard moved into SectionService.
# FIX: Replaced print() with logging.

import logging
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from repositories.csv_section_repository import CsvSectionRepository
from repositories.csv_workspace_repository import CsvWorkspaceRepository
from repositories.csv_student_repository import CsvStudentRepository
from services.section_service import SectionService

logger = logging.getLogger(__name__)
router = APIRouter()


# ── Pydantic request models ───────────────────────────────────────────────────

class ScheduleRequest(BaseModel):
    days: List[str] = Field(default_factory=list)
    start_time: str = ""
    end_time: str = ""
    timezone: str = "UTC"
    reminder_minutes: int = 10


class SectionCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, description="Section name is required")
    location: str = ""
    schedule: ScheduleRequest = Field(default_factory=ScheduleRequest)


# ── Dependency factories ──────────────────────────────────────────────────────

def get_workspace_repo() -> CsvWorkspaceRepository:
    return CsvWorkspaceRepository()


def get_section_repo(
    workspace_repo: CsvWorkspaceRepository = Depends(get_workspace_repo),
) -> CsvSectionRepository:
    return CsvSectionRepository(workspace_repo)


def get_student_repo(
    workspace_repo: CsvWorkspaceRepository = Depends(get_workspace_repo),
) -> CsvStudentRepository:
    return CsvStudentRepository(workspace_repo)


def get_section_service(
    workspace_repo: CsvWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:   CsvSectionRepository   = Depends(get_section_repo),
) -> SectionService:
    return SectionService(section_repo, workspace_repo)


# ── Helper (mirrors workspace_routes._ws_dict without circular import) ────────

def _ws_dict(workspace_id: str, ws, section_repo, student_repo) -> dict:
    d = ws.to_dict()
    sections = section_repo.list_by_workspace(workspace_id)
    for s in sections:
        s["students_count"] = student_repo.count_by_section(workspace_id, s["section_id"])
    d["sections"] = sections
    d["students_count"] = sum(s["students_count"] for s in sections)
    return d


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/workspaces/{workspace_id}/sections", status_code=200)
def create_section(
    workspace_id: str,
    body: SectionCreateRequest,
    service: SectionService = Depends(get_section_service),
):
    try:
        section = service.create_section(workspace_id, body.model_dump())
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Workspace not found")
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

    logger.info("Created section in workspace=%s", workspace_id)
    return {"section": section}


@router.delete("/workspaces/{workspace_id}/sections/{section_id}")
def delete_section(
    workspace_id: str,
    section_id: str,
    workspace_repo: CsvWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:   CsvSectionRepository   = Depends(get_section_repo),
    student_repo:   CsvStudentRepository   = Depends(get_student_repo),
):
    # FIX: moved here from workspace_routes — all section endpoints belong together
    if not workspace_repo.get_by_id(workspace_id):
        raise HTTPException(status_code=404, detail="Workspace not found")
    if not section_repo.delete(workspace_id, section_id):
        raise HTTPException(status_code=404, detail="Section not found")

    ws = workspace_repo.get_by_id(workspace_id)
    logger.info("Deleted section=%s from workspace=%s", section_id, workspace_id)
    return {"workspace": _ws_dict(workspace_id, ws, section_repo, student_repo)}