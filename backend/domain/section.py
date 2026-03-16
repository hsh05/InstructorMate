from .schedule import Schedule


class Section:
    # FIX #1: Added missing __init__ — without this, all attribute accesses in to_dict() crash
    def __init__( #constructor method that runs direclty once object is created 
        self,
        section_id: str,
        workspace_id: str,
        name: str,
        location: str,
        schedule: Schedule, #composition, has a 
    ):
        self.section_id = section_id
        self.workspace_id = workspace_id
        self.name = name
        self.location = location
        self.schedule = schedule

    def to_dict(self): #converts json to python dictionary
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