from datetime import date
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query

from backend.tasks import service
from backend.tasks.schemas import (
    CalendarMonth, SortBy, Task, TaskCreate, TaskMatrix, TaskMoscow, TaskPriority, TaskStatus, TaskUpdate,
)


router = APIRouter()


@router.get("/tasks", response_model=list[Task])
def get_tasks(
    project_id: int | None = None,
    sort_by: SortBy | None = None,
    descending: bool | None = None,
    status: TaskStatus | None = None,
    priority: TaskPriority | None = None,
    tag: Annotated[str | None, Query(min_length=1, max_length=32, pattern=r"\S")] = None,
    overdue: bool | None = None,
) -> list[Task]:
    return service.list_tasks(
        project_id, sort_by, descending, status, priority, tag, overdue
    )


@router.get("/tasks/overdue", response_model=list[Task])
def get_overdue_tasks(project_id: int | None = None) -> list[Task]:
    return service.list_tasks(project_id=project_id, sort_by="deadline", overdue=True)


@router.get("/tasks/matrix", response_model=TaskMatrix)
def get_task_matrix(project_id: int | None = None) -> TaskMatrix:
    return service.task_matrix(project_id)


@router.get("/tasks/moscow", response_model=TaskMoscow)
def get_task_moscow(project_id: int | None = None) -> TaskMoscow:
    return service.task_moscow(project_id)


@router.get("/tasks/calendar", response_model=CalendarMonth)
def get_calendar(
    year: Annotated[int | None, Query(ge=1, le=9999)] = None,
    month: Annotated[int | None, Query(ge=1, le=12)] = None,
    project_id: int | None = None,
    include_schedule: bool = False,
) -> CalendarMonth:
    today = date.today()
    return service.calendar_month(
        year or today.year, month or today.month, project_id, include_schedule,
    )


@router.post("/tasks", response_model=Task, status_code=201)
def create_task(task: TaskCreate) -> Task:
    try:
        return service.create_task(task)
    except service.ProjectNotFound:
        raise HTTPException(status_code=404, detail="Project not found") from None


@router.patch("/tasks/{task_id}", response_model=Task)
def update_task(task_id: int, update: TaskUpdate) -> Task:
    try:
        task = service.update_task(task_id, update)
    except service.ProjectNotFound:
        raise HTTPException(status_code=404, detail="Project not found") from None
    except service.InvalidDateRange:
        raise HTTPException(
            status_code=422, detail="Deadline cannot be earlier than start date"
        ) from None
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


@router.delete("/tasks/{task_id}", status_code=204)
def delete_task(task_id: int) -> None:
    if not service.delete_task(task_id):
        raise HTTPException(status_code=404, detail="Task not found")
