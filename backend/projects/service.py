from fastapi import HTTPException

from backend.projects import repository
from backend.projects.schemas import Project, ProjectCreate


def list_projects() -> list[Project]:
    return repository.list_projects()


def create_project(project: ProjectCreate) -> Project:
    return repository.create_project(project)


def delete_project(project_id: int) -> None:
    if not repository.delete_project(project_id):
        raise HTTPException(status_code=404, detail="Project not found")
