# backend/repositories/pg_workspace_repository.py

import csv
import logging
import shutil
from pathlib import Path
from typing import List, Optional

from sqlalchemy.orm import Session

from domain.workspace import Workspace
from domain.enums import WorkspaceStatus
from domain.workspace_fields import WORKSPACE_FIELD_NAMES
from db.models import Workspace as WorkspaceModel, SyllabusChunk as SyllabusChunkModel

logger = logging.getLogger(__name__)


class PgWorkspaceRepository:

    def __init__(self, db: Session, data_dir: str = "backend/data"):
        self.db = db
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)

    # ── Path helpers ──────────────────────────────────────────────────────────

    def workspace_dir(self, workspace_id: str) -> Path:
        return self.data_dir / workspace_id

    def get_chunks_csv_path(self, workspace_id: str) -> Path:
        return self.workspace_dir(workspace_id) / "chunks.csv"

    # ── Read ──────────────────────────────────────────────────────────────────

    def list_all(self) -> List[Workspace]:
        rows = self.db.query(WorkspaceModel).all()
        return [self._to_domain(row) for row in rows]

    def get_by_id(self, workspace_id: str) -> Optional[Workspace]:
        row = self.db.query(WorkspaceModel).filter(
            WorkspaceModel.workspace_id == workspace_id
        ).first()
        return self._to_domain(row) if row else None

    # ── Write ─────────────────────────────────────────────────────────────────

    def save(self, workspace: Workspace) -> None:
        row = self.db.query(WorkspaceModel).filter(
            WorkspaceModel.workspace_id == workspace.workspace_id
        ).first()

        if row:
            row.pdf_hash = workspace.pdf_hash
            row.status   = workspace.status.value
            for name in WORKSPACE_FIELD_NAMES:
                setattr(row, name, workspace.fields.get(name, ""))
            logger.info("Updated workspace id=%s", workspace.workspace_id)
        else:
            row = WorkspaceModel(
                workspace_id = workspace.workspace_id,
                pdf_hash     = workspace.pdf_hash,
                status       = workspace.status.value,
                **{name: workspace.fields.get(name, "") for name in WORKSPACE_FIELD_NAMES},
            )
            self.db.add(row)
            logger.info("Created workspace id=%s", workspace.workspace_id)

        self.db.commit()

    def delete(self, workspace_id: str) -> bool:
        row = self.db.query(WorkspaceModel).filter(
            WorkspaceModel.workspace_id == workspace_id
        ).first()
        if not row:
            return False
        self.db.delete(row)
        self.db.commit()

        ws_dir = self.workspace_dir(workspace_id)
        if ws_dir.exists():
            shutil.rmtree(ws_dir)
            logger.info("Deleted workspace folder for id=%s", workspace_id)

        return True

    def save_chunks(self, workspace_id: str, chunks_csv_path: Path) -> None:
        """Read chunks CSV and save all rows to the syllabus_chunks table.
        Deletes existing chunks for this workspace first so re-upload is safe."""

        # Delete existing chunks for this workspace
        self.db.query(SyllabusChunkModel).filter(
            SyllabusChunkModel.workspace_id == workspace_id
        ).delete()
        self.db.commit()

        # Insert new chunks from CSV
        with open(chunks_csv_path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                chunk = SyllabusChunkModel(
                    workspace_id = workspace_id,
                    chunk_index  = int(row.get("chunk_id", 0)),
                    content      = row.get("text", ""),
                )
                self.db.add(chunk)

        self.db.commit()
        logger.info("Saved chunks to DB for workspace=%s", workspace_id)

    def get_chunks_for_ask(self, workspace_id: str) -> List[dict]:
        """Load chunks from Postgres for the AskPipeline."""
        rows = self.db.query(SyllabusChunkModel).filter(
            SyllabusChunkModel.workspace_id == workspace_id
        ).order_by(SyllabusChunkModel.chunk_index).all()

        return [
            {"chunk_id": r.chunk_index, "page": r.chunk_index, "content": r.content}
            for r in rows
        ]

    # ── Private ───────────────────────────────────────────────────────────────

    def _to_domain(self, row: WorkspaceModel) -> Workspace:
        return Workspace(
            workspace_id = row.workspace_id,
            pdf_hash     = row.pdf_hash or "",
            status       = WorkspaceStatus(row.status or "draft"),
            fields       = {name: getattr(row, name, "") or "" for name in WORKSPACE_FIELD_NAMES},
        )