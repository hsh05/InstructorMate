# backend/db/models.py

from sqlalchemy import (
    Column, Integer, String, Text, Boolean, ForeignKey, 
    TIMESTAMP, Time, PrimaryKeyConstraint, Float,
    ForeignKeyConstraint # 👈 FIXED: Added this crucial import!
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
import uuid
from datetime import datetime, timezone
from db.database import Base # Ensure this points to your database.py file correctly!

# ==============================================================================
# ── INSTRUCTOR & AUTHENTICATION ───────────────────────────────────────────────
# ==============================================================================

class Instructor(Base):
    __tablename__ = "instructors"

    instructor_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    email = Column(String(100), unique=True, index=True, nullable=False)
    hashed_password = Column(Text, nullable=False)
    full_name = Column(String(100), nullable=False)
    google_id = Column(Text, unique=True, nullable=True)
    is_verified = Column(Boolean, default=False)
    phone_number = Column(String(20), nullable=True)
    college = Column(String(100), nullable=True)
    department = Column(String(100), nullable=True)
    job_title = Column(String(100), nullable=True)
    university_name = Column(String(100), nullable=True)

    refresh_tokens = relationship("RefreshToken", back_populates="instructor", cascade="all, delete-orphan")
    workspaces = relationship("Workspace", back_populates="instructor", cascade="all, delete-orphan")

class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    token = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    instructor_id = Column(Integer, ForeignKey("instructors.instructor_id", ondelete="CASCADE"), nullable=False)
    expires_at = Column(TIMESTAMP(timezone=True), nullable=False)
    created_at = Column(TIMESTAMP(timezone=True), default=lambda: datetime.now(timezone.utc))

    instructor = relationship("Instructor", back_populates="refresh_tokens")


# ==============================================================================
# ── WORKSPACES ──────────────────────────────────────────────────────
# ==============================================================================

class Workspace(Base):
    __tablename__ = "workspace"

    workspace_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    instructor_id = Column(Integer, ForeignKey("instructors.instructor_id", ondelete="CASCADE"), nullable=False)
    workspace_code = Column(String(7), nullable=False)
    semester = Column(String(10), nullable=False)
    workspace_title = Column(String(100), nullable=False)
    
    chunk_index = Column(Integer, nullable=True)
    embedding = Column(JSONB, nullable=True)
    content = Column(Text, nullable=True)

    instructor = relationship("Instructor", back_populates="workspaces")
    sections = relationship("Section", back_populates="workspace", cascade="all, delete-orphan")
    materials = relationship("Material", back_populates="workspace", cascade="all, delete-orphan")


class Material(Base):
    __tablename__ = "materials"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    workspace_id = Column(Integer, ForeignKey("workspaces.workspace_id", ondelete="CASCADE"), nullable=False)
    file_name = Column(Text, nullable=False)
    file_path = Column(Text, nullable=False)
    material_type = Column(Text, nullable=True)

    workspace = relationship("Workspace", back_populates="materials")


# ==============================================================================
# ── SECTIONS & SCHEDULING ─────────────────────────────────────────────────────
# ==============================================================================

class Section(Base):
    __tablename__ = "sections"

    workspace_id = Column(Integer, ForeignKey("workspaces.workspace_id", ondelete="CASCADE"), primary_key=True)
    section_id = Column(String(5), primary_key=True)
    
    start_time = Column(Time, nullable=True)
    end_time = Column(Time, nullable=True)
    reminder_minutes = Column(Integer, nullable=True)
    day = Column(String(21), nullable=True) 
    location = Column(String(10), nullable=True)

    workspace = relationship("Workspace", back_populates="sections")
    enrollments = relationship("Enrollment", back_populates="section", cascade="all, delete-orphan")


# ==============================================================================
# ── STUDENTS & ROSTERS ────────────────────────────────────────────────────────
# ==============================================================================

class Student(Base):
    __tablename__ = "students"

    student_id = Column(String(9), primary_key=True)
    student_name = Column(String(100), nullable=False)
    facial_encoding = Column(JSONB, nullable=True)
    campus_code = Column(String(2), nullable=True)

    enrollments = relationship("Enrollment", back_populates="student", cascade="all, delete-orphan")


class Enrollment(Base):
    __tablename__ = "enrollments"

    student_id = Column(String(9), ForeignKey("students.student_id", ondelete="CASCADE"), primary_key=True)
    workspace_id = Column(Integer, primary_key=True)
    section_id = Column(String(5), primary_key=True)

    __table_args__ = (
        ForeignKeyConstraint(
            ['workspace_id', 'section_id'],
            ['sections.workspace_id', 'sections.section_id'],
            ondelete="CASCADE"
        ),
    )

    student = relationship("Student", back_populates="enrollments")
    section = relationship("Section", back_populates="enrollments")
    attendances = relationship("Attendance", back_populates="enrollment", cascade="all, delete-orphan")


# ==============================================================================
# ── TRACKING ──────────────────────────────────────────────────────────────────
# ==============================================================================

class Attendance(Base):
    __tablename__ = "attendance"

    student_id = Column(String(9), primary_key=True)
    workspace_id = Column(Integer, primary_key=True)
    section_id = Column(String(5), primary_key=True)
    lecture_no = Column(Integer, primary_key=True)
    
    confidence = Column(String(20), nullable=True)
    status = Column(String(10), nullable=True)

    __table_args__ = (
        ForeignKeyConstraint(
            ['student_id', 'workspace_id', 'section_id'],
            ['enrollments.student_id', 'enrollments.workspace_id', 'enrollments.section_id'],
            ondelete="CASCADE"
        ),
    )

    enrollment = relationship("Enrollment", back_populates="attendances")