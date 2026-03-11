# backend/repositories/pg_section_repository.py
#
# SCHEMA NOTE (normalized)
# ────────────────────────
# Section table no longer has 'days' or 'timezone' columns.
# Days are stored in the SectionDay table (one row per day per section).
# Timezone is not persisted — always returned as "UTC" placeholder;
# the actual timezone context lives in the Flutter app.
#
# TIME FORMAT NOTE
# ────────────────
# start_time / end_time stored as-is from Flutter ("9:00 AM" or "09:00").

import logging
from typing import Dict, List

from sqlalchemy.orm import Session

from repositories.pg_workspace_repository import PgWorkspaceRepository
from db.models import Section as SectionModel, SectionDay as SectionDayModel

logger = logging.getLogger(__name__)


class PgSectionRepository:

    def __init__(self, db: Session, ws_repo: PgWorkspaceRepository):
        self.db      = db
        self.ws_repo = ws_repo

    # ── Read ──────────────────────────────────────────────────────────────────

    def list_by_workspace(self, workspace_id: str) -> List[Dict]:
        rows = self.db.query(SectionModel).filter(
            SectionModel.workspace_id == workspace_id
        ).all()
        return [self._to_dict(row) for row in rows]

    # ── Write ─────────────────────────────────────────────────────────────────

    def save(self, workspace_id: str, section_data: Dict) -> None:
        schedule = section_data.get("schedule", {})

        row = SectionModel(
            section_id       = section_data["section_id"],
            workspace_id     = workspace_id,
            name             = section_data.get("name", ""),
            location         = section_data.get("location", ""),
            start_time       = schedule.get("start_time", ""),
            end_time         = schedule.get("end_time", ""),
            reminder_minutes = schedule.get("reminder_minutes", 10),
        )
        self.db.add(row)
        self.db.flush()  # write section_id to DB before inserting days

        self._replace_days(row.section_id, schedule.get("days", []))
        self.db.commit()
        logger.info("Saved section id=%s workspace=%s", row.section_id, workspace_id)

    def update(self, workspace_id: str, section_id: str, section_data: Dict) -> bool:
        """Update section in-place, preserving section_id and all linked students."""
        row = self.db.query(SectionModel).filter(
            SectionModel.workspace_id == workspace_id,
            SectionModel.section_id   == section_id,
        ).first()
        if not row:
            return False

        schedule = section_data.get("schedule", {})

        row.name             = section_data.get("name", row.name)
        row.location         = section_data.get("location", row.location)
        row.start_time       = schedule.get("start_time", row.start_time)
        row.end_time         = schedule.get("end_time", row.end_time)
        row.reminder_minutes = schedule.get("reminder_minutes", row.reminder_minutes)

        # Replace days entirely
        self._replace_days(section_id, schedule.get("days", []))

        self.db.commit()
        logger.info("Updated section id=%s workspace=%s", section_id, workspace_id)
        return True

    def delete(self, workspace_id: str, section_id: str) -> bool:
        row = self.db.query(SectionModel).filter(
            SectionModel.workspace_id == workspace_id,
            SectionModel.section_id   == section_id,
        ).first()
        if not row:
            return False
        self.db.delete(row)  # SectionDay rows cascade via FK
        self.db.commit()
        logger.info("Deleted section id=%s workspace=%s", section_id, workspace_id)
        return True

    # ── Private ───────────────────────────────────────────────────────────────

    def update_import_hash(self, section_id: str, file_hash: str) -> None:
        """Store the hash of the last successfully imported roster file."""
        row = self.db.query(SectionModel).filter(
            SectionModel.section_id == section_id
        ).first()
        if row:
            row.last_import_hash = file_hash
            self.db.commit()
            logger.info("Updated import hash for section=%s", section_id)

    def _replace_days(self, section_id: str, days: list) -> None:
        """Delete existing SectionDay rows and insert fresh ones."""
        self.db.query(SectionDayModel).filter(
            SectionDayModel.section_id == section_id
        ).delete()
        for day in days:
            day = day.strip()
            if day:
                self.db.add(SectionDayModel(section_id=section_id, day=day))            

    def _to_dict(self, row: SectionModel) -> Dict:
        day_rows = self.db.query(SectionDayModel).filter(
            SectionDayModel.section_id == row.section_id
        ).all()
        days = [d.day for d in day_rows]

        try:
            reminder = int(row.reminder_minutes or 10)
        except (ValueError, TypeError):
            reminder = 10

        return {
            "section_id":   row.section_id,
            "workspace_id": row.workspace_id,
            "name":         row.name or "",
            "location":     row.location or "",
            "last_import_hash": row.last_import_hash or "", 
            "schedule": {
                "days":             days,
                "start_time":       (row.start_time or "").strip(),
                "end_time":         (row.end_time or "").strip(),
                "timezone":         "UTC",
                "reminder_minutes": reminder,
            },
        }