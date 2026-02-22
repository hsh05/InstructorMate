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