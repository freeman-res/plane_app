import sqlite3
from contextlib import closing

from backend.database import DB_PATH
from backend.projects.schemas import Project, ProjectCreate


def list_projects() -> list[Project]:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute("SELECT id, name FROM projects ORDER BY id").fetchall()
    return [Project(**dict(row)) for row in rows]


def create_project(project: ProjectCreate) -> Project:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        cursor = conn.execute(
            "INSERT INTO projects (name) VALUES (?)", (project.name,)
        )
        conn.commit()
        return Project(id=cursor.lastrowid, name=project.name)


def project_exists(project_id: int) -> bool:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        row = conn.execute(
            "SELECT 1 FROM projects WHERE id = ?", (project_id,)
        ).fetchone()
    return row is not None


def delete_project(project_id: int) -> bool:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        cursor = conn.execute("DELETE FROM projects WHERE id = ?", (project_id,))
        if cursor.rowcount == 0:
            return False
        conn.commit()
    return True
