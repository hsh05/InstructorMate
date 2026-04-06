# backend/db/models.py

from sqlalchemy import (
    Column, Integer, String, Text, Boolean, ForeignKey, 
    TIMESTAMP, Time, Float, ForeignKeyConstraint
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from sqlalchemy import Column, Integer, String, ForeignKey, ForeignKeyConstraint
import uuid
from datetime import datetime, timezone
from db.database import Base 

# ==============================================================================
# ── INSTRUCTOR & AUTHENTICATION ───────────────────────────────────────────────
# ==============================================================================

class Instructor(Base):
    __tablename__ = "instructor" # 👈 FIXED: Matches your NeonDB 'instructor'

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
    # 👈 FIXED: Point to 'instructor.instructor_id'
    instructor_id = Column(Integer, ForeignKey("instructor.instructor_id", ondelete="CASCADE"), nullable=False)
    expires_at = Column(TIMESTAMP(timezone=True), nullable=False)
    created_at = Column(TIMESTAMP(timezone=True), default=lambda: datetime.now(timezone.utc))

    instructor = relationship("Instructor", back_populates="refresh_tokens")


# ==============================================================================
# ── WORKSPACES ──────────────────────────────────────────────────────
# ==============================================================================

class Workspace(Base):
    __tablename__ = "workspace" # 👈 FIXED: Matches your NeonDB 'workspace'

    workspace_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    # 👈 FIXED: Point to 'instructor.instructor_id'
    instructor_id = Column(Integer, ForeignKey("instructor.instructor_id", ondelete="CASCADE"), nullable=False)
    
    # These match your PG_Repository fields
    course_code = Column(String(20), nullable=True) 
    semester = Column(String(50), nullable=True)
    course_title = Column(String(255), nullable=True)
    
    chunk_index = Column(Integer, nullable=True)
    embedding = Column(JSONB, nullable=True)
    content = Column(Text, nullable=True)

    instructor = relationship("Instructor", back_populates="workspaces")
    sections = relationship("Section", back_populates="workspace", cascade="all, delete-orphan")

# ==============================================================================
# ── SECTIONS & SCHEDULING ─────────────────────────────────────────────────────
# ==============================================================================

class Section(Base):
    __tablename__ = "sections"

    # 👈 FIXED: Composite PK and correct FK reference to 'workspace'
    workspace_id = Column(Integer, ForeignKey("workspace.workspace_id", ondelete="CASCADE"), primary_key=True)
    section_id = Column(String(10), primary_key=True)
    
    start_time = Column(Time, nullable=True)
    end_time = Column(Time, nullable=True)
    reminder_minutes = Column(Integer, nullable=True)
    day = Column(String(21), nullable=True) 
    location = Column(String(50), nullable=True)

    workspace = relationship("Workspace", back_populates="sections")
    enrollments = relationship("Enrollment", back_populates="section", cascade="all, delete-orphan")


# ==============================================================================
# ── STUDENTS & ROSTERS ────────────────────────────────────────────────────────
# ==============================================================================

class Student(Base):
    __tablename__ = "students"

    student_id = Column(String(20), primary_key=True)
    student_name = Column(String(100), nullable=False)
    facial_encoding = Column(JSONB, nullable=True)
    campus_code = Column(String(10), nullable=True)

    enrollments = relationship("Enrollment", back_populates="student", cascade="all, delete-orphan")


class Enrollment(Base):
    __tablename__ = "enrollment" # 👈 FIXED: Matches your NeonDB 'enrollment'

    student_id = Column(String(20), ForeignKey("students.student_id", ondelete="CASCADE"), primary_key=True)
    section_id = Column(String(10), primary_key=True)
    workspace_id = Column(Integer, primary_key=True)

    # 👈 FIXED: Map to the composite key in sections
    __table_args__ = (
        ForeignKeyConstraint(
            ['section_id', 'workspace_id'],
            ['sections.section_id', 'sections.workspace_id'],
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

    student_id = Column(String(20), primary_key=True)
    section_id = Column(String(10), primary_key=True)
    workspace_id = Column(Integer, primary_key=True)
    lecture_no = Column(Integer, primary_key=True)
    
    confidence = Column(String(20), nullable=True)
    status = Column(String(20), nullable=True)

    # 👈 FIXED: Map to the composite key in enrollment
    __table_args__ = (
        ForeignKeyConstraint(
            ['student_id', 'section_id', 'workspace_id'],
            ['enrollment.student_id', 'enrollment.section_id', 'enrollment.workspace_id'],
            ondelete="CASCADE"
        ),
    )

    enrollment = relationship("Enrollment", back_populates="attendances")