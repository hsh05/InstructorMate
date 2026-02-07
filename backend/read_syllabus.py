from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path
from typing import List

from pypdf import PdfReader


# ---------- Data model ----------

@dataclass(frozen=True)

class PdfChunk:
    """Represents extracted text from a single PDF page."""
    page: int
    text: str


# ---------- Reader (PDF -> chunks) ---------- (single responsibility class --> finds pdf and extracts the text)

class SyllabusPdfReader:
    """Reads a syllabus PDF from an input directory and extracts text page-by-page."""

    def __init__(self, input_dir: str = "syllabus_files") -> None:   # stores where pdf is located --> in the file (syllabus_files)
        self.input_dir = Path(input_dir)

    def find_first_pdf(self) -> Path:
        """Find the first PDF file in the input directory."""
        if not self.input_dir.exists():
            raise FileNotFoundError(f"Input folder not found: {self.input_dir.resolve()}")

        pdf_files = sorted(self.input_dir.glob("*.pdf"))
        if not pdf_files:
            raise FileNotFoundError(
                f"No PDF found in {self.input_dir.resolve()}. Put your syllabus PDF there."
            )
        return pdf_files[0]

    def extract_chunks(self, pdf_path: Path) -> List[PdfChunk]:   #reads pdf using pdfReader
        """Extract text from each page into PdfChunk objects (skips empty pages)."""
        if not pdf_path.exists():
            raise FileNotFoundError(f"PDF not found: {pdf_path.resolve()}")

        reader = PdfReader(str(pdf_path))
        chunks: List[PdfChunk] = []

        for page_index, page in enumerate(reader.pages, start=1): #start from page =1 
            page_text = (page.extract_text() or "").strip() # pulls text and (strip) removes the whitespaces 
            if page_text:
                chunks.append(PdfChunk(page=page_index, text=page_text))

        return chunks #return list of pdf chuncks 

    def preview(self, chunks: List[PdfChunk], max_chars: int = 800) -> str:
        """Return a short preview for the terminal."""
        combined = []
        for c in chunks[:3]:  # show first 3 pages only in preview
            combined.append(f"\n--- Page {c.page} ---\n{c.text}")
        preview_text = "\n".join(combined)
        return preview_text[:max_chars]


# ---------- Exporter (chunks -> CSV) ----------

class SyllabusCsvExporter:     
    """
    Exports syllabus chunks to CSV.
    This is your deliverable: a clean structured file Python generated from the PDF.
    """

    def __init__(self, output_dir: str = "output", csv_name: str = "syllabus.csv") -> None: #return the csv in folder output and name it 
        self.output_dir = Path(output_dir)
        self.csv_path = self.output_dir / csv_name

    def ensure_output_dir(self) -> None:
        """Create output directory if it doesn't exist."""
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def export(self, chunks: List[PdfChunk]) -> Path:
        """
        Write chunks to CSV with columns:
        chunk_id, page, text
        """
        self.ensure_output_dir()

        with self.csv_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=["chunk_id", "page", "text"])
            writer.writeheader()

            for i, ch in enumerate(chunks, start=1):
                writer.writerow({
                    "chunk_id": i,
                    "page": ch.page,
                    "text": ch.text
                })

        return self.csv_path


class SyllabusPipeline:  # Controller --> connects reading pdf and exportD csv into output folder -> DEPENDENCY INJECTION (OBJECTS ARE INJECTED FROM OUSTIDE) AND SRP
    """
    Orchestrates the whole step:         # ONLY COORDINATES THESE (FINDING PDF,READ IT, EXTRACT IT, EXPORT TO CSV) STEPS NOT DO ALL OF THEM
    PDF -> extract chunks -> write CSV  
    """

    def __init__(self, reader: SyllabusPdfReader, exporter: SyllabusCsvExporter) -> None:
        self.reader = reader
        self.exporter = exporter

    def run(self) -> Path:
        pdf_path = self.reader.find_first_pdf()
        print(f"📄 Found PDF: {pdf_path.name}")

        chunks = self.reader.extract_chunks(pdf_path)
        if not chunks:
            raise RuntimeError("No text extracted. PDF may be scanned; OCR would be needed.")

        print(f"✅ Extracted {len(chunks)} pages with text.")
        print("\nPreview:")
        print(self.reader.preview(chunks))

        csv_path = self.exporter.export(chunks)
        print(f"\n✅ Saved CSV to: {csv_path.resolve()}")
        return csv_path


def main() -> None:
    reader = SyllabusPdfReader(input_dir="syllabus_files")
    exporter = SyllabusCsvExporter(output_dir="output", csv_name="syllabus.csv")  #EXPORTS the csv into output folder
    pipeline = SyllabusPipeline(reader, exporter)                        #DEPENDENCY INJECTION --> required components are provided to a class rather than created inside it,
    pipeline.run()


if __name__ == "__main__":
    main()
