# backend/repositories/csv_workspace_repository.py

import csv
from pathlib import Path
from datetime import datetime
from typing import List, Optional
from domain.workspace import Workspace
from domain.enums import WorkspaceStatus


class CsvWorkspaceRepository:

    def __init__(self, file_path="backend/data/workspaces.csv"):
        self.file_path = Path(file_path)
        self.file_path.parent.mkdir(parents=True, exist_ok=True)

        if not self.file_path.exists():
            with open(self.file_path, "w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                writer.writerow([
                    "workspace_id",
                    "pdf_hash",
                    "status",
                    "course_title",
                    "semester",
                    "office_hours",
                    "instructor_email",
                    "course_code",
                    "course_name",
                    "created_at"
                ])

    # FIX: Added workspace_dir() — called by CsvSectionRepository and CsvStudentRepository
    # to resolve per-workspace folders for sections.csv and students.csv.
    # Without this method both repositories crash immediately on any save/read.
    def workspace_dir(self, workspace_id: str) -> Path:
        return self.file_path.parent / workspace_id

    # FIX: Added get_chunks_csv_path() — called by workspace_routes.py in the /ask endpoint.
    # Without this the ask endpoint crashes with AttributeError.
    def get_chunks_csv_path(self, workspace_id: str) -> Path:
        return self.workspace_dir(workspace_id) / "chunks.csv"

    def list_all(self) -> List[Workspace]:
        workspaces = []
        with open(self.file_path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                fields = {
                    "course_title": row["course_title"],
                    "semester": row["semester"],
                    "office_hours": row["office_hours"],
                    "instructor_email": row["instructor_email"],
                    "course_code": row["course_code"],
                    "course_name": row["course_name"],
                }
                workspaces.append(
                    Workspace(
                        workspace_id=row["workspace_id"],
                        pdf_hash=row["pdf_hash"],
                        fields=fields,
                        status=WorkspaceStatus(row["status"])
                    )
                )
        return workspaces

    def get_by_id(self, workspace_id: str) -> Optional[Workspace]:
        with open(self.file_path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row["workspace_id"] == workspace_id:
                    fields = {
                        "course_title": row["course_title"],
                        "semester": row["semester"],
                        "office_hours": row["office_hours"],
                        "instructor_email": row["instructor_email"],
                        "course_code": row["course_code"],
                        "course_name": row["course_name"],
                    }
                    return Workspace(
                        workspace_id=row["workspace_id"],
                        pdf_hash=row["pdf_hash"],
                        fields=fields,
                        status=WorkspaceStatus(row["status"])
                    )
        return None

    def save(self, workspace: Workspace):
        rows = []

        with open(self.file_path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        updated = False

        for row in rows:
            if row["workspace_id"] == workspace.workspace_id:
                row.update({
                    "pdf_hash": workspace.pdf_hash,
                    "status": workspace.status.value,
                    "course_title": workspace.fields.get("course_title", ""),
                    "semester": workspace.fields.get("semester", ""),
                    "office_hours": workspace.fields.get("office_hours", ""),
                    "instructor_email": workspace.fields.get("instructor_email", ""),
                    "course_code": workspace.fields.get("course_code", ""),
                    "course_name": workspace.fields.get("course_name", ""),
                })
                updated = True

        if not updated:
            rows.append({
                "workspace_id": workspace.workspace_id,
                "pdf_hash": workspace.pdf_hash,
                "status": workspace.status.value,
                "course_title": workspace.fields.get("course_title", ""),
                "semester": workspace.fields.get("semester", ""),
                "office_hours": workspace.fields.get("office_hours", ""),
                "instructor_email": workspace.fields.get("instructor_email", ""),
                "course_code": workspace.fields.get("course_code", ""),
                "course_name": workspace.fields.get("course_name", ""),
                "created_at": datetime.utcnow().isoformat()
            })

        with open(self.file_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=rows[0].keys())
            writer.writeheader()
            writer.writerows(rows)

    def delete(self, workspace_id: str) -> bool:
        rows = []
        with open(self.file_path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        filtered = [r for r in rows if r["workspace_id"] != workspace_id]
        if len(filtered) == len(rows):
            return False  # not found

        with open(self.file_path, "w", newline="", encoding="utf-8") as f:
            if filtered:
                writer = csv.DictWriter(f, fieldnames=rows[0].keys())
                writer.writeheader()
                writer.writerows(filtered)
            else:
                # All rows deleted — rewrite just the header
                writer = csv.DictWriter(f, fieldnames=rows[0].keys())
                writer.writeheader()

        # Delete the workspace folder (sections.csv, students.csv, chunks.csv, syllabus.pdf)
        ws_dir = self.workspace_dir(workspace_id)
        if ws_dir.exists():
            import shutil
            shutil.rmtree(ws_dir)

        return True