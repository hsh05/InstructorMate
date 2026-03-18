# backend/domain/workspace.py


from typing import Dict, List
from .enums import WorkspaceStatus
from .workspace_fields import REQUIRED_FIELD_NAMES


class Workspace:
    def __init__(
        self,
        workspace_id: str,
        file_hash: str,
        fields: Dict[str, str],
        status: WorkspaceStatus,
    ):
        self._workspace_id = workspace_id
        self._file_hash = file_hash
        self._fields = fields
        self._status = status
        # Populated by the repository after construction
        self._created_at: str = ""
        self._updated_at: str = ""

    @property
    def workspace_id(self) -> str:
        return self._workspace_id

    @property
    def file_hash(self) -> str:
        return self._file_hash

    @property
    def fields(self) -> Dict[str, str]:
        return self._fields # return dict(self._fields)

    @property
    def status(self) -> WorkspaceStatus:
        return self._status

    @status.setter
    def status(self, value: WorkspaceStatus) -> None:
        self._status = value

    def update_fields(self, updates: Dict[str, str]) -> None:
        self._fields.update(updates)
        self._recalculate_status()

    def get_missing_fields(self) -> List[str]:
        return [f for f in REQUIRED_FIELD_NAMES if not self._fields.get(f)]

    def _recalculate_status(self) -> None:
        self._status = (
            WorkspaceStatus.READY if not self.get_missing_fields()
            else WorkspaceStatus.DRAFT
        )

    def to_dict(self) -> dict: #translate json retuned by FastApi to python dictioanry 
        return {
            "id": self.workspace_id,
            # FIX: expose real DB timestamps instead of hardcoded empty strings
            "created_at": self._created_at,
            "updated_at": self._updated_at,
            "original_filename": "",
            "file_hash": self.file_hash,
            "fields": self.fields,
            "status": self.status.value,
            "sections": [],
            "students_count": 0,
        }