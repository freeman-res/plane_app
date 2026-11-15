from typing import Literal

from pydantic import BaseModel, Field


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str = ""


class Task(TaskCreate):
    id: int
    status: Literal["todo", "done"] = "todo"


class TaskStatusUpdate(BaseModel):
    status: Literal["todo", "done"]
