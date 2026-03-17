#!/usr/bin/env python3
"""
Migration: rename `pdf_hash` column to `file_hash` in workspaces table.

The old name was misleading since the app now accepts both PDF and DOCX files.

Run from backend folder:
    python migrate_rename_pdf_hash.py

Safe to run multiple times — checks if the column already exists.
"""

import os
import sys
from pathlib import Path

# ── Load .env automatically ───────────────────────────────────────────────────
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
    sys.exit(1)

print("Connecting to database...")
engine = create_engine(DATABASE_URL)

with engine.connect() as conn:
    inspector = inspect(engine)
    columns = [c["name"] for c in inspector.get_columns("workspaces")]

    if "file_hash" in columns and "pdf_hash" not in columns:
        print("✅  Column already renamed to 'file_hash' — nothing to do.")
    elif "pdf_hash" in columns:
        conn.execute(
            text("ALTER TABLE workspaces RENAME COLUMN pdf_hash TO file_hash")
        )
        conn.commit()
        print("✅  Renamed 'pdf_hash' → 'file_hash' in workspaces table.")
        print()
        print("Next steps:")
        print("  1. Also rename backend/services/pdf_hash_service.py → file_hash_service.py")
        print("  2. Restart your backend server.")
    else:
        print("❌  Neither 'pdf_hash' nor 'file_hash' column found. Check your table.")