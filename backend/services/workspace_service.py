# backend/services/workspace_service.py
#
# PERF: LLM field extraction runs in a background thread via ThreadPoolExecutor.
# create_from_file() returns the workspace shell immediately (<1s).
# Fields are populated in the DB ~5-15s later by the background thread.
# Flutter sees the filled fields on next workspace open (getWorkspace call).

import csv
import logging
import shutil
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from domain.workspace import Workspace
from domain.enums import WorkspaceStatus
from domain.workspace_fields import WORKSPACE_FIELD_NAMES
from repositories.pg_workspace_repository import PgWorkspaceRepository
from services.pdf_hash_service import PdfHashService
from syllabus_converter import SyllabusConverterService

logger = logging.getLogger(__name__)

# Bounded thread pool — limits concurrent GPT calls to avoid overloading the server.
_executor = ThreadPoolExecutor(max_workers=3, thread_name_prefix="converter")


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
            logger.info("Duplicate upload detected, returning existing workspace id=%s",
                        existing.workspace_id)
            return {"already_uploaded": True, "workspace": existing}

        workspace = Workspace(
            workspace_id = str(uuid.uuid4()),
            pdf_hash     = pdf_hash,
            fields       = {name: "" for name in WORKSPACE_FIELD_NAMES},
            status       = WorkspaceStatus.DRAFT,
        )
        self.repo.save(workspace)
        logger.info("Created workspace id=%s — LLM extraction queued in background",
                    workspace.workspace_id)

        # Fire-and-forget: background thread gets its own DB session via SessionLocal.
        workspace_id = workspace.workspace_id
        _executor.submit(self._run_converter_bg, workspace_id, content)

        return {"already_uploaded": False, "workspace": workspace}

    def reprocess_pdf(self, workspace_id: str, content: bytes) -> Workspace:
        ws = self.repo.get_by_id(workspace_id)
        if ws is None:
            raise FileNotFoundError(f"Workspace '{workspace_id}' not found")
        _executor.submit(self._run_converter_bg, workspace_id, content)
        return ws

    def update_workspace(self, workspace_id: str, updates: dict) -> Workspace:
        ws = self.repo.get_by_id(workspace_id)
        if ws is None:
            raise FileNotFoundError(f"Workspace '{workspace_id}' not found")
        ws.update_fields(updates)
        self.repo.save(ws)
        return ws

    def _run_converter_bg(self, workspace_id: str, content: bytes) -> None:
        """
        Runs in a background thread. Opens its own DB session via SessionLocal
        so it doesn't share state with the FastAPI request session (which is
        already closed by the time this runs).
        """
        from db.database import SessionLocal
        db = SessionLocal()
        try:
            repo = PgWorkspaceRepository(db)
            ws   = repo.get_by_id(workspace_id)
            if ws is None:
                logger.warning("Background converter: workspace %s not found, skipping",
                               workspace_id)
                return
            self._run_converter(workspace_id, content, ws, repo)
        except Exception as e:
            logger.error("Background converter failed for workspace=%s: %s",
                         workspace_id, e, exc_info=True)
        finally:
            db.close()

    def _run_converter(self, workspace_id: str, content: bytes,
                       workspace: Workspace, repo: PgWorkspaceRepository) -> None:
        ws_dir  = repo.workspace_dir(workspace_id)
        ws_dir.mkdir(parents=True, exist_ok=True)
        tmp_pdf = ws_dir / "syllabus.pdf"
        tmp_pdf.write_bytes(content)

        try:
            result = self.converter.convert(
                pdf_path          = str(tmp_pdf),
                output_dir        = str(ws_dir),
                template_csv_path = "templates/default_template.csv",
                output_base_name  = "chunks",
            )

            # ── Save chunks ───────────────────────────────────────────────────
            chunks_src = Path(result.chunks_csv)
            if chunks_src.exists():
                repo.save_chunks(workspace_id, chunks_src)
                chunks_dst = repo.get_chunks_csv_path(workspace_id)
                if chunks_src != chunks_dst:
                    shutil.copy2(str(chunks_src), str(chunks_dst))

            # ── Auto-fill workspace fields from extracted single row ──────────
            single_row_src = Path(result.single_row_csv)
            if single_row_src.exists():
                with open(single_row_src, newline="", encoding="utf-8") as f:
                    row = next(csv.DictReader(f), None)
                if row:
                    updates = {
                        k: v for k, v in row.items()
                        if k in workspace.fields and not workspace.fields.get(k) and v
                    }

                    # Mirror course_title <-> course_name so both stay in sync.
                    # The PDF extractor writes course_title; Flutter reads course_name.
                    if updates.get("course_title") and not updates.get("course_name") \
                            and not workspace.fields.get("course_name"):
                        updates["course_name"] = updates["course_title"]
                    elif updates.get("course_name") and not updates.get("course_title") \
                            and not workspace.fields.get("course_title"):
                        updates["course_title"] = updates["course_name"]

                    if updates:
                        workspace.update_fields(updates)
                        repo.save(workspace)
                        logger.info("Auto-filled fields %s for workspace=%s",
                                    list(updates.keys()), workspace_id)

        except Exception as e:
            logger.error("Converter failed for workspace=%s: %s", workspace_id, e)
            raise