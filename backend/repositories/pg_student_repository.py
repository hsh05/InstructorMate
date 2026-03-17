# backend/repositories/pg_student_repository.py
#
# SCHEMA NOTE (normalized)
# ────────────────────────
# Student table has no section_id column.
# Student <-> Section relationship is via StudentSection join table.
#
# DEDUPLICATION
# ─────────────
# Students are deduplicated by (workspace_id, email) as a natural key.
# If a student with the same email already exists in this workspace,
# save() reuses their existing student_id instead of creating a duplicate.
# Falls back to (workspace_id, student_no) if email is blank.

import logging
import uuid
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
                StudentModel.workspace_id      == workspace_id,
                StudentSectionModel.section_id == section_id,
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
                StudentModel.workspace_id      == workspace_id,
                StudentSectionModel.section_id == section_id,
            )
            .count()
        )

    # ── Write ─────────────────────────────────────────────────────────────────

    def save(self, student, section_id: str = "") -> None:
        """
        Upsert student by natural key (workspace_id + email), or
        (workspace_id + student_no) if email is blank.
        Reuses existing student_id to avoid duplicates on re-import.
        Then creates a StudentSection link if not already present.

        section_id is passed explicitly — it is NOT a property of the
        Student domain object since a student can belong to multiple
        sections via the StudentSection join table.
        """
        email      = (getattr(student, "email",      "") or "").strip()
        student_no = (getattr(student, "student_no", "") or "").strip()
        section_id = (section_id or "").strip()

        # Look up existing student by natural key
        existing = None
        if email:
            existing = self.db.query(StudentModel).filter(
                StudentModel.workspace_id == student.workspace_id,
                StudentModel.email        == email,
            ).first()
        if not existing and student_no:
            existing = self.db.query(StudentModel).filter(
                StudentModel.workspace_id == student.workspace_id,
                StudentModel.student_no   == student_no,
            ).first()

        if existing:
            # Update fields in case name/student_no changed
            existing.name       = student.name or existing.name
            existing.student_no = student_no   or existing.student_no
            existing.email      = email        or existing.email
            actual_id = existing.student_id
        else:
            # New student — use the id from the domain object (uuid already set)
            row = StudentModel(
                student_id   = student.student_id,
                workspace_id = student.workspace_id,
                student_no   = student_no,
                name         = student.name,
                email        = email,
            )
            self.db.add(row)
            actual_id = student.student_id

        self.db.flush()

        # Create StudentSection link if not already present
        if section_id:
            exists = self.db.query(StudentSectionModel).filter(
                StudentSectionModel.student_id == actual_id,
                StudentSectionModel.section_id == section_id,
            ).first()
            if not exists:
                self.db.add(StudentSectionModel(
                    student_id = actual_id,
                    section_id = section_id,
                ))

        self.db.commit()
        logger.debug("Saved student id=%s workspace=%s section=%s",
                     actual_id, student.workspace_id, section_id)

    def delete_by_section(self, section_id: str) -> int:
        """
        Remove all StudentSection links for this section so the roster
        can be replaced on re-import. Student rows are intentionally kept
        so that email/student_no deduplication works correctly on re-import.
        Returns number of StudentSection rows removed.
        """
        deleted = self.db.query(StudentSectionModel).filter(
            StudentSectionModel.section_id == section_id
        ).delete()
        self.db.commit()
        logger.info("Removed %d section links for section=%s", deleted, section_id)
        return deleted
    def clear_section(self, workspace_id: str, section_id: str) -> int:
        """
        Remove all students from a section.
        Deletes all StudentSection links for this section, then removes
        any Student rows that have no remaining section links in this workspace.
        Returns the number of students removed.
        """
        # Find all student IDs in this section
        links = self.db.query(StudentSectionModel).filter(
            StudentSectionModel.section_id == section_id
        ).all()
        student_ids = [l.student_id for l in links]

        # Delete all StudentSection links for this section
        self.db.query(StudentSectionModel).filter(
            StudentSectionModel.section_id == section_id
        ).delete()
        self.db.flush()

        # Delete orphaned Student rows (no other section links in this workspace)
        removed = 0
        for sid in student_ids:
            remaining = (
                self.db.query(StudentSectionModel)
                .join(StudentModel, StudentModel.student_id == StudentSectionModel.student_id)
                .filter(
                    StudentModel.workspace_id == workspace_id,
                    StudentSectionModel.student_id == sid,
                )
                .count()
            )
            if remaining == 0:
                self.db.query(StudentModel).filter(
                    StudentModel.student_id == sid
                ).delete()
                removed += 1

        self.db.commit()
        logger.info("Cleared %d students from section=%s workspace=%s",
                    removed, section_id, workspace_id)
        return removed

    def delete_student(self, workspace_id: str, section_id: str, student_id: str) -> bool:
        """
        Remove a single student from a section.
        Deletes the StudentSection link. If the student has no other section
        links in this workspace, also deletes the Student row itself.
        Returns True if the student was found and removed.
        """
        link = self.db.query(StudentSectionModel).filter(
            StudentSectionModel.student_id == student_id,
            StudentSectionModel.section_id == section_id,
        ).first()
        if not link:
            return False

        self.db.delete(link)
        self.db.flush()

        # Check if student has any remaining section links in this workspace
        remaining = (
            self.db.query(StudentSectionModel)
            .join(StudentModel, StudentModel.student_id == StudentSectionModel.student_id)
            .filter(
                StudentModel.workspace_id == workspace_id,
                StudentSectionModel.student_id == student_id,
            )
            .count()
        )
        if remaining == 0:
            # No other section links — safe to delete the student row too
            self.db.query(StudentModel).filter(
                StudentModel.student_id == student_id
            ).delete()

        self._touch_workspace(workspace_id)
        self.db.commit()
        logger.info("Deleted student id=%s from section=%s", student_id, section_id)
        return True

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