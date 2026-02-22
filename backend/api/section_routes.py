# backend/api/section_routes.py

from fastapi import APIRouter, HTTPException
from repositories.csv_workspace_repository import CsvWorkspaceRepository
from repositories.csv_section_repository import CsvSectionRepository
from services.section_service import SectionService

router = APIRouter()

workspace_repo = CsvWorkspaceRepository()
section_repo = CsvSectionRepository(workspace_repo)
service = SectionService(section_repo)


@router.post("/workspaces/{workspace_id}/sections")
def create_section(workspace_id: str, body: dict):

    if not workspace_repo.get_by_id(workspace_id):
        raise HTTPException(status_code=404, detail="Workspace not found")

    section = service.create_section(workspace_id, body)

    return {"section": section}