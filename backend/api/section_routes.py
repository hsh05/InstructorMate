from fastapi import APIRouter
from repositories.csv_workspace_repository import CsvWorkspaceRepository
from repositories.csv_section_repository import CsvSectionRepository
from services.section_service import SectionService

router = APIRouter()

# instantiate workspace repository FIRST
ws_repo = CsvWorkspaceRepository()

# pass ws_repo into section repository
section_repo = CsvSectionRepository(ws_repo)

service = SectionService(section_repo)



@router.post("/workspaces/{workspace_id}/sections")
def create_section(workspace_id: str, body: dict):
    section = service.create_section(workspace_id, body)
    return {"sectionId": section.section_id}
