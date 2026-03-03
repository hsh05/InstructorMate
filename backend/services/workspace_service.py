# backend/services/workspace_service.py

import csv
import logging
import uuid
from pathlib import Path

from domain.workspace import Workspace
from domain.enums import WorkspaceStatus
from domain.workspace_fields import WORKSPACE_FIELD_NAMES
from repositories.pg_workspace_repository import PgWorkspaceRepository
from services.pdf_hash_service import PdfHashService
from syllabus_converter import SyllabusConverterService

logger = logging.getLogger(__name__)


class WorkspaceService:

    def __init__(
        self,
        repo: PgWorkspaceRepository,
        hash_service: PdfHashService,
        converter_model: str = "gpt-5",
    ):
        self.repo         = repo
        self.hash_service = hash_service
        self.converter    = SyllabusConverterService(model=converter_model)

    def create_from_file(self, filename: str, content: bytes) -> dict:
        pdf_hash = self.hash_service.compute(content)

        existing = next(
            (ws for ws in self.repo.list_all() if ws.pdf_hash == pdf_hash),
            None,
        )
        if existing:
            logger.info("Duplicate upload detected, returning existing workspace id=%s", existing.workspace_id)
            return {"already_uploaded": True, "workspace": existing}

        workspace = Workspace(
            workspace_id=str(uuid.uuid4()),
            pdf_hash=pdf_hash,
            fields={name: "" for name in WORKSPACE_FIELD_NAMES},
            status=WorkspaceStatus.DRAFT,
        )
        self.repo.save(workspace)
        logger.info("Created workspace id=%s", workspace.workspace_id)

        self._run_converter(workspace.workspace_id, content, workspace)

        return {"already_uploaded": False, "workspace": workspace}

    def reprocess_pdf(self, workspace_id: str, content: bytes) -> Workspace:
        ws = self.repo.get_by_id(workspace_id)
        if ws is None:
            raise FileNotFoundError(f"Workspace '{workspace_id}' not found")
        self._run_converter(workspace_id, content, ws)
        return ws

    def update_workspace(self, workspace_id: str, updates: dict) -> Workspace:
        ws = self.repo.get_by_id(workspace_id)
        if ws is None:
            raise FileNotFoundError(f"Workspace '{workspace_id}' not found")
        ws.update_fields(updates)
        self.repo.save(ws)
        return ws

    def _run_converter(self, workspace_id: str, content: bytes, workspace: Workspace) -> None:
        ws_dir  = self.repo.workspace_dir(workspace_id)
        ws_dir.mkdir(parents=True, exist_ok=True)
        tmp_pdf = ws_dir / "syllabus.pdf"
        tmp_pdf.write_bytes(content)

        try:
            result = self.converter.convert(
                pdf_path=str(tmp_pdf),
                output_dir=str(ws_dir),
                template_csv_path="templates/default_template.csv",
                output_base_name="chunks",
            )

            # ── Save chunks to Postgres ───────────────────────────────────
            chunks_src = Path(result.chunks_csv)
            if chunks_src.exists():
                # Save to DB so chunks survive Render restarts
                self.repo.save_chunks(workspace_id, chunks_src)
                # Also copy to expected path for AskPipeline file fallback
                chunks_dst = self.repo.get_chunks_csv_path(workspace_id)
                if chunks_src != chunks_dst:
                    import shutil
                    shutil.copy2(str(chunks_src), str(chunks_dst))

            # ── Auto-fill workspace fields from extracted single row ───────
            single_row_src = Path(result.single_row_csv)
            if single_row_src.exists():
                with open(single_row_src, newline="", encoding="utf-8") as f:
                    row = next(csv.DictReader(f), None)
                if row:
                    updates = {
                        k: v for k, v in row.items()
                        if k in workspace.fields and not workspace.fields.get(k) and v
                    }

                    # FIX: The PDF extractor outputs 'course_title' but the
                    # Flutter UI field key is 'course_name'. Mirror the value
                    # into both fields so the Info tab auto-fills correctly.
                    # Also handle the reverse: if extractor ever outputs
                    # 'course_name', mirror it into 'course_title' too.
                    if 'course_title' in updates and not updates.get('course_name') \
                            and not workspace.fields.get('course_name'):
                        updates['course_name'] = updates['course_title']
                    elif 'course_name' in updates and not updates.get('course_title') \
                            and not workspace.fields.get('course_title'):
                        updates['course_title'] = updates['course_name']

                    if updates:
                        workspace.update_fields(updates)
                        self.repo.save(workspace)
                        logger.info("Auto-filled fields %s for workspace=%s", list(updates.keys()), workspace_id)

        except Exception as e:
            logger.error("Converter failed for workspace=%s: %s", workspace_id, e)
            raise