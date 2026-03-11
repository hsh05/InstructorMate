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
    office_number: Optional[str] = None

class ProfileUpdateRequest(BaseModel):
    full_name: Optional[str] = None
    phone_number: Optional[str] = None
    university_name: Optional[str] = None
    college: Optional[str] = None
    department: Optional[str] = None
    job_title: Optional[str] = None
    office_number: Optional[str] = None

# ─── GET /profile/{user_id} ───────────────────────────────────────────────────
@router.get("/{user_id}", response_model=ProfileResponse)
async def get_profile(user_id: str, db=Depends(get_db)):
    row = await db.fetchrow(
        """
        SELECT
            u.id::text  AS user_id,
            u.full_name,
            u.email,
            p.phone_number,
            p.university_name,
            p.college,
            p.department,
            p.job_title,
            p.office_number
        FROM users u
        LEFT JOIN instructor_profiles p ON p.user_id = u.id
        WHERE u.id = $1::uuid
        """,
        user_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail="User not found")
    return dict(row)


# ─── PUT /profile/{user_id} ───────────────────────────────────────────────────
@router.put("/{user_id}", response_model=ProfileResponse)
async def update_profile(
    user_id: str,
    body: ProfileUpdateRequest,
    db=Depends(get_db),
):
    user = await db.fetchrow("SELECT id FROM users WHERE id = $1::uuid", user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if body.full_name is not None:
        await db.execute(
            "UPDATE users SET full_name = $1 WHERE id = $2::uuid",
            body.full_name,
            user_id,
        )

    await db.execute(
        """
        INSERT INTO instructor_profiles (
            user_id, phone_number, university_name,
            college, department, job_title, office_number, updated_at
        )
        VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, NOW())
        ON CONFLICT (user_id) DO UPDATE SET
            phone_number    = COALESCE(EXCLUDED.phone_number,    instructor_profiles.phone_number),
            university_name = COALESCE(EXCLUDED.university_name, instructor_profiles.university_name),
            college         = COALESCE(EXCLUDED.college,         instructor_profiles.college),
            department      = COALESCE(EXCLUDED.department,      instructor_profiles.department),
            job_title       = COALESCE(EXCLUDED.job_title,       instructor_profiles.job_title),
            office_number   = COALESCE(EXCLUDED.office_number,   instructor_profiles.office_number),
            updated_at      = NOW()
        """,
        user_id,
        body.phone_number,
        body.university_name,
        body.college,
        body.department,
        body.job_title,
        body.office_number,
    )

    return await get_profile(user_id, db)