# backend/db/migrations.py
# Run: python -m backend.db.migrations

from db.database import engine, Base
import db.models # noqa: F401 — registers all models with Base


def run_migrations():
    # Creates only tables that don't exist yet — safe to re-run
    Base.metadata.create_all(bind=engine)
    print("✅ All migrations ran successfully.")


if __name__ == "__main__":
    run_migrations()