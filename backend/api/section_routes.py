# backend/api/section_routes.py

import logging
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from db.database import get_db
from db import models

# 👉 THE FIX: Updated repository and service imports to match the new architecture
from repositories.pg_repository import (
    PgWorkspaceRepository,
    PgSectionRepository,
    PgStudentRepository
)
from services.app_service import StudentService

logger = logging.getLogger(__name__)
router = APIRouter()


class ScheduleRequest(BaseModel):
    days: List[str] = Field(default_factory=list)
    start_time: str = ""
    end_time: str = ""
    timezone: str = "UTC"
    reminder_minutes: int = 10


class SectionCreateUpdateRequest(BaseModel):
    name: str = Field(
        ..., 
        pattern=r"^\d{2}[a-zA-Z]$",
        description="Must be exactly 3 characters: 2 digits followed by 1 letter (e.g., 12A)"
    )
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
) -> StudentService:
    # 👉 THE FIX: We use the unified StudentService which handles sections now
    return StudentService(section_repo, workspace_repo)


def _ws_dict(workspace_id, ws, section_repo, student_repo, db: Session) -> dict:
    """
    Helper function that refreshes info after delete/update/create.
    👉 THE FIX: Updated to include materials and dates so the Flutter app doesn't lose state!
    """
    d = ws.to_dict()
    ws_id_int = int(workspace_id)
    
    sections = section_repo.list_by_workspace(ws_id_int)
    for s in sections:
        s["students_count"] = student_repo.count_by_section(ws_id_int, s["section_id"])
    d["sections"] = sections
    d["students_count"] = sum(s["students_count"] for s in sections)
    
    try:
        db_ws = db.query(models.Workspace).filter(models.Workspace.workspace_id == ws_id_int).first()
        if db_ws:
            d["start_date"] = str(db_ws.start_date) if db_ws.start_date else ""
            d["end_date"] = str(db_ws.end_date) if db_ws.end_date else ""
        else:
            d["start_date"] = ""
            d["end_date"] = ""

        # Fetch Materials for this workspace and attach them
        materials = db.query(models.Material).filter(models.Material.workspace_id == ws_id_int).all()
        d["materials"] = [
            {
                "material_id": m.material_id,
                "workspace_id": m.workspace_id,
                "file_name": m.file_name,
                "file_path": m.file_path,
                "material_type": m.material_type
            } for m in materials
        ]
    except Exception:
        d["materials"] = []
        d["start_date"] = ""
        d["end_date"] = ""
        
    return d


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/workspaces/{workspace_id}/sections", status_code=201)
def create_section(
    workspace_id: str,
    body: SectionCreateUpdateRequest,
    service:        StudentService        = Depends(get_section_service), 
    section_repo:   PgSectionRepository   = Depends(get_section_repo),
    student_repo:   PgStudentRepository   = Depends(get_student_repo),
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
    db: Session = Depends(get_db), # 👉 Added DB Session
):       
    ws_id_int = int(workspace_id)
    try:                                                                
        section = service.create_section(ws_id_int, body.model_dump()) 
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Workspace not found") 
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e)) 

    ws = workspace_repo.get_by_id(ws_id_int)  
    logger.info("Created section in workspace=%s", workspace_id) 
    return {"section": section, "workspace": _ws_dict(ws_id_int, ws, section_repo, student_repo, db)} 


@router.patch("/workspaces/{workspace_id}/sections/{section_id}")
def update_section(
    workspace_id: str,
    section_id:   str,
    body: SectionCreateUpdateRequest,
    section_repo:   PgSectionRepository   = Depends(get_section_repo),
    student_repo:   PgStudentRepository   = Depends(get_student_repo),
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
    db: Session = Depends(get_db), # 👉 Added DB Session
):
    """
    Update a section in-place, preserving section_id.
    All students linked to this section will not be lost.
    """
    ws_id_int = int(workspace_id)
    if not workspace_repo.get_by_id(ws_id_int):
        raise HTTPException(status_code=404, detail="Workspace not found")

    updated = section_repo.update(ws_id_int, section_id, body.model_dump())
    if not updated:
        raise HTTPException(status_code=404, detail="Section not found")

    ws = workspace_repo.get_by_id(ws_id_int)
    logger.info("Updated section=%s in workspace=%s", section_id, workspace_id)
    return {"workspace": _ws_dict(ws_id_int, ws, section_repo, student_repo, db)}


@router.delete("/workspaces/{workspace_id}/sections/{section_id}")
def delete_section(
    workspace_id: str,
    section_id:   str,
    workspace_repo: PgWorkspaceRepository = Depends(get_workspace_repo),
    section_repo:   PgSectionRepository   = Depends(get_section_repo),
    student_repo:   PgStudentRepository   = Depends(get_student_repo),
    db: Session = Depends(get_db), # 👉 Added DB Session
):
    ws_id_int = int(workspace_id)
    if not workspace_repo.get_by_id(ws_id_int):
        raise HTTPException(status_code=404, detail="Workspace not found")
    if not section_repo.delete(ws_id_int, section_id):
        raise HTTPException(status_code=404, detail="Section not found")
    ws = workspace_repo.get_by_id(ws_id_int)
    logger.info("Deleted section=%s from workspace=%s", section_id, workspace_id)
    return {"workspace": _ws_dict(ws_id_int, ws, section_repo, student_repo, db)}