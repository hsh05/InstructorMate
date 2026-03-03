# backend/repositories/pg_student_repository.py

import logging
from typing import List

from sqlalchemy.orm import Session

from domain.student import Student
from db.models import Student as StudentModel
from repositories.pg_workspace_repository import PgWorkspaceRepository

logger = logging.getLogger(__name__)


class PgStudentRepository:

    def __init__(self, db: Session, ws_repo: PgWorkspaceRepository):
        self.db      = db
        self.ws_repo = ws_repo  # kept so StudentService interface stays identical

    # ── Read ──────────────────────────────────────────────────────────────────

    def list_by_workspace(self, workspace_id: str) -> List[dict]:
        rows = self.db.query(StudentModel).filter(
            StudentModel.workspace_id == workspace_id
        ).all()
        return [self._to_dict(row) for row in rows]

    def list_by_section(self, workspace_id: str, section_id: str) -> List[dict]:
        rows = self.db.query(StudentModel).filter(
            StudentModel.workspace_id == workspace_id,
            StudentModel.section_id   == section_id,
        ).all()
        return [self._to_dict(row) for row in rows]

    def count_by_section(self, workspace_id: str, section_id: str) -> int:
        return self.db.query(StudentModel).filter(
            StudentModel.workspace_id == workspace_id,
            StudentModel.section_id   == section_id,
        ).count()

    # ── Write ─────────────────────────────────────────────────────────────────

    def save(self, student: Student) -> None:
        row = StudentModel(
            student_id   = student.student_id,
            workspace_id = student.workspace_id,
            section_id   = getattr(student, "section_id", ""),
            student_no   = getattr(student, "student_no", ""),
            name         = student.name,
            email        = student.email,
        )
        self.db.add(row)
        self.db.commit()
        logger.info("Saved student id=%s workspace=%s", student.student_id, student.workspace_id)

    # ── Private ───────────────────────────────────────────────────────────────

    def _to_dict(self, row: StudentModel) -> dict:
        return {
            "student_id":   row.student_id,
            "workspace_id": row.workspace_id,
            "section_id":   row.section_id or "",
            "student_no":   row.student_no or "",
            "name":         row.name or "",
            "email":        row.email or "",
        }