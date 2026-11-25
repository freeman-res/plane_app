from datetime import date
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query

from backend.schedule import service
from backend.schedule.schemas import (
    ScheduleCreate, ScheduleEntry, ScheduleOccurrence, ScheduleUpdate,
)


router = APIRouter()


@router.get("/schedule", response_model=list[ScheduleEntry])
def list_schedule(project_id: Annotated[int | None, Query(ge=1)] = None) -> list[ScheduleEntry]:
    return service.list_entries(project_id)


@router.get("/schedule/occurrences", response_model=list[ScheduleOccurrence])
def get_occurrences(
    start: date,
    end: date,
    project_id: Annotated[int | None, Query(ge=1)] = None,
) -> list[ScheduleOccurrence]:
    if end < start or (end - start).days > 366:
        raise HTTPException(status_code=422, detail="Date range must be from 0 to 366 days")
    return service.occurrences(start, end, project_id)


@router.post("/schedule", response_model=ScheduleEntry, status_code=201)
def create_schedule(payload: ScheduleCreate) -> ScheduleEntry:
    try:
        return service.create_entry(payload)
    except service.ProjectNotFound:
        raise HTTPException(status_code=404, detail="Project not found") from None


@router.get("/schedule/{entry_id}", response_model=ScheduleEntry)
def get_schedule(entry_id: int) -> ScheduleEntry:
    entry = service.get_entry(entry_id)
    if entry is None:
        raise HTTPException(status_code=404, detail="Schedule entry not found")
    return entry


@router.patch("/schedule/{entry_id}", response_model=ScheduleEntry)
def update_schedule(entry_id: int, payload: ScheduleUpdate) -> ScheduleEntry:
    try:
        entry = service.update_entry(entry_id, payload)
    except service.ProjectNotFound:
        raise HTTPException(status_code=404, detail="Project not found") from None
    except service.InvalidInterval:
        raise HTTPException(status_code=422, detail="Invalid schedule dates or times") from None
    if entry is None:
        raise HTTPException(status_code=404, detail="Schedule entry not found")
    return entry


@router.delete("/schedule/{entry_id}", status_code=204)
def delete_schedule(entry_id: int) -> None:
    if not service.delete_entry(entry_id):
        raise HTTPException(status_code=404, detail="Schedule entry not found")


@router.put("/schedule/{entry_id}/exceptions/{day}", response_model=ScheduleEntry)
def skip_occurrence(entry_id: int, day: date) -> ScheduleEntry:
    try:
        entry = service.exclude_occurrence(entry_id, day, True)
    except service.InvalidOccurrence:
        raise HTTPException(status_code=422, detail="Date is not a scheduled occurrence") from None
    if entry is None:
        raise HTTPException(status_code=404, detail="Schedule entry not found")
    return entry


@router.delete("/schedule/{entry_id}/exceptions/{day}", response_model=ScheduleEntry)
def restore_occurrence(entry_id: int, day: date) -> ScheduleEntry:
    try:
        entry = service.exclude_occurrence(entry_id, day, False)
    except service.InvalidOccurrence:
        raise HTTPException(status_code=422, detail="Date is not a scheduled occurrence") from None
    if entry is None:
        raise HTTPException(status_code=404, detail="Schedule entry not found")
    return entry
