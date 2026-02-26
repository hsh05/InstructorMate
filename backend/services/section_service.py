# backend/services/section_service.py
#
# FIX (DI): SectionService now receives workspace_repo so it can validate
# workspace existence itself. The route no longer needs to duplicate this check.
#
# FIX (typing): repo parameters are now typed with their concrete classes.
# In a larger project these would be Protocol/ABC types; for a capstone the
# concrete types give IDE support without adding boilerplate.

import logging
import uuid

from repositories.csv_section_repository import CsvSectionRepository
from repositories.csv_workspace_repository import CsvWorkspaceRepository

logger = logging.getLogger(__name__)


class SectionService:

    def __init__(
        self,
        repo: CsvSectionRepository,
        workspace_repo: CsvWorkspaceRepository,
    ):
        self.repo = repo
        self.workspace_repo = workspace_repo

    def create_section(self, workspace_id: str, data: dict) -> dict:
        # FIX: guard lives here — single place, not in every route that calls this
        if not self.workspace_repo.get_by_id(workspace_id):
            raise FileNotFoundError(f"Workspace '{workspace_id}' not found")

        schedule_data = data.get("schedule", {})

        section_data = {
            "section_id":     str(uuid.uuid4()),
            "name":           data.get("name", ""),
            "instructor_name": data.get("instructor_name", ""),
            "location":       data.get("location", ""),
            "schedule": {
                "days":             schedule_data.get("days", []),
                "start_time":       schedule_data.get("start_time", ""),
                "end_time":         schedule_data.get("end_time", ""),
                "timezone":         schedule_data.get("timezone", "UTC"),
                "reminder_minutes": schedule_data.get("reminder_minutes", 10),
            },
        }

        self.repo.save(workspace_id, section_data)
        logger.info("Section created id=%s workspace=%s", section_data["section_id"], workspace_id)
        return section_data