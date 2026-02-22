import csv
import io
import uuid
from domain.student import Student


class StudentService:

    def __init__(self, repo):
        self.repo = repo

    def import_students(self, workspace_id: str, file_bytes: bytes):
        # Check workspace exists before importing — raises FileNotFoundError
        # so student_routes can catch it and return a proper 404
        if not self.repo.ws_repo.get_by_id(workspace_id):
            raise FileNotFoundError(f"Workspace '{workspace_id}' not found")

        text = file_bytes.decode("utf-8", errors="replace")
        reader = csv.DictReader(io.StringIO(text))

        students = []

        for row in reader:
            student = Student(
                student_id=str(uuid.uuid4()),
                workspace_id=workspace_id,
                student_no=(row.get("student_no") or "").strip(),
                name=(row.get("name") or "").strip(),
                email=(row.get("email") or "").strip(),
            )

            self.repo.save(student)
            students.append(student)

        return students