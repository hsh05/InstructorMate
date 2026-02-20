from typing import Dict
from pypdf import PdfReader
from docx import Document
import io


class FileParserService:

    def extract_text(self, filename: str, content: bytes) -> str:
        if filename.lower().endswith(".pdf"):
            return self._parse_pdf(content)

        if filename.lower().endswith(".docx"):
            return self._parse_docx(content)

        if filename.lower().endswith(".txt"):
            return content.decode("utf-8")

        raise ValueError("Unsupported file format")

    def _parse_pdf(self, content: bytes) -> str:
        reader = PdfReader(io.BytesIO(content))
        text = ""
        for page in reader.pages:
            text += page.extract_text() or ""
        return text

    def _parse_docx(self, content: bytes) -> str:
        doc = Document(io.BytesIO(content))
        return "\n".join(p.text for p in doc.paragraphs)
