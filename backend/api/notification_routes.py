# backend/api/notification_routes.py

import logging
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from db.database import get_db
from repositories.pg_workspace_repository import PgWorkspaceRepository
from repositories.pg_structured_syllabus_repository import PgStructuredSyllabusRepository

logger = logging.getLogger(__name__)
router = APIRouter()

_TYPE_ICONS = {
    "exam":       "📝",
    "assignment": "📋",
    "deadline":   "⏳",
    "other":      "📅",
}

_TYPE_TITLES = {
    "exam":       "Upcoming Exam",
    "assignment": "Assignment Due",
    "deadline":   "Deadline",
    "other":      "Important Date",
}


def get_structured_repo(db: Session = Depends(get_db)) -> PgStructuredSyllabusRepository:
    return PgStructuredSyllabusRepository(db)


def get_workspace_repo(db: Session = Depends(get_db)) -> PgWorkspaceRepository:
    return PgWorkspaceRepository(db)


@router.get("/workspaces/{workspace_id}/notifications/upcoming")
def get_upcoming_notifications(
    workspace_id: str,
    workspace_repo:  PgWorkspaceRepository          = Depends(get_workspace_repo),
    structured_repo: PgStructuredSyllabusRepository = Depends(get_structured_repo),
):
    """Return key dates formatted as notification-ready items for Flutter's
    NotificationScheduler to consume. Flutter calls this on app launch and
    schedules one-shot reminders for each item."""
    ws = workspace_repo.get_by_id(workspace_id)
    if not ws:
        raise HTTPException(status_code=404, detail="Workspace not found")

    key_dates = structured_repo.get_key_dates(workspace_id)
    notifications = []

    for kd in key_dates:
        date_type = kd.get("date_type", "other")
        icon      = _TYPE_ICONS.get(date_type, "📅")
        title     = f"{icon} {_TYPE_TITLES.get(date_type, 'Important Date')}"
        body      = f"{kd['label']} — {kd['date_text']}"

        notifications.append({
            "type":       date_type,
            "title":      title,
            "body":       body,
            "label":      kd["label"],
            "date_text":  kd["date_text"],
            "date_type":  date_type,
        })

    logger.info("Returning %d notification items for workspace=%s", len(notifications), workspace_id)
    return {"notifications": notifications}