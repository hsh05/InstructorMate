# backend/domain/models.py

from dataclasses import dataclass
from typing import Dict, List
from .enums import WorkspaceStatus
from .workspace_fields import REQUIRED_FIELD_NAMES

# ── STUDENT ───────────────────────────────────────────────────────────────────
@dataclass
class Student:
    student_id:   str
    workspace_id: str
    name:         str
    email:        str  
    student_no:   str = ""

# ── SCHEDULE & SECTION ────────────────────────────────────────────────────────
class Schedule:
    def __init__(self, days: List[str], start_time: str, end_time: str, timezone: str, reminder_minutes: int):
        self.days = days
        self.start_time = start_time
        self.end_time = end_time
        self.timezone = timezone
        self.reminder_minutes = reminder_minutes

class Section:
    def __init__(self, section_id: str, workspace_id: str, name: str, location: str, schedule: Schedule):
        self.section_id = section_id
        self.workspace_id = workspace_id
        self.name = name
        self.location = location
        self.schedule = schedule

    def to_dict(self):
        return {
            "section_id": self.section_id,
            "name": self.name,
            "location": self.location,
            "schedule": {
                "days": self.schedule.days,
                "start_time": self.schedule.start_time,
                "end_time": self.schedule.end_time,
                "timezone": self.schedule.timezone,
                "reminder_minutes": self.schedule.reminder_minutes,
            }
        }

# ── WORKSPACE ─────────────────────────────────────────────────────────────────
class Workspace:
    def __init__(self, workspace_id: str, file_hash: str, fields: Dict[str, str], status: WorkspaceStatus):
        self._workspace_id = str(workspace_id)
        self._file_hash = file_hash
        self._fields = fields
        self._status = status
        self._created_at: str = ""
        self._updated_at: str = ""

    @property
    def workspace_id(self) -> str:
        return self._workspace_id

    @workspace_id.setter
    def workspace_id(self, value: str) -> None:
        self._workspace_id = str(value)

    @property
    def file_hash(self) -> str:
        return self._file_hash

    @property
    def fields(self) -> Dict[str, str]:
        return self._fields

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

    def to_dict(self) -> dict:
        return {
            "id": self.workspace_id,
            "created_at": self._created_at,
            "updated_at": self._updated_at,
            "original_filename": "",
            "file_hash": self.file_hash,
            "fields": self.fields,
            "status": self.status.value,
            "sections": [],
            "students_count": 0,
        }