from __future__ import annotations  # forward references support

import math
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()


@dataclass(frozen=True)
class CsvChunk:
    chunk_id: int
    page: int
    text: str
    # Embedding vector, or None for legacy chunks without embeddings.
    # Using a default so existing construction calls stay unchanged.
    embedding: Optional[List[float]] = field(default=None, compare=False)


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


# ── SyllabusListStore ─────────────────────────────────────────────────────────

class SyllabusListStore:
    """
    In-memory store that wraps chunks already loaded from the database.

    Accepts the list of dicts returned by get_chunks_for_ask() and converts
    them to CsvChunk objects directly in memory — no disk I/O, no temp files.

    Each dict shape: {"chunk_id": int, "page": int, "content": str,
                      "embedding": list[float] | None}
    """

    def __init__(self, chunks: List[Dict]) -> None:
        self._chunks = chunks

    def load(self) -> List[CsvChunk]:
        result: List[CsvChunk] = []
        for c in self._chunks:
            raw_emb = c.get("embedding")
            embedding: Optional[List[float]] = (
                [float(v) for v in raw_emb]
                if isinstance(raw_emb, (list, tuple)) and raw_emb
                else None
            )
            result.append(
                CsvChunk(
                    chunk_id=int(c.get("chunk_id", 0)),
                    page=int(c.get("page", 0)),
                    text=str(c.get("content", "")),
                    embedding=embedding,
                )
            )
        return result


# ── EmbeddingRetriever ────────────────────────────────────────────────────────

_EMBED_MODEL = "text-embedding-3-small"


def _cosine_similarity(a: List[float], b: List[float]) -> float:
    """Fast cosine similarity between two equal-length vectors."""
    va = np.array(a, dtype=np.float32)
    vb = np.array(b, dtype=np.float32)
    denom = np.linalg.norm(va) * np.linalg.norm(vb)
    if denom == 0.0:
        return 0.0
    return float(np.dot(va, vb) / denom)


class EmbeddingRetriever:
    """
    Semantic retriever using OpenAI embeddings + cosine similarity.

    At query time it embeds the user question (one API call, ~1 ms latency)
    and ranks all chunks by cosine similarity against their stored embeddings.

    Falls back to LightweightRetriever if a chunk has no stored embedding
    (i.e. the workspace was uploaded before embeddings were introduced).

    Why this is better than TF-IDF:
    - Handles paraphrasing: "will I fail?" matches "grade penalty for absences"
    - Handles synonyms: "textbooks" matches "required readings"
    - Handles implicit references in follow-up questions
    """

    def __init__(self, top_k: int = 8) -> None:
        self.top_k = top_k
        self._client = OpenAI()
        self._fallback = LightweightRetriever(top_k=top_k)

    def _embed_question(self, question: str) -> Optional[List[float]]:
        """Embed a single question string. Returns None on error."""
        try:
            resp = self._client.embeddings.create(
                model=_EMBED_MODEL,
                input=question.strip(),
            )
            return resp.data[0].embedding
        except Exception:
            return None

    def retrieve(self, chunks: List[CsvChunk], question: str) -> List[CsvChunk]:
        # Check whether chunks have embeddings stored
        chunks_with_emb = [c for c in chunks if c.embedding]

        if not chunks_with_emb:
            # Legacy workspace — no embeddings stored yet, use keyword fallback
            return self._fallback.retrieve(chunks, question)

        if len(chunks_with_emb) < len(chunks):
            # Partial coverage — some chunks lack embeddings (shouldn't normally
            # happen, but handle gracefully by using only embedded ones)
            chunks = chunks_with_emb

        # Embed the question
        q_embedding = self._embed_question(question)
        if q_embedding is None:
            # Embedding API failed — fall back to keyword retrieval
            return self._fallback.retrieve(chunks, question)

        # Rank all chunks by cosine similarity
        scored: List[Tuple[float, CsvChunk]] = [
            (_cosine_similarity(q_embedding, c.embedding), c)  # type: ignore[arg-type]
            for c in chunks
        ]
        scored.sort(key=lambda x: x[0], reverse=True)

        return [c for _, c in scored[: self.top_k]]


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
    def __init__(self, model: str = "gpt-4o-mini") -> None:
        self.client = OpenAI()
        self.model = model

    def answer(
        self,
        question: str,
        context_chunks: List[CsvChunk],
        history: Optional[List[Dict]] = None,
    ) -> str:
        """
        Answer a question grounded in syllabus chunks.

        Parameters
        ----------
        question       : The current user question.
        context_chunks : Top-ranked chunks from the retriever.
        history        : Optional prior conversation turns, each a dict with
                         keys "role" ("user"|"assistant") and "content" (str).
                         Caller is responsible for trimming to last N turns.
        """
        # ── Build syllabus context ────────────────────────────────────────────
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

        # ── System prompt ─────────────────────────────────────────────────────
        system_prompt = (
            "You are an intelligent academic assistant embedded in a course management app. "
            "Your job is to help instructors understand their course syllabus "
            "clearly and accurately.\n\n"

            "BEHAVIOUR:\n"
            "- Answer questions strictly based on the syllabus context provided.\n"
            "- If the answer is not in the syllabus, say clearly: "
            "'That information isn't in the syllabus.' "
            "Do NOT guess, infer, or invent any dates, percentages, or policies.\n"
            "- If a follow-up question refers to something in the conversation history "
            "(e.g. 'what about that?', 'and the deadline?'), use the history to resolve it.\n"
            "- Be concise but complete. Aim for 2-5 lines. Use a numbered list only when "
            "listing multiple distinct items (e.g. grading breakdown). "
            "Otherwise use plain sentences.\n"
            "- Speak in a warm, helpful tone like a knowledgeable teaching assistant.\n"
            "- Never mention 'chunks', 'context', 'pages', or internal system details.\n"
            "- Never repeat the question back to the user.\n"
            "- If the question is ambiguous, answer the most likely interpretation "
            "and briefly note your assumption.\n\n"

            f"SYLLABUS CONTEXT:\n{context_text}"
        )

        # ── Build message list: system + history + current question ───────────
        messages: List[Dict] = [{"role": "developer", "content": system_prompt}]

        if history:
            for turn in history:
                role = turn.get("role", "")
                msg_content = (turn.get("content") or "").strip()
                if role in ("user", "assistant") and msg_content:
                    messages.append({"role": role, "content": msg_content})

        messages.append({"role": "user", "content": question})

        response = self.client.responses.create(
            model=self.model,
            input=messages,
        )

        return (response.output_text or "").strip()


def _rewrite_query(
    question: str,
    history: List[Dict],
    client: OpenAI,
    model: str = "gpt-4o-mini",
) -> str:
    """
    Rewrite a follow-up question into a self-contained search query.

    Problem: short follow-up questions like "what chapters are included?"
    have almost no semantic signal on their own. The retriever embeds them
    and finds irrelevant chunks because the question doesn't mention what
    it refers to ("the midterm", "that assignment", etc.).

    Solution: use a fast GPT call to inject the missing context from the
    conversation history, producing a query the retriever can actually use.

    Example:
        history:  "When is the midterm?"  →  "The midterm is on March 15."
        question: "What chapters are included?"
        rewritten: "What chapters are included in the midterm?"

    Returns the original question unchanged if:
      - There is no history (first question — already self-contained)
      - The question is already self-contained (GPT returns it as-is)
      - The rewrite API call fails (safe fallback)
    """
    if not history:
        return question

    # Build a compact summary of the last 3 turns for the rewrite prompt
    recent = history[-6:]  # last 3 user+assistant pairs
    history_text = "\n".join(
        f"{t['role'].capitalize()}: {t['content']}" for t in recent
    )

    try:
        resp = client.responses.create(
            model=model,
            input=[
                {
                    "role": "developer",
                    "content": (
                        "You rewrite follow-up questions into self-contained search queries.\n"
                        "Rules:\n"
                        "- If the question already makes sense on its own, return it unchanged.\n"
                        "- If it refers to something in the conversation ('that', 'it', 'those', "
                        "  'what about', 'and the', etc.), rewrite it so it is fully clear "
                        "  without reading the history.\n"
                        "- Keep it short — one sentence maximum.\n"
                        "- Return ONLY the rewritten question, nothing else."
                    ),
                },
                {
                    "role": "user",
                    "content": (
                        f"Conversation so far:\n{history_text}\n\n"
                        f"Follow-up question: {question}\n\n"
                        "Rewritten question:"
                    ),
                },
            ],
        )
        rewritten = (resp.output_text or "").strip()
        # Safety: if rewrite is empty or suspiciously long, fall back
        if rewritten and len(rewritten) < 300:
            return rewritten
    except Exception:
        pass  # fall back silently — never break the ask flow

    return question


class AskPipeline:
    def __init__(
        self,
        store: "SyllabusCsvStore | SyllabusListStore",
        retriever: "EmbeddingRetriever | LightweightRetriever",
        llm: SyllabusChatGPT,
    ) -> None:
        self.store = store
        self.retriever = retriever
        self.llm = llm
        self._openai_client = OpenAI()

    def run(
        self,
        question: str,
        history: Optional[List[Dict]] = None,
    ) -> str:
        """
        Run the full ask pipeline.

        Parameters
        ----------
        question : The current user question.
        history  : Optional prior conversation turns trimmed to last N.
                   Each entry: {"role": "user"|"assistant", "content": str}

        Flow
        ----
        1. Rewrite question using history so retriever gets full context
        2. Retrieve top-k chunks using the rewritten (self-contained) query
        3. Answer using original question + history so GPT answers naturally
        """
        # Step 1: rewrite vague follow-ups into self-contained retrieval queries.
        # The rewritten query is only used for chunk retrieval, GPT still sees
        # the original question so the answer reads naturally.
        retrieval_query = _rewrite_query(
            question=question,
            history=history or [],
            client=self._openai_client,
        )

        chunks = self.store.load()
        top_chunks = self.retriever.retrieve(chunks, retrieval_query)
        return self.llm.answer(question, top_chunks, history=history)


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
        llm=SyllabusChatGPT(model="gpt-4o-mini"),
    )

    answer = pipeline.run(question)
    print("\n✅ Answer:\n")
    print(answer)


if __name__ == "__main__":
    main()