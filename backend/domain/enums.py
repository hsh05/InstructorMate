from enum import Enum


class WorkspaceStatus(str, Enum):
    DRAFT = "draft"
    READY = "ready"
