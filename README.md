
---

## Core Features
- Upload syllabus directly in **PDF format**
- Extract text page-by-page (in-memory processing)
- Convert pages into structured content chunks
- Retrieve only **relevant syllabus sections**
- Generate **context-grounded answers**
- Return **answer with source references**
- User-friendly **Flutter-based interface**
- No database usage (CSV / memory-based)

---

## Key Design Principles
- **Single Responsibility Principle (SRP)**: Each class performs one task
- **Dependency Injection (DI)**: Components are injected, not hard-coded
- **Separation of Concerns**: UI, backend, retrieval, and LLM logic are decoupled
- **Prompt Safety**: LLM answers only from provided syllabus content

---

## Technology Stack
**Backend**
- Python 3.12+
- FastAPI
- pypdf
- OpenAI API
- Pydantic
- Uvicorn

**Frontend**
- Flutter
- Dart
- file_picker
- http

---

## How to Run

### Backend
```bash
pip install fastapi uvicorn pypdf openai python-dotenv
uvicorn server:app --host 0.0.0.0 --port 8000
uvicorn main:app --reload

git branch
git switch merna-syllabus-ui
git add .
git status
git commit -m "backend+frontend oragizing"
git push origin merna-syllabus-ui
git push deploy merna-syllabus-ui



