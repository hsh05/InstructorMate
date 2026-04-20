# backend/schemas.py

from pydantic import BaseModel
from typing import List, Optional, Any

# ==============================================================================
# ── MATERIALS ─────────────────────────────────────────────────────────────────
# ==============================================================================

class MaterialBase(BaseModel):
    file_name: str
    file_path: str
    material_type: Optional[str] = None

class MaterialCreate(MaterialBase):
    pass

class MaterialResponse(MaterialBase):
    # 👉 THE FIX: Changed 'id' to 'material_id' to perfectly match NeonDB!
    material_id: int 
    workspace_id: int

    class Config:
        from_attributes = True
        orm_mode = True # Included for backwards compatibility with older Pydantic versions


# ==============================================================================
# ── WORKSPACES (Replaces old 'workspaces') ───────────────────────────────────────
# ==============================================================================

class WorkspaceBase(BaseModel):
    workspace_code: str
    semester: str
    workspace_title: str

class WorkspaceCreate(WorkspaceBase):
    pass

class WorkspaceResponse(WorkspaceBase):
    workspace_id: int
    instructor_id: int
    content: Optional[str] = None
    # We deliberately do NOT include the embedding vector here so we don't 
    # accidentally send a massive array of floats to the frontend on every request!
    materials: List[MaterialResponse] = []

    class Config:
        from_attributes = True
        orm_mode = True


# ==============================================================================
# ── AI QUIZ GENERATION ────────────────────────────────────────────────────────
# ==============================================================================

class QuizConfig(BaseModel):
    # This allows Flutter to send whatever config keys it wants (e.g. MCQ, Essay, count)
    # without Pydantic crashing if a new key is added.
    class Config:
        extra = 'allow'

class QuizGenerateRequest(BaseModel):
    selected_material_ids: List[int]
    configs: List[QuizConfig]