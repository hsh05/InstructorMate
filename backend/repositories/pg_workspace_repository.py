# backend/repositories/pg_workspace_repository.py
#
# OFFICE HOURS STORAGE (normalized)
# ──────────────────────────────────
# Office hours are now stored in the OfficeHour table:
#   OfficeHour: id, workspace_id, day, start_time, end_time
#
# The Flutter app sends/receives office_hours as the encoded string:
#   "Mon,Wed|9:00 AM|11:00 AM;Fri|2:00 PM|4:00 PM"
#   (slots by ';', each slot: "days|start|end")
#
# _to_domain reads OfficeHour rows and re-encodes to that string.
# save() detects 'office_hours' in fields and writes OfficeHour rows.

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
    OfficeHour as OfficeHourModel,
)

logger = logging.getLogger(__name__)

# Fields that map directly to Workspace table columns (excluding office_hours)
_DB_FIELD_NAMES = [f for f in WORKSPACE_FIELD_NAMES if f != "office_hours"]


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

        self.db.flush()

        # Persist office_hours via OfficeHour table if field present
        if "office_hours" in workspace.fields:
            self._save_office_hours(
                workspace.workspace_id,
                workspace.fields["office_hours"],
            )

        self.db.commit()

    def delete(self, workspace_id: str) -> bool:
        row = self.db.query(WorkspaceModel).filter(
            WorkspaceModel.workspace_id == workspace_id
        ).first()
        if not row:
            return False
        self.db.delete(row)  # OfficeHour rows cascade via FK
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

    # ── Office Hours helpers ──────────────────────────────────────────────────

    def _save_office_hours(self, workspace_id: str, encoded: str) -> None:
        """
        Decode the Flutter encoded string and write to OfficeHour table.
        Format: "Mon,Wed|9:00 AM|11:00 AM;Fri|2:00 PM|4:00 PM"
        Empty string clears all rows.
        """
        # Delete existing rows for this workspace
        self.db.query(OfficeHourModel).filter(
            OfficeHourModel.workspace_id == workspace_id
        ).delete()

        if not encoded or not encoded.strip():
            return

        for slot in encoded.split(";"):
            slot = slot.strip()
            if not slot:
                continue
            parts = slot.split("|")
            if len(parts) < 2:
                continue
            days_str  = parts[0].strip()
            start     = parts[1].strip() if len(parts) > 1 else ""
            end       = parts[2].strip() if len(parts) > 2 else ""
            # One OfficeHour row per day in the slot
            for day in days_str.split(","):
                day = day.strip()
                if day:
                    self.db.add(OfficeHourModel(
                        workspace_id = workspace_id,
                        day          = day,
                        start_time   = start,
                        end_time     = end,
                    ))

    def _load_office_hours(self, workspace_id: str) -> str:
        """
        Read OfficeHour rows and re-encode to Flutter format string.
        Groups rows with same start/end times into one slot.
        Returns "" if no rows.
        """
        rows = self.db.query(OfficeHourModel).filter(
            OfficeHourModel.workspace_id == workspace_id
        ).all()
        if not rows:
            return ""

        # Group by (start_time, end_time) to reconstruct multi-day slots
        from collections import defaultdict
        groups: dict = defaultdict(list)
        # Preserve insertion order using list of keys
        key_order = []
        for row in rows:
            key = (row.start_time or "", row.end_time or "")
            if key not in groups:
                key_order.append(key)
            groups[key].append(row.day)

        slots = []
        for key in key_order:
            start, end = key
            days = ",".join(groups[key])
            slots.append(f"{days}|{start}|{end}")

        return ";".join(slots)

    # ── Private ───────────────────────────────────────────────────────────────

    def _to_domain(self, row: WorkspaceModel) -> Workspace:
        fields = {name: getattr(row, name, "") or "" for name in _DB_FIELD_NAMES}
        # Inject office_hours from OfficeHour table
        fields["office_hours"] = self._load_office_hours(row.workspace_id)
        return Workspace(
            workspace_id = row.workspace_id,
            pdf_hash     = row.pdf_hash or "",
            status       = WorkspaceStatus(row.status or "draft"),
            fields       = fields,
        )