# backend/ask_syllabus.py

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple

import pandas as pd
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()


# ── Data classes ──────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class CsvChunk:
    chunk_id: int
    page: int
    text: str


@dataclass
class ChatMessage:
    role: str    # "user" or "assistant"
    content: str


@dataclass
class AskResult:
    answer: str
    needs_clarification: bool


# ── Store ─────────────────────────────────────────────────────────────────────

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
        return [
            CsvChunk(chunk_id=int(r["chunk_id"]), page=int(r["page"]), text=str(r["text"]))
            for _, r in df.iterrows()
        ]


# ── Retriever ─────────────────────────────────────────────────────────────────

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
            return self._fallback(chunks)
        doc_freq = self._document_frequencies(chunks, terms)
        n_docs = max(len(chunks), 1)

        def idf(term: str) -> float:
            df = doc_freq.get(term, 0)
            return math.log((n_docs + 1) / (df + 1)) + 1.0

        scored: List[Tuple[float, CsvChunk]] = [
            (self._score_chunk(c.text, terms, idf), c) for c in chunks
        ]
        scored.sort(key=lambda x: (x[0], -x[1].chunk_id), reverse=True)
        top = [c for s, c in scored if s >= self.score_threshold][: self.top_k]
        return top if top else self._fallback(chunks)

    def _fallback(self, chunks: List[CsvChunk]) -> List[CsvChunk]:
        return chunks[: min(self.top_k, 3)]

    def _tokenize(self, text: str) -> List[str]:
        raw = (text or "").lower()
        tokens = re.findall(r"[a-z0-9]{3,}", raw)
        return [t for t in tokens if t not in self.stopwords]

    def _document_frequencies(self, chunks: List[CsvChunk], terms: List[str]) -> Dict[str, int]:
        uniq = set(terms)
        df: Dict[str, int] = {t: 0 for t in uniq}
        for c in chunks:
            text = c.text.lower()
            for t in {t for t in uniq if re.search(rf"\b{re.escape(t)}\b", text)}:
                df[t] += 1
        return df

    def _score_chunk(self, chunk_text: str, terms: List[str], idf_fn: Callable[[str], float]) -> float:
        text = (chunk_text or "").lower()
        score = 0.0
        for t in terms:
            tf = len(re.findall(rf"\b{re.escape(t)}\b", text))
            if tf > 0:
                score += (1.0 + math.log(tf)) * float(idf_fn(t))
        return score


# ── Clarification detector ────────────────────────────────────────────────────

# Single-word or very short phrases that are always vague
_VAGUE_EXACT = {
    "help", "explain", "more", "info", "details", "what", "tell me",
    "i need help", "can you help", "question", "hi", "hello",
}

# Patterns that signal a vague question (regex applied to lowercased, stripped input)
_VAGUE_PATTERNS = [
    r"^(tell me|explain|describe|elaborate|more|details?|information|info)$",
    r"^(what|how|why|when|where|who)\s*\??$",
    r"^.{1,6}\s*\??$",   # 6 chars or fewer — almost certainly incomplete
]
_VAGUE_RE = [re.compile(p) for p in _VAGUE_PATTERNS]


class ClarificationDetector:
    """Two-tier vagueness check. Tier-1 is free (regex). Tier-2 uses LLM only
    for short questions with no conversation history."""

    def __init__(self, model: str = "gpt-4o-mini") -> None:
        self.client = OpenAI()
        self.model = model

    def check(
        self,
        question: str,
        history: Optional[List[ChatMessage]] = None,
    ) -> Tuple[bool, Optional[str]]:
        """Return (needs_clarification, clarifying_question_or_None)."""
        q = question.strip()
        if not q:
            return True, "What would you like to know about the syllabus?"

        q_lower = q.lower()

        # Tier 1 — rule-based (free)
        if q_lower in _VAGUE_EXACT:
            return True, "Could you be more specific? For example: 'When is the midterm?' or 'What are the CLOs?'"
        for pat in _VAGUE_RE:
            if pat.match(q_lower):
                return True, "Could you be more specific? For example: 'When is the final exam?' or 'What topics are covered in Week 3?'"

        # Short follow-up mid-conversation is fine — user is continuing a thread
        has_history = bool(history)
        if has_history:
            return False, None

        # Tier 2 — LLM check, only for short standalone questions (saves tokens)
        if len(q) > 80:
            return False, None  # Long questions are almost always specific enough

        try:
            response = self.client.chat.completions.create(
                model=self.model,
                max_tokens=80,
                temperature=0,
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "You decide if a syllabus question is specific enough to answer.\n"
                            "Reply with ONLY: CLEAR or VAGUE: <short clarifying question>\n"
                            "Examples:\n"
                            "  'When is the midterm?' → CLEAR\n"
                            "  'Tell me stuff' → VAGUE: What specific information are you looking for?\n"
                            "  'grades' → VAGUE: Are you asking about the grading breakdown or how grades are calculated?\n"
                        ),
                    },
                    {"role": "user", "content": q},
                ],
            )
            reply = (response.choices[0].message.content or "").strip()
            if reply.upper().startswith("VAGUE"):
                parts = reply.split(":", 1)
                follow_up = parts[1].strip() if len(parts) > 1 else "Could you please be more specific?"
                return True, follow_up
        except Exception:
            pass  # If LLM check fails, proceed normally

        return False, None


# ── LLM answerer ──────────────────────────────────────────────────────────────

class SyllabusChatGPT:
    def __init__(self, model: str = "gpt-4o-mini") -> None:
        self.client = OpenAI()
        self.model = model

    def answer(
        self,
        question: str,
        context_chunks: List[CsvChunk],
        history: Optional[List[ChatMessage]] = None,
    ) -> str:
        per_chunk_cap = 1500
        total_cap = 9000
        parts: List[str] = []
        total = 0
        for c in context_chunks:
            piece = (c.text or "")[:per_chunk_cap]
            if not piece.strip():
                continue
            if total + len(piece) > total_cap:
                break
            parts.append(piece)
            total += len(piece)

        context_text = "\n\n---\n\n".join(parts)

        system_msg = {
            "role": "system",
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
                f"\nSYLLABUS CONTEXT:\n{context_text}"
            ),
        }

        messages = [system_msg]

        # Inject last 6 history messages (3 turns) for context
        if history:
            for msg in history[-6:]:
                messages.append({"role": msg.role, "content": msg.content})

        messages.append({"role": "user", "content": question})

        response = self.client.chat.completions.create(
            model=self.model,
            max_tokens=500,
            messages=messages,
        )
        return (response.choices[0].message.content or "").strip()


# ── Pipeline ──────────────────────────────────────────────────────────────────

class AskPipeline:
    def __init__(
        self,
        store: SyllabusCsvStore,
        retriever: LightweightRetriever,
        llm: SyllabusChatGPT,
        clarifier: Optional[ClarificationDetector] = None,
    ) -> None:
        self.store = store
        self.retriever = retriever
        self.llm = llm
        self.clarifier = clarifier or ClarificationDetector()

    def run(
        self,
        question: str,
        history: Optional[List[ChatMessage]] = None,
    ) -> AskResult:
        # Check for vague question first (before retrieval — saves tokens)
        needs_clarification, clarifying_q = self.clarifier.check(question, history)
        if needs_clarification:
            return AskResult(
                answer=clarifying_q or "Could you please be more specific?",
                needs_clarification=True,
            )

        chunks = self.store.load()
        top_chunks = self.retriever.retrieve(chunks, question)
        answer = self.llm.answer(question, top_chunks, history=history)
        return AskResult(answer=answer, needs_clarification=False)


# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> None:
    csv_path = input("Enter chunks CSV path: ").strip()
    if not csv_path:
        print("❌ Please provide a chunks CSV path.")
        return

    pipeline = AskPipeline(
        store=SyllabusCsvStore(csv_path),
        retriever=LightweightRetriever(top_k=12, score_threshold=2.0),
        llm=SyllabusChatGPT(model="gpt-4o-mini"),
    )

    history: List[ChatMessage] = []
    print("Syllabus chat ready. Type 'quit' to exit.\n")
    while True:
        question = input("You: ").strip()
        if question.lower() in ("quit", "exit"):
            break
        result = pipeline.run(question, history=history)
        print(f"Bot: {result.answer}")
        if not result.needs_clarification:
            history.append(ChatMessage(role="user", content=question))
            history.append(ChatMessage(role="assistant", content=result.answer))
        print()


if __name__ == "__main__":
    main()