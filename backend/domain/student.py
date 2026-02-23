from dataclasses import dataclass, field

@dataclass
class Student:
    student_id:   str
    workspace_id: str
    name:         str
    email:        str
    section_id:   str = ""
    student_no:   str = ""