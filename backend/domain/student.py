from dataclasses import dataclass, field

@dataclass
class Student: #its data holder, contains no logic, no recalculating, etc
    student_id:   str
    workspace_id: str
    name:         str
    email:        str  #removed section id 
    student_no:   str = ""