# backend/domain/workspace.py
#
# FIX (DRY): REQUIRED_FIELDS was a hardcoded list here that was separate from
# (and could drift from) the field list in CsvWorkspaceRepository.
# Now imports REQUIRED_FIELD_NAMES from workspace_fields.py — one source of truth.

from typing import Dict, List
from .enums import WorkspaceStatus
from .workspace_fields import REQUIRED_FIELD_NAMES


class Workspace:
    def __init__(
        self,
        workspace_id: str,
        pdf_hash: str,
        fields: Dict[str, str],
        status: WorkspaceStatus,
    ):
        self._workspace_id = workspace_id
        self._pdf_hash = pdf_hash
        self._fields = fields
        self._status = status

    @property
    def workspace_id(self) -> str:
        return self._workspace_id

    @property
    def pdf_hash(self) -> str:
        return self._pdf_hash

    @property
    def fields(self) -> Dict[str, str]:
        return self._fields

    @property
    def status(self) -> WorkspaceStatus:
        return self._status

    def update_fields(self, updates: Dict[str, str]) -> None:
        self._fields.update(updates)
        self._recalculate_status()

    def get_missing_fields(self) -> List[str]:
        # FIX: uses shared REQUIRED_FIELD_NAMES instead of its own hardcoded list
        return [f for f in REQUIRED_FIELD_NAMES if not self._fields.get(f)]

    def _recalculate_status(self) -> None:
        self._status = (
            WorkspaceStatus.READY if not self.get_missing_fields()
            else WorkspaceStatus.DRAFT
        )

    def to_dict(self) -> dict:
        return {
            "id": self.workspace_id,
            "created_at": "",
            "original_filename": "",
            "pdf_hash": self.pdf_hash,
            "fields": self.fields,
            "status": self.status.value,
            "sections": [],
            "students_count": 0,
        }