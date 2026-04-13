import os
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from dotenv import load_dotenv

# Load the secret URL from the .env file
load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL")

# Connect to Neon Postgres
# Neon provides a pooled connection, which is great for serverless
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
import asyncpg
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")  # Neon connection string

_pool = None

async def get_pool():
    global _pool
    if _pool is None:
        _pool = await asyncpg.create_pool(DATABASE_URL, ssl="require")
    return _pool

async def create_tables():
    pool = await get_pool()
    async with pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                email TEXT UNIQUE NOT NULL,
                hashed_password TEXT,           -- NULL for OAuth-only users
                full_name TEXT,
                google_id TEXT UNIQUE,          -- NULL for email/password users
                avatar_url TEXT,
                is_verified BOOLEAN DEFAULT FALSE,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS refresh_tokens (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                token TEXT UNIQUE NOT NULL,
                expires_at TIMESTAMPTZ NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
        """)
