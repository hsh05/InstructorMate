# backend/repositories/pg_structured_syllabus_repository.py

from __future__ import annotations
import logging
from typing import List, Dict
from sqlalchemy.orm import Session

from db.models import SyllabusWeeklyTopic, SyllabusCLO, SyllabusKeyDate

logger = logging.getLogger(__name__)


class PgStructuredSyllabusRepository:

    def __init__(self, db: Session) -> None:
        self.db = db

    # ── Write ────────────────────────────────────────────────────────────────

    def save(
        self,
        workspace_id: str,
        weekly_topics: List[Dict],
        clos: List[Dict],
        key_dates: List[Dict],
    ) -> None:
        """Replace all structured data for a workspace (safe to call on re-upload)."""
        self.db.query(SyllabusWeeklyTopic).filter_by(workspace_id=workspace_id).delete()
        self.db.query(SyllabusCLO).filter_by(workspace_id=workspace_id).delete()
        self.db.query(SyllabusKeyDate).filter_by(workspace_id=workspace_id).delete()

        for t in weekly_topics:
            self.db.add(SyllabusWeeklyTopic(
                workspace_id=workspace_id,
                week_number=t.get("week_number", 0),
                topic=t.get("topic", ""),
                description=t.get("description"),
            ))

        for c in clos:
            self.db.add(SyllabusCLO(
                workspace_id=workspace_id,
                clo_id=c.get("clo_id", ""),
                text=c.get("text", ""),
                bloom_level=c.get("bloom_level"),
            ))

        for d in key_dates:
            self.db.add(SyllabusKeyDate(
                workspace_id=workspace_id,
                label=d.get("label", ""),
                date_text=d.get("date_text", ""),
                date_type=d.get("date_type", "other"),
            ))

        self.db.commit()
        logger.info(
            "Saved structured syllabus for workspace=%s: %d topics, %d CLOs, %d key dates",
            workspace_id, len(weekly_topics), len(clos), len(key_dates),
        )

    # ── Read ─────────────────────────────────────────────────────────────────

    def get_weekly_topics(self, workspace_id: str) -> List[Dict]:
        rows = (
            self.db.query(SyllabusWeeklyTopic)
            .filter_by(workspace_id=workspace_id)
            .order_by(SyllabusWeeklyTopic.week_number)
            .all()
        )
        return [{"week_number": r.week_number, "topic": r.topic, "description": r.description} for r in rows]

    def get_clos(self, workspace_id: str) -> List[Dict]:
        rows = (
            self.db.query(SyllabusCLO)
            .filter_by(workspace_id=workspace_id)
            .order_by(SyllabusCLO.id)
            .all()
        )
        return [{"clo_id": r.clo_id, "text": r.text, "bloom_level": r.bloom_level} for r in rows]

    def get_key_dates(self, workspace_id: str) -> List[Dict]:
        rows = (
            self.db.query(SyllabusKeyDate)
            .filter_by(workspace_id=workspace_id)
            .order_by(SyllabusKeyDate.id)
            .all()
        )
        return [{"label": r.label, "date_text": r.date_text, "date_type": r.date_type} for r in rows]

    def has_data(self, workspace_id: str) -> bool:
        return self.db.query(SyllabusWeeklyTopic).filter_by(workspace_id=workspace_id).count() > 0