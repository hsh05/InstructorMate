# backend/repositories/csv_workspace_repository.py
#
# FIX (DRY): Field names were hardcoded identically in __init__, list_all,
# get_by_id, and save (×2). Now all four read from WORKSPACE_FIELD_NAMES.
# Adding a new field is now a single-line change in workspace_fields.py.
#
# FIX: `import shutil` moved to top-level — importing inside a method body
# works but is non-idiomatic and hides the dependency.
#
# FIX: Replaced print() with logging throughout.
#
# FIX: list_all and get_by_id now handle missing/extra CSV columns gracefully
# instead of crashing with a KeyError if the CSV schema drifts.

import csv
import logging
import shutil
from datetime import datetime
from pathlib import Path
from typing import List, Optional

from domain.workspace import Workspace
from domain.enums import WorkspaceStatus
from domain.workspace_fields import WORKSPACE_FIELD_NAMES

logger = logging.getLogger(__name__)

# All columns written to workspaces.csv (field columns + metadata columns).
_CSV_COLUMNS = ["workspace_id", "pdf_hash", "status"] + WORKSPACE_FIELD_NAMES + ["created_at"]


def _row_to_fields(row: dict) -> dict:
    """Extract only the known field columns from a CSV row dict.
    Uses .get() so unknown/missing columns don't raise KeyError."""
    return {name: row.get(name, "") for name in WORKSPACE_FIELD_NAMES}


class CsvWorkspaceRepository:

    def __init__(self, file_path: str = "backend/data/workspaces.csv"):
        self.file_path = Path(file_path)
        self.file_path.parent.mkdir(parents=True, exist_ok=True)

        if not self.file_path.exists():
            with open(self.file_path, "w", newline="", encoding="utf-8") as f:
                # FIX: header built from _CSV_COLUMNS — no more hardcoded list
                writer = csv.writer(f)
                writer.writerow(_CSV_COLUMNS)
            logger.info("Created workspaces.csv at %s", self.file_path)

    # ── Path helpers ──────────────────────────────────────────────────────────

    def workspace_dir(self, workspace_id: str) -> Path:
        return self.file_path.parent / workspace_id

    def get_chunks_csv_path(self, workspace_id: str) -> Path:
        return self.workspace_dir(workspace_id) / "chunks.csv"

    # ── Read ──────────────────────────────────────────────────────────────────

    def list_all(self) -> List[Workspace]:
        workspaces = []
        with open(self.file_path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    workspaces.append(
                        Workspace(
                            workspace_id=row["workspace_id"],
                            pdf_hash=row.get("pdf_hash", ""),
                            # FIX: _row_to_fields() replaces the hardcoded dict literal
                            fields=_row_to_fields(row),
                            status=WorkspaceStatus(row.get("status", "draft")),
                        )
                    )
                except (KeyError, ValueError) as e:
                    logger.warning("Skipping malformed workspace row: %s — %s", row, e)
        return workspaces

    def get_by_id(self, workspace_id: str) -> Optional[Workspace]:
        with open(self.file_path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get("workspace_id") == workspace_id:
                    try:
                        return Workspace(
                            workspace_id=row["workspace_id"],
                            pdf_hash=row.get("pdf_hash", ""),
                            # FIX: _row_to_fields() replaces the hardcoded dict literal
                            fields=_row_to_fields(row),
                            status=WorkspaceStatus(row.get("status", "draft")),
                        )
                    except (KeyError, ValueError) as e:
                        logger.error("Corrupt workspace row id=%s: %s", workspace_id, e)
                        return None
        return None

    # ── Write ─────────────────────────────────────────────────────────────────

    def save(self, workspace: Workspace) -> None:
        rows: list[dict] = []
        with open(self.file_path, newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))

        # FIX: _build_row() replaces two identical hardcoded dicts in save()
        updated = False
        for row in rows:
            if row.get("workspace_id") == workspace.workspace_id:
                row.update(_build_row(workspace))
                updated = True

        if not updated:
            new_row = {"workspace_id": workspace.workspace_id, **_build_row(workspace),
                       "created_at": datetime.utcnow().isoformat()}
            rows.append(new_row)
            logger.info("Created workspace id=%s", workspace.workspace_id)

        with open(self.file_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=_CSV_COLUMNS)
            writer.writeheader()
            # FIX: write only the known columns — stray keys won't cause ValueError
            writer.writerows({col: row.get(col, "") for col in _CSV_COLUMNS} for row in rows)

    def delete(self, workspace_id: str) -> bool:
        rows: list[dict] = []
        with open(self.file_path, newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))

        filtered = [r for r in rows if r.get("workspace_id") != workspace_id]
        if len(filtered) == len(rows):
            return False  # not found

        with open(self.file_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=_CSV_COLUMNS)
            writer.writeheader()
            writer.writerows(filtered)

        # FIX: shutil imported at top, not inside method body
        ws_dir = self.workspace_dir(workspace_id)
        if ws_dir.exists():
            shutil.rmtree(ws_dir)
            logger.info("Deleted workspace folder for id=%s", workspace_id)

        return True


# ── Private helpers ───────────────────────────────────────────────────────────

def _build_row(workspace: Workspace) -> dict:
    """Build the CSV column dict for a workspace (excludes workspace_id and created_at)."""
    row = {
        "pdf_hash": workspace.pdf_hash,
        "status":   workspace.status.value,
    }
    # FIX: loop over WORKSPACE_FIELD_NAMES instead of hardcoding each field
    for name in WORKSPACE_FIELD_NAMES:
        row[name] = workspace.fields.get(name, "")
    return row