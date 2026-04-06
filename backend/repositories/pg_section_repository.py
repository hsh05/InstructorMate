# backend/repositories/pg_section_repository.py

import logging
from typing import Dict, List

from sqlalchemy.orm import Session

from repositories.pg_workspace_repository import PgWorkspaceRepository
# 👈 FIXED: Removed the deleted SectionDayModel!
from db.models import Section as SectionModel 

logger = logging.getLogger(__name__)


class PgSectionRepository:

    def __init__(self, db: Session, ws_repo: PgWorkspaceRepository):
        self.db      = db
        self.ws_repo = ws_repo

    # ── Read ──────────────────────────────────────────────────────────────────

    def list_by_workspace(self, workspace_id: int) -> List[Dict]: # 👈 FIXED: INT!
        rows = self.db.query(SectionModel).filter(
            SectionModel.workspace_id == workspace_id
        ).all()
        return [self._to_dict(row) for row in rows]

    # ── Write ─────────────────────────────────────────────────────────────────

    def save(self, workspace_id: int, section_data: Dict) -> None: # 👈 FIXED: INT!
        schedule = section_data.get("schedule", {})
        
        # Parse the list of days into a comma-separated string
        days_list = schedule.get("days", [])
        days_string = ", ".join([d.strip() for d in days_list if d.strip()])

        row = SectionModel(
            section_id       = section_data["section_id"],
            workspace_id     = workspace_id,
            # name             = section_data.get("name", ""), # Schema doesn't have name currently
            location         = section_data.get("location", ""),
            start_time       = schedule.get("start_time", None), # Use None instead of "" for Time columns
            end_time         = schedule.get("end_time", None),
            reminder_minutes = schedule.get("reminder_minutes", 10),
            day              = days_string # 👈 Save the string directly!
        )
        self.db.add(row)
        self.db.commit()
        logger.info("Saved section id=%s workspace=%s", row.section_id, workspace_id)

    def update(self, workspace_id: int, section_id: str, section_data: Dict) -> bool: # 👈 FIXED: INT!
        """Update section in-place, preserving section_id and all linked students."""
        row = self.db.query(SectionModel).filter(
            SectionModel.workspace_id == workspace_id,
            SectionModel.section_id   == section_id,
        ).first()
        
        if not row:
            return False

        schedule = section_data.get("schedule", {})
        days_list = schedule.get("days", [])
        days_string = ", ".join([d.strip() for d in days_list if d.strip()])

        # row.name             = section_data.get("name", row.name)
        row.location         = section_data.get("location", row.location)
        row.start_time       = schedule.get("start_time", row.start_time)
        row.end_time         = schedule.get("end_time", row.end_time)
        row.reminder_minutes = schedule.get("reminder_minutes", row.reminder_minutes)
        row.day              = days_string # 👈 Update the string directly!

        self.db.commit()
        logger.info("Updated section id=%s workspace=%s", section_id, workspace_id)
        return True

    def delete(self, workspace_id: int, section_id: str) -> bool: # 👈 FIXED: INT!
        row = self.db.query(SectionModel).filter(
            SectionModel.workspace_id == workspace_id,
            SectionModel.section_id   == section_id,
        ).first()
        if not row:
            return False
        self.db.delete(row)  
        self.db.commit()
        logger.info("Deleted section id=%s workspace=%s", section_id, workspace_id)
        return True

    # ── Private ───────────────────────────────────────────────────────────────

    def update_import_hash(self, section_id: str, file_hash: str) -> None:
        """
        Store the hash of the last successfully imported roster file.
        Note: If you want to keep this feature, you need to add `last_import_hash` 
        to the Section table in your db/models.py file! It isn't currently there.
        """
        # Uncomment and fix if you add the column to models.py
        # row = self.db.query(SectionModel).filter(SectionModel.section_id == section_id).first()
        # if row:
        #     row.last_import_hash = file_hash
        #     self.db.commit()
        #     logger.info("Updated import hash for section=%s", section_id)
        pass

    def _to_dict(self, row: SectionModel) -> Dict:
        # Turn the comma-separated string back into a list for Flutter
        days = [d.strip() for d in row.day.split(",")] if row.day else []

        try:
            reminder = int(row.reminder_minutes or 10)
        except (ValueError, TypeError):
            reminder = 10

        return {
            "section_id":   row.section_id,
            "workspace_id": str(row.workspace_id), 
            "name":         str(row.section_id),
            "location":     row.location or "",
            "last_import_hash": "", # Fallback since column isn't in ERD yet
            "schedule": {
                "days":             days,
                "start_time":       row.start_time.strftime('%H:%M:%S') if row.start_time else "",
                "end_time":         row.end_time.strftime('%H:%M:%S') if row.end_time else "",
                "timezone":         "UTC",
                "reminder_minutes": reminder,
            },
        }