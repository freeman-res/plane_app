from datetime import date

from backend.projects.repository import project_exists
from backend.schedule.service import occurrences
from backend.tasks import repository
from backend.tasks.schemas import (
    CalendarDay, CalendarMonth, SortBy, Task, TaskCreate, TaskMatrix, TaskMoscow, TaskPriority,
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


def task_matrix(project_id: int | None = None) -> TaskMatrix:
    groups: dict[str, list[Task]] = {
        "urgent_important": [], "not_urgent_important": [],
        "urgent_not_important": [], "not_urgent_not_important": [],
    }
    for task in repository.list_tasks(project_id=project_id, sort_by="priority"):
        if task.status != "done":
            groups[task.matrix_quadrant].append(task)
    return TaskMatrix(**groups)


def task_moscow(project_id: int | None = None) -> TaskMoscow:
    groups: dict[str, list[Task]] = {
        "must": [], "should": [], "could": [], "wont": [], "unassigned": [],
    }
    for task in repository.list_tasks(project_id=project_id, sort_by="priority"):
        if task.status != "done":
            groups[task.moscow or "unassigned"].append(task)
    return TaskMoscow(**groups)


def calendar_month(
    year: int, month: int, project_id: int | None = None,
    include_schedule: bool = False,
) -> CalendarMonth:
    from calendar import monthrange

    days: dict[date, list[Task]] = {}
    for task in repository.calendar_tasks(year, month, project_id):
        assert task.deadline is not None
        days.setdefault(task.deadline, []).append(task)
    scheduled = {}
    if include_schedule:
        first = date(year, month, 1)
        last = date(year, month, monthrange(year, month)[1])
        for item in occurrences(first, last, project_id):
            scheduled.setdefault(item.date, []).append(item)
    return CalendarMonth(
        year=year,
        month=month,
        days=[CalendarDay(
            date=day, tasks=days.get(day, []), schedule=scheduled.get(day, []),
        ) for day in sorted(days.keys() | scheduled.keys())],
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
