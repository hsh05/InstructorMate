import uuid
from domain.workspace import Workspace
from domain.enums import WorkspaceStatus


class WorkspaceService:

    def __init__(self, repo, parser, extractor, hash_service):
        self.repo = repo
        self.parser = parser
        self.extractor = extractor
        self.hash_service = hash_service

    def create_from_file(self, filename: str, content: bytes):
        pdf_hash = self.hash_service.compute(content)
        existing = None 


        text = self.parser.extract_text(filename, content)
        fields = self.extractor.extract_fields(text)

        workspace = Workspace(
            workspace_id=str(uuid.uuid4()),
            pdf_hash=pdf_hash,
            fields=fields,
            status=WorkspaceStatus.DRAFT
        )

        self.repo.save(workspace)
        return {"already_uploaded": False, "workspace": workspace}

    def update_workspace(self, workspace_id: str, updates: dict):
        ws = self.repo.get_by_id(workspace_id)
        ws.update_fields(updates)
        self.repo.save(ws)
        return ws
