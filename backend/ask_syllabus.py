from __future__ import annotations  # forward references support

import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, List, Tuple

import pandas as pd
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()


@dataclass(frozen=True)
class CsvChunk:
    chunk_id: int
    page: int
    text: str


class SyllabusCsvStore:
    def __init__(self, csv_path: str) -> None:
        self.csv_path = Path(csv_path)

    def load(self) -> List[CsvChunk]:
        if not self.csv_path.exists():
            raise FileNotFoundError(f"CSV not found: {self.csv_path.resolve()}")

        df = pd.read_csv(self.csv_path)

        required = {"chunk_id", "page", "text"}
        if not required.issubset(set(df.columns)):
            raise ValueError(f"CSV must contain columns: {sorted(required)}. Found: {list(df.columns)}")

        chunks: List[CsvChunk] = []
        for _, r in df.iterrows():
            chunks.append(
                CsvChunk(
                    chunk_id=int(r["chunk_id"]),
                    page=int(r["page"]),
                    text=str(r["text"]),
                )
            )
        return chunks


class LightweightRetriever:
    def __init__(self, top_k: int = 10, score_threshold: float = 2.0) -> None:
        self.top_k = top_k
        self.score_threshold = score_threshold
        self.stopwords = {
            "the", "a", "an", "and", "or", "to", "of", "in", "on", "for", "is", "are", "was", "were",
            "with", "at", "by", "from", "as", "that", "this", "it", "be", "can", "will", "what", "when",
            "how", "which", "who", "where", "why",
        }

    def retrieve(self, chunks: List[CsvChunk], question: str) -> List[CsvChunk]:
        terms = self._tokenize(question)
        if not terms:
            # If question is empty/no meaningful terms: fall back to earliest pages
            return self._fallback(chunks)

        doc_freq = self._document_frequencies(chunks, terms)
        n_docs = max(len(chunks), 1)

        def idf(term: str) -> float:
            df = doc_freq.get(term, 0)
            return math.log((n_docs + 1) / (df + 1)) + 1.0

        scored: List[Tuple[float, CsvChunk]] = []
        for c in chunks:
            score = self._score_chunk(c.text, terms, idf)
            scored.append((score, c))

        scored.sort(key=lambda x: (x[0], -x[1].chunk_id), reverse=True)

        # Keep only meaningful matches
        top = [c for s, c in scored if s >= self.score_threshold][: self.top_k]
        return top if top else self._fallback(chunks)

    def _fallback(self, chunks: List[CsvChunk]) -> List[CsvChunk]:
        # Prefer early pages: in your chunks.csv, chunk_id correlates with page order.
        return chunks[: min(self.top_k, 3)]

    def _tokenize(self, text: str) -> List[str]:
        raw = (text or "").lower()
        tokens = re.findall(r"[a-z0-9]{3,}", raw)
        tokens = [t for t in tokens if t not in self.stopwords]
        return tokens

    def _document_frequencies(self, chunks: List[CsvChunk], terms: List[str]) -> Dict[str, int]:
        uniq_terms = set(terms)
        df: Dict[str, int] = {t: 0 for t in uniq_terms}
        for c in chunks:
            text = c.text.lower()
            present = {t for t in uniq_terms if re.search(rf"\b{re.escape(t)}\b", text)}
            for t in present:
                df[t] += 1
        return df

    def _score_chunk(self, chunk_text: str, terms: List[str], idf_fn: Callable[[str], float]) -> float:
        text = (chunk_text or "").lower()
        score = 0.0
        for t in terms:
            matches = re.findall(rf"\b{re.escape(t)}\b", text)
            tf = len(matches)
            if tf > 0:
                score += (1.0 + math.log(tf)) * float(idf_fn(t))
        return score


class SyllabusChatGPT:
    def __init__(self, model: str = "gpt-5") -> None:
        self.client = OpenAI()
        self.model = model

    def answer(self, question: str, context_chunks: List[CsvChunk]) -> str:
        # Cap per chunk + cap total context for speed/cost
        per_chunk_cap = 1500
        total_cap = 9000

        parts: List[str] = []
        total = 0
        for c in context_chunks:
            piece = (c.text or "")[:per_chunk_cap]
            if not piece.strip():
                continue
            next_len = total + len(piece) + (5 if parts else 0)
            if next_len > total_cap:
                break
            parts.append(piece)
            total = next_len

        context_text = "\n\n---\n\n".join(parts)

        response = self.client.responses.create(
            model=self.model,
            input=[
                {
                    "role": "developer",
                    "content": (
                        "You are a syllabus Q&A assistant.\n"
                        "Rules:\n"
                        "- Use ONLY the provided syllabus context.\n"
                        "- If the answer is not explicitly present, reply exactly: 'Not found in the syllabus.'\n"
                        "- Be concise (max 6 lines).\n"
                        "- Respond in a clean user-friendly way.\n"
                        "- Do NOT include citations.\n"
                        "- Do NOT mention chunks or pages.\n"
                        "- Do NOT invent dates/times/numbers.\n"
                    ),
                },
                {
                    "role": "user",
                    "content": f"SYLLABUS CONTEXT:\n{context_text}\n\nQUESTION:\n{question}",
                },
            ],
        )

        return (response.output_text or "").strip()


class AskPipeline:
    def __init__(self, store: SyllabusCsvStore, retriever: LightweightRetriever, llm: SyllabusChatGPT) -> None:
        self.store = store
        self.retriever = retriever
        self.llm = llm

    def run(self, question: str) -> str:
        chunks = self.store.load()
        top_chunks = self.retriever.retrieve(chunks, question)
        return self.llm.answer(question, top_chunks)


def main() -> None:
    csv_path = input("Enter chunks CSV path: ").strip()
    question = input("Ask a syllabus question: ").strip()
    if not csv_path:
        print("❌ Please provide a chunks CSV path.")
        return
    if not question:
        print("❌ Please type a question.")
        return

    pipeline = AskPipeline(
        store=SyllabusCsvStore(csv_path),
        retriever=LightweightRetriever(top_k=12, score_threshold=2.0),
        llm=SyllabusChatGPT(model="gpt-5"),
    )

    answer = pipeline.run(question)
    print("\n✅ Answer:\n")
    print(answer)


if __name__ == "__main__":
    main()