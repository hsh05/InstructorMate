# backend/services/section_service.py

import logging
import uuid

logger = logging.getLogger(__name__)


class SectionService:

    def __init__(self, repo, workspace_repo):
        self.repo = repo
        self.workspace_repo = workspace_repo

    def create_section(self, workspace_id: str, data: dict): 
        # FIX: validate workspace exists (was missing — any random ID was accepted)
        if not self.workspace_repo.get_by_id(workspace_id):
            raise FileNotFoundError(f"Workspace '{workspace_id}' not found")

        schedule_data = data.get("schedule", {})

        section_data = {  #prepares structured data and calls repo to save 
            "section_id": str(uuid.uuid4()), #generate uuid
            "name": data.get("name", ""),
            "location": data.get("location", ""),
            "schedule": {
                "days": schedule_data.get("days", []),
                "start_time": schedule_data.get("start_time", ""),
                "end_time": schedule_data.get("end_time", ""),
               # "timezone": schedule_data.get("timezone", "UTC"),
                "reminder_minutes": schedule_data.get("reminder_minutes", 10),
            },
        }

        self.repo.save(workspace_id, section_data)
        logger.info("Section created id=%s workspace=%s", section_data["section_id"], workspace_id)
        return section_data