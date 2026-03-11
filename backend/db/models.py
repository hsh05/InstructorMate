# backend/db/models.py

from sqlalchemy import (
    Column, Text, Integer, String,
    ForeignKey, TIMESTAMP, func, UniqueConstraint
)
from sqlalchemy.orm import relationship
from db.database import Base


# ── TEAMMATES' TABLES ─────────────────────────────────────────────────────────

class Course(Base):
    __tablename__ = "courses"

    id          = Column(Integer, primary_key=True, index=True)
    title       = Column(String, index=True)
    description = Column(String)

    materials   = relationship("Material", back_populates="course")


class Material(Base):
    __tablename__ = "materials"

    id            = Column(Integer, primary_key=True, index=True)
    course_id     = Column(Integer, ForeignKey("courses.id"))
    file_name     = Column(String, index=True)
    file_path     = Column(String)
    material_type = Column(String)

    course        = relationship("Course", back_populates="materials")


class StudentFace(Base):
    """Teammates' student table (face recognition). Named StudentFace here
    to avoid collision with my Student model below."""
    __tablename__ = "student"

    student_id    = Column(Text, primary_key=True)
    name          = Column(Text, nullable=False)
    encoding_json = Column(Text)

    attendance    = relationship("Attendance", back_populates="student")


class Attendance(Base):
    __tablename__ = "attendance"

    lecture_number = Column(Integer, primary_key=True)
    student_id     = Column(Text, ForeignKey("student.student_id", ondelete="CASCADE"), primary_key=True)
    status         = Column(Text, nullable=False)
    confidence     = Column(Text)

    student        = relationship("StudentFace", back_populates="attendance")


# ── My TABLES ───────────────────────────────────────────────────────────────

class Workspace(Base):
    __tablename__ = "workspaces"

    workspace_id     = Column(Text, primary_key=True)
    pdf_hash         = Column(Text, nullable=False, default="")
    status           = Column(Text, nullable=False, default="draft")  # 'draft' | 'ready'
    course_title     = Column(Text, nullable=False, default="")
    semester         = Column(Text, nullable=False, default="")
    instructor_email = Column(Text, nullable=False, default="")
    course_code      = Column(Text, nullable=False, default="")
    course_name      = Column(Text, nullable=False, default="")
    created_at       = Column(TIMESTAMP(timezone=True), server_default=func.now())

    sections         = relationship("Section", back_populates="workspace",
                                    cascade="all, delete-orphan")
    students         = relationship("Student", back_populates="workspace",
                                    cascade="all, delete-orphan")
    chunks           = relationship("SyllabusChunk", back_populates="workspace",
                                    cascade="all, delete-orphan")
    

class OfficeHour(Base):
    __tablename__ = "office_hours"

    id           = Column(Integer, primary_key=True, autoincrement=True)
    workspace_id = Column(Text, ForeignKey("workspaces.workspace_id", ondelete="CASCADE"), nullable=False)
    day          = Column(Text, nullable=False)
    start_time   = Column(Text, nullable=False, default="")
    end_time     = Column(Text, nullable=False, default="")

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

    workspace        = relationship("Workspace", back_populates="sections")
    students = relationship("StudentSection", cascade="all, delete-orphan")

class SectionDay(Base):
    __tablename__ = "section_days"

    id         = Column(Integer, primary_key=True, autoincrement=True)
    section_id = Column(Text, ForeignKey("sections.section_id", ondelete="CASCADE"), nullable=False)
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

    workspace    = relationship("Workspace", back_populates="students")
    sections     = relationship("StudentSection", cascade="all, delete-orphan")


class StudentSection(Base):
    __tablename__ = "student_sections"

    id = Column(Integer, primary_key=True, autoincrement=True)

    student_id = Column(Text, ForeignKey("students.student_id", ondelete="CASCADE"), nullable=False)
    section_id = Column(Text, ForeignKey("sections.section_id", ondelete="CASCADE"), nullable=False)

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
    created_at   = Column(TIMESTAMP(timezone=True), server_default=func.now())

    workspace    = relationship("Workspace", back_populates="chunks")

class SyllabusWeeklyTopic(Base):
    __tablename__ = "syllabus_weekly_topics"

    id           = Column(Integer, primary_key=True, autoincrement=True)
    workspace_id = Column(String, ForeignKey("workspaces.workspace_id", ondelete="CASCADE"), nullable=False, index=True)
    week_number  = Column(Integer, nullable=False)
    topic        = Column(Text, nullable=False)
    description  = Column(Text, nullable=True)


class SyllabusCLO(Base):
    __tablename__ = "syllabus_clos"

    id           = Column(Integer, primary_key=True, autoincrement=True)
    workspace_id = Column(String, ForeignKey("workspaces.workspace_id", ondelete="CASCADE"), nullable=False, index=True)
    clo_id       = Column(String, nullable=False)   # e.g. "CLO1"
    text         = Column(Text, nullable=False)
    bloom_level  = Column(String, nullable=True)    # e.g. "Apply"


class SyllabusKeyDate(Base):
    __tablename__ = "syllabus_key_dates"

    id           = Column(Integer, primary_key=True, autoincrement=True)
    workspace_id = Column(String, ForeignKey("workspaces.workspace_id", ondelete="CASCADE"), nullable=False, index=True)
    label        = Column(String, nullable=False)   # e.g. "Midterm Exam"
    date_text    = Column(String, nullable=False)   # e.g. "Week 7" or "March 15"
    date_type    = Column(String, nullable=False)   # exam | assignment | deadline | other

