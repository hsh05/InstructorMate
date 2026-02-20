from __future__ import annotations
import uuid
from typing import Dict, Any, List

from repositories.csv_workspace_repository import CsvWorkspaceRepository


class CsvSectionRepository:
    def __init__(self, ws_repo: CsvWorkspaceRepository) -> None:
        self.ws_repo = ws_repo

    def add(self, workspace_id: str, section: Dict[str, Any]) -> Dict[str, Any]:
        ws = self.ws_repo.load(workspace_id)
        sections = ws.get("sections", [])
        section = dict(section)
        section["id"] = section.get("id") or f"sec_{uuid.uuid4().hex[:8]}"
        sections.append(section)
        ws["sections"] = sections
        self.ws_repo.save(workspace_id, ws)
        return ws

    def update(self, workspace_id: str, section_id: str, patch: Dict[str, Any]) -> Dict[str, Any]:
        ws = self.ws_repo.load(workspace_id)
        sections = ws.get("sections", [])
        found = False
        for s in sections:
            if s.get("id") == section_id:
                s.update(patch)
                found = True
                break
        if not found:
            raise FileNotFoundError("Section not found")
        ws["sections"] = sections
        self.ws_repo.save(workspace_id, ws)
        return ws

    def delete(self, workspace_id: str, section_id: str) -> Dict[str, Any]:
        ws = self.ws_repo.load(workspace_id)
        sections = ws.get("sections", [])
        ws["sections"] = [s for s in sections if s.get("id") != section_id]
        self.ws_repo.save(workspace_id, ws)
        return ws
