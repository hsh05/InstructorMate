# backend/repositories/pg_repository.py

import csv
import logging
import shutil
from pathlib import Path
from typing import Any, Dict, List, Optional

from openai import OpenAI
from sqlalchemy.orm import Session

from domain.models import Workspace, Student
from domain.enums import WorkspaceStatus
from db.models import Workspace as WorkspaceModel, Section as SectionModel, Instructor as InstructorModel, Enrollment

logger = logging.getLogger(__name__)

# ==============================================================================
# ── WORKSPACE REPOSITORY ──────────────────────────────────────────────────────
# ==============================================================================
class PgWorkspaceRepository:
    def __init__(self, db: Session, data_dir: str = "backend/data"):
        self.db = db
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)

    def workspace_dir(self, workspace_id: int) -> Path:
        return self.data_dir / str(workspace_id)

    def get_chunks_csv_path(self, workspace_id: int) -> Path:
        return self.workspace_dir(workspace_id) / "chunks.csv"

    def list_all(self) -> List[Workspace]:
        rows = self.db.query(WorkspaceModel).all()
        return [self._to_domain(row) for row in rows]

    def get_by_id(self, workspace_id: int) -> Optional[Workspace]:
        row = self.db.query(WorkspaceModel).filter(WorkspaceModel.workspace_id == workspace_id).first()
        return self._to_domain(row) if row else None

    def save(self, workspace: Workspace) -> None:
        instructor = self.db.query(InstructorModel).first()
        if not instructor:
            raise Exception("No instructor found! Please create an instructor first.")

        c_code  = workspace.fields.get('course_code') or workspace.fields.get('workspace_code') or "TBD"
        semester = workspace.fields.get('semester') or "TBD"
        c_title = workspace.fields.get('course_title') or workspace.fields.get('workspace_title') or "Untitled Workspace"

        w_sched = workspace.fields.get('weekly_schedule')
        a_sched = workspace.fields.get('assessments_schedule')

        if workspace.workspace_id:
            w_id = int(workspace.workspace_id)
            row = self.db.query(WorkspaceModel).filter(WorkspaceModel.workspace_id == w_id).first()
            if row:
                row.course_code = c_code
                row.semester = semester
                row.course_title = c_title
                row.weekly_schedule = w_sched
                row.assessments_schedule = a_sched
                if hasattr(workspace, 'content') and workspace.content:
                    row.content = workspace.content
                self.db.commit()
                return

        row = WorkspaceModel(
            instructor_id = instructor.instructor_id,
            course_code   = c_code,
            semester      = semester, 
            course_title  = c_title,
            weekly_schedule = w_sched,
            assessments_schedule = a_sched,
            chunk_index   = 0,
            content       = getattr(workspace, 'content', None) or "Processing..."
        )
        self.db.add(row)
        self.db.flush() 
        workspace.workspace_id = str(row.workspace_id) 
        self.db.commit()

    def delete(self, workspace_id: int) -> bool:
        row = self.db.query(WorkspaceModel).filter(WorkspaceModel.workspace_id == workspace_id).first()
        if not row: return False
        self.db.delete(row)
        self.db.commit()
        ws_dir = self.workspace_dir(workspace_id)
        if ws_dir.exists(): shutil.rmtree(ws_dir)
        return True

    def save_chunks(self, workspace_id: int, chunks_csv_path: Path) -> None:
        combined_content = ""
        try:
            with open(chunks_csv_path, newline="", encoding="utf-8") as f:
                reader = csv.DictReader(f)
                for row in reader:
                    content = (row.get("text") or "").strip()
                    if content: combined_content += content + "\n\n"
        except FileNotFoundError:
            return

        workspace = self.db.query(WorkspaceModel).filter(WorkspaceModel.workspace_id == workspace_id).first()
        if workspace:
            workspace.content = combined_content.strip()
            self.db.commit()

    def get_chunks_for_ask(self, workspace_id: int) -> List[Dict[str, Any]]:
        row = self.db.query(WorkspaceModel).filter(WorkspaceModel.workspace_id == workspace_id).first()
        if not row or not row.content: return []
        return [{"chunk_id": 1, "page": 1, "content": row.content, "embedding": row.embedding}]

    def generate_and_save_embeddings(self, workspace_id: int) -> int:
        workspace = self.db.query(WorkspaceModel).filter(WorkspaceModel.workspace_id == workspace_id).first()
        if not workspace or not workspace.content or workspace.embedding: return 0

        client = OpenAI()
        try:
            resp = client.embeddings.create(model="text-embedding-3-small", input=[workspace.content])
            workspace.embedding = resp.data[0].embedding
            self.db.commit()
            return 1
        except Exception as exc:
            logger.error("Embedding failed for workspace=%s: %s", workspace_id, exc)
            return 0

    def _to_domain(self, row: WorkspaceModel) -> Workspace:
        fields = {
            "course_code":     row.course_code,
            "workspace_code":  row.course_code,  
            "semester":        row.semester,
            "course_title":    row.course_title,
            "workspace_title": row.course_title,
            "weekly_schedule": row.weekly_schedule,
            "assessments_schedule": row.assessments_schedule
        }
        ws = Workspace(
            workspace_id = str(row.workspace_id),
            file_hash    = row.file_hash if hasattr(row, 'file_hash') and row.file_hash else "",
            status       = WorkspaceStatus("ready" if getattr(row, 'content', None) else "draft"),
            fields       = fields,
        )
        ws._created_at = ws._updated_at = ""
        return ws


# ==============================================================================
# ── SECTION REPOSITORY ────────────────────────────────────────────────────────
# ==============================================================================
class PgSectionRepository:
    def __init__(self, db: Session, ws_repo: PgWorkspaceRepository):
        self.db = db
        self.ws_repo = ws_repo

    def list_by_workspace(self, workspace_id: int) -> List[Dict]:
        rows = self.db.query(SectionModel).filter(SectionModel.workspace_id == workspace_id).all()
        return [self._to_dict(row) for row in rows]

    def save(self, workspace_id: int, section_data: Dict) -> None:
        schedule = section_data.get("schedule", {})
        days_string = ", ".join([d.strip() for d in schedule.get("days", []) if d.strip()])

        row = SectionModel(
            section_id       = section_data["section_id"],
            workspace_id     = workspace_id,
            location         = section_data.get("location", ""),
            start_time       = schedule.get("start_time", None),
            end_time         = schedule.get("end_time", None),
            reminder_minutes = schedule.get("reminder_minutes", 10),
            day              = days_string 
        )
        self.db.add(row)
        self.db.commit()

    def update(self, workspace_id: int, section_id: str, section_data: Dict) -> bool:
        row = self.db.query(SectionModel).filter(
            SectionModel.workspace_id == workspace_id, SectionModel.section_id == section_id
        ).first()
        if not row: return False

        schedule = section_data.get("schedule", {})
        row.location = section_data.get("location", row.location)
        row.start_time = schedule.get("start_time", row.start_time)
        row.end_time = schedule.get("end_time", row.end_time)
        row.reminder_minutes = schedule.get("reminder_minutes", row.reminder_minutes)
        row.day = ", ".join([d.strip() for d in schedule.get("days", []) if d.strip()])

        self.db.commit()
        return True

    def delete(self, workspace_id: int, section_id: str) -> bool:
        row = self.db.query(SectionModel).filter(
            SectionModel.workspace_id == workspace_id, SectionModel.section_id == section_id
        ).first()
        if not row: return False
        self.db.delete(row)  
        self.db.commit()
        return True

    def _to_dict(self, row: SectionModel) -> Dict:
        days = [d.strip() for d in row.day.split(",")] if row.day else []
        try: reminder = int(row.reminder_minutes or 10)
        except (ValueError, TypeError): reminder = 10

        return {
            "section_id":   row.section_id,
            "workspace_id": str(row.workspace_id), 
            "name":         str(row.section_id),
            "location":     row.location or "",
            "last_import_hash": "",
            "schedule": {
                "days":             days,
                "start_time":       row.start_time.strftime('%H:%M:%S') if row.start_time else "",
                "end_time":         row.end_time.strftime('%H:%M:%S') if row.end_time else "",
                "timezone":         "UTC",
                "reminder_minutes": reminder,
            },
        }


# ==============================================================================
# ── STUDENT REPOSITORY ────────────────────────────────────────────────────────
# ==============================================================================
class PgStudentRepository:
    def __init__(self, db: Session, ws_repo: PgWorkspaceRepository):
        self.db = db
        self.ws_repo = ws_repo

    def list_by_workspace(self, workspace_id: int) -> List[dict]:
        rows = self.db.query(Student.__module__).join(Enrollment, Enrollment.student_id == Student.__module__.student_id).filter(Enrollment.workspace_id == workspace_id).distinct().all()
        return [self._to_dict(row, workspace_id=workspace_id) for row in rows]

    def list_by_section(self, workspace_id: int, section_id: str) -> List[dict]:
        from db.models import Student as DBStudent
        rows = self.db.query(DBStudent).join(Enrollment, Enrollment.student_id == DBStudent.student_id).filter(
            Enrollment.workspace_id == workspace_id, Enrollment.section_id == section_id
        ).all()
        return [self._to_dict(row, workspace_id=workspace_id, section_id=section_id) for row in rows]

    def count_by_section(self, workspace_id: int, section_id: str) -> int:
        return self.db.query(Enrollment).filter(
            Enrollment.workspace_id == workspace_id, Enrollment.section_id == section_id
        ).count()

    def save(self, student, section_id: str = "") -> None:
        from db.models import Student as DBStudent
        actual_id = (student.student_no or student.student_id).strip()
        workspace_id = int(student.workspace_id)
        section_id = (section_id or "").strip()

        db_student = self.db.query(DBStudent).filter(DBStudent.student_id == actual_id).first()
        if db_student:
            db_student.student_name = student.name or db_student.student_name
        else:
            db_student = DBStudent(student_id=actual_id, student_name=student.name)
            self.db.add(db_student)
            
        self.db.flush() 

        if section_id:
            exists = self.db.query(Enrollment).filter(
                Enrollment.student_id == actual_id, Enrollment.workspace_id == workspace_id, Enrollment.section_id == section_id
            ).first()
            if not exists:
                self.db.add(Enrollment(student_id=actual_id, workspace_id=workspace_id, section_id=section_id))

        self.db.commit()

    def clear_section(self, workspace_id: int, section_id: str) -> int:
        deleted = self.db.query(Enrollment).filter(
            Enrollment.workspace_id == workspace_id, Enrollment.section_id == section_id
        ).delete()
        self.db.commit()
        return deleted

    def delete_student(self, workspace_id: int, section_id: str, student_id: str) -> bool:
        deleted = self.db.query(Enrollment).filter(
            Enrollment.student_id == student_id, Enrollment.workspace_id == workspace_id, Enrollment.section_id == section_id
        ).delete()
        self.db.commit()
        return deleted > 0

    def _to_dict(self, row, workspace_id: int = 0, section_id: str = "") -> dict:
        return {
            "student_id":   row.student_id,
            "workspace_id": str(workspace_id), 
            "section_id":   section_id,
            "student_no":   row.student_id,    
            "name":         row.student_name,  
            "email":        f"{row.student_id}@aau.ac.ae", 
        }