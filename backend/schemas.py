from pydantic import BaseModel
from typing import List, Optional

# --- Material Schemas ---
class MaterialBase(BaseModel):
    file_name: str
    material_type: str
    file_path: str

class MaterialResponse(MaterialBase):
    id: int
    course_id: int

    class Config:
        from_attributes = True  # Tells Pydantic to read data even if it's not a dictionary

# --- Course Schemas ---
class CourseBase(BaseModel):
    title: str
    description: Optional[str] = None

class CourseCreate(CourseBase):
    pass

class CourseResponse(CourseBase):
    id: int
    materials: List[MaterialResponse] = [] # Automatically nests the materials inside the course!

    class Config:
        from_attributes = True

class QuestionConfig(BaseModel):
    type: str     
    count: int    
    difficulty: str  # <--- ADD THIS
    topic: str    

    class Config:
        from_attributes = True

class QuizGenerateRequest(BaseModel):
    configs: List[QuestionConfig]
    # ADD THIS LINE: This allows the backend to validate the list of IDs from Flutter
    selected_material_ids: List[int]