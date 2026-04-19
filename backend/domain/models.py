# backend/db/models.py

from sqlalchemy import (
    Column, Integer, String, Text, Boolean, ForeignKey, 
    TIMESTAMP, Time, Float, ForeignKeyConstraint, Date
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
import uuid
from datetime import datetime, timezone
from db.database import Base 

# ==============================================================================
# ── INSTRUCTOR & AUTHENTICATION ───────────────────────────────────────────────
# ==============================================================================

class Instructor(Base):
    __tablename__ = "instructor"
    __table_args__ = {'extend_existing': True}

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

    # 👉 THE FIX: Dynamically injects the exact module path to stop registry collisions!
    refresh_tokens = relationship(f"{__name__}.RefreshToken", back_populates="instructor", cascade="all, delete-orphan")
    workspaces = relationship(f"{__name__}.Workspace", back_populates="instructor", cascade="all, delete-orphan")

class RefreshToken(Base):
    __tablename__ = "refresh_tokens"
    __table_args__ = {'extend_existing': True}

    token = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    instructor_id = Column(Integer, ForeignKey("instructor.instructor_id", ondelete="CASCADE"), nullable=False)
    expires_at = Column(TIMESTAMP(timezone=True), nullable=False)
    created_at = Column(TIMESTAMP(timezone=True), default=lambda: datetime.now(timezone.utc))

    instructor = relationship(f"{__name__}.Instructor", back_populates="refresh_tokens")


# ==============================================================================
# ── WORKSPACES ──────────────────────────────────────────────────────
# ==============================================================================

class Workspace(Base):
    __tablename__ = "workspace"
    __table_args__ = {'extend_existing': True}

    workspace_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    instructor_id = Column(Integer, ForeignKey("instructor.instructor_id", ondelete="CASCADE"), nullable=False)
    
    course_code = Column(String(20), nullable=True) 
    semester = Column(String(50), nullable=True)
    course_title = Column(String(255), nullable=True)
    
    chunk_index = Column(Integer, nullable=True)
    embedding = Column(JSONB, nullable=True)
    content = Column(Text, nullable=True)

    start_date = Column(Date, nullable=True)
    end_date = Column(Date, nullable=True)
    
    weekly_schedule = Column(Text, nullable=True)
    assessments_schedule = Column(Text, nullable=True)

    instructor = relationship(f"{__name__}.Instructor", back_populates="workspaces")
    sections = relationship(f"{__name__}.Section", back_populates="workspace", cascade="all, delete-orphan")
    materials = relationship(f"{__name__}.Material", back_populates="workspace", cascade="all, delete-orphan")

# ==============================================================================
# ── SECTIONS & SCHEDULING ─────────────────────────────────────────────────────
# ==============================================================================

class Section(Base):
    __tablename__ = "sections"
    __table_args__ = {'extend_existing': True}

    workspace_id = Column(Integer, ForeignKey("workspace.workspace_id", ondelete="CASCADE"), primary_key=True)
    section_id = Column(String(10), primary_key=True)
    
    start_time = Column(Time, nullable=True)
    end_time = Column(Time, nullable=True)
    reminder_minutes = Column(Integer, nullable=True)
    day = Column(String(21), nullable=True) 
    location = Column(String(50), nullable=True)

    workspace = relationship(f"{__name__}.Workspace", back_populates="sections")
    enrollments = relationship(f"{__name__}.Enrollment", back_populates="section", cascade="all, delete-orphan")


# ==============================================================================
# ── STUDENTS & ROSTERS ────────────────────────────────────────────────────────
# ==============================================================================

class Student(Base):
    __tablename__ = "students"
    __table_args__ = {'extend_existing': True}

    student_id = Column(String(9), primary_key=True)
    student_name = Column(String(100), nullable=False)
    facial_encoding = Column(JSONB, nullable=True)
    campus_code = Column(String(2), nullable=False)
    college_code = Column(Integer, nullable=True)
    college_desc = Column(String(100), nullable=True)
    major_code = Column(String(10), nullable=True)
    major_desc = Column(String(100), nullable=True)
    campus_desc = Column(String(50), nullable=True)

    enrollments = relationship(f"{__name__}.Enrollment", back_populates="student", cascade="all, delete-orphan")


class Enrollment(Base):
    __tablename__ = "enrollment"

    student_id = Column(String(9), ForeignKey("students.student_id", ondelete="CASCADE"), primary_key=True)
    section_id = Column(String(10), primary_key=True)
    workspace_id = Column(Integer, primary_key=True)

    __table_args__ = (
        ForeignKeyConstraint(
            ['section_id', 'workspace_id'],
            ['sections.section_id', 'sections.workspace_id'],
            ondelete="CASCADE"
        ),
        {'extend_existing': True}
    )

    student = relationship(f"{__name__}.Student", back_populates="enrollments")
    section = relationship(f"{__name__}.Section", back_populates="enrollments")
    attendances = relationship(f"{__name__}.Attendance", back_populates="enrollment", cascade="all, delete-orphan")


# ==============================================================================
# ── TRACKING ──────────────────────────────────────────────────────────────────
# ==============================================================================

class Attendance(Base):
    __tablename__ = "attendance"

    student_id = Column(String(9), primary_key=True)
    section_id = Column(String(10), primary_key=True)
    workspace_id = Column(Integer, primary_key=True)
    lecture_no = Column(Integer, primary_key=True)
    
    confidence = Column(String(20), nullable=True)
    status = Column(String(20), nullable=True)

    __table_args__ = (
        ForeignKeyConstraint(
            ['student_id', 'section_id', 'workspace_id'],
            ['enrollment.student_id', 'enrollment.section_id', 'enrollment.workspace_id'],
            ondelete="CASCADE"
        ),
        {'extend_existing': True}
    )

    enrollment = relationship(f"{__name__}.Enrollment", back_populates="attendances")


# ==============================================================================
# ── MATERIALS ──────────────────────────────────────────────────────
# ==============================================================================

class Material(Base):
    __tablename__ = "materials"
    __table_args__ = {'extend_existing': True}

    material_id = Column(Integer, primary_key=True, index=True)
    workspace_id = Column(Integer, ForeignKey("workspace.workspace_id", ondelete="CASCADE"), nullable=False)
    file_name = Column(String(255))
    file_path = Column(String(500))
    material_type = Column(String(50))

    workspace = relationship(f"{__name__}.Workspace", back_populates="materials")