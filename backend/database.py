import os
import asyncpg
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from dotenv import load_dotenv

# ==============================================================================
# ── 1. ENVIRONMENT SETUP ──────────────────────────────────────────────────────
# ==============================================================================
# Load the secret URL from the .env file exactly once
load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL")


# ==============================================================================
# ── 2. SQLALCHEMY SETUP (Synchronous - Used for Workspaces/Sections) ──────────
# ==============================================================================
# Connect to Neon Postgres with a pooled connection
engine = create_engine(DATABASE_URL, pool_pre_ping=True)

# This creates a "Session" which we use to query the database
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# All your future database tables will inherit from this Base class
Base = declarative_base()

# A helper function to grab a database connection when someone makes an API request
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