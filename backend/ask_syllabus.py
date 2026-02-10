from __future__ import annotations  # forward references support

import math  # IDF math
import re  # regex for tokenization + word-boundaries
from dataclasses import dataclass  # data model helper
from pathlib import Path  # safe file paths
from typing import Callable, Dict, List, Tuple  # typing helpers

import pandas as pd  # load CSV easily
from dotenv import load_dotenv  # load .env keys
from openai import OpenAI  # OpenAI client

load_dotenv()  # load OPENAI_API_KEY from .env automatically


@dataclass(frozen=True)  # immutable chunk
class CsvChunk:  # represent a chunk row from chunks CSV
    chunk_id: int  # chunk id (internal use only)
    page: int  # page number (internal use only)
    text: str  # chunk text (what we actually send to the model)


class SyllabusCsvStore:  # SRP: load chunks CSV from disk
    def __init__(self, csv_path: str) -> None:  # constructor
        self.csv_path = Path(csv_path)  # store path safely

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


class LightweightRetriever:  # SRP: retrieve relevant chunks using weighted keyword scoring
    def __init__(self, top_k: int = 10) -> None:  # constructor
        self.top_k = top_k  # store top_k
        self.stopwords = {  # basic stopwords set (small + effective)
            "the", "a", "an", "and", "or", "to", "of", "in", "on", "for", "is", "are", "was", "were",
            "with", "at", "by", "from", "as", "that", "this", "it", "be", "can", "will", "what", "when",
            "how", "which", "who", "where", "why",
        }  # end stopwords

    def retrieve(self, chunks: List[CsvChunk], question: str) -> List[CsvChunk]:  # retrieve best chunks
        terms = self._tokenize(question)  # tokenize question
        if not terms:  # if no meaningful terms
            return chunks[: self.top_k]  # fallback

        doc_freq = self._document_frequencies(chunks, terms)  # compute df across chunks for terms
        n_docs = max(len(chunks), 1)  # avoid division by zero

        def idf(term: str) -> float:  # compute IDF-like weight
            df = doc_freq.get(term, 0)  # get document frequency
            return math.log((n_docs + 1) / (df + 1)) + 1.0  # smoothed idf

        scored: List[Tuple[float, CsvChunk]] = []  # list of (score, chunk)
        for c in chunks:  # score each chunk
            score = self._score_chunk(c.text, terms, idf)  # compute score
            scored.append((score, c))  # store

        scored.sort(key=lambda x: (x[0], -x[1].chunk_id), reverse=True)  # sort high score first
        top = [c for s, c in scored if s > 0][: self.top_k]  # keep positive matches
        return top if top else chunks[: self.top_k]  # fallback if all zero

    def _tokenize(self, text: str) -> List[str]:  # tokenize into meaningful terms
        raw = (text or "").lower()  # normalize to lowercase
        tokens = re.findall(r"[a-z0-9]{3,}", raw)  # extract word-like tokens length >= 3
        tokens = [t for t in tokens if t not in self.stopwords]  # remove stopwords
        return tokens  # return tokens

    def _document_frequencies(self, chunks: List[CsvChunk], terms: List[str]) -> Dict[str, int]:  # count df for each term
        uniq_terms = set(terms)  # unique terms only
        df: Dict[str, int] = {t: 0 for t in uniq_terms}  # init df map
        for c in chunks:  # each doc
            text = c.text.lower()  # normalized text
            present = {t for t in uniq_terms if re.search(rf"\b{re.escape(t)}\b", text)}  # term present?
            for t in present:  # increment df
                df[t] += 1  # add one doc
        return df  # return df

    def _score_chunk(self, chunk_text: str, terms: List[str], idf_fn: Callable[[str], float]) -> float:  # compute weighted score
        text = (chunk_text or "").lower()  # normalize
        score = 0.0  # start score
        for t in terms:  # for each query term
            matches = re.findall(rf"\b{re.escape(t)}\b", text)  # whole-word matches
            tf = len(matches)  # term frequency
            if tf > 0:  # if present
                score += (1.0 + math.log(tf)) * float(idf_fn(t))  # tf-idf-ish weight
        return score  # final score


class SyllabusChatGPT:  # SRP: call OpenAI with selected syllabus context
    def __init__(self, model: str = "gpt-5") -> None:  # constructor
        self.client = OpenAI()  # create OpenAI client
        self.model = model  # store model name

    def answer(self, question: str, context_chunks: List[CsvChunk]) -> str:  # produce final answer
        # IMPORTANT: We do NOT include chunk/page markers in the context to avoid leaking them into answers.
        context_text = "\n\n---\n\n".join(  # join chunks into one context string
            c.text for c in context_chunks  # ONLY the plain text
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
                        "- Respond in a clean user-friendly way.\n"
                        "- Do NOT include citations.\n"
                        "- Do NOT mention chunks or pages.\n"
                        "- Do NOT invent dates/times/numbers.\n"
                    ),  # end instructions
                },  # end developer message
                {  # user message
                    "role": "user",  # role
                    "content": f"SYLLABUS CONTEXT:\n{context_text}\n\nQUESTION:\n{question}",  # provide context + question
                },  # end user message
            ],  # end input
        )  # end call

        return (response.output_text or "").strip()  # return cleaned output


class AskPipeline:  # orchestrator: load -> retrieve -> answer
    def __init__(self, store: SyllabusCsvStore, retriever: LightweightRetriever, llm: SyllabusChatGPT) -> None:  # DI
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
        retriever=LightweightRetriever(top_k=12),  # retriever config
        llm=SyllabusChatGPT(model="gpt-5"),  # model config
    )  # end pipeline

    answer = pipeline.run(question)  # run pipeline
    print("\n✅ Answer:\n")  # header
    print(answer)  # print answer


if __name__ == "__main__":  # run only when executed directly
    main()  # run CLI
