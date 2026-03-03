# backend/db/database.py

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from dotenv import load_dotenv
import os

load_dotenv()

DATABASE_URL = os.getenv("postgresql://neondb_owner:npg_89WpUScBKVao@ep-dawn-scene-agqmedcc-pooler.c-2.eu-central-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require")
if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL is not set in .env")

# Neon requires SSL
engine = create_engine(
    DATABASE_URL,
    connect_args={"sslmode": "require"},
    pool_pre_ping=True,   # drops stale connections automatically
)

SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)

Base = declarative_base()


def get_db():
    """FastAPI dependency — yields a session and closes it after the request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()