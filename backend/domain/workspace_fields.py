# backend/domain/workspace_fields.py

# Fields stored as columns in the workspaces table and as keys in Workspace.fields.
WORKSPACE_FIELD_NAMES = [
    "course_title",
    "course_code",
    "semester",
    "start_date",
    "end_date",
    "workspace_title",
    "weekly_schedule",
    "assessments_schedule"
]

# Fields that must be non-empty for a workspace to reach READY status.
REQUIRED_FIELD_NAMES: list[str] = [
    "workspace_title",
    "semester",
    "workspace_code",
]