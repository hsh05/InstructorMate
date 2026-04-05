# backend/repositories/pg_student_repository.py

import logging
from typing import List

from sqlalchemy.orm import Session

from db.models import Student, Enrollment, Workspace
from repositories.pg_workspace_repository import PgWorkspaceRepository

logger = logging.getLogger(__name__)


class PgStudentRepository:

    def __init__(self, db: Session, ws_repo: PgWorkspaceRepository):
        self.db      = db
        self.ws_repo = ws_repo

    # ── Read ──────────────────────────────────────────────────────────────────

    def list_by_workspace(self, workspace_id: int) -> List[dict]:
        # Join through the Enrollment table to find students in this workspace
        rows = (
            self.db.query(Student)
            .join(Enrollment, Enrollment.student_id == Student.student_id)
            .filter(Enrollment.workspace_id == workspace_id)
            .distinct() # Prevent duplicates if they are in multiple sections
            .all()
        )
        return [self._to_dict(row, workspace_id=workspace_id) for row in rows]

    def list_by_section(self, workspace_id: int, section_id: str) -> List[dict]:
        rows = (
            self.db.query(Student)
            .join(Enrollment, Enrollment.student_id == Student.student_id)
            .filter(
                Enrollment.workspace_id == workspace_id,
                Enrollment.section_id == section_id,
            )
            .all()
        )
        return [self._to_dict(row, workspace_id=workspace_id, section_id=section_id) for row in rows]

    def count_by_section(self, workspace_id: int, section_id: str) -> int:
        return (
            self.db.query(Enrollment)
            .filter(
                Enrollment.workspace_id == workspace_id,
                Enrollment.section_id == section_id,
            )
            .count()
        )

    # ── Write ─────────────────────────────────────────────────────────────────

    def save(self, student, section_id: str = "") -> None:
        """
        Upserts the student into the Global University Roster (Students table),
        then creates an Enrollment record linking them to the Section.
        """
        actual_id = (student.student_no or student.student_id).strip()
        workspace_id = int(student.workspace_id)
        section_id = (section_id or "").strip()

        # 1. UPSERT THE GLOBAL STUDENT
        db_student = self.db.query(Student).filter(Student.student_id == actual_id).first()
        
        if db_student:
            db_student.student_name = student.name or db_student.student_name
        else:
            db_student = Student(
                student_id=actual_id,
                student_name=student.name,
            )
            self.db.add(db_student)
            
        self.db.flush() # Ensure the student exists before linking enrollment

        # 2. CREATE THE ENROLLMENT LINK
        if section_id:
            exists = self.db.query(Enrollment).filter(
                Enrollment.student_id == actual_id,
                Enrollment.workspace_id == workspace_id,
                Enrollment.section_id == section_id,
            ).first()
            
            if not exists:
                self.db.add(Enrollment(
                    student_id=actual_id,
                    workspace_id=workspace_id,
                    section_id=section_id,
                ))

        self.db.commit()
        logger.debug("Saved student id=%s workspace=%s section=%s", actual_id, workspace_id, section_id)


    def clear_section(self, workspace_id: int, section_id: str) -> int:
        """
        Remove all students from a section.
        This ONLY deletes the Enrollment tickets. The students remain safely in the global database.
        """
        deleted = self.db.query(Enrollment).filter(
            Enrollment.workspace_id == workspace_id,
            Enrollment.section_id == section_id
        ).delete()
        
        self.db.commit()
        logger.info("Cleared %d enrollments from section=%s workspace=%s", deleted, section_id, workspace_id)
        return deleted

    def delete_student(self, workspace_id: int, section_id: str, student_id: str) -> bool:
        """
        Removes a single student's Enrollment ticket for this specific section.
        """
        deleted = self.db.query(Enrollment).filter(
            Enrollment.student_id == student_id,
            Enrollment.workspace_id == workspace_id,
            Enrollment.section_id == section_id,
        ).delete()
        
        self.db.commit()
        
        if deleted > 0:
            logger.info("Deleted enrollment for student id=%s from section=%s", student_id, section_id)
            return True
        return False

    # ── Private ───────────────────────────────────────────────────────────────

    def _to_dict(self, row: Student, workspace_id: int = 0, section_id: str = "") -> dict:
        """
        Maps the database row to the dictionary format expected by your Flutter frontend.
        """
        return {
            "student_id":   row.student_id,
            "workspace_id": str(workspace_id), # Cast back to string for Flutter
            "section_id":   section_id,
            "student_no":   row.student_id,    # University ID
            "name":         row.student_name,  # Mapped from student_name
            # Since email was removed from the DB, we generate their AAU email dynamically
            "email":        f"{row.student_id}@aau.ac.ae", 
        }