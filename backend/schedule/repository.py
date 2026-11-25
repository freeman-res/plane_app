import sqlite3
from contextlib import closing
from datetime import date, time

from backend.database import DB_PATH
from backend.schedule.schemas import ScheduleCreate, ScheduleEntry


_FIELDS = (
    "title", "description", "project_id", "first_date", "ends_on",
    "start_time", "end_time", "repeat_every_weeks",
)


def _entry(conn: sqlite3.Connection, row: sqlite3.Row | None) -> ScheduleEntry | None:
    if row is None:
        return None
    dates = [item[0] for item in conn.execute(
        "SELECT date FROM schedule_exceptions WHERE entry_id = ? ORDER BY date",
        (row["id"],),
    )]
    return ScheduleEntry(**dict(row), excluded_dates=dates)


def get_entry(entry_id: int) -> ScheduleEntry | None:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.row_factory = sqlite3.Row
        row = conn.execute("SELECT * FROM schedule_entries WHERE id = ?", (entry_id,)).fetchone()
        return _entry(conn, row)


def list_entries(project_id: int | None = None) -> list[ScheduleEntry]:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.row_factory = sqlite3.Row
        if project_id is None:
            rows = conn.execute("SELECT * FROM schedule_entries ORDER BY first_date, start_time, id").fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM schedule_entries WHERE project_id = ? "
                "ORDER BY first_date, start_time, id", (project_id,),
            ).fetchall()
        return [_entry(conn, row) for row in rows]


def _db_value(value):
    return value.isoformat() if isinstance(value, (date, time)) else value


def create_entry(payload: ScheduleCreate) -> ScheduleEntry:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        values = [_db_value(getattr(payload, field)) for field in _FIELDS]
        cursor = conn.execute(
            f"INSERT INTO schedule_entries ({', '.join(_FIELDS)}) "
            f"VALUES ({', '.join('?' for _ in _FIELDS)})", values,
        )
        conn.commit()
        conn.row_factory = sqlite3.Row
        row = conn.execute("SELECT * FROM schedule_entries WHERE id = ?", (cursor.lastrowid,)).fetchone()
        return _entry(conn, row)


def update_entry(entry_id: int, changes: dict) -> ScheduleEntry | None:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        conn.row_factory = sqlite3.Row
        if conn.execute("SELECT 1 FROM schedule_entries WHERE id = ?", (entry_id,)).fetchone() is None:
            return None
        fields = [field for field in _FIELDS if field in changes]
        values = [_db_value(changes[field]) for field in fields]
        conn.execute(
            f"UPDATE schedule_entries SET {', '.join(f'{field} = ?' for field in fields)} WHERE id = ?",
            (*values, entry_id),
        )
        if {"first_date", "ends_on", "repeat_every_weeks"} & changes.keys():
            conn.execute("DELETE FROM schedule_exceptions WHERE entry_id = ?", (entry_id,))
        conn.commit()
        row = conn.execute("SELECT * FROM schedule_entries WHERE id = ?", (entry_id,)).fetchone()
        return _entry(conn, row)


def delete_entry(entry_id: int) -> bool:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        cursor = conn.execute("DELETE FROM schedule_entries WHERE id = ?", (entry_id,))
        conn.commit()
        return cursor.rowcount > 0


def set_exception(entry_id: int, occurrence_date: date, excluded: bool) -> ScheduleEntry | None:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        conn.row_factory = sqlite3.Row
        row = conn.execute("SELECT * FROM schedule_entries WHERE id = ?", (entry_id,)).fetchone()
        if row is None:
            return None
        if excluded:
            conn.execute(
                "INSERT OR IGNORE INTO schedule_exceptions (entry_id, date) VALUES (?, ?)",
                (entry_id, occurrence_date.isoformat()),
            )
        else:
            conn.execute(
                "DELETE FROM schedule_exceptions WHERE entry_id = ? AND date = ?",
                (entry_id, occurrence_date.isoformat()),
            )
        conn.commit()
        return _entry(conn, row)
