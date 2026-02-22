class Student:
    # FIX #2: Added student_no to match the students.csv schema and repository
    def __init__(self, student_id: str, workspace_id: str, student_no: str, name: str, email: str):
        self.student_id = student_id
        self.workspace_id = workspace_id
        self.student_no = student_no
        self.name = name
        self.email = email