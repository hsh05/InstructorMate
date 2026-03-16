#!/usr/bin/env python3
"""
Migration: add `embedding` column to syllabus_chunks table.

Run once against your database:
    python migrate_add_embeddings.py

Safe to run multiple times — checks if the column already exists before
adding it. After running, re-upload any existing workspaces (or call the
/workspaces/{id}/reembed endpoint if you add one later) to generate
embeddings for legacy chunks. Until embeddings are generated, the
EmbeddingRetriever automatically falls back to keyword search.
"""

import os
import sys

from sqlalchemy import create_engine, inspect, text

DATABASE_URL = os.environ.get("DATABASE_URL")
if not DATABASE_URL:
    print("❌  DATABASE_URL environment variable is not set.")
    sys.exit(1)

engine = create_engine(DATABASE_URL)

with engine.connect() as conn:
    inspector = inspect(engine)
    columns = [c["name"] for c in inspector.get_columns("syllabus_chunks")]

    if "embedding" in columns:
        print("✅  Column 'embedding' already exists in syllabus_chunks — nothing to do.")
    else:
        # JSON / JSONB column — use JSONB on Postgres for better performance
        dialect = engine.dialect.name
        col_type = "JSONB" if dialect == "postgresql" else "JSON"

        conn.execute(
            text(f"ALTER TABLE syllabus_chunks ADD COLUMN embedding {col_type}")
        )
        conn.commit()
        print(f"✅  Added 'embedding' ({col_type}) column to syllabus_chunks.")
        print()
        print("Next steps:")
        print("  1. Restart your backend server.")
        print("  2. New workspaces will automatically get embeddings on upload.")
        print("  3. Existing workspaces will use keyword search until re-uploaded.")