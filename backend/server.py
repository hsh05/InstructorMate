from __future__ import annotations

import asyncio
import logging
import re
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, Literal

from fastapi import FastAPI, HTTPException, UploadFile, File, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, PlainTextResponse
from pydantic import BaseModel, Field

from ask_syllabus import (
    SyllabusCsvStore,
    LightweightRetriever,
    SyllabusChatGPT,
    AskPipeline,
)
from syllabus_converter import convert_pdf_to_csvs

logger = logging.getLogger("syllabus_backend")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


@dataclass(frozen=True)
class AppConfig:
    top_k: int = 12
    model: str = "gpt-5"
    template_csv_path: str = str((Path(__file__).parent / "templates" / "default_template.csv").resolve())
    output_dir: str = "output"
    uploads_dir: str = "uploads"
    max_upload_mb: int = 25
    ask_timeout_sec: int = 25


config = AppConfig()


class ServiceContainer:
    def __init__(self, config: AppConfig) -> None:
        self.config = config

    def build_pipeline(self, chunks_csv_path: Path) -> AskPipeline:
        store = SyllabusCsvStore(str(chunks_csv_path))
        retriever = LightweightRetriever(top_k=self.config.top_k, score_threshold=2.0)
        llm = SyllabusChatGPT(model=self.config.model)
        return AskPipeline(store=store, retriever=retriever, llm=llm)


container = ServiceContainer(config)


@asynccontextmanager
async def lifespan(app: FastAPI):
    Path(config.output_dir).mkdir(parents=True, exist_ok=True)
    Path(config.uploads_dir).mkdir(parents=True, exist_ok=True)
    yield


app = FastAPI(title="Syllabus QA Backend", lifespan=lifespan)

# Keeping your current open CORS for now (student project)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


class ConvertResponse(BaseModel):
    doc_id: str
    single_row_name: str
    chunks_name: str


class AskRequest(BaseModel):
    question: str = Field(..., min_length=1)
    doc_id: str = Field(..., min_length=1)


class AnswerResponse(BaseModel):
    answer: str


CsvKind = Literal["single_row", "chunks"]

_DOC_ID_RE = re.compile(r"^[a-zA-Z0-9._-]{5,200}$")

_CITATION_PATTERNS = [
    re.compile(r"\(\s*chunk\s*\d+\s*,\s*page\s*\d+\s*\)", re.IGNORECASE),
    re.compile(r"\(\s*chunk\s*\d+\s*\)", re.IGNORECASE),
    re.compile(r"\(\s*page\s*\d+\s*\)", re.IGNORECASE),
    re.compile(r"\[\s*chunk\s*\d+\s*\|\s*page\s*\d+\s*\]", re.IGNORECASE),
]


def _strip_chunk_page_markers(text: str) -> str:
    s = (text or "")
    for pat in _CITATION_PATTERNS:
        s = pat.sub("", s)
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r"\n{3,}", "\n\n", s).strip()
    return s


def _validate_doc_id(doc_id: str) -> str:
    d = (doc_id or "").strip()
    if not d or not _DOC_ID_RE.match(d):
        raise HTTPException(
            status_code=400,
            detail=f"Invalid doc_id. Must match {_DOC_ID_RE.pattern} (len 5..200). Got: '{d}' (len={len(d)})",
        )
    return d


def _csv_path_from_doc_id(doc_id: str, kind: CsvKind) -> Path:
    out_dir = Path(config.output_dir).resolve()
    filename = f"{doc_id}.single_row.csv" if kind == "single_row" else f"{doc_id}.chunks.csv"
    p = (out_dir / filename).resolve()

    try:
        p.relative_to(out_dir)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid doc_id/path.")

    if not p.exists():
        raise HTTPException(status_code=404, detail="CSV not found. Convert first.")
    return p


@app.middleware("http")
async def add_request_id(request: Request, call_next):
    rid = request.headers.get("x-request-id") or datetime.now().strftime("%Y%m%d%H%M%S%f")
    response = await call_next(request)
    response.headers["x-request-id"] = rid
    return response


@app.post("/convert-upload", response_model=ConvertResponse)
async def convert_upload(pdf: UploadFile = File(...)) -> ConvertResponse:
    if not pdf.filename or not pdf.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF files are supported.")

    pdf_bytes = await pdf.read()
    if not pdf_bytes:
        raise HTTPException(status_code=400, detail="Empty PDF uploaded.")

    max_bytes = config.max_upload_mb * 1024 * 1024
    if len(pdf_bytes) > max_bytes:
        raise HTTPException(status_code=413, detail=f"PDF too large. Limit is {config.max_upload_mb} MB.")

    uploads_dir = Path(config.uploads_dir)
    uploads_dir.mkdir(parents=True, exist_ok=True)

    safe_name = Path(pdf.filename).name
    original_base = Path(safe_name).stem
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    saved_pdf_path = uploads_dir / f"{timestamp}_{safe_name}"
    saved_pdf_path.write_bytes(pdf_bytes)

    try:
        result: Dict[str, str] = convert_pdf_to_csvs(
            pdf_path=str(saved_pdf_path),
            output_dir=config.output_dir,
            model=config.model,
            template_csv_path=config.template_csv_path,
            output_base_name=original_base,
        )
    except Exception as e:
        logger.exception("Conversion failed")
        raise HTTPException(status_code=500, detail=f"Conversion failed: {e}")

    single_row_path = Path(result["single_row_csv"])
    chunks_path = Path(result["chunks_csv"])

    doc_id = single_row_path.name.replace(".single_row.csv", "")
    doc_id = _validate_doc_id(doc_id)

    return ConvertResponse(
        doc_id=doc_id,
        single_row_name=single_row_path.name,
        chunks_name=chunks_path.name,
    )


@app.get("/csv-text")
def csv_text(doc_id: str, kind: CsvKind = "single_row") -> PlainTextResponse:
    doc_id = _validate_doc_id(doc_id)
    csv_path = _csv_path_from_doc_id(doc_id, kind)
    text = csv_path.read_text(encoding="utf-8", errors="replace")
    return PlainTextResponse(text)


@app.get("/csv-download")
def csv_download(doc_id: str, kind: CsvKind = "single_row") -> FileResponse:
    doc_id = _validate_doc_id(doc_id)
    csv_path = _csv_path_from_doc_id(doc_id, kind)
    return FileResponse(
        path=str(csv_path),
        media_type="text/csv",
        filename=csv_path.name,
    )


@app.post("/ask", response_model=AnswerResponse)
async def ask(req: AskRequest) -> AnswerResponse:
    question = req.question.strip()
    doc_id = _validate_doc_id(req.doc_id)
    chunks_csv_path = _csv_path_from_doc_id(doc_id, "chunks")

    try:
        pipeline = container.build_pipeline(chunks_csv_path)

        loop = asyncio.get_running_loop()
        answer = await asyncio.wait_for(
            loop.run_in_executor(None, pipeline.run, question),
            timeout=config.ask_timeout_sec,
        )

        answer = (answer or "").strip() or "Not found in the syllabus."
        answer = _strip_chunk_page_markers(answer)

    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail=f"Ask timed out after {config.ask_timeout_sec}s.")
    except Exception as e:
        logger.exception("Ask failed")
        raise HTTPException(status_code=500, detail=f"Ask failed: {e}")

    return AnswerResponse(answer=answer)
