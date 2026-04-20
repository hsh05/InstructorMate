# backend/services/file_service.py

import hashlib
import time
import csv
import re
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from openai import OpenAI
import pdfplumber

try:
    from docx import Document as DocxDocument
    _DOCX_AVAILABLE = True
except ImportError:
    _DOCX_AVAILABLE = False


# ── File Hashing ──────────────────────────────────────────────────────────────
class FileHashService:
    @staticmethod
    def compute(data: bytes) -> str:
        return hashlib.sha256(data).hexdigest()


# ── Data Classes ──────────────────────────────────────────────────────────────
@dataclass(frozen=True)
class PdfChunk:
    chunk_id: int
    page: int
    text: str

@dataclass(frozen=True)
class ConversionResult:
    single_row_csv: str
    chunks_csv: str


# ── JSON Parsing ──────────────────────────────────────────────────────────────
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


# ── Extractors ────────────────────────────────────────────────────────────────
class PdfTextExtractor:
    def extract_chunks(self, pdf_path: Path) -> List[PdfChunk]:
        if not pdf_path.exists():
            raise FileNotFoundError(f"PDF not found: {pdf_path.resolve()}")
            
        chunks: List[PdfChunk] = []
        chunk_id = 1
        
        with pdfplumber.open(str(pdf_path)) as pdf:
            for page_index, page in enumerate(pdf.pages, start=1):
                text = (page.extract_text(layout=True) or "").strip()
                if not text:
                    continue
                chunks.append(PdfChunk(chunk_id=chunk_id, page=page_index, text=text))
                chunk_id += 1
                
        if not chunks:
            raise RuntimeError("No text extracted. PDF may be scanned; OCR would be needed.")
        return chunks

class DocxTextExtractor:
    _PARAS_PER_CHUNK = 40

    def extract_chunks(self, docx_path: Path) -> List[PdfChunk]:
        if not _DOCX_AVAILABLE:
            raise RuntimeError("python-docx is not installed. Run: pip install python-docx")
        if not docx_path.exists():
            raise FileNotFoundError(f"DOCX not found: {docx_path.resolve()}")

        doc = DocxDocument(str(docx_path))
        all_text: list[str] = []

        def _iter_block_items(parent):
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
            chunks.append(PdfChunk(chunk_id=chunk_id, page=chunk_id, text=text))
            chunk_id += 1

        return chunks


# ── AI Field Extraction ───────────────────────────────────────────────────────
class SyllabusFieldExtractor:
    def __init__(self, model: str = "gpt-4o") -> None:
        self.client = OpenAI()
        self.model = model

    def extract_single_row(self, chunks: List[PdfChunk], columns: List[str]) -> Dict[str, str]:
        syllabus_text = self._compact_text(chunks, max_chars=15000)
        if len(syllabus_text.strip()) < 250:
            return {col: "" for col in columns}

        cols_json = json.dumps(columns, ensure_ascii=True)
        
        prompt = (
            "You are an expert data extractor. Extract structured fields from the syllabus text below.\n"
            "Return ONLY a valid JSON object matching the exact structure below. Do not add markdown formatting.\n\n"
            "EXPECTED JSON STRUCTURE:\n"
            "{\n"
            "  \"_scratchpad\": \"I am scanning for all assessments. On one page under OUT-OF-CLASS ASSIGNMENTS, I see Assignments. On the next page at the very top, I see orphaned table rows for Quiz 1, Quiz 2, Quiz 3, Midterm, and Final Exam. I will include ALL of them.\",\n"
            "  \"course_title\": \"Name of the course\",\n"
            "  \"course_code\": \"Course code (e.g., PHYS-101)\",\n"
            "  \"weekly_schedule\": {\n"
            "    \"1\": \"Topic for week 1\"\n"
            "  },\n"
            "  \"assessments_schedule\": [\n"
            "    {\"week\": \"4\", \"assessment\": \"Assignment 1\"},\n"
            "    {\"week\": \"4\", \"assessment\": \"Quiz 1\"}\n"
            "  ]\n"
            "}\n\n"
            "CRITICAL INSTRUCTIONS:\n"
            "1. 'assessments_schedule' MUST be a JSON Array of objects.\n"
            "2. DO NOT BE LAZY. Extract EVERY SINGLE Assignment, Quiz, Midterm, and Final Exam. \n"
            "3. PAGE BREAK WARNING: Tables break across pages! The 'Assessment Methods' header is at the bottom of one page, but the actual rows ('Quiz 1', 'Quiz 2', 'Midterm', 'Final') are at the VERY TOP of the NEXT page. Scan page tops carefully!\n"
            "4. You MUST use the '_scratchpad' key to explicitly write down every assessment you found across all pages before filling the array. This forces you to not forget any items.\n\n"
            f"COLUMNS(JSON array of strings): {cols_json}\n\n"
            f"SYLLABUS TEXT:\n{syllabus_text}\n"
        )

        raw = self._call_with_retries(prompt)
        data = SafeJson.loads_strict_or_extract(raw)

        if not isinstance(data, dict):
            raise ValueError("Extraction failed: output is not a JSON object.")

        normalized: Dict[str, str] = {}
        for name in columns:
            value = data.get(name, "")
            
            if name == "assessments_schedule" and isinstance(value, list):
                combined = {}
                for item in value:
                    if isinstance(item, dict):
                        w = str(item.get("week", "")).strip()
                        a = str(item.get("assessment", "")).strip()
                        if w and a:
                            if w in combined and a not in combined[w]:
                                combined[w] = f"{combined[w]}, {a}"
                            else:
                                combined[w] = a
                normalized[name] = json.dumps(combined)
            elif isinstance(value, (dict, list)):
                normalized[name] = json.dumps(value)
            else:
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
        first_pages = [c for c in chunks if c.page <= 5] 
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

        joined = "\n\n".join((c.text or "") for c in selected)
        return joined[:max_chars]


# ── CSV Writers ───────────────────────────────────────────────────────────────
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


# ── Main File Converter Service ───────────────────────────────────────────────
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
        template_csv_path: str, 
        output_base_name: Optional[str] = None,
    ) -> ConversionResult:
        doc_path = Path(pdf_path)
        if not doc_path.exists():
            raise FileNotFoundError(f"File not found: {doc_path.resolve()}")

        extractor = self._get_extractor(doc_path.suffix)
        out_dir = Path(output_dir)
        out_dir.mkdir(parents=True, exist_ok=True)

        # 👉 THE FIX: Tell the field extractor to look for the new schedule columns!
        columns = ["course_title", "course_code", "weekly_schedule", "assessments_schedule"]

        doc_bytes  = doc_path.read_bytes()
        doc_hash   = hashlib.sha256(doc_bytes).hexdigest()[:10]
        cache_buster = str(time.time())
        header_hash = hashlib.sha256(("|".join(columns) + cache_buster).encode("utf-8")).hexdigest()[:10]

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