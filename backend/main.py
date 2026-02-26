# backend/main.py
#
# FIX (Security): CORS was `allow_origins=["*"]` with `allow_credentials=True`.
# This is actually rejected by browsers (credentialed requests can't use wildcard
# origin). Fixed to use an explicit allowlist from an env variable, falling back
# to localhost for development. Set ALLOWED_ORIGINS env var in production.
#
# FIX: Added proper logging configuration — previously there was no logging setup
# so all logger calls across the app were silently discarded.
#
# FIX: Added startup log so you can confirm the server started cleanly on Render.

import logging
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api.workspace_routes import router as workspace_router
from api.section_routes import router as section_router
from api.student_routes import router as student_router

# ── Logging setup ─────────────────────────────────────────────────────────────
# FIX: Configure logging once at startup so all logger.info/error calls work.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s — %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

# ── CORS origins ──────────────────────────────────────────────────────────────
# FIX: Read from environment so production and dev can differ without code changes.
# Set ALLOWED_ORIGINS="https://your-app.web.app,https://your-app.firebaseapp.com"
_raw_origins = os.getenv("ALLOWED_ORIGINS", "http://localhost:5000,http://localhost:51792")
ALLOWED_ORIGINS: list[str] = [o.strip() for o in _raw_origins.split(",") if o.strip()]

app = FastAPI(title="InstructorMate API", version="1.0.0")

# FIX: explicit origin list instead of wildcard + credentials
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
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

logger.info("InstructorMate API started. Allowed origins: %s", ALLOWED_ORIGINS)