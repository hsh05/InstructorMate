from __future__ import annotations  # enable forward references in type hints

import csv  # read/write CSV files
import json  # parse model outputs (JSON)
import re  # validate snake_case column names
from dataclasses import dataclass  # lightweight immutable data structures
from pathlib import Path  # safe path operations
from typing import Dict, List, Optional, Any  # typing helpers

from pypdf import PdfReader  # PDF text extraction library
from openai import OpenAI  # OpenAI client


@dataclass(frozen=True)  # make instances immutable
class PdfChunk:  # represent one extracted chunk from the PDF
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
        chunks: List[PdfChunk] = []  # allocate list
        chunk_id = 1  # start chunk id at 1

        for page_index, page in enumerate(reader.pages, start=1):  # loop pages 1-based
            text = (page.extract_text() or "").strip()  # extract text and trim whitespace
            if not text:  # if page has no text
                continue  # skip it
            chunks.append(PdfChunk(chunk_id=chunk_id, page=page_index, text=text))  # store chunk
            chunk_id += 1  # increment id

        if not chunks:  # if nothing extracted
            raise RuntimeError("No text extracted. PDF may be scanned; OCR would be needed.")  # fail clearly

        return chunks  # return chunks list


class CsvSchemaLoader:  # SRP: load schema columns from a reference CSV header
    def load_columns(self, csv_path: str) -> List[str]:  # return header column list
        path = Path(csv_path)  # normalize to Path
        if not path.exists():  # validate template exists
            raise FileNotFoundError(f"Template CSV not found: {path.resolve()}")  # clear error

        with path.open("r", encoding="utf-8") as f:  # open template file
            reader = csv.reader(f)  # build CSV reader
            header = next(reader, None)  # read first row

        if not header:  # if header missing
            raise ValueError("Template CSV has no header row.")  # fail clearly

        return [h.strip() for h in header if h and h.strip()]  # return trimmed header names


class SchemaPromptBuilder:  # SRP: build prompts for schema inference
    def build_reference_aware_prompt(self, syllabus_text: str, reference_columns: List[str]) -> str:  # build prompt
        ref_cols = ", ".join(reference_columns)  # join reference columns for readability

        return (  # return full prompt text
            "You are a syllabus schema designer.\n"  # role
            "\n"  # spacing
            "You will receive:\n"  # intro
            "(A) REQUIRED columns from a reference CSV template (must be preserved exactly)\n"  # requirement
            "(B) Syllabus text\n"  # syllabus content
            "\n"  # spacing
            "Goal:\n"  # goal header
            "Create a SINGLE-ROW CSV schema for this syllabus.\n"  # goal
            "\n"  # spacing
            "Rules:\n"  # rules header
            "1) You MUST include every REQUIRED column exactly (same spelling, same snake_case).\n"  # must keep
            "2) You MAY add extra columns ONLY if the syllabus clearly contains that info in a structured way.\n"  # allow extras
            "3) Do NOT rename or remove REQUIRED columns.\n"  # forbid rename/remove
            "4) Do NOT invent information that is not present.\n"  # no hallucination
            "5) Column names must be snake_case ASCII: [a-z0-9_], no spaces.\n"  # naming rule
            "6) Prefer 12–35 total columns.\n"  # size guidance
            "7) Output ONLY valid JSON, no markdown, no explanation.\n"  # strict output
            "\n"  # spacing
            "JSON format:\n"  # format header
            '{\n  "columns": [\n    {"name": "col_name", "description": "what goes here", "expected_type": "string|number|list|string_multiline"}\n  ]\n}\n'  # JSON shape
            "\n"  # spacing
            f"REQUIRED COLUMNS:\n{ref_cols}\n"  # insert required columns
            "\n"  # spacing
            f"SYLLABUS TEXT:\n{syllabus_text}\n"  # insert syllabus text
        )  # end prompt


class SyllabusSchemaInferer:  # SRP: infer schema columns using OpenAI
    def __init__(self, model: str = "gpt-5") -> None:  # configure model
        self.client = OpenAI()  # create OpenAI client
        self.model = model  # store model
        self.schema_loader = CsvSchemaLoader()  # dependency: template loader
        self.prompt_builder = SchemaPromptBuilder()  # dependency: prompt builder

    def infer_columns(self, chunks: List[PdfChunk], template_csv_path: Optional[str]) -> List[Dict[str, str]]:  # infer schema
        syllabus_text = self._compact_text(chunks, max_chars=12000)  # shrink text for token efficiency

        reference_columns: List[str] = []  # default: none
        if template_csv_path:  # if template provided
            reference_columns = self.schema_loader.load_columns(template_csv_path)  # load required columns

        if not reference_columns:  # if no reference columns
            raise ValueError("template_csv_path is required to enforce consistent column names.")  # enforce template usage

        prompt = self.prompt_builder.build_reference_aware_prompt(syllabus_text, reference_columns)  # build prompt

        response = self.client.responses.create(  # call OpenAI
            model=self.model,  # model
            input=[{"role": "user", "content": prompt}],  # user prompt
        )  # end call

        raw = response.output_text.strip()  # get output text
        data = json.loads(raw)  # parse JSON strictly
        columns = data.get("columns", [])  # read columns list

        if not isinstance(columns, list) or not columns:  # validate list exists
            raise ValueError("Schema inference failed: 'columns' missing or empty.")  # fail clearly

        self._validate_columns(columns)  # validate snake_case names
        final_columns = self._ensure_reference_columns(columns, reference_columns)  # enforce required columns
        return final_columns  # return enforced schema

    def _compact_text(self, chunks: List[PdfChunk], max_chars: int) -> str:  # cap text
        joined = "\n\n".join(f"[page {c.page}]\n{c.text}" for c in chunks)  # join with page tags
        return joined[:max_chars]  # truncate
    
    def _normalize_name(self, name: str) -> str:
    # Convert to snake_case
        name = name.strip().lower()
        name = re.sub(r"[^a-z0-9]+", "_", name)  # replace non-alnum with _
        name = re.sub(r"_+", "_", name)  # collapse multiple _
        return name.strip("_")

    def _validate_columns(self, columns: List[Dict[str, Any]]) -> None:
       for col in columns:
        raw_name = str(col.get("name", "")).strip()
        normalized = self._normalize_name(raw_name)

        if not normalized:
            raise ValueError(f"Invalid column name after normalization: {raw_name}")

        col["name"] = normalized  # ✅ overwrite with safe name

    def _ensure_reference_columns(self, columns: List[Dict[str, Any]], reference_columns: List[str]) -> List[Dict[str, str]]:  # enforce required cols
        model_map: Dict[str, Dict[str, str]] = {}  # map name -> spec

        for c in columns:  # read model columns
            name = str(c.get("name", "")).strip()  # normalize name
            model_map[name] = {  # store normalized spec
                "name": name,  # name
                "description": str(c.get("description", "")).strip(),  # description
                "expected_type": str(c.get("expected_type", "string")).strip(),  # expected type
            }  # end dict

        final_cols: List[Dict[str, str]] = []  # final ordered list

        for ref_name in reference_columns:  # enforce each required column
            if ref_name in model_map:  # if model included it
                final_cols.append(model_map.pop(ref_name))  # take model’s spec
            else:  # if model missed it
                final_cols.append({  # create safe fallback
                    "name": ref_name,  # exact name
                    "description": "Required column preserved from template.",  # generic description
                    "expected_type": "string",  # safe default
                })  # add it

        for _, spec in model_map.items():  # append extras (only if model produced them)
            final_cols.append(spec)  # append extra

        return final_cols  # return final schema


class SyllabusFieldExtractor:  # SRP: extract values given a schema (single-row)
    def __init__(self, model: str = "gpt-5") -> None:  # configure model
        self.client = OpenAI()  # OpenAI client
        self.model = model  # model name

    def extract_single_row(self, chunks: List[PdfChunk], columns: List[Dict[str, str]]) -> Dict[str, str]:  # extract row
        syllabus_text = self._compact_text(chunks, max_chars=14000)  # cap text
        col_spec = json.dumps(columns, ensure_ascii=True)  # serialize schema

        prompt = (  # build extraction prompt
            "You extract structured fields from syllabus text.\n"  # role
            "Return ONLY valid JSON (no markdown, no commentary).\n"  # strict
            "Output must be a single JSON object mapping column names to values.\n"  # output shape
            "Rules:\n"  # rules header
            "- Use ONLY the provided syllabus text.\n"  # grounding
            "- If a value is not found, use an empty string.\n"  # missing rule
            "- Keep lists as semicolon-separated strings.\n"  # CSV-friendly
            "- For multiline fields, use '\\n' inside the string.\n"  # newline rule
            "\n"  # spacing
            f"COLUMNS(JSON): {col_spec}\n"  # provide schema
            "\n"  # spacing
            f"SYLLABUS TEXT:\n{syllabus_text}\n"  # provide syllabus text
        )  # end prompt

        response = self.client.responses.create(  # call OpenAI
            model=self.model,  # model
            input=[{"role": "user", "content": prompt}],  # prompt
        )  # end call

        raw = response.output_text.strip()  # read output
        data = json.loads(raw)  # parse JSON

        if not isinstance(data, dict):  # validate output
            raise ValueError("Extraction failed: output is not a JSON object.")  # fail clearly

        normalized: Dict[str, str] = {}  # final row dict
        for col in columns:  # preserve schema order
            name = str(col["name"])  # read column name
            value = data.get(name, "")  # get extracted value
            normalized[name] = str(value) if value is not None else ""  # force string

        return normalized  # return row

    def _compact_text(self, chunks: List[PdfChunk], max_chars: int) -> str:  # cap text
        joined = "\n\n".join(f"[page {c.page}]\n{c.text}" for c in chunks)  # join pages
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


class SyllabusConverterService:  # orchestrator: PDF -> schema -> values -> CSVs
    def __init__(self, model: str = "gpt-5") -> None:  # configure model
        self.extractor = PdfTextExtractor()  # dependency: PDF extractor
        self.schema_inferer = SyllabusSchemaInferer(model=model)  # dependency: schema inferer
        self.field_extractor = SyllabusFieldExtractor(model=model)  # dependency: field extractor
        self.writer = CsvFileWriter()  # dependency: writer

    def convert(  # main conversion method
        self,
        pdf_path: str,  # input pdf path
        output_dir: str,  # output directory
        template_csv_path: str,  # template csv path (required)
        output_base_name: Optional[str] = None,  # optional override base name for output files
    ) -> ConversionResult:  # returns output paths
        pdf = Path(pdf_path)  # normalize to Path
        chunks = self.extractor.extract_chunks(pdf)  # extract chunks
        columns = self.schema_inferer.infer_columns(chunks, template_csv_path=template_csv_path)  # infer schema
        single_row = self.field_extractor.extract_single_row(chunks, columns)  # extract single-row values

        base = output_base_name.strip() if output_base_name and output_base_name.strip() else pdf.stem  # choose base name
        out_dir = Path(output_dir)  # normalize output dir
        single_row_path = out_dir / f"{base}.single_row.csv"  # name single-row file
        chunks_path = out_dir / f"{base}.chunks.csv"  # name chunks file

        self.writer.write_single_row(single_row_path, single_row)  # write single-row CSV
        self.writer.write_chunks(chunks_path, chunks)  # write chunks CSV

        return ConversionResult(single_row_csv=str(single_row_path), chunks_csv=str(chunks_path))  # return result


def convert_pdf_to_csvs(  # instructor-required function: takes a file path
    pdf_path: str,  # path to PDF
    output_dir: str = "output",  # output directory
    model: str = "gpt-5",  # OpenAI model
    template_csv_path: str = "OOP_0102221_Syllabus_SingleRow.csv",  # reference schema template
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
