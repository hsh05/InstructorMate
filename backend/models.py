from sqlalchemy import Column, Integer, String, ForeignKey
from sqlalchemy.orm import relationship
from database import Base

class Course(Base):
    __tablename__ = "courses"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, index=True)
    description = Column(String, nullable=True)

    # One-to-Many relationship: Connects the course to its materials
    materials = relationship("Material", back_populates="course", cascade="all, delete-orphan")

class Material(Base):
    __tablename__ = "materials"

    id = Column(Integer, primary_key=True, index=True)
    course_id = Column(Integer, ForeignKey("courses.id")) # The foreign key linking back to the course
    file_name = Column(String, index=True)
    file_path = Column(String)  # We will update this to an AWS S3 URL later
    material_type = Column(String)  # e.g., 'syllabus' or 'slides'

    # Many-to-One relationship
    course = relationship("Course", back_populates="materials")