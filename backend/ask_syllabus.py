from __future__ import annotations  # forward references for typing

from dataclasses import dataclass  # small data structure
from pathlib import Path  # file paths
from typing import List, Tuple  # typing helpers

import pandas as pd  # read CSV easily
from dotenv import load_dotenv  # load .env OpenAI key
from openai import OpenAI  # OpenAI client

load_dotenv()  # load OPENAI_API_KEY from .env


@dataclass(frozen=True)  # immutable chunk object
class CsvChunk:  # one row of chunks CSV
    chunk_id: int  # id
    page: int  # page number
    text: str  # chunk text


class SyllabusCsvStore:  # SRP: load chunks CSV from disk
    def __init__(self, csv_path: str) -> None:  # accept path (not hardcoded)
        self.csv_path = Path(csv_path)  # store as Path

    def load(self) -> List[CsvChunk]:  # load csv into list of CsvChunk
        if not self.csv_path.exists():  # validate file exists
            raise FileNotFoundError(f"CSV not found: {self.csv_path.resolve()}")  # clear error

        df = pd.read_csv(self.csv_path)  # load CSV into DataFrame

        required = {"chunk_id", "page", "text"}  # required columns
        if not required.issubset(set(df.columns)):  # validate schema
            raise ValueError(f"CSV must contain columns: {sorted(required)}. Found: {list(df.columns)}")  # error

        chunks: List[CsvChunk] = []  # allocate list
        for _, r in df.iterrows():  # iterate rows
            chunks.append(  # append a CsvChunk
                CsvChunk(  # create chunk object
                    chunk_id=int(r["chunk_id"]),  # parse id
                    page=int(r["page"]),  # parse page
                    text=str(r["text"]),  # parse text
                )  # end CsvChunk
            )  # end append
        return chunks  # return chunks list


class KeywordRetriever:  # SRP: retrieve best chunks by keyword scoring
    def __init__(self, top_k: int = 10) -> None:  # configure top-k
        self.top_k = top_k  # store top-k

    def retrieve(self, chunks: List[CsvChunk], question: str) -> List[CsvChunk]:  # pick relevant chunks
        terms = [t.lower() for t in question.replace("?", " ").split() if len(t) >= 3]  # extract meaningful terms
        if not terms:  # if question has no useful words
            return chunks[: self.top_k]  # fallback: first chunks

        def score(text: str) -> int:  # score function
            t = text.lower()  # lowercase chunk text
            return sum(1 for term in terms if term in t)  # count matched terms

        scored: List[Tuple[int, CsvChunk]] = [(score(c.text), c) for c in chunks]  # score all chunks
        scored.sort(key=lambda x: (x[0], -x[1].chunk_id), reverse=True)  # sort by score desc

        top = [c for s, c in scored if s > 0][: self.top_k]  # select positive-score chunks
        return top if top else chunks[: self.top_k]  # fallback if none matched


class SyllabusChatGPT:  # SRP: call OpenAI with context chunks
    def __init__(self, model: str = "gpt-5") -> None:  # configure model
        self.client = OpenAI()  # OpenAI client
        self.model = model  # store model name

    def answer(self, question: str, context_chunks: List[CsvChunk]) -> str:  # produce answer using context
        context_text = "\n\n---\n\n".join(  # join chunks into a context string
            f"[chunk {c.chunk_id} | page {c.page}]\n{c.text}" for c in context_chunks  # include citations tokens
        )  # end join

        response = self.client.responses.create(  # call OpenAI
            model=self.model,  # model
            input=[  # multi-message input
                {  # developer role message
                    "role": "developer",  # role
                    "content": (  # instructions to model
                        "You are a syllabus Q&A assistant.\n"  # role description
                        "Rules:\n"  # rules header
                        "- Use ONLY the provided syllabus context.\n"  # no outside info
                        "- If the answer is not explicitly present, reply exactly: 'Not found in the syllabus.'\n"  # strict fallback
                        "- Be concise (max 6 lines).\n"  # concision
                        "- Every sentence must end with citations like (chunk 3, page 2).\n"  # citation policy
                        "- Do NOT invent dates/times/numbers.\n"  # no hallucinations
                    ),  # end instructions
                },  # end developer msg
                {  # user role message
                    "role": "user",  # role
                    "content": f"SYLLABUS CONTEXT:\n{context_text}\n\nQUESTION:\n{question}",  # prompt
                },  # end user msg
            ],  # end input
        )  # end call

        return response.output_text  # return final answer text


class AskPipeline:  # orchestrator: load -> retrieve -> answer
    def __init__(self, store: SyllabusCsvStore, retriever: KeywordRetriever, llm: SyllabusChatGPT) -> None:  # DI
        self.store = store  # store dependency
        self.retriever = retriever  # retriever dependency
        self.llm = llm  # llm dependency

    def run(self, question: str) -> str:  # run full pipeline
        chunks = self.store.load()  # load chunks from CSV
        top_chunks = self.retriever.retrieve(chunks, question)  # retrieve relevant chunks
        return self.llm.answer(question, top_chunks)  # ask OpenAI and return answer


def main() -> None:  # CLI entrypoint
    csv_path = input("Enter chunks CSV path: ").strip()  # ask for CSV path
    question = input("Ask a syllabus question: ").strip()  # ask for question
    if not csv_path:  # validate CSV path
        print("❌ Please provide a CSV path.")  # error
        return  # stop
    if not question:  # validate question
        print("❌ Please type a question.")  # error
        return  # stop

    pipeline = AskPipeline(  # build pipeline
        store=SyllabusCsvStore(csv_path),  # store uses provided path
        retriever=KeywordRetriever(top_k=12),  # top-k retrieval
        llm=SyllabusChatGPT(model="gpt-5"),  # OpenAI model
    )  # end pipeline build

    answer = pipeline.run(question)  # run pipeline
    print("\n✅ Answer:\n")  # header
    print(answer)  # print answer


if __name__ == "__main__":  # if file executed directly
    main()  # run CLI
