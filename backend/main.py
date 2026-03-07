from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routers import auth
from database import create_tables
from dotenv import load_dotenv
import os

load_dotenv()

app = FastAPI(title="SaaS Auth API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Replace with your Flutter app's origin in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup():
    try:
        await create_tables()
        print("Database connected and tables ensured.")
    except Exception as e:
        print(f"⚠️ Failed to connect to database on startup: {e}")

app.include_router(auth.router, prefix="/auth", tags=["auth"])

@app.get("/health")
def health():
    return {"status": "ok"}