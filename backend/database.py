import sqlite3
from contextlib import closing
from datetime import date
from pathlib import Path


DB_PATH = Path(__file__).with_name("tasks.db")


def init_db() -> None:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS projects (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                description TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'todo',
                project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
                start_date TEXT,
                deadline TEXT,
                priority TEXT NOT NULL DEFAULT 'medium',
                urgent INTEGER CHECK (urgent IS NULL OR urgent IN (0, 1)),
                moscow TEXT CHECK (moscow IS NULL OR moscow IN ('must', 'should', 'could', 'wont'))
            )
            """
        )
        columns = {row[1] for row in conn.execute("PRAGMA table_info(tasks)")}
        if "project_id" not in columns:
            conn.execute(
                "ALTER TABLE tasks ADD COLUMN project_id INTEGER "
                "REFERENCES projects(id) ON DELETE SET NULL"
            )
        if "deadline" not in columns:
            conn.execute("ALTER TABLE tasks ADD COLUMN deadline TEXT")
        if "priority" not in columns:
            conn.execute(
                "ALTER TABLE tasks ADD COLUMN priority TEXT NOT NULL DEFAULT 'medium'"
            )
        if "start_date" not in columns:
            conn.execute("ALTER TABLE tasks ADD COLUMN start_date TEXT")
        if "urgent" not in columns:
            conn.execute(
                "ALTER TABLE tasks ADD COLUMN urgent INTEGER "
                "CHECK (urgent IS NULL OR urgent IN (0, 1))"
            )
        if "moscow" not in columns:
            conn.execute(
                "ALTER TABLE tasks ADD COLUMN moscow TEXT "
                "CHECK (moscow IS NULL OR moscow IN ('must', 'should', 'could', 'wont'))"
            )
        today = date.today().isoformat()
        conn.execute(
            "UPDATE tasks SET start_date = CASE "
            "WHEN deadline IS NOT NULL AND deadline < ? THEN deadline "
            "ELSE ? END WHERE start_date IS NULL",
            (today, today),
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS task_tags (
                task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                name_key TEXT NOT NULL,
                position INTEGER NOT NULL,
                PRIMARY KEY (task_id, name)
            )
            """
        )
        tag_columns = {
            row[1] for row in conn.execute("PRAGMA table_info(task_tags)")
        }
        if "name_key" not in tag_columns:
            conn.execute("ALTER TABLE task_tags ADD COLUMN name_key TEXT")
            for task_id, name in conn.execute("SELECT task_id, name FROM task_tags"):
                conn.execute(
                    "UPDATE task_tags SET name_key = ? WHERE task_id = ? AND name = ?",
                    (name.casefold(), task_id, name),
                )
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_task_tags_unique_key "
            "ON task_tags(task_id, name_key)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_task_tags_key "
            "ON task_tags(name_key, task_id)"
        )
        conn.execute(
            """CREATE TABLE IF NOT EXISTS notes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                content TEXT NOT NULL DEFAULT '[]',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )"""
        )
        conn.execute(
            """CREATE TABLE IF NOT EXISTS note_tasks (
                note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
                PRIMARY KEY (note_id, task_id)
            )"""
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_note_tasks_task ON note_tasks(task_id)"
        )
        conn.execute(
            """CREATE TABLE IF NOT EXISTS note_attachments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                filename TEXT NOT NULL,
                media_type TEXT NOT NULL,
                size INTEGER NOT NULL,
                storage_name TEXT NOT NULL UNIQUE
            )"""
        )
        conn.execute(
            """CREATE TABLE IF NOT EXISTS schedule_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
                first_date TEXT NOT NULL,
                ends_on TEXT,
                start_time TEXT NOT NULL,
                end_time TEXT NOT NULL,
                repeat_every_weeks INTEGER NOT NULL CHECK (repeat_every_weeks IN (0, 1, 2))
            )"""
        )
        conn.execute(
            """CREATE TABLE IF NOT EXISTS schedule_exceptions (
                entry_id INTEGER NOT NULL REFERENCES schedule_entries(id) ON DELETE CASCADE,
                date TEXT NOT NULL,
                PRIMARY KEY (entry_id, date)
            )"""
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_schedule_project ON schedule_entries(project_id)"
        )
        conn.commit()
