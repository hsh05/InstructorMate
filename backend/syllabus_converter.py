from __future__ import annotations  # forward references in type hints

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
                    return text[start : i + 1]

        return None


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


class SyllabusFieldExtractor:
    def __init__(self, model: str = "gpt-5") -> None:
        self.client = OpenAI()
        self.model = model

    def extract_single_row(self, chunks: List[PdfChunk], columns: List[str]) -> Dict[str, str]:
        # Smaller cap = faster + cheaper, still enough for most syllabi.
        syllabus_text = self._compact_text(chunks, max_chars=3500)

        # If the syllabus text is too small, avoid paying for an LLM call.
        # (Usually means broken extraction or near-empty PDF.)
        if len(syllabus_text.strip()) < 250:
            return {col: "" for col in columns}

        cols_json = json.dumps(columns, ensure_ascii=True)

        prompt = (
            "You extract structured fields from syllabus text.\n"
            "Return ONLY valid JSON (no markdown, no commentary).\n"
            "Output must be a single JSON object mapping column names to values.\n"
            "Rules:\n"
            "- Use ONLY the provided syllabus text.\n"
            "- If a value is not found, use an empty string.\n"
            "- Keep lists as semicolon-separated strings.\n"
            "- For multiline fields, use '\\n' inside the string.\n"
            "- Keys MUST match the given columns EXACTLY.\n"
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
                # simple backoff: 1.5s, 3.0s, 4.5s
                time.sleep(1.5 * (attempt + 1))
        raise RuntimeError(f"OpenAI call failed after retries: {last_err}")

    def _compact_text(self, chunks: List[PdfChunk], max_chars: int) -> str:
        # Most syllabi put the key stuff early
        first_pages = [c for c in chunks if c.page <= 3]

        # “High-signal” pages across the doc
        keywords = (
            "assessment", "grading", "grade", "rubric", "evaluation",
            "office hour", "office hours", "instructor", "email", "contact",
            "schedule", "timeline", "calendar", "weekly", "outline", "topics",
            "policy", "policies", "attendance", "late", "late work","textbook",
            "academic integrity", "plagiarism", "exam", "midterm", "final",
            "quiz", "project", "assignment", "learning outcomes", "objectives",
            "prerequisite", "required text", "textbook",
        )

        keyword_pages: List[PdfChunk] = []
        for c in chunks:
            t = c.text.lower()
            if any(k in t for k in keywords):
                keyword_pages.append(c)

        # Dedupe pages while preserving order
        seen_pages = set()
        selected: List[PdfChunk] = []
        for c in first_pages + keyword_pages:
            if c.page not in seen_pages:
                selected.append(c)
                seen_pages.add(c.page)

        # IMPORTANT: do NOT include any "[page X]" markers in the model input
        # Also cap each page text so one huge page doesn’t dominate.
        per_page_cap = 1200
        joined = "\n\n".join((c.text or "")[:per_page_cap] for c in selected)

        return joined[:max_chars]


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


class SyllabusConverterService:
    def __init__(self, model: str = "gpt-5") -> None:
        self.extractor = PdfTextExtractor()
        self.schema_loader = CsvSchemaLoader()
        self.field_extractor = SyllabusFieldExtractor(model=model)
        self.writer = CsvFileWriter()

    def convert(
        self,
        pdf_path: str,
        output_dir: str,
        template_csv_path: str,
        output_base_name: Optional[str] = None,
    ) -> ConversionResult:
        pdf = Path(pdf_path)
        if not pdf.exists():
            raise FileNotFoundError(f"PDF not found: {pdf.resolve()}")

        out_dir = Path(output_dir)
        out_dir.mkdir(parents=True, exist_ok=True)

        # Load template columns first (fast)
        columns = self.schema_loader.load_columns(template_csv_path)

        # Hashes first (enables true cache hit short-circuit)
        pdf_bytes = pdf.read_bytes()
        pdf_hash = hashlib.sha256(pdf_bytes).hexdigest()[:10]
        header_hash = hashlib.sha256(("|".join(columns)).encode("utf-8")).hexdigest()[:10]

        base = output_base_name.strip() if output_base_name and output_base_name.strip() else pdf.stem

        # sanitize base to match doc_id regex [A-Za-z0-9._-]
        base = re.sub(r"[^A-Za-z0-9._-]+", "_", base)
        base = base.strip("._-")
        if not base:
            base = "syllabus"

        # cap base so "{base}.{pdf_hash}.{header_hash}" stays within 200 chars
        max_total = 200
        suffix = f".{pdf_hash}.{header_hash}"
        max_base_len = max_total - len(suffix)
        if max_base_len < 5:
            max_base_len = 5
        if len(base) > max_base_len:
            base = base[:max_base_len].rstrip("._-")

        prefix = f"{base}.{pdf_hash}.{header_hash}"

        single_row_path = out_dir / f"{prefix}.single_row.csv"
        chunks_path = out_dir / f"{prefix}.chunks.csv"

        # Cache hit: no extraction, no OpenAI
        if single_row_path.exists() and chunks_path.exists():
            return ConversionResult(single_row_csv=str(single_row_path), chunks_csv=str(chunks_path))

        # Heavy extraction
        t0 = time.time()
        chunks = self.extractor.extract_chunks(pdf)
        print("extract_chunks sec:", round(time.time() - t0, 2))

        # LLM extraction (slowest)
        t1 = time.time()
        single_row = self.field_extractor.extract_single_row(chunks, columns)
        print("llm sec:", round(time.time() - t1, 2))

        self.writer.write_single_row(single_row_path, single_row)
        self.writer.write_chunks(chunks_path, chunks)

        return ConversionResult(single_row_csv=str(single_row_path), chunks_csv=str(chunks_path))


def convert_pdf_to_csvs(
    pdf_path: str,
    output_dir: str = "output",
    model: str = "gpt-5",
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