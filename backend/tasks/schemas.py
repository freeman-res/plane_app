from datetime import date
from typing import Literal

from pydantic import BaseModel, Field, computed_field, field_validator, model_validator


TaskStatus = Literal["todo", "in_progress", "done"]
TaskPriority = Literal["low", "medium", "high"]
SortBy = Literal["priority", "deadline"]


def clean_tags(tags: list[str]) -> list[str]:
    if len(tags) > 20:
        raise ValueError("A task can have at most 20 tags")
    result: list[str] = []
    seen: set[str] = set()
    for raw in tags:
        name = raw.strip()
        if not name or len(name) > 32:
            raise ValueError("Tag length must be between 1 and 32 characters")
        if name.casefold() in seen:
            raise ValueError("Duplicate tag")
        seen.add(name.casefold())
        result.append(name)
    return result


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str = ""
    project_id: int | None = Field(default=None, ge=1)
    status: TaskStatus = "todo"
    start_date: date = Field(default_factory=date.today)
    deadline: date | None = None
    priority: TaskPriority = "medium"
    tags: list[str] = Field(default_factory=list)

    @field_validator("tags")
    @classmethod
    def validate_tags(cls, tags: list[str]) -> list[str]:
        return clean_tags(tags)

    @model_validator(mode="after")
    def check_dates(self) -> "TaskCreate":
        if self.deadline is not None and self.deadline < self.start_date:
            raise ValueError("Deadline cannot be earlier than start date")
        return self


class Task(TaskCreate):
    id: int

    @computed_field
    @property
    def is_overdue(self) -> bool:
        return (
            self.status != "done"
            and self.deadline is not None
            and self.deadline < date.today()
        )


class TaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    status: TaskStatus | None = None
    project_id: int | None = Field(default=None, ge=1)
    start_date: date | None = None
    deadline: date | None = None
    priority: TaskPriority | None = None
    tags: list[str] | None = None

    @field_validator("tags")
    @classmethod
    def validate_tags(cls, tags: list[str] | None) -> list[str] | None:
        return clean_tags(tags) if tags is not None else None

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


class CalendarDay(BaseModel):
    date: date
    tasks: list[Task]


class CalendarMonth(BaseModel):
    year: int
    month: int
    days: list[CalendarDay]
