# backend/repositories/pg_student_repository.py

import logging
from typing import List

from sqlalchemy import func as sqlfunc
from sqlalchemy.orm import Session

from db.models import (
    Student as StudentModel,
    StudentSection as StudentSectionModel,
    Workspace as WorkspaceModel,
)
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
            existing.name       = student.name or existing.name
            existing.student_no = student_no   or existing.student_no
            existing.email      = email        or existing.email
            actual_id = existing.student_id
        else:
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

        self._touch_workspace(student.workspace_id)
        self.db.commit()
        logger.debug("Saved student id=%s workspace=%s section=%s",
                     actual_id, student.workspace_id, section_id)

    def delete_by_section(self, section_id: str) -> int:
        """
        Remove all StudentSection links for this section so the roster
        can be replaced on re-import. Student rows are kept so deduplication
        works correctly on re-import.
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
        """
        links = self.db.query(StudentSectionModel).filter(
            StudentSectionModel.section_id == section_id
        ).all()
        student_ids = [l.student_id for l in links]

        self.db.query(StudentSectionModel).filter(
            StudentSectionModel.section_id == section_id
        ).delete()
        self.db.flush()

        removed = 0
        for sid in student_ids:
            remaining = (
                self.db.query(StudentSectionModel)
                .join(StudentModel, StudentModel.student_id == StudentSectionModel.student_id)
                .filter(
                    StudentModel.workspace_id      == workspace_id,
                    StudentSectionModel.student_id == sid,
                )
                .count()
            )
            if remaining == 0:
                self.db.query(StudentModel).filter(
                    StudentModel.student_id == sid
                ).delete()
                removed += 1

        self._touch_workspace(workspace_id)
        self.db.commit()
        logger.info("Cleared %d students from section=%s workspace=%s",
                    removed, section_id, workspace_id)
        return removed

    def delete_student(self, workspace_id: str, section_id: str, student_id: str) -> bool:
        """
        Remove a single student from a section.
        Deletes the StudentSection link. If the student has no other section
        links in this workspace, also deletes the Student row itself.
        """
        link = self.db.query(StudentSectionModel).filter(
            StudentSectionModel.student_id == student_id,
            StudentSectionModel.section_id == section_id,
        ).first()
        if not link:
            return False

        self.db.delete(link)
        self.db.flush()

        remaining = (
            self.db.query(StudentSectionModel)
            .join(StudentModel, StudentModel.student_id == StudentSectionModel.student_id)
            .filter(
                StudentModel.workspace_id      == workspace_id,
                StudentSectionModel.student_id == student_id,
            )
            .count()
        )
        if remaining == 0:
            self.db.query(StudentModel).filter(
                StudentModel.student_id == student_id
            ).delete()

        self._touch_workspace(workspace_id)
        self.db.commit()
        logger.info("Deleted student id=%s from section=%s", student_id, section_id)
        return True

    # ── Private ───────────────────────────────────────────────────────────────

    def _touch_workspace(self, workspace_id: str) -> None:
        """
        Update workspace updated_at so Flutter shows the correct
        'Updated X ago' timestamp after any student mutation.
        """
        self.db.query(WorkspaceModel).filter(
            WorkspaceModel.workspace_id == workspace_id
        ).update({"updated_at": sqlfunc.now()}, synchronize_session=False)

    def _to_dict(self, row: StudentModel, section_id: str = "") -> dict:
        return {
            "student_id":   row.student_id,
            "workspace_id": row.workspace_id,
            "section_id":   section_id,
            "student_no":   row.student_no or "",
            "name":         row.name or "",
            "email":        row.email or "",
        }