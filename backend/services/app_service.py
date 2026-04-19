# backend/services/app_service.py

import io
import csv
import logging
import shutil
import pandas as pd
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from sqlalchemy import text

# 👉 UPDATED IMPORTS: Pointing to the consolidated files!
from db.models import Workspace
from domain.enums import WorkspaceStatus
from domain.workspace_fields import WORKSPACE_FIELD_NAMES
from repositories.pg_repository import PgWorkspaceRepository
from services.file_service import FileHashService, SyllabusConverterService

logger = logging.getLogger(__name__)


# ==============================================================================
# ── STUDENT & SECTION SERVICE ─────────────────────────────────────────────────
# ==============================================================================
class StudentService:
    def __init__(self, repo, workspace_repo):
        self.repo = repo
        self.workspace_repo = workspace_repo

    def import_students(
        self,
        workspace_id: int,
        file_bytes: bytes,
        filename: str = "",
        section_id: str = "",
    ):
        if filename.lower().endswith(".csv"):
            df = pd.read_csv(io.BytesIO(file_bytes))
        elif filename.lower().endswith((".xlsx", ".xls")):
            df = pd.read_excel(io.BytesIO(file_bytes))
        else:
            raise ValueError("Unsupported file type. Please upload a CSV or Excel file.")

        df.columns = [str(c).strip().lower() for c in df.columns]

        if "student_id" not in df.columns or "student_name" not in df.columns:
            raise ValueError(f"Missing required columns. Found: {list(df.columns)}. Need 'STUDENT_ID' and 'STUDENT_NAME'.")

        db = getattr(self.repo, 'db', None)
        if not db:
            raise RuntimeError("Database connection not found.")

        if section_id:
            db.execute(
                text("DELETE FROM enrollment WHERE workspace_id = :w_id AND section_id = :s_id"),
                {"w_id": workspace_id, "s_id": section_id}
            )
            db.commit()

        students_imported = []

        for _, row in df.iterrows():
            s_id = str(row["student_id"]).strip()
            s_name = str(row["student_name"]).strip()

            c_code = "MAIN"
            if "campus_code" in df.columns and pd.notna(row["campus_code"]):
                val = str(row["campus_code"]).strip()
                if val and val.lower() != "nan":
                    c_code = val

            if not s_id or s_id.lower() == "nan":
                continue

            db.execute(
                text("""
                INSERT INTO students (student_id, student_name, campus_code)
                VALUES (:id, :name, :campus)
                ON CONFLICT (student_id)
                DO UPDATE SET
                    student_name = EXCLUDED.student_name,
                    campus_code = COALESCE(EXCLUDED.campus_code, students.campus_code)
                """),
                {"id": s_id, "name": s_name, "campus": c_code}
            )

            if section_id:
                db.execute(
                    text("""
                    INSERT INTO enrollment (student_id, section_id, workspace_id)
                    VALUES (:id, :sec_id, :w_id)
                    ON CONFLICT DO NOTHING
                    """),
                    {"id": s_id, "sec_id": section_id, "w_id": workspace_id}
                )
            
            students_imported.append(s_id)

        db.commit()
        logger.info("Imported %d students workspace=%s section=%s", len(students_imported), workspace_id, section_id)
        return students_imported

    def create_section(self, workspace_id: str, data: dict): 
        if not self.workspace_repo.get_by_id(workspace_id):
            raise FileNotFoundError(f"Workspace '{workspace_id}' not found")

        schedule_data = data.get("schedule", {})
        section_name = data.get("name", "").strip()
        
        if not section_name:
            raise ValueError("Section name cannot be empty.")

        section_data = {  
            "section_id": section_name, 
            "name": section_name,
            "location": data.get("location", ""),
            "schedule": {
                "days": schedule_data.get("days", []),
                "start_time": schedule_data.get("start_time", ""),
                "end_time": schedule_data.get("end_time", ""),
                "reminder_minutes": schedule_data.get("reminder_minutes", 10),
            },
        }

        self.repo.save(workspace_id, section_data)
        logger.info("Section created id=%s workspace=%s", section_data["section_id"], workspace_id)
        return section_data


# ==============================================================================
# ── WORKSPACE SERVICE ─────────────────────────────────────────────────────────
# ==============================================================================
_executor = ThreadPoolExecutor(max_workers=3, thread_name_prefix="converter")
_in_flight: set[str] = set()
_cancelled: set[str] = set()

class WorkspaceService:
    def __init__(
        self,
        repo: PgWorkspaceRepository,
        hash_service: FileHashService,
        converter_model: str = "gpt-4o",
    ):
        self.repo         = repo
        self.hash_service = hash_service
        self.converter    = SyllabusConverterService(model=converter_model)

    def create_from_file(self, filename: str, content: bytes, instructor_id: int) -> dict:
        file_hash = self.hash_service.compute(content)

        # 1. Check for duplicates
        existing = next(
            (ws for ws in self.repo.list_all() if ws.file_hash == file_hash),
            None,
        )
        if existing:
            return {"already_uploaded": True, "workspace": existing}

        # 2. Create the workspace using the REAL instructor_id passed from the UI
        workspace = Workspace(
            instructor_id = instructor_id, 
            file_hash     = file_hash,
            content       = None 
        )
        
        self.repo.save(workspace)
        logger.info("Created workspace id=%s — LLM extraction queued in background", workspace.workspace_id)

        workspace_id = workspace.workspace_id

        if workspace_id not in _in_flight:
            _in_flight.add(workspace_id)
            _executor.submit(self._run_converter_bg, workspace_id, content, filename)

        return {"already_uploaded": False, "workspace": workspace}

    def cancel_if_in_flight(self, workspace_id: str) -> None:
        if workspace_id in _in_flight:
            _cancelled.add(workspace_id)
            logger.info("Marked workspace=%s for cancellation", workspace_id)

    def update_workspace(self, workspace_id: str, updates: dict) -> Workspace:
        ws = self.repo.get_by_id(workspace_id)
        if ws is None:
            raise FileNotFoundError(f"Workspace '{workspace_id}' not found")
        ws.update_fields(updates)
        self.repo.save(ws)
        return ws

    def _run_converter_bg(self, workspace_id: str, content: bytes, filename: str = "syllabus.pdf") -> None:
        if workspace_id in _cancelled:
            _cancelled.discard(workspace_id)
            return
            
        logger.info("🚀 Background AI Extraction STARTED for workspace=%s. This takes ~30 seconds...", workspace_id)
        
        # 👉 UPDATED IMPORT: Points to the new db/database.py location
        from db.database import SessionLocal
        db = SessionLocal()
        try:
            repo = PgWorkspaceRepository(db)
            ws   = repo.get_by_id(workspace_id)
            if ws is None or workspace_id in _cancelled:
                _cancelled.discard(workspace_id)
                return
            self._run_converter(workspace_id, content, filename, ws, repo)
        except Exception as e:
            logger.error("❌ Background converter failed for workspace=%s: %s", workspace_id, e, exc_info=True)
            try:
                from db.database import SessionLocal as SL
                db2 = SL()
                try:
                    repo2 = PgWorkspaceRepository(db2)
                    ws2 = repo2.get_by_id(workspace_id)
                    if ws2:
                        ws2.status = WorkspaceStatus.ERROR
                        repo2.save(ws2)
                finally:
                    db2.close()
            except Exception:
                pass
        finally:
            _in_flight.discard(workspace_id)
            db.close()

    def _run_converter(
        self,
        workspace_id: str,
        content: bytes,
        filename: str,
        workspace: Workspace,
        repo: PgWorkspaceRepository,
    ) -> None:
        ws_dir = repo.workspace_dir(workspace_id)
        ws_dir.mkdir(parents=True, exist_ok=True)

        ext = Path(filename).suffix.lower() or ".pdf"
        tmp_file = ws_dir / f"syllabus{ext}"
        tmp_file.write_bytes(content)

        try:
            result = self.converter.convert(
                pdf_path          = str(tmp_file),
                output_dir        = str(ws_dir),
                template_csv_path = "templates/default_template.csv",
                output_base_name  = "chunks",
            )

            # ── Save chunks ──────────────────────────────────────────────────
            chunks_src = Path(result.chunks_csv)
            if chunks_src.exists():
                repo.save_chunks(workspace_id, chunks_src)
                chunks_dst = repo.get_chunks_csv_path(workspace_id)
                if chunks_src != chunks_dst:
                    shutil.copy2(str(chunks_src), str(chunks_dst))
                repo.generate_and_save_embeddings(workspace_id)

            # ── Auto-fill workspace fields ───────────────────────────────────
            single_row_src = Path(result.single_row_csv)
            if single_row_src.exists():
                with open(single_row_src, newline="", encoding="utf-8") as f:
                    row = next(csv.DictReader(f), None)
                if row:
                    updates = {
                        k: v.strip() for k, v in row.items() if v and v.strip()
                    }
                    
                    if updates:
                        for key, val in updates.items():
                            workspace.fields[key] = val
                            
                        repo.save(workspace) 
                        logger.info("✅ Extracted & Saved to DB: %s for workspace=%s", list(updates.keys()), workspace_id)

            # Mark ready
            workspace.status = WorkspaceStatus.READY
            repo.save(workspace)
            logger.info("🎯 Extraction COMPLETE for workspace=%s", workspace_id)

        except Exception as e:
            logger.error("Converter failed for workspace=%s: %s", workspace_id, e)
            raise