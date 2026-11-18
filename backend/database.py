import sqlite3
from contextlib import closing
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
                project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL
            )
            """
        )
        columns = {row[1] for row in conn.execute("PRAGMA table_info(tasks)")}
        if "project_id" not in columns:
            conn.execute(
                "ALTER TABLE tasks ADD COLUMN project_id INTEGER "
                "REFERENCES projects(id) ON DELETE SET NULL"
            )
        conn.commit()
