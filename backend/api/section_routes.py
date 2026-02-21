from fastapi import APIRouter #so that we split endpoints, not to put al of them in just one file
from repositories.csv_workspace_repository import CsvWorkspaceRepository
from repositories.csv_section_repository import CsvSectionRepository
from services.section_service import SectionService                                    

router = APIRouter() 
#This creates the router object.               # SRP -->this file's only reason is to define HTTP endpoints for sections only (url chnages and http requests).

# instantiate workspace repository FIRST
ws_repo = CsvWorkspaceRepository() #Create a workspace manager that knows how to read and write workspaces from CSV files.”

# pass ws_repo into section repository
section_repo = CsvSectionRepository(ws_repo) # section repository, if you need workspace information, use this workspace repository.”

service = SectionService(section_repo) #business logic (validations, generates id,  ) of section is here



@router.post("/workspaces/{workspace_id}/sections")
def create_section(workspace_id: str, body: dict):
    section = service.create_section(workspace_id, body)
    return {"sectionId": section.section_id}
