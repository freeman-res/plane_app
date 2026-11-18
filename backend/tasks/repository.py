import sqlite3
from contextlib import closing
from datetime import date

from backend.database import DB_PATH
from backend.tasks.schemas import Task, TaskCreate


_TASK_COLUMNS = "id, title, description, status, project_id, deadline, priority"


def list_tasks(project_id: int | None = None) -> list[Task]:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.row_factory = sqlite3.Row
        query = f"SELECT {_TASK_COLUMNS} FROM tasks"
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
            "INSERT INTO tasks "
            "(title, description, status, project_id, deadline, priority) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (
                task.title,
                task.description,
                task.status,
                task.project_id,
                task.deadline.isoformat() if task.deadline else None,
                task.priority,
            ),
        )
        conn.commit()
        task_id = cursor.lastrowid
    return Task(id=task_id, **task.model_dump())


def update_task(task_id: int, changes: dict[str, str | int | date | None]) -> Task | None:
    # Only these fixed column names can become part of the SQL statement.
    fields = [
        field
        for field in (
            "title", "description", "status", "project_id", "deadline", "priority"
        )
        if field in changes
    ]
    assignments = ", ".join(f"{field} = ?" for field in fields)
    values = []
    for field in fields:
        value = changes[field]
        values.append(value.isoformat() if isinstance(value, date) else value)
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
            f"SELECT {_TASK_COLUMNS} FROM tasks WHERE id = ?",
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
