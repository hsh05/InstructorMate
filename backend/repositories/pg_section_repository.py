# backend/repositories/pg_section_repository.py

import logging
from typing import Dict, List

from sqlalchemy.orm import Session

from db.models import Section as SectionModel
from repositories.pg_workspace_repository import PgWorkspaceRepository

logger = logging.getLogger(__name__)


class PgSectionRepository:

    def __init__(self, db: Session, ws_repo: PgWorkspaceRepository):
        self.db      = db
        self.ws_repo = ws_repo  # kept so SectionService interface stays identical

    # ── Read ──────────────────────────────────────────────────────────────────

    def list_by_workspace(self, workspace_id: str) -> List[Dict]:
        rows = self.db.query(SectionModel).filter(
            SectionModel.workspace_id == workspace_id
        ).all()
        return [self._to_dict(row) for row in rows]

    # ── Write ─────────────────────────────────────────────────────────────────

    def save(self, workspace_id: str, section_data: Dict) -> None:
        schedule = section_data.get("schedule", {})

        # Serialise days list → "Mon,Wed,Fri" (matches existing behaviour)
        days_raw = schedule.get("days", [])
        days_str = ",".join(days_raw) if isinstance(days_raw, list) else days_raw

        # Guard: never store timezone string in end_time
        end_time = schedule.get("end_time", "")
        timezone = schedule.get("timezone", "UTC")
        if end_time and end_time == timezone:
            end_time = ""

        row = SectionModel(
            section_id       = section_data["section_id"],
            workspace_id     = workspace_id,
            name             = section_data.get("name", ""),
            location         = section_data.get("location", ""),
            days             = days_str,
            start_time       = schedule.get("start_time", ""),
            end_time         = end_time,
            timezone         = timezone,
            reminder_minutes = schedule.get("reminder_minutes", 10),
        )
        self.db.add(row)
        self.db.commit()
        logger.info("Saved section id=%s workspace=%s", row.section_id, workspace_id)

    def delete(self, workspace_id: str, section_id: str) -> bool:
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

    def _to_dict(self, row: SectionModel) -> Dict:
        days_raw = row.days or ""
        days = [d.strip() for d in days_raw.split(",") if d.strip()]

        end_time     = (row.end_time or "").strip()
        timezone_val = (row.timezone or "UTC").strip() or "UTC"
        if end_time and end_time == timezone_val:
            end_time = ""

        try:
            reminder = int(row.reminder_minutes or 10)
        except (ValueError, TypeError):
            reminder = 10

        return {
            "section_id":   row.section_id,
            "workspace_id": row.workspace_id,
            "name":         row.name or "",
            "location":     row.location or "",
            "schedule": {
                "days":             days,
                "start_time":       (row.start_time or "").strip(),
                "end_time":         end_time,
                "timezone":         timezone_val,
                "reminder_minutes": reminder,
            },
        }