# backend/repositories/pg_repository.py

import csv
import logging
import shutil
from pathlib import Path
from typing import Any, Dict, List, Optional
from openai import OpenAI
from sqlalchemy.orm import Session
from db.models import Workspace, Section, Instructor, Enrollment, Student, Attendance
from sqlalchemy import func

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
        return self.db.query(Workspace).all()

    def get_by_id(self, workspace_id: int) -> Optional[Workspace]:
        return self.db.query(Workspace).filter(Workspace.workspace_id == workspace_id).first()

    def save(self, workspace: Workspace) -> None:
        self.db.add(workspace)
        self.db.commit()
        self.db.refresh(workspace)

    def delete(self, workspace_id: int) -> bool:
        row = self.get_by_id(workspace_id)
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

        workspace = self.get_by_id(workspace_id)
        if workspace:
            workspace.content = combined_content.strip()
            self.db.commit()

    def get_chunks_for_ask(self, workspace_id: int) -> List[Dict[str, Any]]:
        row = self.get_by_id(workspace_id)
        if not row or not row.content: return []
        return [{"chunk_id": 1, "page": 1, "content": row.content, "embedding": row.embedding}]

    def generate_and_save_embeddings(self, workspace_id: int) -> int:
        workspace = self.get_by_id(workspace_id)
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


# ==============================================================================
# ── SECTION REPOSITORY ────────────────────────────────────────────────────────
# ==============================================================================
class PgSectionRepository:
    def __init__(self, db: Session, ws_repo: PgWorkspaceRepository):
        self.db = db
        self.ws_repo = ws_repo

    def list_by_workspace(self, workspace_id: int) -> List[Dict]:
        rows = self.db.query(Section).filter(Section.workspace_id == workspace_id).all()
        return [self._to_dict(row) for row in rows]

    def save(self, workspace_id: int, section_data: Dict) -> None:
        schedule = section_data.get("schedule", {})
        days_string = ", ".join([d.strip() for d in schedule.get("days", []) if d.strip()])

        row = Section(
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
        row = self.db.query(Section).filter(
            Section.workspace_id == workspace_id, Section.section_id == section_id
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
        row = self.db.query(Section).filter(
            Section.workspace_id == workspace_id, Section.section_id == section_id
        ).first()
        if not row: return False
        self.db.delete(row)  
        self.db.commit()
        return True

    def update_import_hash(self, section_id: str, file_hash: str):
        row = self.db.query(Section).filter(Section.section_id == section_id).first()
        if row:
            row.file_hash = file_hash
            self.db.commit()
            self.db.refresh(row)
        return row

    def _to_dict(self, row: Section) -> Dict:
        days = [d.strip() for d in row.day.split(",")] if row.day else []
        try: reminder = int(row.reminder_minutes or 10)
        except (ValueError, TypeError): reminder = 10

        return {
            "section_id":   row.section_id,
            "workspace_id": str(row.workspace_id), 
            "name":         str(row.section_id),
            "location":     row.location or "",
            "last_import_hash": getattr(row, "file_hash", ""),
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
        rows = self.db.query(Student).join(Enrollment, Enrollment.student_id == Student.student_id).filter(Enrollment.workspace_id == workspace_id).distinct().all()
        return [self._to_dict(row, workspace_id=workspace_id) for row in rows]

    def list_by_section(self, workspace_id: int, section_id: str) -> List[dict]:
        rows = self.db.query(Student).join(Enrollment, Enrollment.student_id == Student.student_id).filter(
            Enrollment.workspace_id == workspace_id, Enrollment.section_id == section_id
        ).all()
        return [self._to_dict(row, workspace_id=workspace_id, section_id=section_id) for row in rows]

    def count_by_section(self, workspace_id: int, section_id: str) -> int:
        return self.db.query(Enrollment).filter(
            Enrollment.workspace_id == workspace_id, Enrollment.section_id == section_id
        ).count()

    def save(self, student, section_id: str = "") -> None:
        actual_id = (student.student_no or student.student_id).strip()
        workspace_id = int(student.workspace_id)
        section_id = (section_id or "").strip()

        db_student = self.db.query(Student).filter(Student.student_id == actual_id).first()
        if db_student:
            db_student.student_name = student.name or db_student.student_name
        else:
            db_student = Student(student_id=actual_id, student_name=student.name)
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

    def _to_dict(self, row: Student, workspace_id: int = 0, section_id: str = "") -> dict:
        return {
            "student_id":   row.student_id,
            "workspace_id": str(workspace_id), 
            "section_id":   section_id,
            "student_no":   row.student_id,    
            "name":         row.student_name,  
            "email":        f"{row.student_id}@aau.ac.ae", 
        }
    
# ==============================================================================
# ── ATTENDANCE REPOSITORY ─────────────────────────────────────────────────────
# ==============================================================================
class PgAttendanceRepository:
    def __init__(self, db: Session):
        self.db = db

    def get_last_lecture_number(self, workspace_id: int, section_id: str) -> Optional[int]:
        result = self.db.query(func.max(Attendance.lecture_no)).filter(
            Attendance.workspace_id == workspace_id,
            Attendance.section_id == section_id
        ).scalar()
        return result

    def save_attendance_for_lecture(self, workspace_id: int, section_id: str, lecture_number: int, rows: List[Dict]):
        # 1. Delete old rows (replace behavior)
        self.db.query(Attendance).filter(
            Attendance.workspace_id == workspace_id,
            Attendance.section_id == section_id,
            Attendance.lecture_no == lecture_number
        ).delete()

        # 2. Insert new rows
        for r in rows:
            new_att = Attendance(
                student_id=str(r.get("StudentID")),
                section_id=section_id,
                workspace_id=workspace_id,
                lecture_no=lecture_number,
                status=str(r.get("Status")),
                confidence=str(r.get("Confidence", "Unknown"))
            )
            self.db.add(new_att)
        self.db.commit()

    def fetch_attendance_rows(self, workspace_id: int, section_id: str, lecture_number: Optional[int] = None) -> List[Dict]:
        query = self.db.query(Attendance).filter(
            Attendance.workspace_id == workspace_id,
            Attendance.section_id == section_id
        )
        if lecture_number is not None:
            query = query.filter(Attendance.lecture_no == lecture_number)
        
        rows = query.order_by(Attendance.lecture_no, Attendance.student_id).all()
        return [
            {
                "lecture_number": r.lecture_no,
                "student_id": r.student_id,
                "status": r.status,
                "confidence": r.confidence
            } for r in rows
        ]
        
    def update_student_encoding(self, student_id: str, encoding_list: list) -> bool:
        student = self.db.query(Student).filter(Student.student_id == str(student_id)).first()
        if student:
            student.facial_encoding = encoding_list
            self.db.commit()
            return True
        return False
        
    def get_students_with_encodings(self, workspace_id: int, section_id: str):
        return self.db.query(Student).join(Enrollment).filter(
            Enrollment.workspace_id == workspace_id,
            Enrollment.section_id == section_id
        ).all()