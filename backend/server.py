from __future__ import annotations  # forward references in typing

import re  # regex for stripping (chunk x, page y) markers from answers
import traceback  # print full stack traces on server for debugging
from contextlib import asynccontextmanager  # FastAPI lifespan manager
from dataclasses import dataclass  # config container
from datetime import datetime  # timestamp for saving uploads
from pathlib import Path  # safe path operations
from typing import Optional, Dict  # typing helpers
from urllib.parse import unquote  # decode URL-encoded query strings

from fastapi import FastAPI, HTTPException, UploadFile, File  # FastAPI core
from fastapi.middleware.cors import CORSMiddleware  # CORS for Flutter web
from fastapi.responses import FileResponse, PlainTextResponse  # file/text responses
from pydantic import BaseModel  # request/response models



from ask_syllabus import (  # import Q&A pieces
    SyllabusCsvStore,  # chunks store loader
    LightweightRetriever,  # keyword retriever (fast)
    SyllabusChatGPT,  # OpenAI wrapper (should NOT inject chunk/page into context)
    AskPipeline,  # orchestrator pipeline
)  # end imports

from syllabus_converter import convert_pdf_to_csvs  # PDF->CSVs converter function


@dataclass(frozen=True)  # immutable config class
class AppConfig:  # app config container
    top_k: int = 12  # retrieve top-k chunks
    model: str = "gpt-5"  # model name
    template_csv_path: str = str(  # portable template path
        (Path(__file__).parent / "templates" / "default_template.csv").resolve()
    )  # end template path
    output_dir: str = "output"  # output folder where CSVs are stored
    uploads_dir: str = "uploads"  # uploads folder where PDFs are stored


class ServiceContainer:  # lightweight DI container
    def __init__(self, config: AppConfig) -> None:  # constructor
        self.config = config  # store config

    def build_pipeline(self, chunks_csv_path: Path) -> AskPipeline:  # build pipeline for a chunks CSV
        store = SyllabusCsvStore(str(chunks_csv_path))  # store reads chunks CSV
        retriever = LightweightRetriever(top_k=self.config.top_k)  # retriever uses top_k
        llm = SyllabusChatGPT(model=self.config.model)  # llm uses model
        return AskPipeline(store=store, retriever=retriever, llm=llm)  # build pipeline


class AskFromPathRequest(BaseModel):  # request body for asking from a chunks path
    question: str  # user question
    chunks_csv_path: str  # path to chunks csv returned by /convert-upload


class AnswerResponse(BaseModel):  # response body
    answer: str  # final answer text


class ConvertRequest(BaseModel):  # request body for convert-from-path
    pdf_path: str  # server path to pdf
    template_csv_path: Optional[str] = None  # optional override template


class ConvertResponse(BaseModel):  # conversion response
    single_row_csv: str  # path to generated single-row CSV
    chunks_csv: str  # path to generated chunks CSV


config = AppConfig()  # create app config
container = ServiceContainer(config)  # DI container for services


@asynccontextmanager  # lifespan hook for startup/shutdown
async def lifespan(app: FastAPI):  # lifespan function
    Path(config.output_dir).mkdir(parents=True, exist_ok=True)  # ensure output folder exists
    Path(config.uploads_dir).mkdir(parents=True, exist_ok=True)  # ensure uploads folder exists
    yield  # continue running app


app = FastAPI(title="Syllabus QA Backend", lifespan=lifespan)  # create FastAPI app

app.add_middleware(  # attach middleware
    CORSMiddleware,  # enable CORS
    allow_origins=["*"],  # allow all origins (ok for student project; tighten later)
    allow_credentials=False,  # cookies not needed
    allow_methods=["*"],  # allow all methods
    allow_headers=["*"],  # allow all headers
)  # end CORS middleware


def _safe_csv_path(user_path: str) -> Path:  # validate/normalize CSV paths securely
    decoded = unquote(user_path).strip()  # decode URL encoding and trim
    if not decoded:  # validate not empty
        raise HTTPException(status_code=400, detail="path cannot be empty.")  # bad request

    p = Path(decoded)  # build Path from string
    out_dir = Path(config.output_dir).resolve()  # resolve output dir safely
    resolved = p.resolve()  # resolve requested path to absolute

    try:  # ensure path is inside output directory
        resolved.relative_to(out_dir)  # throws if outside output
    except Exception:  # catch escape attempts
        raise HTTPException(status_code=400, detail="Invalid path: must be inside output folder.")  # reject

    if not resolved.exists():  # ensure file exists
        raise HTTPException(status_code=404, detail="File not found.")  # not found

    if resolved.suffix.lower() != ".csv":  # allow only .csv
        raise HTTPException(status_code=400, detail="Only .csv files are allowed.")  # reject

    return resolved  # return safe resolved path


_CITATION_PATTERNS = [  # patterns to strip chunk/page markers if the model prints them
    re.compile(r"\(\s*chunk\s*\d+\s*,\s*page\s*\d+\s*\)", re.IGNORECASE),  # (chunk 3, page 2)
    re.compile(r"\(\s*chunk\s*\d+\s*\)", re.IGNORECASE),  # (chunk 3)
    re.compile(r"\(\s*page\s*\d+\s*\)", re.IGNORECASE),  # (page 2)
    re.compile(r"\[\s*chunk\s*\d+\s*\|\s*page\s*\d+\s*\]", re.IGNORECASE),  # [chunk 3|page 2]
]  # end patterns list


def _strip_chunk_page_markers(text: str) -> str:  # remove chunk/page hints from answers
    s = (text or "")  # normalize input
    for pat in _CITATION_PATTERNS:  # loop patterns
        s = pat.sub("", s)  # remove matches
    s = re.sub(r"[ \t]+", " ", s)  # normalize spaces
    s = re.sub(r"\n{3,}", "\n\n", s).strip()  # normalize blank lines
    return s  # return cleaned text


@app.get("/csv-text")  # endpoint to view CSV text
def csv_text(path: str) -> PlainTextResponse:  # query param: path
    csv_path = _safe_csv_path(path)  # validate that it's a safe output csv
    text = csv_path.read_text(encoding="utf-8", errors="replace")  # read file safely
    return PlainTextResponse(text)  # return as plain text


@app.get("/csv-download")  # endpoint to download CSV
def csv_download(path: str) -> FileResponse:  # query param: path
    csv_path = _safe_csv_path(path)  # validate safe path
    return FileResponse(  # send file
        path=str(csv_path),  # file path
        media_type="text/csv",  # mime type
        filename=csv_path.name,  # download filename
    )  # end response


@app.post("/convert-from-path", response_model=ConvertResponse)  # convert using server-side PDF path
def convert_from_path(req: ConvertRequest) -> ConvertResponse:  # handler
    pdf_path = req.pdf_path.strip()  # get pdf path
    if not pdf_path:  # validate
        raise HTTPException(status_code=400, detail="pdf_path cannot be empty.")  # bad request

    template_path = (req.template_csv_path or config.template_csv_path)  # pick template path

    try:  # run conversion
        result: Dict[str, str] = convert_pdf_to_csvs(  # call converter
            pdf_path=pdf_path,  # pass pdf path
            output_dir=config.output_dir,  # output folder
            model=config.model,  # model name
            template_csv_path=template_path,  # template header CSV
            output_base_name=Path(pdf_path).stem,  # stable base name
        )  # end conversion call
    except FileNotFoundError as e:  # pdf/template missing
        raise HTTPException(status_code=404, detail=str(e))  # map to 404
    except Exception as e:  # any other failure
        traceback.print_exc()  # print full stack trace for debugging
        raise HTTPException(status_code=500, detail=f"Conversion failed: {e}")  # map to 500

    return ConvertResponse(  # return response model
        single_row_csv=result["single_row_csv"],  # path to single row csv
        chunks_csv=result["chunks_csv"],  # path to chunks csv
    )  # end response


@app.post("/convert-upload", response_model=ConvertResponse)  # upload PDF and convert
async def convert_upload(pdf: UploadFile = File(...)) -> ConvertResponse:  # handler
    if not pdf.filename or not pdf.filename.lower().endswith(".pdf"):  # validate extension
        raise HTTPException(status_code=400, detail="Only PDF files are supported.")  # reject

    pdf_bytes = await pdf.read()  # read uploaded bytes
    if not pdf_bytes:  # validate not empty
        raise HTTPException(status_code=400, detail="Empty PDF uploaded.")  # reject empty upload

    uploads_dir = Path(config.uploads_dir)  # uploads folder Path
    uploads_dir.mkdir(parents=True, exist_ok=True)  # ✅ ensure uploads folder exists

    safe_name = Path(pdf.filename).name  # strip any client path
    original_base = Path(safe_name).stem  # base name for outputs
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")  # stable timestamp
    saved_pdf_path = uploads_dir / f"{timestamp}_{safe_name}"  # final saved path
    saved_pdf_path.write_bytes(pdf_bytes)  # write PDF to disk

    try:  # run conversion
        result: Dict[str, str] = convert_pdf_to_csvs(  # call converter
            pdf_path=str(saved_pdf_path),  # convert from saved PDF
            output_dir=config.output_dir,  # output folder
            model=config.model,  # model name
            template_csv_path=config.template_csv_path,  # template CSV
            output_base_name=original_base,  # base name for outputs
        )  # end conversion call
    except Exception as e:  # conversion failed
        traceback.print_exc()  # print stack trace
        raise HTTPException(status_code=500, detail=f"Conversion failed: {e}")  # return 500

    return ConvertResponse(  # return paths to frontend
        single_row_csv=result["single_row_csv"],  # single row path
        chunks_csv=result["chunks_csv"],  # chunks path
    )  # end response


@app.post("/ask-from-chunks-path", response_model=AnswerResponse)  # answer question using chunks csv path
def ask_from_chunks_path(req: AskFromPathRequest) -> AnswerResponse:  # handler
    question = req.question.strip()  # normalize question
    chunks_csv_path_raw = req.chunks_csv_path.strip()  # normalize chunks path

    if not question:  # validate question
        raise HTTPException(status_code=400, detail="Question cannot be empty.")  # reject
    if not chunks_csv_path_raw:  # validate path
        raise HTTPException(status_code=400, detail="chunks_csv_path cannot be empty.")  # reject

    chunks_csv_path = _safe_csv_path(chunks_csv_path_raw)  # validate the chunks csv is safe

    try:  # run ask pipeline
        pipeline = container.build_pipeline(chunks_csv_path)  # build pipeline
        answer = pipeline.run(question).strip() or "Not found in the syllabus."  # run model
        answer = _strip_chunk_page_markers(answer)  # clean any (chunk/page) markers
    except FileNotFoundError as e:  # file missing
        raise HTTPException(status_code=404, detail=str(e))  # 404
    except ValueError as e:  # validation failure
        raise HTTPException(status_code=400, detail=str(e))  # 400
    except Exception as e:  # unexpected error
        traceback.print_exc()  # print trace
        raise HTTPException(status_code=500, detail=f"Ask failed: {e}")  # 500

    return AnswerResponse(answer=answer)  # return final answer
