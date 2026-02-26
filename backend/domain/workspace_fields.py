# backend/domain/workspace_fields.py
#
# FIX (DRY): Previously the list of workspace field names was hardcoded in
# FOUR separate places inside CsvWorkspaceRepository:
#   - __init__  (CSV header)
#   - list_all  (dict construction)
#   - get_by_id (dict construction again)
#   - save      (row building, twice)
#
# Now it lives here once. Adding or renaming a field is a single-line change.

# Fields stored as columns in workspaces.csv and as keys in Workspace.fields.
WORKSPACE_FIELD_NAMES: list[str] = [
    "course_title",
    "semester",
    "office_hours",
    "instructor_email",
    "course_code",
    "course_name",
]

# Fields that must be non-empty for a workspace to reach READY status.
REQUIRED_FIELD_NAMES: list[str] = [
    "course_title",
    "semester",
    "office_hours",
]