import uuid
from domain.section import Section
from domain.schedule import Schedule


class SectionService:

    def __init__(self, repo):
        self.repo = repo

    def create_section(self, workspace_id: str, data: dict):
        schedule = Schedule(
            days=data["days"],
            start_time=data["start_time"],
            end_time=data["end_time"],
            timezone=data["timezone"],
            reminder_minutes=data["reminder_minutes"]
        )

        section = Section(
            section_id=str(uuid.uuid4()),
            workspace_id=workspace_id,
            name=data["name"],
            schedule=schedule
        )

        self.repo.save(section)
        return section
