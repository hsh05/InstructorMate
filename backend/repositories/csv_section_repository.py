# backend/repositories/csv_section_repository.py

import csv
from pathlib import Path
from typing import Dict, List
from repositories.csv_workspace_repository import CsvWorkspaceRepository


class CsvSectionRepository:

    def __init__(self, ws_repo: CsvWorkspaceRepository):
        self.ws_repo = ws_repo

    def _file_path(self, workspace_id: str) -> Path:
        ws_dir = self.ws_repo.workspace_dir(workspace_id)
        ws_dir.mkdir(parents=True, exist_ok=True)
        return ws_dir / "sections.csv"

    def save(self, workspace_id: str, section_data: Dict):
        file_path = self._file_path(workspace_id)
        file_exists = file_path.exists()

        with open(file_path, mode="a", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(
                f,
                fieldnames=[
                    "section_id", "workspace_id", "name", "instructor_name",
                    "location", "days", "start_time", "end_time", "timezone", "reminder_minutes",
                ],
            )
            if not file_exists:
                writer.writeheader()

            schedule = section_data.get("schedule", {})
            days = schedule.get("days", [])

            writer.writerow({
                "section_id":       section_data["section_id"],
                "workspace_id":     workspace_id,
                "name":             section_data.get("name", ""),
                "instructor_name":  section_data.get("instructor_name", ""),
                "location":         section_data.get("location", ""),
                "days":             ",".join(days) if isinstance(days, list) else days,
                "start_time":       schedule.get("start_time", ""),
                "end_time":         schedule.get("end_time", ""),
                "timezone":         schedule.get("timezone", ""),
                "reminder_minutes": schedule.get("reminder_minutes", ""),
            })

    # FIX: Added list_by_workspace so workspace_routes can inject real sections into responses
    def list_by_workspace(self, workspace_id: str) -> List[Dict]:
        file_path = self._file_path(workspace_id)
        if not file_path.exists():
            return []

        results = []
        with open(file_path, "r", newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get("workspace_id") == workspace_id:
                    # Re-expand days from comma-separated string back to a list
                    days_raw = row.get("days", "")
                    days = [d.strip() for d in days_raw.split(",") if d.strip()] if days_raw else []
                    results.append({
                        "section_id":      row.get("section_id", ""),
                        "workspace_id":    row.get("workspace_id", ""),
                        "name":            row.get("name", ""),
                        "instructor_name": row.get("instructor_name", ""),
                        "location":        row.get("location", ""),
                        "schedule": {
                            "days":             days,
                            "start_time":       row.get("start_time", ""),
                            "end_time":         row.get("end_time", ""),
                            "timezone":         row.get("timezone", "UTC"),
                            "reminder_minutes": int(row.get("reminder_minutes") or 10),
                        },
                    })
        return results

    def delete(self, workspace_id: str, section_id: str) -> bool:
        file_path = self._file_path(workspace_id)
        if not file_path.exists():
            return False

        rows = []
        with open(file_path, "r", newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        filtered = [r for r in rows if r.get("section_id") != section_id]
        if len(filtered) == len(rows):
            return False  # not found

        with open(file_path, "w", newline="", encoding="utf-8") as f:
            if rows:
                writer = csv.DictWriter(f, fieldnames=rows[0].keys())
                writer.writeheader()
                writer.writerows(filtered)

        return True