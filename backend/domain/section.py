from .schedule import Schedule


class Section:
    def __init__(self, section_id: str, workspace_id: str, name: str, schedule: Schedule):
        self.section_id = section_id
        self.workspace_id = workspace_id
        self.name = name
        self.schedule = schedule
