from __future__ import annotations  # forward references in type hints

import csv  # read/write CSV files
import hashlib  # hashing for caching by PDF content
import json  # parse model outputs (JSON)
from dataclasses import dataclass  # lightweight immutable data structures
from pathlib import Path  # safe path operations
from typing import Any, Dict, List, Optional, Tuple  # typing helpers

from openai import OpenAI  # OpenAI client
from pypdf import PdfReader  # PDF text extraction library


@dataclass(frozen=True)  # make instances immutable
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


class SafeJson:  # SRP: robust JSON parsing utilities
    @staticmethod
    def loads_strict_or_extract(text: str) -> Any:  # parse JSON or extract JSON substring
        text = (text or "").strip()  # normalize and strip whitespace
        if not text:  # empty output is invalid
            raise JsonParseError("Empty model output; expected JSON.")  # clear failure

        try:  # first try normal strict parsing
            return json.loads(text)  # parse full string
        except Exception:  # if it fails, try to extract JSON object substring
            pass  # continue below

        extracted = SafeJson._extract_first_json(text)  # locate JSON portion
        if extracted is None:  # if no JSON-looking block found
            raise JsonParseError("Model output was not valid JSON and no JSON block was found.")  # fail

        try:  # try parsing extracted block
            return json.loads(extracted)  # parse extracted JSON
        except Exception as e:  # still invalid JSON
            raise JsonParseError(f"Failed to parse extracted JSON block: {e}") from e  # include cause

    @staticmethod
    def _extract_first_json(text: str) -> Optional[str]:  # find first {...} or [...] block
        start_candidates: List[Tuple[int, str]] = []  # candidate starts list
        obj_i = text.find("{")  # find first object
        arr_i = text.find("[")  # find first array
        if obj_i != -1:  # if object exists
            start_candidates.append((obj_i, "{"))  # add candidate
        if arr_i != -1:  # if array exists
            start_candidates.append((arr_i, "["))  # add candidate
        if not start_candidates:  # if nothing found
            return None  # cannot extract

        start_candidates.sort(key=lambda x: x[0])  # choose earliest bracket
        start, opening = start_candidates[0]  # select earliest
        closing = "}" if opening == "{" else "]"  # choose matching closing bracket

        depth = 0  # track nesting depth
        in_string = False  # track if inside quotes
        escape = False  # track escaped characters

        for i in range(start, len(text)):  # scan forward
            ch = text[i]  # current character

            if in_string:  # if inside string
                if escape:  # if previous was backslash
                    escape = False  # consume escape
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


class PdfTextExtractor:  # SRP: only extract text from PDF
    def extract_chunks(self, pdf_path: Path) -> List[PdfChunk]:  # PDF -> list of PdfChunk
        if not pdf_path.exists():  # validate path exists
            raise FileNotFoundError(f"PDF not found: {pdf_path.resolve()}")  # clear error

        reader = PdfReader(str(pdf_path))  # open PDF
        chunks: List[PdfChunk] = []  # allocate output list
        chunk_id = 1  # start chunk id at 1

        for page_index, page in enumerate(reader.pages, start=1):  # loop pages
            text = (page.extract_text() or "").strip()  # extract text and trim
            if not text:  # skip empty pages
                continue  # next page
            chunks.append(PdfChunk(chunk_id=chunk_id, page=page_index, text=text))  # store chunk
            chunk_id += 1  # increment id

        if not chunks:  # if nothing extracted
            raise RuntimeError("No text extracted. PDF may be scanned; OCR would be needed.")  # fail clearly

        return chunks  # return extracted chunks


class CsvSchemaLoader:  # SRP: load schema columns from a reference CSV header
    def load_columns(self, csv_path: str) -> List[str]:  # return header column list
        path = Path(csv_path)  # normalize to Path
        if not path.exists():  # validate template exists
            raise FileNotFoundError(f"Template CSV not found: {path.resolve()}")  # clear error

        with path.open("r", encoding="utf-8") as f:  # open template file
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
        syllabus_text = self._compact_text(chunks, max_chars=8500)  # cap text (speed/cost)
        cols_json = json.dumps(columns, ensure_ascii=True)  # serialize column list

        prompt = (  # build extraction prompt
            "You extract structured fields from syllabus text.\n"  # role
            "Return ONLY valid JSON (no markdown, no commentary).\n"  # strict
            "Output must be a single JSON object mapping column names to values.\n"  # output shape
            "Rules:\n"  # rules header
            "- Use ONLY the provided syllabus text.\n"  # grounding
            "- If a value is not found, use an empty string.\n"  # missing rule
            "- Keep lists as semicolon-separated strings.\n"  # CSV-friendly
            "- For multiline fields, use '\\n' inside the string.\n"  # newline rule
            "- Keys MUST match the given columns EXACTLY.\n"  # strict keys
            "\n"  # spacing
            f"COLUMNS(JSON array of strings): {cols_json}\n"  # provide schema
            "\n"  # spacing
            f"SYLLABUS TEXT:\n{syllabus_text}\n"  # provide syllabus text
        )  # end prompt

        response = self.client.responses.create(  # call OpenAI
            model=self.model,  # model
            input=[{"role": "user", "content": prompt}],  # user prompt
        )  # end call

        raw = (response.output_text or "").strip()  # read output safely
        data = SafeJson.loads_strict_or_extract(raw)  # parse JSON robustly

        if not isinstance(data, dict):  # must be object
            raise ValueError("Extraction failed: output is not a JSON object.")  # fail clearly

        normalized: Dict[str, str] = {}  # final row dict
        for name in columns:  # preserve template order
            value = data.get(name, "")  # get value
            normalized[name] = str(value) if value is not None else ""  # force string

        return normalized  # return row

    def _compact_text(self, chunks: List[PdfChunk], max_chars: int) -> str:  # cap text helper
        joined = "\n\n".join(f"[page {c.page}]\n{c.text}" for c in chunks)  # join pages with tags
        return joined[:max_chars]  # truncate


class CsvFileWriter:  # SRP: write CSV files
    def write_single_row(self, csv_path: Path, row: Dict[str, str]) -> None:  # write header + one row
        csv_path.parent.mkdir(parents=True, exist_ok=True)  # ensure output dir exists
        fieldnames = list(row.keys())  # preserve order
        with csv_path.open("w", newline="", encoding="utf-8") as f:  # open file
            writer = csv.DictWriter(f, fieldnames=fieldnames)  # create writer
            writer.writeheader()  # write header
            writer.writerow(row)  # write row

    def write_chunks(self, csv_path: Path, chunks: List[PdfChunk]) -> None:  # write chunks csv
        csv_path.parent.mkdir(parents=True, exist_ok=True)  # ensure output dir exists
        with csv_path.open("w", newline="", encoding="utf-8") as f:  # open file
            writer = csv.DictWriter(f, fieldnames=["chunk_id", "page", "text"])  # fixed schema
            writer.writeheader()  # header
            for c in chunks:  # loop chunks
                writer.writerow({"chunk_id": c.chunk_id, "page": c.page, "text": c.text})  # write row


class SyllabusConverterService:  # orchestrator: PDF -> values -> CSVs
    def __init__(self, model: str = "gpt-5") -> None:  # configure model
        self.extractor = PdfTextExtractor()  # dependency: PDF extractor
        self.schema_loader = CsvSchemaLoader()  # dependency: template header loader
        self.field_extractor = SyllabusFieldExtractor(model=model)  # dependency: field extractor (1 LLM call)
        self.writer = CsvFileWriter()  # dependency: writer

    def convert(  # main conversion method
        self,
        pdf_path: str,  # input pdf path
        output_dir: str,  # output directory
        template_csv_path: str,  # template csv path (required)
        output_base_name: Optional[str] = None,  # optional base name for outputs
    ) -> ConversionResult:  # returns output paths
        pdf = Path(pdf_path)  # normalize to Path
        if not pdf.exists():  # validate pdf exists early
            raise FileNotFoundError(f"PDF not found: {pdf.resolve()}")  # clear error

        out_dir = Path(output_dir)  # normalize output dir
        out_dir.mkdir(parents=True, exist_ok=True)  # ensure output dir exists

        # ✅ ALWAYS load template columns first (fast + needed for deterministic naming)
        columns = self.schema_loader.load_columns(template_csv_path)  # strict schema from template header

        # ✅ compute hashes BEFORE any heavy work (this enables true cache-hit short-circuit)
        pdf_bytes = pdf.read_bytes()  # read pdf bytes once (needed for hashing + maybe later)
        pdf_hash = hashlib.sha256(pdf_bytes).hexdigest()[:10]  # stable content hash (short)
        header_hash = hashlib.sha256(("|".join(columns)).encode("utf-8")).hexdigest()[:10]  # schema hash

        base = output_base_name.strip() if output_base_name and output_base_name.strip() else pdf.stem  # base name
        prefix = f"{base}.{pdf_hash}.{header_hash}"  # deterministic cache key prefix

        single_row_path = out_dir / f"{prefix}.single_row.csv"  # deterministic single-row path
        chunks_path = out_dir / f"{prefix}.chunks.csv"  # deterministic chunks path

        # ✅ CACHE-HIT SHORT-CIRCUIT: return immediately (NO text extraction, NO OpenAI)
        if single_row_path.exists() and chunks_path.exists():  # if both outputs exist
            return ConversionResult(single_row_csv=str(single_row_path), chunks_csv=str(chunks_path))  # fast return

        # ❗only now do the heavy extraction
        chunks = self.extractor.extract_chunks(pdf)  # extract chunks from PDF (slowish)

        # ❗only now do the LLM call (slowest)
        single_row = self.field_extractor.extract_single_row(chunks, columns)  # ONE OpenAI call

        # ✅ write outputs to deterministic paths
        self.writer.write_single_row(single_row_path, single_row)  # write single-row CSV
        self.writer.write_chunks(chunks_path, chunks)  # write chunks CSV

        return ConversionResult(single_row_csv=str(single_row_path), chunks_csv=str(chunks_path))  # return result


def convert_pdf_to_csvs(  # instructor-required function: takes a file path
    pdf_path: str,  # path to PDF
    output_dir: str = "output",  # output directory
    model: str = "gpt-5",  # OpenAI model
    template_csv_path: str = "templates/default_template.csv",  # reference schema template
    output_base_name: Optional[str] = None,  # optional override base name for outputs
) -> Dict[str, str]:  # return dict of output paths
    service = SyllabusConverterService(model=model)  # create service
    result = service.convert(  # run conversion
        pdf_path=pdf_path,  # pass pdf path
        output_dir=output_dir,  # pass output dir
        template_csv_path=template_csv_path,  # pass template csv path
        output_base_name=output_base_name,  # pass basename override
    )  # end convert
    return {"single_row_csv": result.single_row_csv, "chunks_csv": result.chunks_csv}  # return outputs
