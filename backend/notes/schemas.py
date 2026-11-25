from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from backend.tasks.schemas import TaskPriority, TaskStatus


class TextSpan(BaseModel):
    text: str = Field(min_length=1, max_length=10000)
    font_family: Literal["sans", "serif", "mono"] = "sans"
    font_size: int = Field(default=14, ge=8, le=48)
    bold: bool = False
    italic: bool = False
    underline: bool = False
    color: str | None = Field(default=None, pattern=r"^#[0-9a-fA-F]{6}$")


class NoteBlock(BaseModel):
    type: Literal["paragraph", "heading", "bullet", "numbered"] = "paragraph"
    spans: list[TextSpan] = Field(default_factory=list, max_length=100)


class NoteCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    content: list[NoteBlock] = Field(default_factory=list, max_length=500)

    @field_validator("title")
    @classmethod
    def clean_title(cls, title: str) -> str:
        title = title.strip()
        if not title:
            raise ValueError("Note title cannot be empty")
        return title

    @field_validator("content")
    @classmethod
    def limit_text(cls, content: list[NoteBlock]) -> list[NoteBlock]:
        if sum(len(span.text) for block in content for span in block.spans) > 100000:
            raise ValueError("Note text cannot exceed 100000 characters")
        return content


class NoteUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    content: list[NoteBlock] | None = Field(default=None, max_length=500)

    @field_validator("title")
    @classmethod
    def clean_title(cls, title: str | None) -> str | None:
        return NoteCreate.clean_title(title) if title is not None else None

    @field_validator("content")
    @classmethod
    def limit_text(cls, content: list[NoteBlock] | None) -> list[NoteBlock] | None:
        return NoteCreate.limit_text(content) if content is not None else None

    @model_validator(mode="after")
    def nonempty_update(self) -> "NoteUpdate":
        if not self.model_dump(exclude_unset=True) or any(
            value is None for value in self.model_dump(exclude_unset=True).values()
        ):
            raise ValueError("Provide at least one non-null note field")
        return self


class Attachment(BaseModel):
    id: int
    note_id: int
    filename: str
    media_type: str
    size: int


class Note(NoteCreate):
    id: int
    created_at: datetime
    updated_at: datetime
    task_ids: list[int] = Field(default_factory=list)
    attachments: list[Attachment] = Field(default_factory=list)


class NoteToTask(BaseModel):
    project_id: int | None = Field(default=None, ge=1)
    status: TaskStatus = "todo"
    start_date: date = Field(default_factory=date.today)
    deadline: date | None = None
    priority: TaskPriority = "medium"

    @model_validator(mode="after")
    def check_dates(self) -> "NoteToTask":
        if self.deadline is not None and self.deadline < self.start_date:
            raise ValueError("Deadline cannot be earlier than start date")
        return self
