# backend/services/student_service.py

import io
import logging
import pandas as pd
from sqlalchemy import text

logger = logging.getLogger(__name__)

class StudentService:
    def __init__(self, repo):
        self.repo = repo

    def import_students(
        self,
        workspace_id: int,
        file_bytes: bytes,
        filename: str = "",
        section_id: str = "",
    ):
        # 1. Parse file using the bulletproof pandas logic
        if filename.lower().endswith(".csv"):
            df = pd.read_csv(io.BytesIO(file_bytes))
        elif filename.lower().endswith((".xlsx", ".xls")):
            df = pd.read_excel(io.BytesIO(file_bytes))
        else:
            raise ValueError("Unsupported file type. Please upload a CSV or Excel file.")

        df.columns = [str(c).strip().lower() for c in df.columns]

        if "student_id" not in df.columns or "student_name" not in df.columns:
            raise ValueError(f"Missing required columns. Found: {list(df.columns)}. Need 'STUDENT_ID' and 'STUDENT_NAME'.")

        # Grab the database session from the repository
        db = getattr(self.repo, 'db', None)
        if not db:
            raise RuntimeError("Database connection not found.")

        # 2. If replacing an existing roster, clear the old section links first
        if section_id:
            db.execute(
                text("DELETE FROM enrollment WHERE workspace_id = :w_id AND section_id = :s_id"),
                {"w_id": workspace_id, "s_id": section_id}
            )
            db.commit()

        students_imported = []

        # 3. Process every row safely
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

            # A. Upsert the student into the main university directory
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

            # B. Enroll the student in this specific class section!
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

        # Finalize the database transaction
        db.commit()

        logger.info("Imported %d students workspace=%s section=%s", len(students_imported), workspace_id, section_id)
        
        # We return the list to the router, which just needs to know the length (len(students))
        return students_imported