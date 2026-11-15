import sqlite3
from contextlib import closing
from typing import Literal

from backend.database import DB_PATH
from backend.schemas import Task, TaskCreate


def list_tasks() -> list[Task]:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            "SELECT id, title, description, status FROM tasks ORDER BY id"
        ).fetchall()
    return [Task(**dict(row)) for row in rows]


def create_task(task: TaskCreate) -> Task:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        cursor = conn.execute(
            "INSERT INTO tasks (title, description) VALUES (?, ?)",
            (task.title, task.description),
        )
        conn.commit()
        task_id = cursor.lastrowid
    return Task(id=task_id, **task.model_dump())


def update_status(task_id: int, status: Literal["todo", "done"]) -> Task | None:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.row_factory = sqlite3.Row
        cursor = conn.execute(
            "UPDATE tasks SET status = ? WHERE id = ?",
            (status, task_id),
        )
        if cursor.rowcount == 0:
            return None
        conn.commit()
        row = conn.execute(
            "SELECT id, title, description, status FROM tasks WHERE id = ?",
            (task_id,),
        ).fetchone()
    return Task(**dict(row))


def delete_task(task_id: int) -> bool:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        cursor = conn.execute(
            "DELETE FROM tasks WHERE id = ?",
            (task_id,),
        )
        if cursor.rowcount == 0:
            return False
        conn.commit()
    return True
