import uuid
import csv
from pathlib import Path
from domain.workspace import Workspace
from domain.enums import WorkspaceStatus
from syllabus_converter import SyllabusConverterService


class WorkspaceService:

    def __init__(self, repo, parser, extractor, hash_service):
        self.repo         = repo
        self.parser       = parser
        self.extractor    = extractor
        self.hash_service = hash_service
        self.converter    = SyllabusConverterService(model="gpt-5")

    def create_from_file(self, filename: str, content: bytes):
        pdf_hash = self.hash_service.compute(content)

        existing = next(
            (ws for ws in self.repo.list_all() if ws.pdf_hash == pdf_hash),
            None
        )
        if existing:
            return {"already_uploaded": True, "workspace": existing}

        text   = self.parser.extract_text(filename, content)
        fields = self.extractor.extract_fields(text)

        workspace = Workspace(
            workspace_id=str(uuid.uuid4()),
            pdf_hash=pdf_hash,
            fields=fields,
            status=WorkspaceStatus.DRAFT,
        )
        self.repo.save(workspace)

        # Generate chunks.csv for the Ask AI feature
        self._run_converter(workspace.workspace_id, content, workspace)

        return {"already_uploaded": False, "workspace": workspace}

    def reprocess_pdf(self, workspace_id: str, content: bytes):
        """Re-run the converter for an existing workspace to generate/refresh chunks.csv.
        Used when a workspace was created before the converter ran, or chunks.csv is missing.
        """
        ws = self.repo.get_by_id(workspace_id)
        if ws is None:
            raise FileNotFoundError(f"Workspace '{workspace_id}' not found")

        self._run_converter(workspace_id, content, ws)
        return ws

    def _run_converter(self, workspace_id: str, content: bytes, workspace: Workspace):
        ws_dir  = self.repo.workspace_dir(workspace_id)
        ws_dir.mkdir(parents=True, exist_ok=True)
        tmp_pdf = ws_dir / "syllabus.pdf"
        tmp_pdf.write_bytes(content)

        try:
            result = self.converter.convert(
                pdf_path=str(tmp_pdf),
                output_dir=str(ws_dir),
                template_csv_path="backend/data/workspaces.csv",
                output_base_name="chunks",
            )

            # Move converter output to the fixed path get_chunks_csv_path() expects
            chunks_src = Path(result.chunks_csv)
            chunks_dst = self.repo.get_chunks_csv_path(workspace_id)
            if chunks_src.exists() and chunks_src != chunks_dst:
                chunks_src.replace(chunks_dst)

            # Fill any empty workspace fields from the richer LLM extraction
            single_row_src = Path(result.single_row_csv)
            if single_row_src.exists():
                with open(single_row_src, newline="", encoding="utf-8") as f:
                    row = next(csv.DictReader(f), None)
                if row:
                    updates = {
                        k: v for k, v in row.items()
                        if k in workspace.fields and not workspace.fields.get(k) and v
                    }
                    if updates:
                        workspace.update_fields(updates)
                        self.repo.save(workspace)

        except Exception as e:
            print(f"[WorkspaceService] converter warning: {e}")
            raise  # re-raise so routes can return a proper error

    def update_workspace(self, workspace_id: str, updates: dict):
        ws = self.repo.get_by_id(workspace_id)
        if ws is None:
            raise FileNotFoundError(f"Workspace '{workspace_id}' not found")
        ws.update_fields(updates)
        self.repo.save(ws)
        return ws