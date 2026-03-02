# backend/main.py

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api.workspace_routes import router as workspace_router
from api.section_routes import router as section_router
from api.student_routes import router as student_router

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s — %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

# ── App ───────────────────────────────────────────────────────────────────────
app = FastAPI(title="InstructorMate API", version="1.0.0")

# FIX 1: allow_origins=["*"] + allow_credentials=True is invalid — browsers
# reject credentialed requests to a wildcard origin with a CORS error.
# Fix: set allow_credentials=False so wildcard is legal.
#
# FIX 2: removed the logger.info("... ALLOWED_ORIGINS") line at the bottom
# that referenced an undefined variable, crashing the server on every startup.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Health check ──────────────────────────────────────────────────────────────
@app.get("/")
def health():
    return {"status": "ok", "service": "InstructorMate API"}

# ── Routers ───────────────────────────────────────────────────────────────────
app.include_router(workspace_router)
app.include_router(section_router)
app.include_router(student_router)

logger.info("InstructorMate API started.")