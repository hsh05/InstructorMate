import csv
import uuid
import io
from domain.student import Student


class StudentService:

    def __init__(self, repo):
        self.repo = repo

    def import_students(self, workspace_id: str, file_bytes: bytes):
        stream = io.StringIO(file_bytes.decode("utf-8"))
        reader = csv.DictReader(stream)

        students = []

        for row in reader:
            student = Student(
                student_id=str(uuid.uuid4()),
                workspace_id=workspace_id,
                name=row.get("name"),
                email=row.get("email")
            )
            self.repo.save(student)
            students.append(student)

        return students
