from pathlib import Path
import csv
from domain.student import Student
from repositories.csv_workspace_repository import CsvWorkspaceRepository


class CsvStudentRepository:

    def __init__(self, ws_repo: CsvWorkspaceRepository):
        self.ws_repo = ws_repo

    def _file_path(self, workspace_id: str) -> Path:
        ws_dir = self.ws_repo.workspace_dir(workspace_id)
        ws_dir.mkdir(parents=True, exist_ok=True)
        return ws_dir / "students.csv"

    def save(self, student: Student) -> None:
        file_path = self._file_path(student.workspace_id)
        file_exists = file_path.exists()

        with open(file_path, "a", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(
                f,
                fieldnames=["student_id", "workspace_id", "section_id", "student_no", "name", "email"],
            )
            if not file_exists:
                writer.writeheader()

            writer.writerow({
                "student_id":   student.student_id,
                "workspace_id": student.workspace_id,
                "section_id":   getattr(student, "section_id", ""),
                "student_no":   getattr(student, "student_no", ""),
                "name":         student.name,
                "email":        student.email,
            })

    def list_by_workspace(self, workspace_id: str):
        file_path = self._file_path(workspace_id)
        if not file_path.exists():
            return []
        with open(file_path, "r", newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            return [row for row in reader if row.get("workspace_id") == workspace_id]

    def list_by_section(self, workspace_id: str, section_id: str):
        return [
            r for r in self.list_by_workspace(workspace_id)
            if r.get("section_id") == section_id
        ]

    def count_by_section(self, workspace_id: str, section_id: str) -> int:
        return len(self.list_by_section(workspace_id, section_id))