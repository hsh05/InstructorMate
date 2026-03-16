# backend/db/models.py

from sqlalchemy import (
    Column, Text, Integer, String,
    ForeignKey, TIMESTAMP, func, UniqueConstraint, JSON
)
from sqlalchemy.orm import relationship
from db.database import Base

#ORM model is Python class representing a database table
class Workspace(Base):
    __tablename__ = "workspaces"

    workspace_id = Column(Text, primary_key=True)
    pdf_hash     = Column(Text, nullable=False, default="")
    status       = Column(Text, nullable=False, default="draft")  # 'draft' | 'ready'
    course_title = Column(Text, nullable=False, default="")
    semester     = Column(Text, nullable=False, default="")
    course_code  = Column(Text, nullable=False, default="")
    course_name  = Column(Text, nullable=False, default="")
    created_at   = Column(TIMESTAMP(timezone=True), server_default=func.now())
    updated_at   = Column(TIMESTAMP(timezone=True), server_default=func.now(),
                          onupdate=func.now())

    sections = relationship("Section", back_populates="workspace",
                            cascade="all, delete-orphan")
    students = relationship("Student", back_populates="workspace",
                            cascade="all, delete-orphan")
    chunks   = relationship("SyllabusChunk", back_populates="workspace",
                            cascade="all, delete-orphan")


class Section(Base):
    __tablename__ = "sections"

    section_id       = Column(Text, primary_key=True)
    workspace_id     = Column(Text, ForeignKey("workspaces.workspace_id", ondelete="CASCADE"),
                               nullable=False)
    name             = Column(Text, nullable=False, default="")
    location         = Column(Text, nullable=False, default="")
    start_time       = Column(Text, nullable=False, default="")
    end_time         = Column(Text, nullable=False, default="")
    reminder_minutes = Column(Integer, nullable=False, default=10)
    created_at       = Column(TIMESTAMP(timezone=True), server_default=func.now())
    last_import_hash = Column(String, default="")

    workspace = relationship("Workspace", back_populates="sections")
    students  = relationship("StudentSection", cascade="all, delete-orphan")


class SectionDay(Base):
    __tablename__ = "section_days"

    id         = Column(Integer, primary_key=True, autoincrement=True)
    section_id = Column(Text, ForeignKey("sections.section_id", ondelete="CASCADE"),
                        nullable=False)
    day        = Column(Text, nullable=False)


class Student(Base):
    __tablename__ = "students"

    student_id   = Column(Text, primary_key=True)
    workspace_id = Column(Text, ForeignKey("workspaces.workspace_id", ondelete="CASCADE"),
                          nullable=False)
    student_no   = Column(Text, nullable=False, default="")
    name         = Column(Text, nullable=False, default="")
    email        = Column(Text, nullable=False, default="")
    created_at   = Column(TIMESTAMP(timezone=True), server_default=func.now())

    workspace = relationship("Workspace", back_populates="students")
    # FIX: No cascade here — StudentSection rows are owned by Section.
    # Having cascade="all, delete-orphan" on BOTH Section.students and
    # Student.sections caused a double-delete conflict → 500 on workspace delete.
    sections  = relationship("StudentSection")


class StudentSection(Base):
    __tablename__ = "student_sections"

    id = Column(Integer, primary_key=True, autoincrement=True)

    student_id = Column(Text, ForeignKey("students.student_id", ondelete="CASCADE"),
                        nullable=False)
    section_id = Column(Text, ForeignKey("sections.section_id", ondelete="CASCADE"),
                        nullable=False)

    student = relationship("Student")
    section = relationship("Section")

    __table_args__ = (
        UniqueConstraint("student_id", "section_id", name="uq_student_section"),
    )


class SyllabusChunk(Base):
    __tablename__ = "syllabus_chunks"

    id           = Column(Integer, primary_key=True, autoincrement=True)
    workspace_id = Column(Text, ForeignKey("workspaces.workspace_id", ondelete="CASCADE"),
                          nullable=False)
    chunk_index  = Column(Integer, nullable=False)
    content      = Column(Text, nullable=False, default="")
    # Embedding vector stored as a JSON array of floats.
    # NULL for legacy chunks uploaded before embeddings were introduced —
    # the retriever falls back to LightweightRetriever for those.
    embedding    = Column(JSON, nullable=True)
    created_at   = Column(TIMESTAMP(timezone=True), server_default=func.now())

    workspace = relationship("Workspace", back_populates="chunks")