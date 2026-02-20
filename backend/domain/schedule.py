from typing import List


class Schedule:
    def __init__(self, days: List[str], start_time: str, end_time: str, timezone: str, reminder_minutes: int):
        self.days = days
        self.start_time = start_time
        self.end_time = end_time
        self.timezone = timezone
        self.reminder_minutes = reminder_minutes
