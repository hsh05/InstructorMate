import os
import pandas as pd
from db.database import engine
from sqlalchemy import text

INPUT_FOLDER = "input_student_list"


def list_files():
    files = [
        f for f in os.listdir(INPUT_FOLDER)
        if f.endswith((".csv", ".xlsx", ".xls"))
    ]

    if not files:
        print("No valid files found.")
        return []

    print("\nAvailable files:")
    for i, f in enumerate(files, 1):
        print(f"{i}) {f}")

    return files


def choose_files(files):
    choice = input("\nEnter file numbers (comma separated) or 'all': ").strip()

    if choice.lower() == "all":
        return files

    selected = []
    for idx in choice.split(","):
        try:
            selected.append(files[int(idx.strip()) - 1])
        except:
            print(f"Invalid choice: {idx}")

    return selected


def read_file(filepath):
    if filepath.endswith(".csv"):
        return pd.read_csv(filepath)

    elif filepath.endswith((".xlsx", ".xls")):
        return pd.read_excel(filepath)

    else:
        raise ValueError("Unsupported file format")


def insert_students_from_file(filepath):
    df = read_file(filepath)
    df.columns = [c.strip().lower() for c in df.columns]

    required_cols = [
        "student_id", "student_name",
        "campus_code", "campus_desc",
        "college_code", "college_desc",
        "major_code", "major_desc"
    ]

    for col in required_cols:
        if col not in df.columns:
            raise ValueError(f"Missing column: {col}")

    inserted = 0
    skipped = 0

    # engine.begin() automatically starts a transaction and commits it when done!
    with engine.begin() as conn:
        for _, row in df.iterrows():
            student_id = str(row["student_id"]).strip()

            # 1. Use text() and named parameters (:student_id) to check for existing student
            check_query = text("SELECT 1 FROM student WHERE student_id = :student_id")
            result = conn.execute(check_query, {"student_id": student_id})

            if result.fetchone():
                skipped += 1
                continue

            # 2. Use named parameters for the insert as well
            insert_query = text("""
                INSERT INTO student (
                    student_id,
                    student_name,
                    campus_code,
                    campus_desc,
                    college_code,
                    college_desc,
                    major_code,
                    major_desc,
                    facial_encoding
                )
                VALUES (
                    :student_id,
                    :student_name,
                    :campus_code,
                    :campus_desc,
                    :college_code,
                    :college_desc,
                    :major_code,
                    :major_desc,
                    NULL
                )
            """)

            # 3. Execute directly on the connection, passing a dictionary of the values
            conn.execute(insert_query, {
                "student_id": student_id,
                "student_name": str(row["student_name"]).strip(),
                "campus_code": str(row["campus_code"]).strip(),
                "campus_desc": str(row["campus_desc"]).strip(),
                "college_code": int(row["college_code"]) if not pd.isna(row["college_code"]) else None,
                "college_desc": str(row["college_desc"]).strip(),
                "major_code": str(row["major_code"]).strip(),
                "major_desc": str(row["major_desc"]).strip(),
            })
            inserted += 1

    print(f"\nProcessed {os.path.basename(filepath)}")
    print(f"Inserted: {inserted}")
    print(f"Skipped: {skipped}")


def main():
    files = list_files()
    if not files:
        return

    selected_files = choose_files(files)

    for f in selected_files:
        path = os.path.join(INPUT_FOLDER, f)
        insert_students_from_file(path)


if __name__ == "__main__":
    main()