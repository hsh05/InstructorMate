# backend/services/student_service.py
#
# SCHEMA NOTE
# ───────────
# Import flow: save Student row (merge) + create StudentSection link.
# Replace flow: delete StudentSection links for section, then re-import.
#
# section_id is passed to repo.save() as an explicit parameter — it is NOT
# stored on the Student domain object since a student can belong to multiple
# sections via the StudentSection join table.

import csv
import io
import uuid
import logging

import openpyxl

from domain.student import Student

logger = logging.getLogger(__name__)


class StudentService:

    def __init__(self, repo):
        self.repo = repo

    def import_students(
        self,
        workspace_id: str,
        file_bytes: bytes,
        filename: str = "",
        section_id: str = "",
    ):
        if not self.repo.ws_repo.get_by_id(workspace_id):
            raise FileNotFoundError(f"Workspace '{workspace_id}' not found")

        rows = self._parse_file(file_bytes, filename)

        # If replacing an existing roster, clear the section links first.
        # Student rows themselves stay (they belong to the workspace);
        # only the StudentSection links are removed so the count resets.
        if section_id:
            self.repo.delete_by_section(section_id)

        students = []
        for row in rows:
            student = Student(
                student_id   = str(uuid.uuid4()),
                workspace_id = workspace_id,
                name         = (row.get("name") or "").strip(),
                email        = (row.get("email") or "").strip(),
                student_no   = (row.get("student_no") or "").strip(),
            )
            if not student.name and not student.email:
                continue  # skip completely blank rows
            # section_id passed separately — not part of Student identity
            self.repo.save(student, section_id=section_id)
            students.append(student)

        logger.info("Imported %d students workspace=%s section=%s",
                    len(students), workspace_id, section_id)
        return students

    # ── Parsers ───────────────────────────────────────────────────────────────

    def _parse_file(self, file_bytes: bytes, filename: str) -> list:
        fname = filename.lower()
        if fname.endswith(".xlsx") or fname.endswith(".xls"):
            return self._parse_xlsx(file_bytes)
        return self._parse_csv(file_bytes)

    def _parse_csv(self, file_bytes: bytes) -> list:
        text = file_bytes.decode("utf-8", errors="replace")
        reader = csv.DictReader(io.StringIO(text))
        return [{k.strip().lower(): v for k, v in row.items()} for row in reader]

    def _parse_xlsx(self, file_bytes: bytes) -> list:
        wb = openpyxl.load_workbook(
            io.BytesIO(file_bytes), read_only=True, data_only=True
        )
        ws = wb.active
        rows = list(ws.iter_rows(values_only=True))
        if not rows:
            return []
        headers = [
            str(h).strip().lower() if h is not None else ""
            for h in rows[0]
        ]
        result = []
        for row in rows[1:]:
            if all(cell is None or str(cell).strip() == "" for cell in row):
                continue
            result.append({
                headers[i]: (str(cell).strip() if cell is not None else "")
                for i, cell in enumerate(row)
                if i < len(headers)
            })
        return result