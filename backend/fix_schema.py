# fix_duplicate_students.py
from db.database import engine
from sqlalchemy import text

with engine.connect() as conn:
    # Find duplicate students (same workspace_id + email, keep the oldest)
    result = conn.execute(text("""
        DELETE FROM students
        WHERE student_id IN (
            SELECT student_id FROM (
                SELECT student_id,
                       ROW_NUMBER() OVER (
                           PARTITION BY workspace_id, email
                           ORDER BY created_at ASC
                       ) as rn
                FROM students
                WHERE email IS NOT NULL AND email != ''
            ) ranked
            WHERE rn > 1
        )
    """))
    print(f"✅ Removed {result.rowcount} duplicate student rows")

    # Also clean up any student_sections pointing to now-deleted students
    result2 = conn.execute(text("""
        DELETE FROM student_sections
        WHERE student_id NOT IN (SELECT student_id FROM students)
    """))
    print(f"✅ Cleaned {result2.rowcount} dangling student_section links")

    conn.commit()
    print("\n✅ Done — restart backend and re-import your student lists.")