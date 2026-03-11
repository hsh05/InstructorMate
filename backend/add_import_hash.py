# add_import_hash.py for student list
from db.database import engine
from sqlalchemy import text

with engine.connect() as conn:
    conn.execute(text("""
        ALTER TABLE sections 
        ADD COLUMN IF NOT EXISTS last_import_hash TEXT DEFAULT ''
    """))
    conn.commit()
    print("✅ Added last_import_hash to sections table")