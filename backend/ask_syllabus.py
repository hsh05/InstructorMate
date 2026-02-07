from __future__ import annotations  # forward references support

from dataclasses import dataclass  # data model helper
from pathlib import Path  # safe file paths
from typing import List, Tuple  # typing helpers

import pandas as pd  # load CSV easily
from dotenv import load_dotenv  # load .env keys
from openai import OpenAI  # OpenAI client

load_dotenv()  # load OPENAI_API_KEY from .env automatically


@dataclass(frozen=True)  # immutable chunk
class CsvChunk:  # represent a chunk row from chunks CSV
    chunk_id: int  # chunk id
    page: int  # page number
    text: str  # chunk text


class SyllabusCsvStore:  # SRP: load chunks CSV from disk
    def __init__(self, csv_path: str) -> None:  # constructor
        self.csv_path = Path(csv_path)  # store as Path

    def load(self) -> List[CsvChunk]:  # load CSV into list of CsvChunk
        if not self.csv_path.exists():  # validate file exists
            raise FileNotFoundError(f"CSV not found: {self.csv_path.resolve()}")  # clear error

        df = pd.read_csv(self.csv_path)  # load into DataFrame

        required = {"chunk_id", "page", "text"}  # required schema
        if not required.issubset(set(df.columns)):  # validate schema
            raise ValueError(f"CSV must contain columns: {sorted(required)}. Found: {list(df.columns)}")  # error

        chunks: List[CsvChunk] = []  # output list
        for _, r in df.iterrows():  # iterate rows
            chunks.append(  # append chunk
                CsvChunk(  # build chunk object
                    chunk_id=int(r["chunk_id"]),  # parse id
                    page=int(r["page"]),  # parse page
                    text=str(r["text"]),  # parse text
                )  # end chunk
            )  # end append
        return chunks  # return chunks list


class KeywordRetriever:  # SRP: retrieve relevant chunks using keyword matching
    def __init__(self, top_k: int = 10) -> None:  # constructor
        self.top_k = top_k  # store top_k

    def retrieve(self, chunks: List[CsvChunk], question: str) -> List[CsvChunk]:  # retrieve best chunks
        terms = [t.lower() for t in question.replace("?", " ").split() if len(t) >= 3]  # extract meaningful terms
        if not terms:  # if no meaningful terms
            return chunks[: self.top_k]  # fallback to first chunks

        def score(text: str) -> int:  # scoring function
            t = text.lower()  # lower-case chunk text
            return sum(1 for term in terms if term in t)  # count term matches

        scored: List[Tuple[int, CsvChunk]] = [(score(c.text), c) for c in chunks]  # score each chunk
        scored.sort(key=lambda x: (x[0], -x[1].chunk_id), reverse=True)  # sort by highest score

        top = [c for s, c in scored if s > 0][: self.top_k]  # keep positive matches
        return top if top else chunks[: self.top_k]  # fallback if no matches


class SyllabusChatGPT:  # SRP: call OpenAI with selected syllabus context
    def __init__(self, model: str = "gpt-5") -> None:  # constructor
        self.client = OpenAI()  # create OpenAI client
        self.model = model  # store model name

    def answer(self, question: str, context_chunks: List[CsvChunk]) -> str:  # produce final answer
        context_text = "\n\n---\n\n".join(  # join chunks into one context string
            f"[chunk {c.chunk_id} | page {c.page}]\n{c.text}" for c in context_chunks  # include citations tokens
        )  # end join

        response = self.client.responses.create(  # call OpenAI
            model=self.model,  # model
            input=[  # multi-message input
                {  # developer message
                    "role": "developer",  # role
                    "content": (  # instructions
                        "You are a syllabus Q&A assistant.\n"
                        "Rules:\n"
                        "- Use ONLY the provided syllabus context.\n"
                        "- If the answer is not explicitly present, reply exactly: 'Not found in the syllabus.'\n"
                        "- Be concise (max 6 lines).\n"
                        "- Every sentence must end with citations like (chunk 3, page 2).\n"
                        "- Do NOT invent dates/times/numbers.\n"
                    ),  # end instructions
                },  # end developer message
                {  # user message
                    "role": "user",  # role
                    "content": f"SYLLABUS CONTEXT:\n{context_text}\n\nQUESTION:\n{question}",  # provide context + question
                },  # end user message
            ],  # end input
        )  # end call

        return response.output_text  # return model output


class AskPipeline:  # orchestrator: load -> retrieve -> answer
    def __init__(self, store: SyllabusCsvStore, retriever: KeywordRetriever, llm: SyllabusChatGPT) -> None:  # DI
        self.store = store  # store dependency
        self.retriever = retriever  # retriever dependency
        self.llm = llm  # llm dependency

    def run(self, question: str) -> str:  # run full pipeline
        chunks = self.store.load()  # load chunks
        top_chunks = self.retriever.retrieve(chunks, question)  # retrieve relevant chunks
        return self.llm.answer(question, top_chunks)  # answer using LLM


def main() -> None:  # CLI entrypoint
    csv_path = input("Enter chunks CSV path: ").strip()  # ask user for chunks csv
    question = input("Ask a syllabus question: ").strip()  # ask question
    if not csv_path:  # validate path
        print("❌ Please provide a chunks CSV path.")  # error
        return  # stop
    if not question:  # validate question
        print("❌ Please type a question.")  # error
        return  # stop

    pipeline = AskPipeline(  # build pipeline
        store=SyllabusCsvStore(csv_path),  # store
        retriever=KeywordRetriever(top_k=12),  # retriever config
        llm=SyllabusChatGPT(model="gpt-5"),  # model config
    )  # end pipeline

    answer = pipeline.run(question)  # run pipeline
    print("\n✅ Answer:\n")  # header
    print(answer)  # print answer


if __name__ == "__main__":  # run only when executed directly
    main()  # run CLI
