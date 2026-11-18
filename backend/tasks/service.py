from datetime import date

from backend.projects.repository import project_exists
from backend.tasks import repository
from backend.tasks.schemas import (
    CalendarDay, CalendarMonth, SortBy, Task, TaskCreate, TaskPriority,
    TaskStatus, TaskUpdate,
)


class ProjectNotFound(Exception):
    pass


class InvalidDateRange(Exception):
    pass


def list_tasks(
    project_id: int | None = None,
    sort_by: SortBy | None = None,
    descending: bool | None = None,
    status: TaskStatus | None = None,
    priority: TaskPriority | None = None,
    tag: str | None = None,
    overdue: bool | None = None,
) -> list[Task]:
    return repository.list_tasks(
        project_id, sort_by, descending, status, priority, tag, overdue
    )


def calendar_month(year: int, month: int, project_id: int | None = None) -> CalendarMonth:
    days: dict[date, list[Task]] = {}
    for task in repository.calendar_tasks(year, month, project_id):
        assert task.deadline is not None
        days.setdefault(task.deadline, []).append(task)
    return CalendarMonth(
        year=year,
        month=month,
        days=[CalendarDay(date=day, tasks=tasks) for day, tasks in days.items()],
    )


def create_task(task: TaskCreate) -> Task:
    if task.project_id is not None and not project_exists(task.project_id):
        raise ProjectNotFound
    return repository.create_task(task)


def update_task(task_id: int, update: TaskUpdate) -> Task | None:
    if update.project_id is not None and not project_exists(update.project_id):
        raise ProjectNotFound
    current = repository.get_task(task_id)
    if current is None:
        return None
    changes = update.model_dump(exclude_unset=True)
    start_date = changes.get("start_date", current.start_date)
    deadline = changes.get("deadline", current.deadline)
    if deadline is not None and deadline < start_date:
        raise InvalidDateRange
    return repository.update_task(task_id, changes)


def delete_task(task_id: int) -> bool:
    return repository.delete_task(task_id)
