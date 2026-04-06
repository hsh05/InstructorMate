# backend/services/section_service.py

import logging

logger = logging.getLogger(__name__)


class SectionService:

    def __init__(self, repo, workspace_repo):
        self.repo = repo
        self.workspace_repo = workspace_repo

    def create_section(self, workspace_id: str, data: dict): 
        # FIX: validate workspace exists
        if not self.workspace_repo.get_by_id(workspace_id):
            raise FileNotFoundError(f"Workspace '{workspace_id}' not found")

        schedule_data = data.get("schedule", {})
        
        # 👈 NEW: Grab the name from Flutter and ensure it isn't blank
        section_name = data.get("name", "").strip()
        if not section_name:
            raise ValueError("Section name cannot be empty.")

        section_data = {  
            "section_id": section_name, # 👈 FIXED: No more UUIDs! Uses your custom name.
            "name": section_name,
            "location": data.get("location", ""),
            "schedule": {
                "days": schedule_data.get("days", []),
                "start_time": schedule_data.get("start_time", ""),
                "end_time": schedule_data.get("end_time", ""),
                "reminder_minutes": schedule_data.get("reminder_minutes", 10),
            },
        }

        self.repo.save(workspace_id, section_data)
        logger.info("Section created id=%s workspace=%s", section_data["section_id"], workspace_id)
        return section_data