# backend/db/database.py

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from dotenv import load_dotenv #loads env valriables from .env
import os #reads env variables 

load_dotenv()
#ORM model is Python class representing a database table

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL is not set in .env")

# Neon requires SSL
engine = create_engine( #This creates the connection pool and database interface, this does not connect yet.
    DATABASE_URL,
    connect_args={"sslmode": "require"},#Connection is encrypted, required for cloud Postgres providers
    pool_pre_ping=True,   # drops stale connections automatically, before using a connection, SQLAlchemy checks if it’s still alive.
)

SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)

Base = declarative_base() #All your models inherit from this:


def get_db():
    """FastAPI dependency — yields a session and closes it after the request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()