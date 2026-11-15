from fastapi import APIRouter, HTTPException

from backend.schemas import Task, TaskCreate, TaskStatusUpdate
from backend.services import tasks as task_service


router = APIRouter()


@router.get("/tasks", response_model=list[Task])
def get_tasks() -> list[Task]:
    return task_service.list_tasks()


@router.post("/tasks", response_model=Task, status_code=201)
def create_task(task: TaskCreate) -> Task:
    return task_service.create_task(task)


@router.patch("/tasks/{task_id}", response_model=Task)
def update_task_status(task_id: int, update: TaskStatusUpdate) -> Task:
    task = task_service.update_status(task_id, update.status)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


@router.delete("/tasks/{task_id}", status_code=204)
def delete_task(task_id: int) -> None:
    if not task_service.delete_task(task_id):
        raise HTTPException(status_code=404, detail="Task not found")
