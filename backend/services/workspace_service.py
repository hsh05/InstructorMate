import uuid
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
        # FIX BUG 2: instantiate converter so we can generate chunks.csv on upload
        self.converter    = SyllabusConverterService(model="gpt-5")

    def create_from_file(self, filename: str, content: bytes):
        pdf_hash = self.hash_service.compute(content)

        # Check for duplicate upload
        existing = next(
            (ws for ws in self.repo.list_all() if ws.pdf_hash == pdf_hash),
            None
        )
        if existing:
            return {"already_uploaded": True, "workspace": existing}

        # Parse text for basic field extraction
        text   = self.parser.extract_text(filename, content)
        fields = self.extractor.extract_fields(text)

        workspace = Workspace(
            workspace_id=str(uuid.uuid4()),
            pdf_hash=pdf_hash,
            fields=fields,
            status=WorkspaceStatus.DRAFT,
        )

        self.repo.save(workspace)

        # FIX BUG 2: write the PDF to a temp file and run the converter
        # to produce chunks.csv (needed by the Ask AI feature)
        ws_dir = self.repo.workspace_dir(workspace.workspace_id)
        ws_dir.mkdir(parents=True, exist_ok=True)
        tmp_pdf = ws_dir / "syllabus.pdf"
        tmp_pdf.write_bytes(content)

        try:
            result = self.converter.convert(
                pdf_path=str(tmp_pdf),
                output_dir=str(ws_dir),
                # Template defines what fields to extract — use the workspace CSV columns
                template_csv_path="backend/data/workspaces.csv",
                output_base_name="chunks",
            )
            # converter writes chunks.csv with a hash-based name — rename to a fixed path
            # so get_chunks_csv_path() can always find it
            chunks_src = Path(result.chunks_csv)
            chunks_dst = self.repo.get_chunks_csv_path(workspace.workspace_id)
            if chunks_src.exists() and chunks_src != chunks_dst:
                chunks_src.replace(chunks_dst)

            # Also pull extracted fields from single_row_csv if richer than basic extraction
            import csv
            single_row_src = Path(result.single_row_csv)
            if single_row_src.exists():
                with open(single_row_src, newline="", encoding="utf-8") as f:
                    row = next(csv.DictReader(f), None)
                if row:
                    # Only update fields that are currently empty
                    for k, v in row.items():
                        if k in workspace.fields and not workspace.fields.get(k) and v:
                            fields[k] = v
                    workspace.update_fields(fields)
                    self.repo.save(workspace)

        except Exception as e:
            # Don't fail the whole upload if converter errors — workspace still usable
            print(f"[WorkspaceService] converter warning: {e}")

        return {"already_uploaded": False, "workspace": workspace}

    def update_workspace(self, workspace_id: str, updates: dict):
        ws = self.repo.get_by_id(workspace_id)
        if ws is None:
            raise FileNotFoundError(f"Workspace '{workspace_id}' not found")
        ws.update_fields(updates)
        self.repo.save(ws)
        return ws