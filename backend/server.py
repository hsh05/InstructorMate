from __future__ import annotations  # forward references in typing
import traceback  # add at top with imports

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
    KeywordRetriever,  # keyword retriever
    SyllabusChatGPT,  # OpenAI wrapper
    AskPipeline,  # orchestrator pipeline
)  # end imports

from syllabus_converter import convert_pdf_to_csvs  # PDF->CSVs converter function


@dataclass(frozen=True)  # immutable config class
class AppConfig:  # app config container
    top_k: int = 12  # retrieve top-k chunks
    model: str = "gpt-5"  # model name
    template_csv_path: str = str((Path(__file__).parent / "templates" / "default_template.csv").resolve())  # portable template path
 # your template header file
    output_dir: str = "output"  # output folder where CSVs are stored


class ServiceContainer:  # lightweight DI container
    def __init__(self, config: AppConfig) -> None:  # constructor
        self.config = config  # store config

    def build_pipeline(self, chunks_csv_path: str) -> AskPipeline:  # build pipeline for a chunks CSV
        store = SyllabusCsvStore(chunks_csv_path)  # store reads chunks CSV
        retriever = KeywordRetriever(top_k=self.config.top_k)  # retriever uses top_k
        llm = SyllabusChatGPT(model=self.config.model)  # llm uses model
        return AskPipeline(store=store, retriever=retriever, llm=llm)  # return pipeline


class AskFromPathRequest(BaseModel):  # ask request body
    question: str  # question text
    chunks_csv_path: str  # path to chunks CSV


class AnswerResponse(BaseModel):  # answer response body
    answer: str  # answer text


class ConvertRequest(BaseModel):  # convert-from-path body
    pdf_path: str  # local PDF path
    template_csv_path: Optional[str] = None  # optional template override


class ConvertResponse(BaseModel):  # convert response body
    single_row_csv: str  # output main CSV path
    chunks_csv: str  # output chunks CSV path


config = AppConfig()  # create config instance
container = ServiceContainer(config)  # create DI container


@asynccontextmanager  # lifespan hook
async def lifespan(app: FastAPI):  # lifespan function
    yield  # no startup needed but keeps structure professional


app = FastAPI(title="Syllabus QA Backend", lifespan=lifespan)  # create FastAPI app


app.add_middleware(  # enable CORS for Flutter
    CORSMiddleware,  # middleware type
    allow_origins=["*"],  # dev setting (tighten for production)
    allow_credentials=False,  # must be False if allow_origins is "*"
    allow_methods=["*"],  # allow all methods
    allow_headers=["*"],  # allow all headers
)  # end middleware


def _safe_csv_path(user_path: str) -> Path:  # validate/normalize CSV paths securely
    decoded = unquote(user_path).strip()  # decode URL encoding and trim
    if not decoded:  # validate not empty
        raise HTTPException(status_code=400, detail="path cannot be empty.")  # bad request

    p = Path(decoded)  # build Path from string
    out_dir = Path(config.output_dir).resolve()  # resolve output dir safely
    resolved = p.resolve()  # resolve requested path to absolute

    try:  # ensure path is inside output directory
        resolved.relative_to(out_dir)  # throws ValueError if outside output
    except Exception:  # catch any path escape
        raise HTTPException(status_code=400, detail="Invalid path: must be inside output folder.")  # reject

    if not resolved.exists():  # ensure file exists
        raise HTTPException(status_code=404, detail="File not found.")  # not found

    if resolved.suffix.lower() != ".csv":  # ensure it's a CSV file
        raise HTTPException(status_code=400, detail="Only .csv files are allowed.")  # reject

    return resolved  # return safe resolved path


@app.get("/csv-text")  # return CSV content as plain text (for viewing in UI)
def csv_text(path: str) -> PlainTextResponse:  # query param: ?path=output/xxx.csv
    csv_path = _safe_csv_path(path)  # validate path is safe and exists
    text = csv_path.read_text(encoding="utf-8", errors="replace")  # read CSV as text
    return PlainTextResponse(text)  # return as plain text


@app.get("/csv-download")  # download CSV as an attachment
def csv_download(path: str) -> FileResponse:  # query param: ?path=output/xxx.csv
    csv_path = _safe_csv_path(path)  # validate path is safe and exists
    return FileResponse(  # return file response
        path=str(csv_path),  # file path
        media_type="text/csv",  # CSV mime type
        filename=csv_path.name,  # download filename
    )  # end response


@app.post("/convert-from-path", response_model=ConvertResponse)  # convert local server pdf path to csvs
def convert_from_path(req: ConvertRequest) -> ConvertResponse:  # handler
    pdf_path = req.pdf_path.strip()  # sanitize pdf path
    if not pdf_path:  # validate
        raise HTTPException(status_code=400, detail="pdf_path cannot be empty.")  # bad request

    template_path = (req.template_csv_path or config.template_csv_path)  # choose template

    try:  # protected conversion
        result: Dict[str, str] = convert_pdf_to_csvs(  # call converter
            pdf_path=pdf_path,  # input PDF path
            output_dir=config.output_dir,  # output directory
            model=config.model,  # model name
            template_csv_path=template_path,  # template path
            output_base_name=Path(pdf_path).stem,  # base name = pdf file name
        )  # end call
    except FileNotFoundError as e:  # missing file
        raise HTTPException(status_code=404, detail=str(e))  # 404
    
    except Exception as e:  # conversion errors
        traceback.print_exc()  # prints full error trace to terminal
    raise HTTPException(status_code=500, detail=f"Conversion failed: {e}")  # return detail to Flutter
    
    return ConvertResponse(  # return output paths
        single_row_csv=result["single_row_csv"],  # main csv path
        chunks_csv=result["chunks_csv"],  # chunks csv path
    )  # end response


@app.post("/convert-upload", response_model=ConvertResponse)  # upload pdf -> convert -> return paths
async def convert_upload(pdf: UploadFile = File(...)) -> ConvertResponse:  # handler
    if not pdf.filename or not pdf.filename.lower().endswith(".pdf"):  # validate extension
        raise HTTPException(status_code=400, detail="Only PDF files are supported.")  # error

    pdf_bytes = await pdf.read()  # read bytes from upload
    if not pdf_bytes:  # validate not empty
        raise HTTPException(status_code=400, detail="Empty PDF uploaded.")  # error

    uploads_dir = Path("uploads")  # folder to store uploads
    uploads_dir.mkdir(parents=True, exist_ok=True)  # ensure folder exists

    safe_name = Path(pdf.filename).name  # strip any path parts
    original_base = Path(safe_name).stem  # base name of uploaded file
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")  # timestamp for uniqueness
    saved_pdf_path = uploads_dir / f"{timestamp}_{safe_name}"  # saved PDF path

    saved_pdf_path.write_bytes(pdf_bytes)  # save uploaded pdf to disk

    try:  # protected conversion
        result: Dict[str, str] = convert_pdf_to_csvs(  # call converter
            pdf_path=str(saved_pdf_path),  # saved pdf path
            output_dir=config.output_dir,  # output directory
            model=config.model,  # model
            template_csv_path=config.template_csv_path,  # default template
            output_base_name=original_base,  # IMPORTANT: outputs named like original PDF
        )  # end call
    except Exception as e:  # conversion errors
        raise HTTPException(status_code=500, detail=f"Conversion failed: {e}")  # error

    return ConvertResponse(  # return output paths
        single_row_csv=result["single_row_csv"],  # main csv path
        chunks_csv=result["chunks_csv"],  # chunks csv path
    )  # end response


@app.post("/ask-from-chunks-path", response_model=AnswerResponse)  # ask question using chunks CSV path
def ask_from_chunks_path(req: AskFromPathRequest) -> AnswerResponse:  # handler
    question = req.question.strip()  # sanitize question
    chunks_csv_path = req.chunks_csv_path.strip()  # sanitize chunks path

    if not question:  # validate question not empty
        raise HTTPException(status_code=400, detail="Question cannot be empty.")  # error
    if not chunks_csv_path:  # validate path not empty
        raise HTTPException(status_code=400, detail="chunks_csv_path cannot be empty.")  # error

    try:  # protected run
        pipeline = container.build_pipeline(chunks_csv_path)  # build pipeline
        answer = pipeline.run(question)  # run Q&A
    except FileNotFoundError as e:  # missing chunks csv
        raise HTTPException(status_code=404, detail=str(e))  # 404
    except ValueError as e:  # schema errors
        raise HTTPException(status_code=400, detail=str(e))  # 400
    except Exception as e:  # unknown errors
        raise HTTPException(status_code=500, detail=f"Ask failed: {e}")  # 500

    return AnswerResponse(answer=answer)  # return answer
