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
from db.models import (
    Workspace as WorkspaceModel,
    SyllabusChunk as SyllabusChunkModel,
)

logger = logging.getLogger(__name__)

# All workspace fields map directly to table columns.
_DB_FIELD_NAMES = WORKSPACE_FIELD_NAMES


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
            for name in _DB_FIELD_NAMES:
                setattr(row, name, workspace.fields.get(name, ""))
            logger.info("Updated workspace id=%s", workspace.workspace_id)
        else:
            row = WorkspaceModel(
                workspace_id = workspace.workspace_id,
                pdf_hash     = workspace.pdf_hash,
                status       = workspace.status.value,
                **{name: workspace.fields.get(name, "") for name in _DB_FIELD_NAMES},
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
        self.db.query(SyllabusChunkModel).filter(
            SyllabusChunkModel.workspace_id == workspace_id
        ).delete()
        self.db.commit()

        inserted = 0
        with open(chunks_csv_path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    chunk_index = int(row.get("chunk_id") or 0)
                except (ValueError, TypeError):
                    chunk_index = 0
                content = (row.get("text") or "").strip()
                if not content:
                    continue
                self.db.add(SyllabusChunkModel(
                    workspace_id=workspace_id,
                    chunk_index=chunk_index,
                    content=content,
                ))
                inserted += 1

        self.db.commit()
        logger.info("Saved %d chunks for workspace=%s", inserted, workspace_id)

    def get_chunks_for_ask(self, workspace_id: str) -> List[dict]:
        rows = self.db.query(SyllabusChunkModel).filter(
            SyllabusChunkModel.workspace_id == workspace_id
        ).order_by(SyllabusChunkModel.chunk_index).all()
        return [
            {"chunk_id": r.chunk_index, "page": r.chunk_index, "content": r.content}
            for r in rows
        ]

    # ── Private ───────────────────────────────────────────────────────────────

    def _to_domain(self, row: WorkspaceModel) -> Workspace:
        fields = {name: getattr(row, name, "") or "" for name in _DB_FIELD_NAMES}
        ws = Workspace(
            workspace_id = row.workspace_id,
            pdf_hash     = row.pdf_hash or "",
            status       = WorkspaceStatus(row.status or "draft"),
            fields       = fields,
        )
        # Attach timestamps so to_dict() can expose them to Flutter
        ws._created_at = str(row.created_at) if getattr(row, "created_at", None) else ""
        ws._updated_at = str(row.updated_at) if getattr(row, "updated_at", None) else ""
        return ws