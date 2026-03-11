# backend/services/structured_syllabus_extractor.py

from __future__ import annotations
import json
import logging
import re
from dataclasses import dataclass, field
from typing import List

from pypdf import PdfReader
from openai import OpenAI

logger = logging.getLogger(__name__)

# Keywords that signal a page likely contains schedule/CLO/assessment info
_SIGNAL_KEYWORDS = {
    "week", "lecture", "topic", "clo", "outcome", "objective",
    "exam", "midterm", "quiz", "assignment", "due", "deadline",
    "schedule", "calendar", "assessment",
}

_SYSTEM_PROMPT = """You are a syllabus parser. Extract structured data from the syllabus text.
Return ONLY valid JSON — no preamble, no markdown fences, no explanation.

Return exactly this structure:
{
  "weekly_topics": [
    {"week_number": 1, "topic": "Introduction to OOP", "description": "Optional detail or null"}
  ],
  "clos": [
    {"clo_id": "CLO1", "text": "Describe the learning outcome", "bloom_level": "Remember"}
  ],
  "key_dates": [
    {"label": "Midterm Exam", "date_text": "Week 7 / March 15", "date_type": "exam"}
  ]
}

Rules:
- date_type must be one of: exam, assignment, deadline, other
- bloom_level must be one of: Remember, Understand, Apply, Analyze, Evaluate, Create — or null if not clear
- If a section is not found, return an empty list [] for it
- Do NOT invent data. Only extract what is explicitly in the text.
"""


@dataclass
class StructuredSyllabusData:
    weekly_topics: List[dict] = field(default_factory=list)
    clos: List[dict] = field(default_factory=list)
    key_dates: List[dict] = field(default_factory=list)


class StructuredSyllabusExtractor:

    def __init__(self, model: str = "gpt-o4-mini") -> None:
        self.client = OpenAI()
        self.model = model

    def extract(self, pdf_path: str) -> StructuredSyllabusData:
        try:
            text = self._select_pages(pdf_path)
            if not text.strip():
                logger.warning("No text extracted from PDF: %s", pdf_path)
                return StructuredSyllabusData()
            return self._call_llm(text)
        except Exception as e:
            logger.warning("Structured extraction failed for %s: %s", pdf_path, e)
            return StructuredSyllabusData()

    # ── Private ───────────────────────────────────────────────────────────────

    def _select_pages(self, pdf_path: str) -> str:
        """Return first 3 pages + any pages containing signal keywords (capped)."""
        reader = PdfReader(pdf_path)
        pages = reader.pages
        per_page_cap = 1000
        total_cap = 6000

        selected: list[str] = []
        seen_indices: set[int] = set()

        def add_page(i: int) -> None:
            if i in seen_indices or i >= len(pages):
                return
            seen_indices.add(i)
            text = (pages[i].extract_text() or "")[:per_page_cap]
            if text.strip():
                selected.append(text)

        for i in range(min(3, len(pages))):
            add_page(i)

        for i in range(len(pages)):
            if i in seen_indices:
                continue
            page_text = (pages[i].extract_text() or "").lower()
            if any(kw in page_text for kw in _SIGNAL_KEYWORDS):
                add_page(i)

        combined = "\n\n".join(selected)
        return combined[:total_cap]

    def _call_llm(self, text: str) -> StructuredSyllabusData:
        response = self.client.chat.completions.create(
            model=self.model,
            max_tokens=1500,
            temperature=0,
            messages=[
                {"role": "system", "content": _SYSTEM_PROMPT},
                {"role": "user", "content": f"SYLLABUS TEXT:\n{text}"},
            ],
        )

        raw = (response.choices[0].message.content or "").strip()

        # Strip markdown fences if model adds them despite instructions
        raw = re.sub(r"^```(?:json)?\s*", "", raw)
        raw = re.sub(r"\s*```$", "", raw)

        try:
            data = json.loads(raw)
        except json.JSONDecodeError as e:
            logger.warning("JSON parse failed in structured extractor: %s\nRaw: %s", e, raw[:300])
            return StructuredSyllabusData()

        return StructuredSyllabusData(
            weekly_topics=data.get("weekly_topics") or [],
            clos=data.get("clos") or [],
            key_dates=data.get("key_dates") or [],
        )