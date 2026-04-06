# backend/repositories/pg_workspace_repository.py

import csv
import logging
import shutil
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

from openai import OpenAI
from sqlalchemy import func
from sqlalchemy.orm import Session

from domain.workspace import Workspace
from domain.enums import WorkspaceStatus
from domain.workspace_fields import WORKSPACE_FIELD_NAMES

# 👈 FIXED: SyllabusChunk has been removed from imports!
from db.models import Workspace as WorkspaceModel

logger = logging.getLogger(__name__)

_DB_FIELD_NAMES = WORKSPACE_FIELD_NAMES


class PgWorkspaceRepository:

    def __init__(self, db: Session, data_dir: str = "backend/data"):
        self.db = db
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)

    # ── Path helpers ──────────────────────────────────────────────────────────

    def workspace_dir(self, workspace_id: int) -> Path: # 👈 ID changed to int
        return self.data_dir / str(workspace_id)

    def get_chunks_csv_path(self, workspace_id: int) -> Path:
        return self.workspace_dir(workspace_id) / "chunks.csv"

    # ── Read ──────────────────────────────────────────────────────────────────

    def list_all(self) -> List[Workspace]:
        rows = self.db.query(WorkspaceModel).all()
        return [self._to_domain(row) for row in rows]

    def get_by_id(self, workspace_id: int) -> Optional[Workspace]:
        row = self.db.query(WorkspaceModel).filter(
            WorkspaceModel.workspace_id == workspace_id
        ).first()
        return self._to_domain(row) if row else None

    # ── Write ─────────────────────────────────────────────────────────────────

    def save(self, workspace: Workspace) -> None:
        from db.models import Instructor # Import the Instructor model
        
        # 1. Ensure we have a valid instructor to own this workspace
        instructor = self.db.query(Instructor).first()
        if not instructor:
            instructor = Instructor(
                email="admin@instructormate.com",
                hashed_password="placeholder_password",
                full_name="Admin Instructor"
            )
            self.db.add(instructor)
            self.db.commit()
            self.db.refresh(instructor)

        # 2. Try to see if this is an existing integer ID
        try:
            ws_id = int(workspace.workspace_id)
            row = self.db.query(WorkspaceModel).filter(
                WorkspaceModel.workspace_id == ws_id
            ).first()
        except ValueError:
            row = None 

        if row:
            row.course_code  = workspace.fields.get('course_code', "")
            row.semester     = workspace.fields.get('semester', "")
            row.course_title = workspace.fields.get('course_title', "")
            logger.info("Updated workspace id=%s", ws_id)
        else:
            # Get values, but if they are empty strings, force them to "TBD"
            c_code  = workspace.fields.get('course_code') or "TBD"
            semester = workspace.fields.get('semester') or "TBD"
            c_title = workspace.fields.get('course_title') or "Untitled Workspace"

            row = WorkspaceModel(
                instructor_id = instructor.instructor_id,
                course_code   = c_code,
                semester      = semester, 
                course_title  = c_title,
                chunk_index   = 0,
                content       = "Processing..."
            )
            self.db.add(row)
            self.db.flush() 
            
            workspace.workspace_id = str(row.workspace_id) 
            logger.info("Created workspace id=%s", row.workspace_id)

        self.db.commit()

    def delete(self, workspace_id: int) -> bool:
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

    def save_chunks(self, workspace_id: int, chunks_csv_path: Path) -> None:
        """
        Reads the CSV of extracted text and combines it into a single string 
        to be saved directly into the Workspace.content column!
        """
        combined_content = ""
        
        try:
            with open(chunks_csv_path, newline="", encoding="utf-8") as f:
                reader = csv.DictReader(f)
                for row in reader:
                    content = (row.get("text") or "").strip()
                    if content:
                        combined_content += content + "\n\n"
        except FileNotFoundError:
            logger.error("Could not find chunks CSV for workspace %s", workspace_id)
            return

        workspace = self.db.query(WorkspaceModel).filter(
            WorkspaceModel.workspace_id == workspace_id
        ).first()

        if workspace:
            workspace.content = combined_content.strip()
            self.db.commit()
            logger.info("Saved consolidated content for workspace=%s", workspace_id)

    def get_chunks_for_ask(self, workspace_id: int) -> List[Dict[str, Any]]:
        """
        Returns the consolidated workspace content in the list format 
        that the frontend AI Ask feature still expects.
        """
        row = self.db.query(WorkspaceModel).filter(
            WorkspaceModel.workspace_id == workspace_id
        ).first()
        
        if not row or not row.content:
            return []
            
        return [
            {
                "chunk_id":  1,
                "page":      1,
                "content":   row.content,
                "embedding": row.embedding, 
            }
        ]

    def generate_and_save_embeddings(self, workspace_id: int) -> int:
        """
        Generates a single OpenAI embedding for the consolidated Workspace content.
        """
        _EMBED_MODEL = "text-embedding-3-small"

        workspace = self.db.query(WorkspaceModel).filter(
            WorkspaceModel.workspace_id == workspace_id
        ).first()

        if not workspace or not workspace.content or workspace.embedding:
            logger.info("No embedding needed for workspace=%s", workspace_id)
            return 0

        client = OpenAI()
        
        try:
            # We only have to make ONE api call now instead of batching 100!
            resp = client.embeddings.create(model=_EMBED_MODEL, input=[workspace.content])
            emb = resp.data[0].embedding
            workspace.embedding = emb
            self.db.commit()
            
            logger.info("Generated embedding for workspace=%s", workspace_id)
            return 1
            
        except Exception as exc:
            logger.error("Embedding failed for workspace=%s: %s", workspace_id, exc)
            return 0

    # ── Private ───────────────────────────────────────────────────────────────

    def _to_domain(self, row: WorkspaceModel) -> Workspace:
        # Re-construct the fields dictionary for the legacy domain model
        fields = {
            "course_code":  row.course_code,
            "semester":     row.semester,
            "course_title": row.course_title
        }
        
        ws = Workspace(
            workspace_id = str(row.workspace_id),
            file_hash    = row.file_hash if hasattr(row, 'file_hash') and row.file_hash else "",
            status       = WorkspaceStatus("ready" if getattr(row, 'content', None) else "draft"),
            fields       = fields,
        )
        ws._created_at = ""
        ws._updated_at = ""
        return ws