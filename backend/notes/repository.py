import json
import sqlite3
from contextlib import closing
from datetime import datetime, timezone

from backend.database import DB_PATH
from backend.notes.schemas import Attachment, Note, NoteCreate


def _get(conn: sqlite3.Connection, note_id: int) -> Note | None:
    conn.row_factory = sqlite3.Row
    row = conn.execute("SELECT * FROM notes WHERE id = ?", (note_id,)).fetchone()
    if row is None:
        return None
    task_ids = [item[0] for item in conn.execute(
        "SELECT task_id FROM note_tasks WHERE note_id = ? ORDER BY task_id", (note_id,)
    )]
    attachments = [Attachment(**dict(item)) for item in conn.execute(
        "SELECT id, note_id, filename, media_type, size FROM note_attachments "
        "WHERE note_id = ? ORDER BY id", (note_id,)
    )]
    return Note(
        id=row["id"], title=row["title"], content=json.loads(row["content"]),
        created_at=row["created_at"], updated_at=row["updated_at"],
        task_ids=task_ids, attachments=attachments,
    )


def get_note(note_id: int) -> Note | None:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        return _get(conn, note_id)


def list_notes(task_id: int | None = None) -> list[Note]:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        if task_id is None:
            ids = conn.execute("SELECT id FROM notes ORDER BY updated_at DESC, id DESC")
        else:
            ids = conn.execute(
                "SELECT notes.id FROM notes JOIN note_tasks ON note_tasks.note_id = notes.id "
                "WHERE note_tasks.task_id = ? ORDER BY notes.updated_at DESC, notes.id DESC",
                (task_id,),
            )
        return [_get(conn, row[0]) for row in ids.fetchall()]


def create_note(payload: NoteCreate) -> Note:
    now = datetime.now(timezone.utc).isoformat()
    with closing(sqlite3.connect(DB_PATH)) as conn:
        cursor = conn.execute(
            "INSERT INTO notes (title, content, created_at, updated_at) VALUES (?, ?, ?, ?)",
            (payload.title, json.dumps([block.model_dump() for block in payload.content]), now, now),
        )
        conn.commit()
        return _get(conn, cursor.lastrowid)


def update_note(note_id: int, changes: dict) -> Note | None:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        if _get(conn, note_id) is None:
            return None
        fields = []
        values = []
        for field in ("title", "content"):
            if field in changes:
                fields.append(f"{field} = ?")
                value = changes[field]
                values.append(json.dumps(value) if field == "content" else value)
        fields.append("updated_at = ?")
        values.append(datetime.now(timezone.utc).isoformat())
        conn.execute(f"UPDATE notes SET {', '.join(fields)} WHERE id = ?", (*values, note_id))
        conn.commit()
        return _get(conn, note_id)


def delete_note(note_id: int) -> list[str] | None:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        if _get(conn, note_id) is None:
            return None
        names = [row[0] for row in conn.execute(
            "SELECT storage_name FROM note_attachments WHERE note_id = ?", (note_id,)
        )]
        conn.execute("DELETE FROM notes WHERE id = ?", (note_id,))
        conn.commit()
        return names


def link_task(note_id: int, task_id: int) -> Note | None:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        if _get(conn, note_id) is None:
            return None
        conn.execute(
            "INSERT OR IGNORE INTO note_tasks (note_id, task_id) VALUES (?, ?)",
            (note_id, task_id),
        )
        conn.commit()
        return _get(conn, note_id)


def unlink_task(note_id: int, task_id: int) -> Note | None:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        if _get(conn, note_id) is None:
            return None
        conn.execute(
            "DELETE FROM note_tasks WHERE note_id = ? AND task_id = ?", (note_id, task_id)
        )
        conn.commit()
        return _get(conn, note_id)


def add_attachment(note_id: int, filename: str, media_type: str, size: int, storage_name: str) -> Attachment:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        cursor = conn.execute(
            "INSERT INTO note_attachments (note_id, filename, media_type, size, storage_name) "
            "VALUES (?, ?, ?, ?, ?)", (note_id, filename, media_type, size, storage_name),
        )
        conn.commit()
        return Attachment(
            id=cursor.lastrowid, note_id=note_id, filename=filename,
            media_type=media_type, size=size,
        )


def get_attachment(note_id: int, attachment_id: int) -> tuple[Attachment, str] | None:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.row_factory = sqlite3.Row
        row = conn.execute(
            "SELECT * FROM note_attachments WHERE id = ? AND note_id = ?",
            (attachment_id, note_id),
        ).fetchone()
        if row is None:
            return None
        return Attachment(**dict(row)), row["storage_name"]


def delete_attachment(note_id: int, attachment_id: int) -> str | None:
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        item = get_attachment(note_id, attachment_id)
        if item is None:
            return None
        conn.execute("DELETE FROM note_attachments WHERE id = ?", (attachment_id,))
        conn.commit()
        return item[1]
