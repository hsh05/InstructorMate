# backend/services/workspace_service.py
#
# CHANGES vs original:
# 1. FIX #1 — Background converter now sets status='error' when extraction fails,
#    so Flutter can surface a real error state instead of polling forever.
# 2. FIX #4 — _run_converter_bg is guarded: won't double-submit if already running.
# 3. FIX #5 — _run_converter writes original filename extension to disk so
#    syllabus_converter knows whether to use PdfTextExtractor or DocxTextExtractor.

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

_executor = ThreadPoolExecutor(max_workers=3, thread_name_prefix="converter")
# FIX #4: track in-flight workspace IDs so we never double-submit
_in_flight: set[str] = set()
# Workspace IDs that have been cancelled — background thread checks this and exits early
_cancelled: set[str] = set()


class WorkspaceService:

    def __init__(
        self,
        repo: PgWorkspaceRepository,
        hash_service: PdfHashService,
        converter_model: str = "gpt-4o",
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

        workspace_id = workspace.workspace_id

        # FIX #4: guard against double-submission
        if workspace_id not in _in_flight:
            _in_flight.add(workspace_id)
            _executor.submit(self._run_converter_bg, workspace_id, content, filename)

        return {"already_uploaded": False, "workspace": workspace}

    def cancel_if_in_flight(self, workspace_id: str) -> None:
        """Mark a workspace as cancelled so the background thread exits early.
        Safe to call even if no extraction is running for this workspace."""
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
        """Runs in a background thread with its own DB session."""
        # Check if this workspace was cancelled (e.g. deleted) before we even start
        if workspace_id in _cancelled:
            _cancelled.discard(workspace_id)
            logger.info("Background converter: workspace %s was cancelled before start", workspace_id)
            return
        from db.database import SessionLocal
        db = SessionLocal()
        try:
            repo = PgWorkspaceRepository(db)
            ws   = repo.get_by_id(workspace_id)
            if ws is None or workspace_id in _cancelled:
                logger.warning("Background converter: workspace %s not found or cancelled, skipping", workspace_id)
                _cancelled.discard(workspace_id)
                return
            self._run_converter(workspace_id, content, filename, ws, repo)
        except Exception as e:
            logger.error("Background converter failed for workspace=%s: %s", workspace_id, e, exc_info=True)
            # FIX #1: persist error status so Flutter stops polling
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

        # FIX #5: preserve original extension so the converter picks the right extractor
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

            # ── Generate and store embeddings ─────────────────────────────────
            # Runs immediately after chunks are saved so that the very first
            # /ask call against this workspace uses semantic retrieval.
            # Failures are logged but do not block workspace creation —
            # the retriever falls back to keyword search if embeddings are absent.
            try:
                n = repo.generate_and_save_embeddings(workspace_id)
                logger.info("Stored %d embeddings for workspace=%s", n, workspace_id)
            except Exception as emb_err:
                logger.warning(
                    "Embedding generation failed for workspace=%s (non-fatal): %s",
                    workspace_id, emb_err,
                )

            # ── Auto-fill workspace fields ───────────────────────────────────
            single_row_src = Path(result.single_row_csv)
            if single_row_src.exists():
                with open(single_row_src, newline="", encoding="utf-8") as f:
                    row = next(csv.DictReader(f), None)
                if row:
                    updates = {
                        k: v for k, v in row.items()
                        if k in workspace.fields and not workspace.fields.get(k) and v
                    }
                    # Mirror course_title <-> course_name
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

            # Mark ready
            workspace.status = WorkspaceStatus.READY
            repo.save(workspace)
            logger.info("Extraction complete for workspace=%s", workspace_id)

        except Exception as e:
            logger.error("Converter failed for workspace=%s: %s", workspace_id, e)
            raise