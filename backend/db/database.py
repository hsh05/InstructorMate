# backend/db/database.py

import os
import asyncpg
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from dotenv import load_dotenv

# ==============================================================================
# ── 1. ENVIRONMENT SETUP ──────────────────────────────────────────────────────
# ==============================================================================
load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL is not set in .env")

# ==============================================================================
# ── 2. SQLALCHEMY SETUP (Synchronous - Used for Workspaces/Sections) ──────────
# ==============================================================================
engine = create_engine(DATABASE_URL, connect_args={"sslmode": "require"}, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# ==============================================================================
# ── 3. ASYNCPG SETUP (Asynchronous - Used for Auth/Profiles) ──────────────────
# ==============================================================================
_pool = None

async def get_pool():
    global _pool
    if _pool is None:
        _pool = await asyncpg.create_pool(DATABASE_URL, ssl="require")
    return _pool