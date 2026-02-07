from __future__ import annotations  # allow forward references in type hints

import csv  # read/write CSV files
import json  # parse model outputs (JSON)
import re  # validate snake_case column names
from dataclasses import dataclass  # lightweight immutable data structures
from pathlib import Path  # safe path operations
from typing import Dict, List, Optional, Any  # typing helpers

from pypdf import PdfReader  # PDF text extraction library
from openai import OpenAI  # OpenAI client


@dataclass(frozen=True)  # make instances immutable
class PdfChunk:  # represent one extracted chunk (page) from the PDF
    chunk_id: int  # unique chunk id (1..N)
    page: int  # page number (1..N)
    text: str  # extracted text for that page


@dataclass(frozen=True)  # make instances immutable
class ConversionResult:  # represent final conversion file paths
    single_row_csv: str  # output path to single-row summary CSV
    chunks_csv: str  # output path to chunks CSV used for Q&A


class PdfTextExtractor:  # SRP: only extract text from PDF
    def extract_chunks(self, pdf_path: Path) -> List[PdfChunk]:  # convert PDF to list of PdfChunk
        if not pdf_path.exists():  # validate path exists
            raise FileNotFoundError(f"PDF not found: {pdf_path.resolve()}")  # raise clear error

        reader = PdfReader(str(pdf_path))  # open PDF reader
        chunks: List[PdfChunk] = []  # create output list
        chunk_id = 1  # start chunk id from 1

        for page_index, page in enumerate(reader.pages, start=1):  # loop pages, 1-based
            text = (page.extract_text() or "").strip()  # extract text and trim whitespace
            if not text:  # if page has no text
                continue  # skip it
            chunks.append(PdfChunk(chunk_id=chunk_id, page=page_index, text=text))  # store chunk
            chunk_id += 1  # increment chunk id

        if not chunks:  # if nothing extracted
            raise RuntimeError("No text extracted. PDF might be scanned; OCR would be needed.")  # fail clearly

        return chunks  # return extracted chunks


class CsvSchemaLoader:  # SRP: load schema columns from a reference CSV header
    def load_columns(self, csv_path: str) -> List[str]:  # return header column list
        path = Path(csv_path)  # normalize to Path
        if not path.exists():  # validate reference csv exists
            raise FileNotFoundError(f"Template CSV not found: {path.resolve()}")  # clear error

        with path.open("r", encoding="utf-8") as f:  # open reference CSV safely
            reader = csv.reader(f)  # build CSV reader
            header = next(reader, None)  # read first row header

        if not header:  # if header missing
            raise ValueError("Template CSV has no header row.")  # fail clearly

        return [h.strip() for h in header if h.strip()]  # return trimmed non-empty headers


class SchemaPromptBuilder:  # SRP: build prompts for schema inference
    def build_reference_aware_prompt(self, syllabus_text: str, reference_columns: List[str]) -> str:  # build prompt string
        ref_cols = ", ".join(reference_columns)  # join reference columns for readability
        return (  # return full prompt
            "You are a data-extraction architect.\n"  # role
            "\n"  # spacing
            "You are given:\n"  # intro
            "1) A list of REQUIRED column names from a reference CSV\n"  # reference
            "2) The syllabus text\n"  # text
            "\n"  # spacing
            "Your job:\n"  # task
            "- Preserve ALL reference columns exactly as given\n"  # keep columns
            "- Add new columns ONLY if the syllabus clearly contains structured information\n"  # allow extra
            "- Do NOT rename reference columns\n"  # rule
            "- Do NOT remove reference columns\n"  # rule
            "\n"  # spacing
            "Rules:\n"  # rules header
            "1) Output ONLY valid JSON (no markdown, no commentary).\n"  # strict JSON
            "2) JSON shape:\n"  # structure rule
            '   {"columns": [{"name": "...", "description": "...", "expected_type": "string|number|list|string_multiline"}]}\n'  # schema
            "3) Column names must be snake_case ASCII (a-z, 0-9, _).\n"  # naming constraints
            "4) Prefer 12–35 columns total.\n"  # size target
            "5) Do NOT invent information.\n"  # no hallucination
            "\n"  # spacing
            f"REFERENCE COLUMNS:\n{ref_cols}\n"  # insert reference columns
            "\n"  # spacing
            f"SYLLABUS TEXT:\n{syllabus_text}\n"  # insert syllabus text
        )  # end prompt

    def build_free_prompt(self, syllabus_text: str) -> str:  # fallback prompt if no reference CSV provided
        return (  # return full prompt
            "You are a data-extraction architect.\n"  # role
            "\n"  # spacing
            "Given the syllabus text below, design a CSV schema for a SINGLE-ROW summary table.\n"  # task
            "\n"  # spacing
            "Rules:\n"  # rules header
            "1) Output ONLY valid JSON (no markdown, no commentary).\n"  # strict output
            "2) JSON must follow this shape:\n"  # structure
            '   {"columns": [{"name": "...", "description": "...", "expected_type": "string|number|list|string_multiline"}]}\n'  # schema
            "3) Column names must be snake_case ASCII, no spaces.\n"  # naming
            "4) Include ONLY columns supported by typical syllabi. Do not invent.\n"  # grounded schema
            "5) Prefer 12–30 columns.\n"  # size target
            "\n"  # spacing
            f"SYLLABUS TEXT:\n{syllabus_text}\n"  # insert text
        )  # end prompt


class SyllabusSchemaInferer:  # SRP: infer schema columns using OpenAI
    def __init__(self, model: str = "gpt-5") -> None:  # configure model
        self.client = OpenAI()  # create OpenAI client
        self.model = model  # store model name
        self.schema_loader = CsvSchemaLoader()  # dependency to load reference schema
        self.prompt_builder = SchemaPromptBuilder()  # dependency to build prompts

    def infer_columns(self, chunks: List[PdfChunk], template_csv_path: Optional[str] = None) -> List[Dict[str, str]]:  # infer columns
        syllabus_text = self._compact_text(chunks, max_chars=12000)  # reduce tokens for schema inference

        reference_columns: List[str] = []  # default empty list
        if template_csv_path:  # if template path provided
            reference_columns = self.schema_loader.load_columns(template_csv_path)  # load reference columns

        if reference_columns:  # if we have a reference schema
            prompt = self.prompt_builder.build_reference_aware_prompt(syllabus_text, reference_columns)  # build ref-aware prompt
        else:  # otherwise
            prompt = self.prompt_builder.build_free_prompt(syllabus_text)  # build fallback prompt

        response = self.client.responses.create(  # call OpenAI
            model=self.model,  # model name
            input=[{"role": "user", "content": prompt}],  # prompt as user message
        )  # end API call

        raw = response.output_text.strip()  # get output text
        data = json.loads(raw)  # parse JSON strictly
        columns = data.get("columns", [])  # read columns list
        if not isinstance(columns, list) or not columns:  # validate columns exist
            raise ValueError("Schema inference failed: 'columns' missing or empty.")  # fail clearly

        self._validate_columns(columns)  # validate column names
        columns = self._ensure_reference_first(columns, reference_columns)  # enforce reference columns present
        return columns  # return final schema

    def _compact_text(self, chunks: List[PdfChunk], max_chars: int) -> str:  # helper to cap text length
        joined = "\n\n".join(f"[page {c.page}]\n{c.text}" for c in chunks)  # join chunks with page tags
        return joined[:max_chars]  # truncate to limit tokens

    def _validate_columns(self, columns: List[Dict[str, Any]]) -> None:  # validate schema format
        for col in columns:  # loop each column dict
            name = str(col.get("name", "")).strip()  # read name safely
            if not re.fullmatch(r"[a-z0-9_]+", name):  # enforce snake_case ASCII
                raise ValueError(f"Bad column name from model: {name}")  # fail clearly

    def _ensure_reference_first(self, columns: List[Dict[str, Any]], reference_columns: List[str]) -> List[Dict[str, str]]:  # enforce ref columns
        if not reference_columns:  # if no reference schema
            return columns  # return as-is

        col_map: Dict[str, Dict[str, str]] = {}  # map name -> column dict
        for c in columns:  # build mapping from model output
            name = str(c.get("name", "")).strip()  # read column name
            col_map[name] = {  # store normalized dict
                "name": name,  # keep name
                "description": str(c.get("description", "")).strip(),  # keep description
                "expected_type": str(c.get("expected_type", "string")).strip(),  # keep expected type
            }  # end dict

        final_cols: List[Dict[str, str]] = []  # final ordered list

        for ref_name in reference_columns:  # loop reference columns
            if ref_name in col_map:  # if model included it
                final_cols.append(col_map.pop(ref_name))  # take model version
            else:  # if model missed it
                final_cols.append({  # create minimal column spec
                    "name": ref_name,  # exact reference name
                    "description": "Reference column preserved from template.",  # generic description
                    "expected_type": "string",  # safe default type
                })  # add preserved reference column

        for name, spec in col_map.items():  # add remaining extra columns from model
            final_cols.append(spec)  # append extras

        return final_cols  # return merged schema


class SyllabusFieldExtractor:  # SRP: extract values given a schema (single-row)
    def __init__(self, model: str = "gpt-5") -> None:  # configure model
        self.client = OpenAI()  # create OpenAI client
        self.model = model  # store model name

    def extract_single_row(self, chunks: List[PdfChunk], columns: List[Dict[str, str]]) -> Dict[str, str]:  # extract values for schema
        syllabus_text = self._compact_text(chunks, max_chars=14000)  # cap text for extraction
        col_spec = json.dumps(columns, ensure_ascii=True)  # serialize schema into JSON string

        prompt = (  # build extraction prompt
            "You extract structured fields from syllabus text.\n"  # role
            "Return ONLY valid JSON (no markdown, no commentary).\n"  # strict JSON
            "Output must be a single JSON object mapping column names to values.\n"  # output shape
            "Rules:\n"  # rules header
            "- Use ONLY the provided syllabus text.\n"  # grounding
            "- If a value is not found, use an empty string.\n"  # missing policy
            "- Keep lists as semicolon-separated strings.\n"  # CSV-friendly lists
            "- For multiline fields, use '\\n' inside the string.\n"  # newline policy
            "\n"  # spacing
            f"COLUMNS(JSON): {col_spec}\n"  # provide schema
            "\n"  # spacing
            f"SYLLABUS TEXT:\n{syllabus_text}\n"  # provide syllabus text
        )  # end prompt

        response = self.client.responses.create(  # call OpenAI
            model=self.model,  # model
            input=[{"role": "user", "content": prompt}],  # prompt
        )  # end call

        raw = response.output_text.strip()  # read model output
        data = json.loads(raw)  # parse JSON
        if not isinstance(data, dict):  # validate dict output
            raise ValueError("Extraction failed: output is not a JSON object.")  # fail clearly

        normalized: Dict[str, str] = {}  # final normalized mapping
        for col in columns:  # iterate schema columns
            name = str(col["name"])  # column name
            value = data.get(name, "")  # extracted value or empty
            normalized[name] = str(value) if value is not None else ""  # force string value

        return normalized  # return the row dict

    def _compact_text(self, chunks: List[PdfChunk], max_chars: int) -> str:  # helper to cap text
        joined = "\n\n".join(f"[page {c.page}]\n{c.text}" for c in chunks)  # join with page tags
        return joined[:max_chars]  # truncate


class CsvFileWriter:  # SRP: write CSV files
    def write_single_row(self, csv_path: Path, row: Dict[str, str]) -> None:  # write header + 1 row
        csv_path.parent.mkdir(parents=True, exist_ok=True)  # create output folder if missing
        fieldnames = list(row.keys())  # preserve schema order
        with csv_path.open("w", newline="", encoding="utf-8") as f:  # open file
            writer = csv.DictWriter(f, fieldnames=fieldnames)  # create dict writer
            writer.writeheader()  # write header
            writer.writerow(row)  # write one row

    def write_chunks(self, csv_path: Path, chunks: List[PdfChunk]) -> None:  # write chunk_id/page/text rows
        csv_path.parent.mkdir(parents=True, exist_ok=True)  # ensure output folder exists
        with csv_path.open("w", newline="", encoding="utf-8") as f:  # open file
            writer = csv.DictWriter(f, fieldnames=["chunk_id", "page", "text"])  # fixed schema
            writer.writeheader()  # write header
            for c in chunks:  # loop chunks
                writer.writerow({"chunk_id": c.chunk_id, "page": c.page, "text": c.text})  # write row


class SyllabusConverterService:  # orchestrator: PDF -> schema -> values -> CSVs
    def __init__(self, model: str = "gpt-5") -> None:  # accept model
        self.extractor = PdfTextExtractor()  # dependency: PDF extractor
        self.schema_inferer = SyllabusSchemaInferer(model=model)  # dependency: schema inferer
        self.field_extractor = SyllabusFieldExtractor(model=model)  # dependency: value extractor
        self.writer = CsvFileWriter()  # dependency: CSV writer

    def convert(self, pdf_path: str, output_dir: str = "output", template_csv_path: Optional[str] = None) -> ConversionResult:  # main path method
        pdf = Path(pdf_path)  # normalize path
        chunks = self.extractor.extract_chunks(pdf)  # extract chunks from PDF
        columns = self.schema_inferer.infer_columns(chunks, template_csv_path=template_csv_path)  # infer schema
        single_row = self.field_extractor.extract_single_row(chunks, columns)  # extract values into dict

        base = pdf.stem  # get pdf base name (no extension)
        out_dir = Path(output_dir)  # normalize output dir
        single_row_path = out_dir / f"{base}.single_row.csv"  # name single-row csv using pdf name
        chunks_path = out_dir / f"{base}.chunks.csv"  # name chunks csv using pdf name

        self.writer.write_single_row(single_row_path, single_row)  # write single-row csv
        self.writer.write_chunks(chunks_path, chunks)  # write chunks csv

        return ConversionResult(single_row_csv=str(single_row_path), chunks_csv=str(chunks_path))  # return paths


def convert_pdf_to_csvs(  # function wrapper for instructor requirement (method that takes file path)
    pdf_path: str,  # PDF file path
    output_dir: str = "output",  # where to save csv
    model: str = "gpt-5",  # OpenAI model
    template_csv_path: Optional[str] = None,  # optional reference csv path
) -> Dict[str, str]:  # return output paths as dict
    service = SyllabusConverterService(model=model)  # build service
    result = service.convert(pdf_path=pdf_path, output_dir=output_dir, template_csv_path=template_csv_path)  # run conversion
    return {"single_row_csv": result.single_row_csv, "chunks_csv": result.chunks_csv}  # return outputs
