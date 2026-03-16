#!/usr/bin/env python3
"""
Migration: add `embedding` column to syllabus_chunks table.

Run from your backend folder:
    python migrate_add_embeddings.py

Loads DATABASE_URL from your .env file automatically — no manual
environment variable setup needed.
"""

import os
import sys
from pathlib import Path

# ── Load .env automatically ───────────────────────────────────────────────────
# Walk up from this file looking for a .env file (backend/.env or root/.env)
_here = Path(__file__).resolve().parent
for _candidate in [_here, _here.parent, _here.parent.parent]:
    _env_file = _candidate / ".env"
    if _env_file.exists():
        with open(_env_file) as _f:
            for _line in _f:
                _line = _line.strip()
                if _line and not _line.startswith("#") and "=" in _line:
                    _k, _, _v = _line.partition("=")
                    os.environ.setdefault(_k.strip(), _v.strip())
        print(f"Loaded .env from {_env_file}")
        break

from sqlalchemy import create_engine, inspect, text

DATABASE_URL = os.environ.get("DATABASE_URL")
if not DATABASE_URL:
    print("❌  DATABASE_URL not found in environment or .env file.")
    print("    Make sure your .env contains:  DATABASE_URL=postgresql://...")
    sys.exit(1)

print("Connecting to database...")
engine = create_engine(DATABASE_URL)

with engine.connect() as conn:
    inspector = inspect(engine)
    columns = [c["name"] for c in inspector.get_columns("syllabus_chunks")]

    if "embedding" in columns:
        print("✅  Column 'embedding' already exists — nothing to do.")
    else:
        col_type = "JSONB" if engine.dialect.name == "postgresql" else "JSON"
        conn.execute(
            text(f"ALTER TABLE syllabus_chunks ADD COLUMN embedding {col_type}")
        )
        conn.commit()
        print(f"✅  Added 'embedding' ({col_type}) column to syllabus_chunks.")
        print()
        print("Next steps:")
        print("  1. Restart your backend server.")
        print("  2. New workspaces will get embeddings automatically on upload.")
        print("  3. Existing workspaces fall back to keyword search until re-uploaded.")