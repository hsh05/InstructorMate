# backend/db/models.py

import uuid
from datetime import datetime, timezone
from typing import Dict, List, Optional

from sqlalchemy import (
    Column, Integer, String, Text, Boolean, ForeignKey, 
    TIMESTAMP, Time, Float, ForeignKeyConstraint, Date
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship, registry
from db.database import Base 

# Registry configuration to handle Render's dual-import behavior
Base.registry.configure(cascade=True)

# ==============================================================================
# ── MODELS ────────────────────────────────────────────────────────────────────
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

    refresh_tokens = relationship(lambda: RefreshToken, back_populates="instructor", cascade="all, delete-orphan")
    workspaces = relationship(lambda: Workspace, back_populates="instructor", cascade="all, delete-orphan")

class RefreshToken(Base):
    __tablename__ = "refresh_tokens"
    __table_args__ = {'extend_existing': True}

    token = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    instructor_id = Column(Integer, ForeignKey("instructor.instructor_id", ondelete="CASCADE"), nullable=False)
    expires_at = Column(TIMESTAMP(timezone=True), nullable=False)
    created_at = Column(TIMESTAMP(timezone=True), default=lambda: datetime.now(timezone.utc))

    instructor = relationship(lambda: Instructor, back_populates="refresh_tokens")

class Workspace(Base):
    __tablename__ = "workspace"
    __table_args__ = {'extend_existing': True}

    workspace_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    instructor_id = Column(Integer, ForeignKey("instructor.instructor_id", ondelete="CASCADE"), nullable=False)
    
    course_code = Column(String(20), nullable=True) 
    semester = Column(String(50), nullable=True)
    course_title = Column(String(255), nullable=True)
    file_hash = Column(String(255), nullable=True)
    
    chunk_index = Column(Integer, nullable=True)
    embedding = Column(JSONB, nullable=True)
    content = Column(Text, nullable=True)

    start_date = Column(Date, nullable=True)
    end_date = Column(Date, nullable=True)
    
    weekly_schedule = Column(Text, nullable=True)
    assessments_schedule = Column(Text, nullable=True)

    instructor = relationship(lambda: Instructor, back_populates="workspaces")
    sections = relationship(lambda: Section, back_populates="workspace", cascade="all, delete-orphan")
    materials = relationship(lambda: Material, back_populates="workspace", cascade="all, delete-orphan")

    # ── MERGED LOGIC FROM DOMAIN ──────────────────────────────────────────────
    
    @property
    def fields(self) -> dict:
        """Mimics the old fields dictionary for Flutter compatibility."""
        return {
            "course_code": self.course_code,
            "workspace_code": self.course_code,
            "semester": self.semester,
            "course_title": self.course_title,
            "workspace_title": self.course_title,
            "weekly_schedule": self.weekly_schedule,
            "assessments_schedule": self.assessments_schedule,
            "start_date": str(self.start_date) if self.start_date else "",
            "end_date": str(self.end_date) if self.end_date else ""
        }

    def to_dict(self) -> dict:
        return {
            "id": str(self.workspace_id),
            "file_hash": self.file_hash or "",
            "fields": self.fields,
            "status": "ready" if self.content else "draft",
            "sections": [],
            "students_count": 0,
        }

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

    workspace = relationship(lambda: Workspace, back_populates="sections")
    enrollments = relationship(lambda: Enrollment, back_populates="section", cascade="all, delete-orphan")

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

    enrollments = relationship(lambda: Enrollment, back_populates="student", cascade="all, delete-orphan")

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

    student = relationship(lambda: Student, back_populates="enrollments")
    section = relationship(lambda: Section, back_populates="enrollments")
    attendances = relationship(lambda: Attendance, back_populates="enrollment", cascade="all, delete-orphan")

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

    enrollment = relationship(lambda: Enrollment, back_populates="attendances")

class Material(Base):
    __tablename__ = "materials"
    __table_args__ = {'extend_existing': True}

    material_id = Column(Integer, primary_key=True, index=True)
    workspace_id = Column(Integer, ForeignKey("workspace.workspace_id", ondelete="CASCADE"), nullable=False)
    file_name = Column(String(255))
    file_path = Column(String(500))
    material_type = Column(String(50))

    workspace = relationship(lambda: Workspace, back_populates="materials")