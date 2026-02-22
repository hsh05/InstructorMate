# backend/services/section_service.py

import uuid


class SectionService:

    def __init__(self, repo):
        self.repo = repo

    def create_section(self, workspace_id: str, data: dict):

        # FIX #2: Extract schedule fields from the request body and include them
        # in section_data so the repository can write all 10 CSV columns correctly
        schedule_data = data.get("schedule", {})

        section_data = {
            "section_id": str(uuid.uuid4()),
            "name": data.get("name", ""),
            "instructor_name": data.get("instructor_name", ""),
            "location": data.get("location", ""),
            "schedule": {
                "days": schedule_data.get("days", []),
                "start_time": schedule_data.get("start_time", ""),
                "end_time": schedule_data.get("end_time", ""),
                "timezone": schedule_data.get("timezone", ""),
                "reminder_minutes": schedule_data.get("reminder_minutes", ""),
            },
        }

        self.repo.save(workspace_id, section_data)

        return section_data