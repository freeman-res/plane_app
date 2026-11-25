from datetime import date, time
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator


RepeatWeeks = Literal[0, 1, 2]


def check_interval(first_date: date, ends_on: date | None,
                   start_time: time, end_time: time) -> None:
    if ends_on is not None and ends_on < first_date:
        raise ValueError("End date cannot be earlier than first date")
    if start_time.tzinfo is not None or end_time.tzinfo is not None:
        raise ValueError("Use local time without a timezone offset")
    if start_time >= end_time:
        raise ValueError("End time must be later than start time")


class ScheduleCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(default="", max_length=5000)
    project_id: int | None = Field(default=None, ge=1)
    first_date: date
    ends_on: date | None = None
    start_time: time
    end_time: time
    repeat_every_weeks: RepeatWeeks = 1

    @field_validator("title")
    @classmethod
    def clean_title(cls, title: str) -> str:
        title = title.strip()
        if not title:
            raise ValueError("Title cannot be empty")
        return title

    @model_validator(mode="after")
    def validate_interval(self) -> "ScheduleCreate":
        check_interval(self.first_date, self.ends_on, self.start_time, self.end_time)
        return self


class ScheduleUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=5000)
    project_id: int | None = Field(default=None, ge=1)
    first_date: date | None = None
    ends_on: date | None = None
    start_time: time | None = None
    end_time: time | None = None
    repeat_every_weeks: RepeatWeeks | None = None

    @field_validator("title")
    @classmethod
    def clean_title(cls, title: str | None) -> str | None:
        return ScheduleCreate.clean_title(title) if title is not None else None

    @model_validator(mode="after")
    def check_changes(self) -> "ScheduleUpdate":
        changes = self.model_dump(exclude_unset=True)
        if not changes or any(
            value is None for field, value in changes.items()
            if field not in {"project_id", "ends_on"}
        ):
            raise ValueError("Provide at least one non-null schedule field")
        return self


class ScheduleEntry(ScheduleCreate):
    id: int
    excluded_dates: list[date] = Field(default_factory=list)


class ScheduleOccurrence(BaseModel):
    schedule_id: int
    title: str
    description: str
    project_id: int | None
    date: date
    start_time: time
    end_time: time
