from __future__ import annotations  # forward references in type hints
import time  # <-- make sure this is at top of file
import csv  # read/write CSV files
import re
import hashlib  # hashing for caching by PDF content
import json  # parse model outputs (JSON)
from dataclasses import dataclass  # lightweight immutable data structures
from pathlib import Path  # safe path operations
from typing import Any, Dict, List, Optional, Tuple  # typing helpers

from openai import OpenAI  # OpenAI client
from pypdf import PdfReader  # PDF text extraction library


@dataclass(frozen=True)  # make instances immutable (UNCHANGEABLE) EX: ID WILL NEVER CHANGE so you dont accidently overwriting
class PdfChunk:  # represent one extracted chunk from the PDF
    chunk_id: int  # unique chunk id (1..N)
    page: int  # page number (1..N)
    text: str  # extracted text for that page


@dataclass(frozen=True)  # make instances immutable
class ConversionResult:  # represent final conversion file paths
    single_row_csv: str  # output path to single-row summary CSV
    chunks_csv: str  # output path to chunks CSV used for Q&A


class JsonParseError(ValueError):  # specialized parse error for clarity
    pass  # no extra fields needed


class SafeJson:  # “Make JSON parsing (converting json to python structured way(def)) not break even if ChatGPT adds extra words” #SRP = Single Responsibility Principle: “this class only does JSON parsing stuff.”
    @staticmethod #does not store, doesnt depend on prev calls, does not create objetcs, it just recieves text, tries to parse to json, returns result
    def loads_strict_or_extract(text: str) -> Any:  ## “Try normal JSON parse; if it fails, try to extract JSON from the text”
        text = (text or "").strip()  # normalize and strip whitespace
        if not text:  # empty output is invalid
            raise JsonParseError("Empty model output; expected JSON.")  # clear failure (the one up)

        try:  # #handles errors safely, instead of crashing if error exists, it will go to (except) to do smth else
            return json.loads(text)  # Converts JSON text (a string) into Python data.
        except Exception:  # if it fails, goes to pass
            pass  # continue below

        extracted = SafeJson._extract_first_json(text)  # locate JSON portion --> Its a helper method that not to be used outside this class
        if extracted is None:  # If we couldn’t find {...} or [...] at all.
            raise JsonParseError("Model output was not valid JSON and no JSON block was found.")  # fail

        try:  #handles errors safely, instead of crashing if error exists, it will go to (except) to do smth else
            return json.loads(extracted)  # parse extracted JSON, found {...} or [...] at all.
        except Exception as e:  # still invalid JSON
            raise JsonParseError(f"Failed to parse extracted JSON block: {e}") from e  # include cause

    @staticmethod
    def _extract_first_json(text: str) -> Optional[str]:  # find first {...} or [...] block  --> optional means return string (blocks found {} , or )might return non (no json block found)
        start_candidates: List[Tuple[int, str]] = []  # candidate starts list (starts empty)
        obj_i = text.find("{")  # find first object
        arr_i = text.find("[")  # find first array
        if obj_i != -1:  # if object exists
            start_candidates.append((obj_i, "{"))  # add candidate (stores at the end of list), If { exists, store the index and the symbol.
        if arr_i != -1:  # if array exists
            start_candidates.append((arr_i, "["))  # add candidate
        if not start_candidates:  # if nothing found
            return None  # cannot extract

        start_candidates.sort(key=lambda x: x[0])  # Sort candidates by index (earliest in text).
        start, opening = start_candidates[0]  # select earliest
        closing = "}" if opening == "{" else "]"  # choose matching closing bracket

        depth = 0  # track nesting depth  For {}: seeing { increases depth, seeing } decreases depth,When depth returns to 0 → JSON block ended.
        in_string = False  # Tracks if we have braces inside strings "..." cause then they dont count
        escape = False  # tracks escaping like \" inside strings.

        for i in range(start, len(text)):  # scan forward
            ch = text[i]  # current character

            if in_string:  # if inside string
                if escape:  # if previous was backslash
                    escape = False  # we remove it /
                elif ch == "\\":  # start escape
                    escape = True  # mark escape
                elif ch == '"':  # end string
                    in_string = False  # leave string mode
                continue  # skip bracket logic inside strings

            if ch == '"':  # enter string
                in_string = True  # set string mode
                continue  # next

            if ch == opening:  # opening bracket
                depth += 1  # increase depth
            elif ch == closing:  # closing bracket
                depth -= 1  # decrease depth
                if depth == 0:  # finished first JSON block
                    return text[start : i + 1]  # return substring

        return None  # no balanced JSON found


class PdfTextExtractor:  # SRP: only extract text from PDF (makes pdf chunks) Happens when we pick a pdf from disk
    def extract_chunks(self, pdf_path: Path) -> List[PdfChunk]:  # PDF -> list of PdfChunk (Input: pdf_path (Path object). Output: list of PdfChunk objects.)
        if not pdf_path.exists():  # validate path exists
            raise FileNotFoundError(f"PDF not found: {pdf_path.resolve()}")  # Stop the program here and throw an error.

        reader = PdfReader(str(pdf_path))  # open PDF
        chunks: List[PdfChunk] = []  # allocate output list
        chunk_id = 1  # start chunk id at 1

        for page_index, page in enumerate(reader.pages, start=1):  # loop pages
            text = (page.extract_text() or "").strip()  # extract text and trim
            if not text:  # skip empty pages
                continue  # next page
            chunks.append(PdfChunk(chunk_id=chunk_id, page=page_index, text=text))  # append chunk
            chunk_id += 1  # increment id

        if not chunks:  # if nothing extracted
            raise RuntimeError("No text extracted. PDF may be scanned; OCR would be needed.")  # fail clearly

        return chunks  # return extracted chunks


class CsvSchemaLoader:  # SRP: “Read only the header row from your template CSV”
    def load_columns(self, csv_path: str) -> List[str]:  # return header column list
        path = Path(csv_path)  # normalize to Path (string)
        if not path.exists():  # validate template exists
            raise FileNotFoundError(f"Template CSV not found: {path.resolve()}")  # clear error

        with path.open("r", encoding="utf-8") as f:  # read mode
            reader = csv.reader(f)  # build CSV reader
            header = next(reader, None)  # read first row

        if not header:  # header missing
            raise ValueError("Template CSV has no header row.")  # fail clearly

        cols = [h.strip() for h in header if h and h.strip()]  # trim + remove empties
        if not cols:  # header exists but empty
            raise ValueError("Template CSV header is empty.")  # fail clearly

        return cols  # return column list


class SyllabusFieldExtractor:  # SRP: extract values for a fixed schema (single-row)
    def __init__(self, model: str = "gpt-5") -> None:  # configure model
        self.client = OpenAI()  # OpenAI client
        self.model = model  # model name

    def extract_single_row(self, chunks: List[PdfChunk], columns: List[str]) -> Dict[str, str]:  # extract row
        syllabus_text = self._compact_text(chunks, max_chars=5000)  # cap text (speed/cost)
        cols_json = json.dumps(columns, ensure_ascii=True)  # schema as JSON for the prompt

        prompt = (  # build extraction prompt
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

        response = self.client.responses.create(
            model=self.model,
            input=[{"role": "user", "content": prompt}],
        )

        raw = (response.output_text or "").strip()
        data = SafeJson.loads_strict_or_extract(raw)

        if not isinstance(data, dict):
            raise ValueError("Extraction failed: output is not a JSON object.")

        normalized: Dict[str, str] = {}
        for name in columns:
            value = data.get(name, "")
            normalized[name] = str(value) if value is not None else ""

        return normalized

    def _compact_text(self, chunks: List[PdfChunk], max_chars: int) -> str:
        # ✅ prioritize early pages (most syllabi put key info first)
        first_pages = [c for c in chunks if c.page <= 3]

        # ✅ also include “high-signal” pages if they exist
        keywords = ("assessment", "grading", "office hour", "instructor", "email", "schedule", "policy")
        keyword_pages: List[PdfChunk] = []
        for c in chunks:
            t = c.text.lower()
            if any(k in t for k in keywords):
                keyword_pages.append(c)

        # ✅ dedupe while preserving order
        seen = set()
        selected: List[PdfChunk] = []
        for c in first_pages + keyword_pages:
            if c.page not in seen:
                selected.append(c)
                seen.add(c.page)

        joined = "\n\n".join(f"[page {c.page}]\n{c.text}" for c in selected)
        return joined[:max_chars]


class CsvFileWriter:  # SRP: write CSV files
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


class SyllabusConverterService:  # orchestrator: PDF -> values -> CSVs
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

        # ✅ ALWAYS load template columns first (fast + needed for deterministic naming)
        columns = self.schema_loader.load_columns(template_csv_path)

        # ✅ compute hashes BEFORE any heavy work (this enables true cache-hit short-circuit)
        pdf_bytes = pdf.read_bytes()
        pdf_hash = hashlib.sha256(pdf_bytes).hexdigest()[:10]
        header_hash = hashlib.sha256(("|".join(columns)).encode("utf-8")).hexdigest()[:10]

        base = output_base_name.strip() if output_base_name and output_base_name.strip() else pdf.stem

        # ✅ sanitize so doc_id ALWAYS matches backend regex [A-Za-z0-9._-]
        base = re.sub(r"[^A-Za-z0-9._-]+", "_", base)
        base = base.strip("._-")
        if not base:
            base = "syllabus"

        # ✅ IMPORTANT FIX:
        # Backend requires doc_id length 5..200.
        # Your doc_id is: "{base}.{pdf_hash}.{header_hash}"
        # So if base is long, doc_id becomes >200 and backend returns 400 AFTER the LLM finishes.
        #
        # We cap base length so prefix always fits.
        max_total = 200
        suffix = f".{pdf_hash}.{header_hash}"
        max_base_len = max_total - len(suffix)
        if max_base_len < 5:  # safety: should never happen, but just in case
            max_base_len = 5
        if len(base) > max_base_len:
            base = base[:max_base_len].rstrip("._-")  # trim and clean end

        prefix = f"{base}.{pdf_hash}.{header_hash}"

        single_row_path = out_dir / f"{prefix}.single_row.csv"
        chunks_path = out_dir / f"{prefix}.chunks.csv"

        # ✅ CACHE-HIT SHORT-CIRCUIT: return immediately (NO text extraction, NO OpenAI)
        if single_row_path.exists() and chunks_path.exists():
            return ConversionResult(single_row_csv=str(single_row_path), chunks_csv=str(chunks_path))

        # ❗only now do the heavy extraction
        t0 = time.time()
        chunks = self.extractor.extract_chunks(pdf)
        print("extract_chunks sec:", round(time.time() - t0, 2))

        # ❗only now do the LLM call (slowest)
        t1 = time.time()
        single_row = self.field_extractor.extract_single_row(chunks, columns)
        print("llm sec:", round(time.time() - t1, 2))

        # ✅ write outputs to deterministic paths
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
