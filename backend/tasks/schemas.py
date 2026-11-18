from datetime import date
from typing import Literal

from pydantic import BaseModel, Field, model_validator


TaskStatus = Literal["todo", "in_progress", "done"]
TaskPriority = Literal["low", "medium", "high"]


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str = ""
    project_id: int | None = Field(default=None, ge=1)
    status: TaskStatus = "todo"
    deadline: date | None = None
    priority: TaskPriority = "medium"


class Task(TaskCreate):
    id: int


class TaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    status: TaskStatus | None = None
    project_id: int | None = Field(default=None, ge=1)
    deadline: date | None = None
    priority: TaskPriority | None = None

    @model_validator(mode="after")
    def check_fields(self) -> "TaskUpdate":
        changes = self.model_dump(exclude_unset=True)
        if not changes or any(
            value is None
            for field, value in changes.items()
            if field not in {"project_id", "deadline"}
        ):
            raise ValueError("Provide at least one non-null task field")
        return self
