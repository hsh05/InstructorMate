# backend/main.py

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api.workspace_routes import router as workspace_router
from api.section_routes import router as section_router
from api.student_routes import router as student_router

app = FastAPI()

# ---- CORS (for Flutter web) ----
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---- Register Routers ----
app.include_router(workspace_router)
app.include_router(section_router)
app.include_router(student_router)