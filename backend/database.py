import sqlite3
from contextlib import closing
from pathlib import Path


DB_PATH = Path(__file__).with_name("tasks.db")


def init_db() -> None:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                description TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'todo'
            )
            """
        )
        conn.commit()
