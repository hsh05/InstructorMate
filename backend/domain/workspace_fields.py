# backend/domain/workspace_fields.py

# Fields stored as columns in the workspaces table and as keys in Workspace.fields.
WORKSPACE_FIELD_NAMES: list[str] = [
    "course_title",
    "semester",
    "course_code",
    "course_name",
]

# Fields that must be non-empty for a workspace to reach READY status.
REQUIRED_FIELD_NAMES: list[str] = [
    "course_title",
    "semester",
    "course_code",
]