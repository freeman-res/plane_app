from fastapi import APIRouter

from backend.projects import service
from backend.projects.schemas import Project, ProjectCreate


router = APIRouter()


@router.get("/projects", response_model=list[Project])
def get_projects() -> list[Project]:
    return service.list_projects()


@router.post("/projects", response_model=Project, status_code=201)
def create_project(project: ProjectCreate) -> Project:
    return service.create_project(project)


@router.delete("/projects/{project_id}", status_code=204)
def delete_project(project_id: int) -> None:
    service.delete_project(project_id)
