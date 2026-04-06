# backend/syllabus_converter.py

from __future__ import annotations

import time
import csv
import re
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from openai import OpenAI
from pypdf import PdfReader


try:
    from docx import Document as DocxDocument
    _DOCX_AVAILABLE = True
except ImportError:
    _DOCX_AVAILABLE = False


@dataclass(frozen=True)
class PdfChunk:
    chunk_id: int
    page: int
    text: str


@dataclass(frozen=True)
class ConversionResult:
    single_row_csv: str
    chunks_csv: str


class JsonParseError(ValueError):
    pass


class SafeJson:
    @staticmethod
    def loads_strict_or_extract(text: str) -> Any:
        text = (text or "").strip()
        if not text:
            raise JsonParseError("Empty model output; expected JSON.")
        try:
            return json.loads(text)
        except Exception:
            pass
        extracted = SafeJson._extract_first_json(text)
        if extracted is None:
            raise JsonParseError("Model output was not valid JSON and no JSON block was found.")
        try:
            return json.loads(extracted)
        except Exception as e:
            raise JsonParseError(f"Failed to parse extracted JSON block: {e}") from e

    @staticmethod
    def _extract_first_json(text: str) -> Optional[str]:
        start_candidates: List[Tuple[int, str]] = []
        obj_i = text.find("{")
        arr_i = text.find("[")
        if obj_i != -1:
            start_candidates.append((obj_i, "{"))
        if arr_i != -1:
            start_candidates.append((arr_i, "["))
        if not start_candidates:
            return None
        start_candidates.sort(key=lambda x: x[0])
        start, opening = start_candidates[0]
        closing = "}" if opening == "{" else "]"
        depth = 0
        in_string = False
        escape = False
        for i in range(start, len(text)):
            ch = text[i]
            if in_string:
                if escape:
                    escape = False
                elif ch == "\\":
                    escape = True
                elif ch == '"':
                    in_string = False
                continue
            if ch == '"':
                in_string = True
                continue
            if ch == opening:
                depth += 1
            elif ch == closing:
                depth -= 1
                if depth == 0:
                    return text[start: i + 1]
        return None


# ── PDF extractor ──────────────────────────────────────────────────────────────

class PdfTextExtractor:
    def extract_chunks(self, pdf_path: Path) -> List[PdfChunk]:
        if not pdf_path.exists():
            raise FileNotFoundError(f"PDF not found: {pdf_path.resolve()}")
        reader = PdfReader(str(pdf_path))
        chunks: List[PdfChunk] = []
        chunk_id = 1
        for page_index, page in enumerate(reader.pages, start=1):
            text = (page.extract_text() or "").strip()
            if not text:
                continue
            chunks.append(PdfChunk(chunk_id=chunk_id, page=page_index, text=text))
            chunk_id += 1
        if not chunks:
            raise RuntimeError("No text extracted. PDF may be scanned; OCR would be needed.")
        return chunks


# ── DOCX extractor ─────────────────────────────────────────────────────────────

class DocxTextExtractor:
    """
    Extracts text from .docx files using python-docx.
    Groups paragraphs into ~page-sized chunks (every 40 paragraphs = 1 chunk)
    so the downstream pipeline treats them the same as PDF pages.
    """

    _PARAS_PER_CHUNK = 40

    def extract_chunks(self, docx_path: Path) -> List[PdfChunk]:
        if not _DOCX_AVAILABLE:
            raise RuntimeError(
                "python-docx is not installed. Run: pip install python-docx --break-system-packages"
            )
        if not docx_path.exists():
            raise FileNotFoundError(f"DOCX not found: {docx_path.resolve()}")

        doc = DocxDocument(str(docx_path))
        all_text: list[str] = []
        from docx.oxml.ns import qn

        def _iter_block_items(parent):
            """Yield paragraphs and tables in document order."""
            from docx.table import Table
            from docx.text.paragraph import Paragraph
            for child in parent.element.body:
                tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                if tag == 'p':
                    yield Paragraph(child, parent)
                elif tag == 'tbl':
                    yield Table(child, parent)

        for block in _iter_block_items(doc):
            from docx.table import Table
            from docx.text.paragraph import Paragraph
            if isinstance(block, Paragraph):
                t = block.text.strip()
                if t:
                    all_text.append(t)
            elif isinstance(block, Table):
                for row in block.rows:
                    row_cells = [c.text.strip() for c in row.cells if c.text.strip()]
                    # Deduplicate merged cells (python-docx repeats them)
                    seen = []
                    for cell in row_cells:
                        if not seen or cell != seen[-1]:
                            seen.append(cell)
                    if seen:
                        all_text.append(' | '.join(seen))

        paragraphs = all_text

        if not paragraphs:
            raise RuntimeError("No text extracted from DOCX. The file may be empty.")

        chunks: List[PdfChunk] = []
        chunk_id = 1
        for i in range(0, len(paragraphs), self._PARAS_PER_CHUNK):
            group = paragraphs[i: i + self._PARAS_PER_CHUNK]
            text = "\n".join(group)
            # "page" is a virtual page number — fine for downstream use
            page = chunk_id
            chunks.append(PdfChunk(chunk_id=chunk_id, page=page, text=text))
            chunk_id += 1

        return chunks


# ── Schema loader ──────────────────────────────────────────────────────────────

class CsvSchemaLoader:
    def load_columns(self, csv_path: str) -> List[str]:
        path = Path(csv_path)
        if not path.exists():
            raise FileNotFoundError(f"Template CSV not found: {path.resolve()}")
        with path.open("r", encoding="utf-8") as f:
            reader = csv.reader(f)
            header = next(reader, None)
        if not header:
            raise ValueError("Template CSV has no header row.")
        cols = [h.strip() for h in header if h and h.strip()]
        if not cols:
            raise ValueError("Template CSV header is empty.")
        return cols


# ── LLM field extractor ────────────────────────────────────────────────────────

class SyllabusFieldExtractor:
    def __init__(self, model: str = "gpt-4o") -> None:
        self.client = OpenAI()
        self.model = model

    def extract_single_row(self, chunks: List[PdfChunk], columns: List[str]) -> Dict[str, str]:
        syllabus_text = self._compact_text(chunks, max_chars=3500)
        if len(syllabus_text.strip()) < 250:
            return {col: "" for col in columns}

        cols_json = json.dumps(columns, ensure_ascii=True)
        prompt = (
            "You extract structured fields from university syllabus text.\n"
            "Return ONLY valid JSON (no markdown, no commentary).\n"
            "Output must be a single JSON object mapping column names to values.\n"
            "Rules:\n"
            "- Use ONLY the provided syllabus text.\n"
            "- If a value is not found, use an empty string.\n"
            "- Keys MUST match the given columns EXACTLY.\n"
            "Definitions:\n"
            "- 'course_title': The actual name of the class (e.g. 'Intro to Physics', 'Calculus I'). DO NOT put the instructor's name here.\n"
            "- 'course_code': The short alphanumeric code for the class (e.g. 'PHYS-101', 'CS102').\n"
            "\n"
            f"COLUMNS(JSON array of strings): {cols_json}\n"
            "\n"
            f"SYLLABUS TEXT:\n{syllabus_text}\n"
        )

        raw = self._call_with_retries(prompt)
        data = SafeJson.loads_strict_or_extract(raw)

        if not isinstance(data, dict):
            raise ValueError("Extraction failed: output is not a JSON object.")

        normalized: Dict[str, str] = {}
        for name in columns:
            value = data.get(name, "")
            normalized[name] = str(value) if value is not None else ""
        return normalized

    def _call_with_retries(self, prompt: str) -> str:
        last_err: Optional[Exception] = None
        for attempt in range(3):
            try:
                resp = self.client.responses.create(
                    model=self.model,
                    input=[{"role": "user", "content": prompt}],
                )
                return (resp.output_text or "").strip()
            except Exception as e:
                last_err = e
                time.sleep(1.5 * (attempt + 1))
        raise RuntimeError(f"OpenAI call failed after retries: {last_err}")

    def _compact_text(self, chunks: List[PdfChunk], max_chars: int) -> str:
        first_pages = [c for c in chunks if c.page <= 3]
        keywords = (
            "assessment", "grading", "grade", "rubric", "evaluation",
            "office hour", "instructor", "email", "contact",
            "schedule", "timeline", "calendar", "weekly", "outline",
            "policy", "attendance", "late", "textbook",
            "exam", "midterm", "final", "quiz", "project", "assignment",
        )
        keyword_pages: List[PdfChunk] = []
        for c in chunks:
            t = c.text.lower()
            if any(k in t for k in keywords):
                keyword_pages.append(c)

        seen_pages = set()
        selected: List[PdfChunk] = []
        for c in first_pages + keyword_pages:
            if c.page not in seen_pages:
                selected.append(c)
                seen_pages.add(c.page)

        per_page_cap = 1200
        joined = "\n\n".join((c.text or "")[:per_page_cap] for c in selected)
        return joined[:max_chars]


# ── CSV writer ─────────────────────────────────────────────────────────────────
# (Keep your CsvFileWriter exactly as is)
class CsvFileWriter:
    def write_single_row(self, csv_path: Path, row: Dict[str, str]) -> None:
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        fieldnames = list(row.keys())
        with csv_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerow(row)

    def write_chunks(self, csv_path: Path, chunks: List[PdfChunk]) -> None:
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        with csv_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=["chunk_id", "page", "text"])
            writer.writeheader()
            for c in chunks:
                writer.writerow({"chunk_id": c.chunk_id, "page": c.page, "text": c.text})


# ── Main service ───────────────────────────────────────────────────────────────

_SUPPORTED_EXTENSIONS = {".pdf", ".docx"}

class SyllabusConverterService:
    def __init__(self, model: str = "gpt-4o") -> None:
        self.pdf_extractor  = PdfTextExtractor()
        self.docx_extractor = DocxTextExtractor()
        self.field_extractor = SyllabusFieldExtractor(model=model)
        self.writer = CsvFileWriter()

    def _get_extractor(self, suffix: str):
        s = suffix.lower()
        if s == ".pdf":
            return self.pdf_extractor
        if s == ".docx":
            if not _DOCX_AVAILABLE:
                raise ValueError("python-docx is not installed.")
            return self.docx_extractor
        raise ValueError(f"Unsupported file type '{s}'")

    def convert(
        self,
        pdf_path: str,
        output_dir: str,
        template_csv_path: str, # We keep the argument so we don't break function calls, but we ignore it!
        output_base_name: Optional[str] = None,
    ) -> ConversionResult:
        doc_path = Path(pdf_path)
        if not doc_path.exists():
            raise FileNotFoundError(f"File not found: {doc_path.resolve()}")

        extractor = self._get_extractor(doc_path.suffix)
        out_dir = Path(output_dir)
        out_dir.mkdir(parents=True, exist_ok=True)

        # 👉 THE FIX: Bypass the confusing CSV template. Force the exact 3 DB columns!
        columns = ["course_title", "course_code"]

        doc_bytes  = doc_path.read_bytes()
        doc_hash   = hashlib.sha256(doc_bytes).hexdigest()[:10]
        header_hash = hashlib.sha256(("|".join(columns)).encode("utf-8")).hexdigest()[:10]

        base = output_base_name.strip() if output_base_name and output_base_name.strip() else doc_path.stem
        base = re.sub(r"[^A-Za-z0-9._-]+", "_", base).strip("._-") or "syllabus"
        suffix = f".{doc_hash}.{header_hash}"
        max_base_len = max(200 - len(suffix), 5)
        if len(base) > max_base_len:
            base = base[:max_base_len].rstrip("._-")

        prefix = f"{base}.{doc_hash}.{header_hash}"
        single_row_path = out_dir / f"{prefix}.single_row.csv"
        chunks_path     = out_dir / f"{prefix}.chunks.csv"

        if single_row_path.exists() and chunks_path.exists():
            return ConversionResult(single_row_csv=str(single_row_path), chunks_csv=str(chunks_path))

        chunks = extractor.extract_chunks(doc_path)
        single_row = self.field_extractor.extract_single_row(chunks, columns)

        self.writer.write_single_row(single_row_path, single_row)
        self.writer.write_chunks(chunks_path, chunks)

        return ConversionResult(single_row_csv=str(single_row_path), chunks_csv=str(chunks_path))


# ── Public helper ──────────────────────────────────────────────────────────────

def convert_pdf_to_csvs(
    pdf_path: str,
    output_dir: str = "output",
    model: str = "gpt-4o",
    template_csv_path: str = "templates/default_template.csv",
    output_base_name: Optional[str] = None,
) -> Dict[str, str]:
    service = SyllabusConverterService(model=model)
    result = service.convert(
        pdf_path=pdf_path,
        output_dir=output_dir,
        template_csv_path=template_csv_path,
        output_base_name=output_base_name,
    )
    return {"single_row_csv": result.single_row_csv, "chunks_csv": result.chunks_csv}