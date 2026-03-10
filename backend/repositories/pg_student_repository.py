# backend/repositories/pg_student_repository.py
#
# SCHEMA NOTE (normalized)
# ────────────────────────
# Student table no longer has a section_id column.
# The Student <-> Section relationship is now via the StudentSection join table:
#   StudentSection: id, student_id, section_id
#
# list_by_section / count_by_section join through StudentSection.
# import_students creates a StudentSection row for each student.

import logging
from typing import List

from sqlalchemy.orm import Session

from db.models import Student as StudentModel, StudentSection as StudentSectionModel
from repositories.pg_workspace_repository import PgWorkspaceRepository

logger = logging.getLogger(__name__)


class PgStudentRepository:

    def __init__(self, db: Session, ws_repo: PgWorkspaceRepository):
        self.db      = db
        self.ws_repo = ws_repo

    # ── Read ──────────────────────────────────────────────────────────────────

    def list_by_workspace(self, workspace_id: str) -> List[dict]:
        rows = self.db.query(StudentModel).filter(
            StudentModel.workspace_id == workspace_id
        ).all()
        return [self._to_dict(row) for row in rows]

    def list_by_section(self, workspace_id: str, section_id: str) -> List[dict]:
        rows = (
            self.db.query(StudentModel)
            .join(StudentSectionModel,
                  StudentSectionModel.student_id == StudentModel.student_id)
            .filter(
                StudentModel.workspace_id        == workspace_id,
                StudentSectionModel.section_id   == section_id,
            )
            .all()
        )
        return [self._to_dict(row, section_id=section_id) for row in rows]

    def count_by_section(self, workspace_id: str, section_id: str) -> int:
        return (
            self.db.query(StudentModel)
            .join(StudentSectionModel,
                  StudentSectionModel.student_id == StudentModel.student_id)
            .filter(
                StudentModel.workspace_id        == workspace_id,
                StudentSectionModel.section_id   == section_id,
            )
            .count()
        )

    # ── Write ─────────────────────────────────────────────────────────────────

    def save(self, student) -> None:
        """
        Save a student row and, if section_id is provided, create a
        StudentSection link. Uses merge so re-importing the same student_id
        (same email within workspace) updates rather than duplicates.
        """
        row = StudentModel(
            student_id   = student.student_id,
            workspace_id = student.workspace_id,
            student_no   = getattr(student, "student_no", "") or "",
            name         = student.name,
            email        = student.email,
        )
        self.db.merge(row)
        self.db.flush()

        section_id = getattr(student, "section_id", "") or ""
        if section_id:
            # Upsert StudentSection (ignore if already linked)
            existing = self.db.query(StudentSectionModel).filter(
                StudentSectionModel.student_id == student.student_id,
                StudentSectionModel.section_id == section_id,
            ).first()
            if not existing:
                self.db.add(StudentSectionModel(
                    student_id = student.student_id,
                    section_id = section_id,
                ))

        self.db.commit()
        logger.info("Saved student id=%s workspace=%s section=%s",
                    student.student_id, student.workspace_id, section_id)

    def delete_by_section(self, section_id: str) -> int:
        """Remove all StudentSection links for a section (used when replacing roster)."""
        deleted = self.db.query(StudentSectionModel).filter(
            StudentSectionModel.section_id == section_id
        ).delete()
        self.db.commit()
        return deleted

    # ── Private ───────────────────────────────────────────────────────────────

    def _to_dict(self, row: StudentModel, section_id: str = "") -> dict:
        return {
            "student_id":   row.student_id,
            "workspace_id": row.workspace_id,
            "section_id":   section_id,
            "student_no":   row.student_no or "",
            "name":         row.name or "",
            "email":        row.email or "",
        }