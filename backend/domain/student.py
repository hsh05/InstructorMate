from dataclasses import dataclass, field

@dataclass
class Student: #its data holder, contains no logic, no recalculating, etc
    student_id:   str
    workspace_id: str
    name:         str
    email:        str  
    section_id:   str = ""
    student_no:   str = ""