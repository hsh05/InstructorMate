from __future__ import annotations
import json
import os
from pathlib import Path
from typing import Optional, Dict, Any, List
from domain.workspace import Workspace
from domain.enums import WorkspaceStatus


DATA_DIR = Path("data")
WS_DIR = DATA_DIR / "workspaces"
INDEX_PATH = DATA_DIR / "index.json"



class CsvWorkspaceRepository:
    def __init__(self) -> None:
        WS_DIR.mkdir(parents=True, exist_ok=True)
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        if not INDEX_PATH.exists():
            INDEX_PATH.write_text(json.dumps({"hash_to_id": {}}, indent=2), encoding="utf-8")

    def _load_index(self) -> Dict[str, str]:
        obj = json.loads(INDEX_PATH.read_text(encoding="utf-8"))
        return dict(obj.get("hash_to_id", {}))
    
    def get_by_pdf_hash(self, pdf_hash: str):
        for ws in self.list_all():
            if ws.pdf_hash == pdf_hash:
                return ws
        return None

    def _save_index(self, m: Dict[str, str]) -> None:
        INDEX_PATH.write_text(json.dumps({"hash_to_id": m}, indent=2), encoding="utf-8")

    def find_by_hash(self, syllabus_hash: str) -> Optional[str]:
        return self._load_index().get(syllabus_hash)

    def link_hash(self, syllabus_hash: str, workspace_id: str) -> None:
        idx = self._load_index()
        idx[syllabus_hash] = workspace_id
        self._save_index(idx)

    def workspace_dir(self, workspace_id: str) -> Path:
        return WS_DIR / workspace_id

    def save(self, workspace) -> None:
        wid = workspace.workspace_id
        wdir = self.workspace_dir(wid)
        wdir.mkdir(parents=True, exist_ok=True)

        path = wdir / "workspace.json"

        # Convert workspace object to dict
        data = {
            "workspace_id": workspace.workspace_id,
            "pdf_hash": workspace.pdf_hash,
            "fields": workspace.fields,
            "status": workspace.status.value
        }

        path.write_text(json.dumps(data, indent=2), encoding="utf-8")


    def load(self, workspace_id: str):
        path = self.workspace_dir(workspace_id) / "workspace.json"
        if not path.exists():
            raise FileNotFoundError("Workspace not found")
        

        data = json.loads(path.read_text(encoding="utf-8"))
        return Workspace(
            workspace_id=data["workspace_id"],
            pdf_hash=data["pdf_hash"],
            fields=data["fields"],
            status=WorkspaceStatus(data["status"])
        )
    
    def list_all(self) -> List[Workspace]:
        out: List[Workspace] = []
        for d in sorted(WS_DIR.iterdir()):
            if d.is_dir():
                p = d / "workspace.json"
                if p.exists():
                    data = json.loads(p.read_text(encoding="utf-8"))
                    ws = Workspace(
                        workspace_id=data["workspace_id"],
                        pdf_hash=data["pdf_hash"],
                        fields=data["fields"],
                        status=WorkspaceStatus(data["status"])
                    )
                    out.append(ws)
        return out



