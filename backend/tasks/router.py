from fastapi import APIRouter, HTTPException

from backend.tasks import service
from backend.tasks.schemas import Task, TaskCreate, TaskUpdate


router = APIRouter()


@router.get("/tasks", response_model=list[Task])
def get_tasks(project_id: int | None = None) -> list[Task]:
    return service.list_tasks(project_id)


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
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


@router.delete("/tasks/{task_id}", status_code=204)
def delete_task(task_id: int) -> None:
    if not service.delete_task(task_id):
        raise HTTPException(status_code=404, detail="Task not found")
