from __future__ import annotations  # forward typing support

from contextlib import asynccontextmanager  # FastAPI lifespan
from dataclasses import dataclass  # config class
from io import BytesIO  # in-memory bytes stream for PDF reading
from pathlib import Path  # safe path operations
from typing import Optional, List, Dict  # typing helpers

from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form  # FastAPI primitives
from fastapi.middleware.cors import CORSMiddleware  # CORS
from pydantic import BaseModel  # request/response models
from pypdf import PdfReader  # parse uploaded PDF bytes

from ask_syllabus import (  # import Q&A components
    SyllabusCsvStore,  # loads chunks CSV
    KeywordRetriever,  # keyword retrieval
    SyllabusChatGPT,  # OpenAI wrapper
    AskPipeline,  # orchestrator
    CsvChunk,  # chunk model
)

from syllabus_converter import convert_pdf_to_csvs  # converter (PDF path -> CSV paths)


@dataclass(frozen=True)  # immutable config container
class AppConfig:  # configuration values
    top_k: int = 12  # retrieval top-k
    model: str = "gpt-5"  # OpenAI model
    template_csv_path: str = "OOP_0102221_Syllabus_SingleRow.csv"  # reference schema template path


class ServiceContainer:  # DI container (keeps shared settings)
    def __init__(self, config: AppConfig) -> None:  # constructor
        self.config = config  # store config

    def build_pipeline(self, chunks_csv_path: str) -> AskPipeline:  # build pipeline for a specific chunks file
        store = SyllabusCsvStore(chunks_csv_path)  # store loads the chosen chunks csv
        retriever = KeywordRetriever(top_k=self.config.top_k)  # retriever uses config top_k
        llm = SyllabusChatGPT(model=self.config.model)  # llm uses config model
        return AskPipeline(store=store, retriever=retriever, llm=llm)  # return pipeline


class QuestionRequest(BaseModel):  # request body for ask endpoints
    question: str  # question text


class AskFromPathRequest(BaseModel):  # request body to ask using a chosen chunks csv
    question: str  # question text
    chunks_csv_path: str  # path to chunks csv


class AnswerResponse(BaseModel):  # response body
    answer: str  # answer text


class ConvertRequest(BaseModel):  # request body for convert-from-path
    pdf_path: str  # local pdf path string
    template_csv_path: Optional[str] = None  # optional override reference template path


class ConvertResponse(BaseModel):  # response body for convert-from-path
    single_row_csv: str  # output single-row csv path
    chunks_csv: str  # output chunks csv path


config = AppConfig()  # create config instance
container = ServiceContainer(config)  # create DI container


@asynccontextmanager  # lifespan hook
async def lifespan(app: FastAPI):  # lifespan function
    yield  # nothing to initialize, but keeps structure professional


app = FastAPI(title="Syllabus QA Backend", lifespan=lifespan)  # create FastAPI app


app.add_middleware(  # enable CORS for Flutter web dev
    CORSMiddleware,  # middleware type
    allow_origins=["*"],  # allow all origins for development
    allow_credentials=False,  # must be False when allow_origins is "*"
    allow_methods=["*"],  # allow all HTTP methods
    allow_headers=["*"],  # allow all headers
)


def pdf_to_chunks(pdf_bytes: bytes) -> List[CsvChunk]:  # convert in-memory pdf bytes into chunks (for ask-with-pdf)
    reader = PdfReader(BytesIO(pdf_bytes))  # open pdf from memory
    chunks: List[CsvChunk] = []  # allocate list
    chunk_id = 1  # init chunk id
    for page_index, page in enumerate(reader.pages, start=1):  # loop pages
        text = (page.extract_text() or "").strip()  # extract text
        if not text:  # skip empty text
            continue  # next
        chunks.append(CsvChunk(chunk_id=chunk_id, page=page_index, text=text))  # append chunk
        chunk_id += 1  # increment id
    return chunks  # return chunks list


@app.post("/convert-from-path", response_model=ConvertResponse)  # convert PDF path -> output csv paths
def convert_from_path(req: ConvertRequest) -> ConvertResponse:  # endpoint handler
    pdf_path = req.pdf_path.strip()  # sanitize
    if not pdf_path:  # validate not empty
        raise HTTPException(status_code=400, detail="pdf_path cannot be empty.")  # bad request

    template_path = (req.template_csv_path or config.template_csv_path)  # choose override or default template

    try:  # protected conversion
        result: Dict[str, str] = convert_pdf_to_csvs(  # call converter
            pdf_path=pdf_path,  # pass pdf path
            output_dir="output",  # write to output folder
            model=config.model,  # use model from config
            template_csv_path=template_path,  # reference schema template path
        )  # end conversion call
    except FileNotFoundError as e:  # file not found
        raise HTTPException(status_code=404, detail=str(e))  # map to 404
    except Exception as e:  # any other conversion error
        raise HTTPException(status_code=500, detail=f"Conversion failed: {e}")  # map to 500

    return ConvertResponse(  # return output paths
        single_row_csv=result["single_row_csv"],  # single-row CSV path
        chunks_csv=result["chunks_csv"],  # chunks CSV path
    )  # end response


@app.post("/ask-from-chunks-path", response_model=AnswerResponse)  # ask using a chosen chunks csv
def ask_from_chunks_path(req: AskFromPathRequest) -> AnswerResponse:  # endpoint handler
    question = req.question.strip()  # sanitize question
    chunks_csv_path = req.chunks_csv_path.strip()  # sanitize path

    if not question:  # validate question
        raise HTTPException(status_code=400, detail="Question cannot be empty.")  # bad request
    if not chunks_csv_path:  # validate path
        raise HTTPException(status_code=400, detail="chunks_csv_path cannot be empty.")  # bad request

    try:  # protected pipeline build/run
        pipeline = container.build_pipeline(chunks_csv_path)  # build pipeline for that file
        answer = pipeline.run(question)  # run Q&A
    except FileNotFoundError as e:  # chunks csv missing
        raise HTTPException(status_code=404, detail=str(e))  # map to 404
    except ValueError as e:  # CSV schema wrong
        raise HTTPException(status_code=400, detail=str(e))  # map to 400
    except Exception as e:  # unknown errors
        raise HTTPException(status_code=500, detail=f"Ask failed: {e}")  # map to 500

    return AnswerResponse(answer=answer)  # return response


import os  # file ops
from datetime import datetime  # timestamp for unique saved file names


@app.post("/convert-upload", response_model=ConvertResponse)  # upload pdf -> create CSVs -> return paths
async def convert_upload(pdf: UploadFile = File(...)) -> ConvertResponse:  # accept uploaded pdf file
    if not pdf.filename.lower().endswith(".pdf"):  # validate file extension
        raise HTTPException(status_code=400, detail="Only PDF files are supported.")  # error response

    pdf_bytes = await pdf.read()  # read uploaded file into bytes
    if not pdf_bytes:  # validate not empty
        raise HTTPException(status_code=400, detail="Empty PDF uploaded.")  # error response

    uploads_dir = Path("uploads")  # directory to store uploaded PDFs
    uploads_dir.mkdir(parents=True, exist_ok=True)  # ensure uploads folder exists

    safe_name = Path(pdf.filename).name  # avoid directory traversal (keep only name)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")  # create unique timestamp
    saved_pdf_path = uploads_dir / f"{timestamp}_{safe_name}"  # final path to save pdf

    saved_pdf_path.write_bytes(pdf_bytes)  # write pdf bytes to disk

    template_path = config.template_csv_path  # use default reference template

    try:  # protected conversion
        result: Dict[str, str] = convert_pdf_to_csvs(  # convert saved pdf to csvs
            pdf_path=str(saved_pdf_path),  # pass saved path
            output_dir="output",  # output folder
            model=config.model,  # model
            template_csv_path=template_path,  # reference schema template
        )
    except Exception as e:  # map all errors
        raise HTTPException(status_code=500, detail=f"Conversion failed: {e}")  # error response

    return ConvertResponse(  # return paths
        single_row_csv=result["single_row_csv"],  # summary csv path
        chunks_csv=result["chunks_csv"],  # chunks csv path used for Q&A
    )



@app.post("/ask-with-pdf", response_model=AnswerResponse)  # ask with PDF upload (no saved CSV needed)
async def ask_with_pdf(question: str = Form(...), pdf: UploadFile = File(...)) -> AnswerResponse:  # endpoint handler
    q = question.strip()  # sanitize question
    if not q:  # validate question
        raise HTTPException(status_code=400, detail="Question cannot be empty.")  # error
    if not pdf.filename.lower().endswith(".pdf"):  # validate extension
        raise HTTPException(status_code=400, detail="Only PDF files are supported.")  # error

    pdf_bytes = await pdf.read()  # read uploaded bytes
    if not pdf_bytes:  # validate file not empty
        raise HTTPException(status_code=400, detail="Empty PDF file uploaded.")  # error

    chunks = pdf_to_chunks(pdf_bytes)  # convert to chunks
    if not chunks:  # validate extracted text
        raise HTTPException(status_code=400, detail="No text extracted from PDF (might be scanned).")  # error

    retriever = KeywordRetriever(top_k=config.top_k)  # create retriever
    llm = SyllabusChatGPT(model=config.model)  # create llm
    top_chunks = retriever.retrieve(chunks, q)  # retrieve relevant chunks
    answer = llm.answer(q, top_chunks)  # generate answer

    return AnswerResponse(answer=answer)  # return response
