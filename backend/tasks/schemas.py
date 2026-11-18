from typing import Literal

from pydantic import BaseModel, Field, model_validator


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str = ""
    project_id: int | None = Field(default=None, ge=1)


class Task(TaskCreate):
    id: int
    status: Literal["todo", "done"] = "todo"


class TaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    status: Literal["todo", "done"] | None = None
    project_id: int | None = Field(default=None, ge=1)

    @model_validator(mode="after")
    def check_fields(self) -> "TaskUpdate":
        changes = self.model_dump(exclude_unset=True)
        if not changes or any(
            value is None for field, value in changes.items() if field != "project_id"
        ):
            raise ValueError("Provide at least one non-null task field")
        return self
