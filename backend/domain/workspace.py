from typing import Dict, List
from .enums import WorkspaceStatus

REQUIRED_FIELDS = [
    "course_title",
    "semester",
    "office_hours"
]


class Workspace:
    def __init__(self, workspace_id: str, pdf_hash: str, fields: Dict[str, str], status: WorkspaceStatus):
        self._workspace_id = workspace_id
        self._pdf_hash = pdf_hash
        self._fields = fields
        self._status = status

    @property
    def workspace_id(self):
        return self._workspace_id

    @property
    def pdf_hash(self):
        return self._pdf_hash

    @property
    def fields(self):
        return self._fields

    @property
    def status(self):
        return self._status

    def update_fields(self, updates: Dict[str, str]):
        self._fields.update(updates)
        self._recalculate_status()

    def get_missing_fields(self) -> List[str]:
        return [f for f in REQUIRED_FIELDS if not self._fields.get(f)]

    def _recalculate_status(self):
        self._status = WorkspaceStatus.READY if not self.get_missing_fields() else WorkspaceStatus.DRAFT

    def to_dict(self):
        return {
            "id": self.workspace_id,
            "pdfHash": self.pdf_hash,
            "fields": self.fields,
            "status": self.status.value,
            "missing": self.get_missing_fields(),
        }

        

        
