# backend/db/migrations.py
# Run: python -m backend.db.migrations

from db.database import engine, Base
import db.models  # noqa: F401 — registers all models with Base


def run_migrations():
    # Creates only tables that don't exist yet — safe to re-run
    Base.metadata.create_all(bind=engine)
    print("✅ Schema migrations ran successfully.")

    # Backfill normalized tables from old columns (safe to re-run)
    _backfill()
    print("✅ Data backfill complete.")


def _backfill():
    from sqlalchemy import text
    from db.database import SessionLocal
    import logging
    logger = logging.getLogger(__name__)

    db = SessionLocal()
    try:
        # ── 1. student_sections from old section_id column ────────────────────
        try:
            result = db.execute(text("""
                INSERT INTO student_sections (student_id, section_id)
                SELECT s.student_id, s.section_id
                FROM   students s
                WHERE  s.section_id IS NOT NULL
                  AND  s.section_id <> ''
                  AND  EXISTS (
                      SELECT 1 FROM sections sc WHERE sc.section_id = s.section_id
                  )
                ON CONFLICT (student_id, section_id) DO NOTHING
            """))
            db.commit()
            print(f"   student_sections: {result.rowcount} rows backfilled")
        except Exception as e:
            db.rollback()
            print(f"   student_sections skipped: {e}")

        # ── 2. section_days from old days text column ─────────────────────────
        try:
            rows = db.execute(text(
                "SELECT section_id, days FROM sections "
                "WHERE days IS NOT NULL AND days <> ''"
            )).fetchall()
            inserted = 0
            for section_id, days_str in rows:
                for day in days_str.split(","):
                    day = day.strip()
                    if not day:
                        continue
                    db.execute(text("""
                        INSERT INTO section_days (section_id, day)
                        VALUES (:sid, :day)
                        ON CONFLICT DO NOTHING
                    """), {"sid": section_id, "day": day})
                    inserted += 1
            db.commit()
            print(f"   section_days: {inserted} rows backfilled")
        except Exception as e:
            db.rollback()
            print(f"   section_days skipped: {e}")

        # ── 3. office_hours table from old text column ────────────────────────
        try:
            col_exists = db.execute(text("""
                SELECT 1 FROM information_schema.columns
                WHERE table_name = 'workspaces' AND column_name = 'office_hours'
            """)).first()

            if col_exists:
                rows = db.execute(text(
                    "SELECT workspace_id, office_hours FROM workspaces "
                    "WHERE office_hours IS NOT NULL AND office_hours <> ''"
                )).fetchall()
                inserted = 0
                for workspace_id, encoded in rows:
                    for slot in encoded.split(";"):
                        slot = slot.strip()
                        if not slot:
                            continue
                        parts = slot.split("|")
                        days_str = parts[0].strip()
                        start    = parts[1].strip() if len(parts) > 1 else ""
                        end      = parts[2].strip() if len(parts) > 2 else ""
                        for day in days_str.split(","):
                            day = day.strip()
                            if not day:
                                continue
                            db.execute(text("""
                                INSERT INTO office_hours
                                    (workspace_id, day, start_time, end_time)
                                VALUES (:wid, :day, :start, :end)
                                ON CONFLICT DO NOTHING
                            """), {"wid": workspace_id, "day": day,
                                   "start": start, "end": end})
                            inserted += 1
                db.commit()
                print(f"   office_hours: {inserted} rows backfilled")
            else:
                print("   office_hours: no old column found, skipping")
        except Exception as e:
            db.rollback()
            print(f"   office_hours skipped: {e}")

    finally:
        db.close()


if __name__ == "__main__":
    run_migrations()