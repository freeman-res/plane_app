import sqlite3
from contextlib import closing
from datetime import date
from calendar import monthrange

from backend.database import DB_PATH
from backend.tasks.schemas import SortBy, Task, TaskCreate, TaskPriority, TaskStatus


_TASK_COLUMNS = (
    "id, title, description, status, project_id, start_date, deadline, priority, urgent, moscow"
)


def _with_tags(conn: sqlite3.Connection, rows: list[sqlite3.Row]) -> list[Task]:
    if not rows:
        return []
    placeholders = ", ".join("?" for _ in rows)
    tag_rows = conn.execute(
        f"SELECT task_id, name FROM task_tags WHERE task_id IN ({placeholders}) "
        "ORDER BY task_id, position",
        [row["id"] for row in rows],
    ).fetchall()
    tags_by_task: dict[int, list[str]] = {row["id"]: [] for row in rows}
    for tag_row in tag_rows:
        tags_by_task[tag_row["task_id"]].append(tag_row["name"])
    return [Task(**dict(row), tags=tags_by_task[row["id"]]) for row in rows]


def _save_tags(conn: sqlite3.Connection, task_id: int, tags: list[str]) -> None:
    conn.executemany(
        "INSERT INTO task_tags (task_id, name, name_key, position) "
        "VALUES (?, ?, ?, ?)",
        [(task_id, name, name.casefold(), index) for index, name in enumerate(tags)],
    )


def _order_by(sort_by: SortBy | None, descending: bool | None) -> str:
    if sort_by == "priority":
        direction = "DESC" if descending is None or descending else "ASC"
        return (
            "ORDER BY CASE priority WHEN 'high' THEN 3 "
            "WHEN 'medium' THEN 2 ELSE 1 END "
            f"{direction}, deadline IS NULL, deadline ASC, id ASC"
        )
    if sort_by == "deadline":
        direction = "DESC" if descending else "ASC"
        return (
            f"ORDER BY deadline IS NULL, deadline {direction}, "
            "CASE priority WHEN 'high' THEN 3 "
            "WHEN 'medium' THEN 2 ELSE 1 END DESC, id ASC"
        )
    return "ORDER BY id DESC" if descending else "ORDER BY id ASC"


def list_tasks(
    project_id: int | None = None,
    sort_by: SortBy | None = None,
    descending: bool | None = None,
    status: TaskStatus | None = None,
    priority: TaskPriority | None = None,
    tag: str | None = None,
    overdue: bool | None = None,
) -> list[Task]:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.row_factory = sqlite3.Row
        conditions: list[str] = []
        params: list[int | str] = []
        if project_id is not None:
            conditions.append("project_id = ?")
            params.append(project_id)
        if status is not None:
            conditions.append("status = ?")
            params.append(status)
        if priority is not None:
            conditions.append("priority = ?")
            params.append(priority)
        if tag is not None:
            conditions.append(
                "EXISTS (SELECT 1 FROM task_tags WHERE task_tags.task_id = tasks.id "
                "AND task_tags.name_key = ?)"
            )
            params.append(tag.strip().casefold())
        if overdue is not None:
            if overdue:
                conditions.append("deadline < ? AND status != 'done'")
            else:
                conditions.append("(deadline IS NULL OR deadline >= ? OR status = 'done')")
            params.append(date.today().isoformat())
        query = f"SELECT {_TASK_COLUMNS} FROM tasks"
        if conditions:
            query += " WHERE " + " AND ".join(conditions)
        order = _order_by(sort_by, descending)
        rows = conn.execute(f"{query} {order}", params).fetchall()
        return _with_tags(conn, rows)


def get_task(task_id: int) -> Task | None:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.row_factory = sqlite3.Row
        row = conn.execute(
            f"SELECT {_TASK_COLUMNS} FROM tasks WHERE id = ?", (task_id,)
        ).fetchone()
        return _with_tags(conn, [row])[0] if row is not None else None


def calendar_tasks(year: int, month: int, project_id: int | None = None) -> list[Task]:
    first = f"{year:04d}-{month:02d}-01"
    last = f"{year:04d}-{month:02d}-{monthrange(year, month)[1]:02d}"
    query = f"SELECT {_TASK_COLUMNS} FROM tasks WHERE deadline BETWEEN ? AND ?"
    params: tuple[str, str] | tuple[str, str, int] = (first, last)
    if project_id is not None:
        query += " AND project_id = ?"
        params = (first, last, project_id)
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute(f"{query} {_order_by('deadline', None)}", params).fetchall()
        return _with_tags(conn, rows)


def create_task(task: TaskCreate) -> Task:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        cursor = conn.execute(
            "INSERT INTO tasks "
            "(title, description, status, project_id, start_date, deadline, priority, urgent, moscow) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                task.title,
                task.description,
                task.status,
                task.project_id,
                task.start_date.isoformat(),
                task.deadline.isoformat() if task.deadline else None,
                task.priority,
                task.urgent,
                task.moscow,
            ),
        )
        task_id = cursor.lastrowid
        _save_tags(conn, task_id, task.tags)
        conn.commit()
    return Task(id=task_id, **task.model_dump())


def update_task(
    task_id: int, changes: dict[str, str | int | date | list[str] | None]
) -> Task | None:
    # Only these fixed column names can become part of the SQL statement.
    fields = [
        field
        for field in (
            "title", "description", "status", "project_id", "start_date",
            "deadline", "priority", "urgent", "moscow"
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
        if conn.execute("SELECT 1 FROM tasks WHERE id = ?", (task_id,)).fetchone() is None:
            return None
        if fields:
            conn.execute(
                f"UPDATE tasks SET {assignments} WHERE id = ?", (*values, task_id)
            )
        if "tags" in changes:
            conn.execute("DELETE FROM task_tags WHERE task_id = ?", (task_id,))
            _save_tags(conn, task_id, changes["tags"])
        conn.commit()
        row = conn.execute(
            f"SELECT {_TASK_COLUMNS} FROM tasks WHERE id = ?",
            (task_id,),
        ).fetchone()
        return _with_tags(conn, [row])[0]


def delete_task(task_id: int) -> bool:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        cursor = conn.execute("DELETE FROM tasks WHERE id = ?", (task_id,))
        if cursor.rowcount == 0:
            return False
        conn.commit()
    return True
