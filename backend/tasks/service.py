from backend.projects.repository import project_exists
from backend.tasks import repository
from backend.tasks.schemas import Task, TaskCreate, TaskUpdate


class ProjectNotFound(Exception):
    pass


def list_tasks(project_id: int | None = None) -> list[Task]:
    return repository.list_tasks(project_id)


def create_task(task: TaskCreate) -> Task:
    if task.project_id is not None and not project_exists(task.project_id):
        raise ProjectNotFound
    return repository.create_task(task)


def update_task(task_id: int, update: TaskUpdate) -> Task | None:
    if update.project_id is not None and not project_exists(update.project_id):
        raise ProjectNotFound
    return repository.update_task(task_id, update.model_dump(exclude_unset=True))


def delete_task(task_id: int) -> bool:
    return repository.delete_task(task_id)
