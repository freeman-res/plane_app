import sqlite3
from contextlib import closing

from backend.database import DB_PATH
from backend.tasks.schemas import Task, TaskCreate


def list_tasks(project_id: int | None = None) -> list[Task]:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.row_factory = sqlite3.Row
        query = "SELECT id, title, description, status, project_id FROM tasks"
        if project_id is None:
            rows = conn.execute(f"{query} ORDER BY id").fetchall()
        else:
            rows = conn.execute(
                f"{query} WHERE project_id = ? ORDER BY id", (project_id,)
            ).fetchall()
    return [Task(**dict(row)) for row in rows]


def create_task(task: TaskCreate) -> Task:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        cursor = conn.execute(
            "INSERT INTO tasks (title, description, project_id) VALUES (?, ?, ?)",
            (task.title, task.description, task.project_id),
        )
        conn.commit()
        task_id = cursor.lastrowid
    return Task(id=task_id, **task.model_dump())


def update_task(task_id: int, changes: dict[str, str | int | None]) -> Task | None:
    # Only these fixed column names can become part of the SQL statement.
    fields = [
        field for field in ("title", "description", "status", "project_id")
        if field in changes
    ]
    assignments = ", ".join(f"{field} = ?" for field in fields)
    values = [changes[field] for field in fields]
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        conn.row_factory = sqlite3.Row
        cursor = conn.execute(
            f"UPDATE tasks SET {assignments} WHERE id = ?", (*values, task_id)
        )
        if cursor.rowcount == 0:
            return None
        conn.commit()
        row = conn.execute(
            "SELECT id, title, description, status, project_id FROM tasks WHERE id = ?",
            (task_id,),
        ).fetchone()
    return Task(**dict(row))


def delete_task(task_id: int) -> bool:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        cursor = conn.execute("DELETE FROM tasks WHERE id = ?", (task_id,))
        if cursor.rowcount == 0:
            return False
        conn.commit()
    return True
