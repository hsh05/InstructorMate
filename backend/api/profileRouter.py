from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import Optional
import asyncpg
import os

router = APIRouter(prefix="/profile", tags=["Profile"])

# ─── DB connection ────────────────────────────────────────────────────────────
async def get_db():
    conn = await asyncpg.connect(os.environ["DATABASE_URL"])
    try:
        yield conn
    finally:
        await conn.close()

# ─── Schemas ──────────────────────────────────────────────────────────────────
class ProfileResponse(BaseModel):
    user_id: str
    full_name: str
    email: str
    phone_number: Optional[str] = None
    university_name: Optional[str] = None
    college: Optional[str] = None
    department: Optional[str] = None
    job_title: Optional[str] = None

class ProfileUpdateRequest(BaseModel):
    full_name: Optional[str] = None
    phone_number: Optional[str] = None
    university_name: Optional[str] = None
    college: Optional[str] = None
    department: Optional[str] = None
    job_title: Optional[str] = None

# ─── GET /profile/{user_id} ───────────────────────────────────────────────────
@router.get("/{user_id}", response_model=ProfileResponse)
async def get_profile(user_id: str, db=Depends(get_db)):
    row = await db.fetchrow(
        """
        SELECT
            instructor_id::text AS user_id,
            full_name,
            email,
            phone_number,
            university_name,
            college,
            department,
            job_title
        FROM instructor
        WHERE instructor_id = $1
        """,
        int(user_id), # Cast to int for Neon DB
    )
    if not row:
        raise HTTPException(status_code=404, detail="Instructor not found")
    return dict(row)


# ─── PUT /profile/{user_id} ───────────────────────────────────────────────────
@router.put("/{user_id}", response_model=ProfileResponse)
async def update_profile(
    user_id: str,
    body: ProfileUpdateRequest,
    db=Depends(get_db),
):
    instructor_id = int(user_id)
    
    # Check if instructor exists
    user = await db.fetchrow("SELECT instructor_id FROM instructor WHERE instructor_id = $1", instructor_id)
    if not user:
        raise HTTPException(status_code=404, detail="Instructor not found")

    # Update all fields in a single query using COALESCE (keeps old data if new data is None)
    await db.execute(
        """
        UPDATE instructor SET
            full_name = COALESCE($1, full_name),
            phone_number = COALESCE($2, phone_number),
            university_name = COALESCE($3, university_name),
            college = COALESCE($4, college),
            department = COALESCE($5, department),
            job_title = COALESCE($6, job_title)
        WHERE instructor_id = $7
        """,
        body.full_name,
        body.phone_number,
        body.university_name,
        body.college,
        body.department,
        body.job_title,
        instructor_id
    )

    return await get_profile(user_id, db)