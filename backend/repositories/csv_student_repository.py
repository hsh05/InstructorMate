from __future__ import annotations
import csv
import io
import uuid
from typing import Dict, Any

from repositories.csv_workspace_repository import CsvWorkspaceRepository


class CsvStudentRepository:
    def __init__(self, ws_repo: CsvWorkspaceRepository) -> None:
        self.ws_repo = ws_repo

    def import_csv(self, workspace_id: str, csv_bytes: bytes) -> Dict[str, Any]:
        ws = self.ws_repo.load(workspace_id)
        students = ws.get("students", [])

        text = csv_bytes.decode("utf-8", errors="replace")
        reader = csv.DictReader(io.StringIO(text))

        for row in reader:
            students.append({
                "id": f"stu_{uuid.uuid4().hex[:8]}",
                "student_no": (row.get("student_no") or "").strip(),
                "name": (row.get("name") or "").strip(),
                "email": (row.get("email") or "").strip(),
            })

        ws["students"] = students
        self.ws_repo.save(workspace_id, ws)
        return ws
