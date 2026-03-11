# backend/main.py

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api.workspace_routes import router as workspace_router
from api.section_routes import router as section_router
from api.student_routes import router as student_router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s — %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

app = FastAPI(title="InstructorMate API", version="1.0.0")

# FIX: allow_origins=["*"] + allow_credentials=True is invalid per the CORS spec.
# Browsers silently block ALL credentialed requests to a wildcard origin —
# this is why PATCH (office hours save), POST (sections), DELETE all fail
# on the web client with a network error, not a 4xx.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,  # ← FIX: was True, illegal with wildcard origin
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def health():
    return {"status": "ok", "service": "InstructorMate API"}

app.include_router(workspace_router)
app.include_router(section_router)
app.include_router(student_router)

logger.info("InstructorMate API started.")