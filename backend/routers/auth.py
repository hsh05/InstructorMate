import os
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import APIRouter, Depends, HTTPException, Header
from pydantic import BaseModel, EmailStr
from typing import Optional

from database import get_pool
from auth_utils import (
    hash_password, verify_password,
    create_access_token, create_refresh_token, decode_access_token,
    REFRESH_TOKEN_EXPIRE_DAYS
)

router = APIRouter()

GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID")
GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET")
GOOGLE_REDIRECT_URI = os.getenv("GOOGLE_REDIRECT_URI")


# ── Schemas ───────────────────────────────────────────────────────────────────

class SignUpRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: Optional[str] = None

class LoginRequest(BaseModel):
    email: EmailStr
    password: str

class GoogleCallbackRequest(BaseModel):
    code: str

class RefreshRequest(BaseModel):
    refresh_token: str


# ── Helpers ───────────────────────────────────────────────────────────────────

async def get_current_user(authorization: str = Header(...)):
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    token = authorization[7:]
    payload = decode_access_token(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Token expired or invalid")
    return payload

async def issue_tokens(user_id: str, email: str, pool) -> dict:
    access_token = create_access_token(user_id, email)
    refresh_token = create_refresh_token()
    expires_at = datetime.now(timezone.utc) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)

    async with pool.acquire() as conn:
        await conn.execute(
            """INSERT INTO refresh_tokens (user_id, token, expires_at)
               VALUES ($1, $2, $3)""",
            user_id, refresh_token, expires_at
        )

    return {
        "user_id": user_id,          # ← added so Flutter can use it directly
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
    }


# ── Email / Password ──────────────────────────────────────────────────────────

@router.post("/signup")
async def signup(body: SignUpRequest):
    pool = await get_pool()
    async with pool.acquire() as conn:
        existing = await conn.fetchrow("SELECT id FROM users WHERE email = $1", body.email)
        if existing:
            raise HTTPException(status_code=409, detail="Email already registered")

        hashed = hash_password(body.password)
        user = await conn.fetchrow(
            """INSERT INTO users (email, hashed_password, full_name)
               VALUES ($1, $2, $3) RETURNING id, email""",
            body.email, hashed, body.full_name
        )

    return await issue_tokens(str(user["id"]), user["email"], pool)


@router.post("/login")
async def login(body: LoginRequest):
    pool = await get_pool()
    async with pool.acquire() as conn:
        user = await conn.fetchrow(
            "SELECT id, email, hashed_password FROM users WHERE email = $1", body.email
        )

    if not user or not user["hashed_password"]:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not verify_password(body.password, user["hashed_password"]):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    return await issue_tokens(str(user["id"]), user["email"], pool)


# ── Google OAuth ──────────────────────────────────────────────────────────────

@router.post("/google/callback")
async def google_callback(body: GoogleCallbackRequest):
    async with httpx.AsyncClient() as client:
        token_res = await client.post("https://oauth2.googleapis.com/token", data={
            "code": body.code,
            "client_id": GOOGLE_CLIENT_ID,
            "client_secret": GOOGLE_CLIENT_SECRET,
            "redirect_uri": GOOGLE_REDIRECT_URI,
            "grant_type": "authorization_code",
        })
        if token_res.status_code != 200:
            raise HTTPException(status_code=400, detail="Failed to exchange Google code")

        google_tokens = token_res.json()
        id_token = google_tokens.get("id_token")

        verify_res = await client.get(
            f"https://oauth2.googleapis.com/tokeninfo?id_token={id_token}"
        )
        if verify_res.status_code != 200:
            raise HTTPException(status_code=400, detail="Invalid Google ID token")

        info = verify_res.json()
        google_id = info["sub"]
        email = info["email"]
        full_name = info.get("name")
        avatar_url = info.get("picture")

    pool = await get_pool()
    async with pool.acquire() as conn:
        user = await conn.fetchrow(
            """INSERT INTO users (email, google_id, full_name, avatar_url, is_verified)
               VALUES ($1, $2, $3, $4, TRUE)
               ON CONFLICT (email) DO UPDATE
                 SET google_id = EXCLUDED.google_id,
                     avatar_url = EXCLUDED.avatar_url,
                     updated_at = NOW()
               RETURNING id, email""",
            email, google_id, full_name, avatar_url
        )

    return await issue_tokens(str(user["id"]), user["email"], pool)


# ── Token Refresh ─────────────────────────────────────────────────────────────

@router.post("/refresh")
async def refresh(body: RefreshRequest):
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """SELECT rt.user_id, rt.expires_at, u.email
               FROM refresh_tokens rt
               JOIN users u ON u.id = rt.user_id
               WHERE rt.token = $1""",
            body.refresh_token
        )
        if not row:
            raise HTTPException(status_code=401, detail="Invalid refresh token")
        if row["expires_at"] < datetime.now(timezone.utc):
            raise HTTPException(status_code=401, detail="Refresh token expired")

        await conn.execute("DELETE FROM refresh_tokens WHERE token = $1", body.refresh_token)

    return await issue_tokens(str(row["user_id"]), row["email"], pool)


# ── Me ────────────────────────────────────────────────────────────────────────

@router.get("/me")
async def me(current_user: dict = Depends(get_current_user)):
    pool = await get_pool()
    async with pool.acquire() as conn:
        user = await conn.fetchrow(
            "SELECT id, email, full_name, avatar_url, is_verified, created_at FROM users WHERE id = $1",
            current_user["sub"]
        )
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return dict(user)


# ── Logout ────────────────────────────────────────────────────────────────────

@router.post("/logout")
async def logout(body: RefreshRequest):
    pool = await get_pool()
    async with pool.acquire() as conn:
        await conn.execute("DELETE FROM refresh_tokens WHERE token = $1", body.refresh_token)
    return {"message": "Logged out"}