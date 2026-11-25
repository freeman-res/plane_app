from pathlib import Path
from uuid import uuid4

from backend.notes import repository
from backend.notes.schemas import Note, NoteCreate, NoteToTask, NoteUpdate
from backend.tasks import repository as task_repository
from backend.tasks import service as task_service
from backend.tasks.schemas import Task, TaskCreate


class TaskNotFound(Exception):
    pass


def list_notes(task_id: int | None = None) -> list[Note]:
    return repository.list_notes(task_id)


def get_note(note_id: int) -> Note | None:
    return repository.get_note(note_id)


def create_note(payload: NoteCreate) -> Note:
    return repository.create_note(payload)


def update_note(note_id: int, payload: NoteUpdate) -> Note | None:
    return repository.update_note(note_id, payload.model_dump(exclude_unset=True))


def upload_dir() -> Path:
    return repository.DB_PATH.parent / "uploads"


def delete_note(note_id: int) -> bool:
    names = repository.delete_note(note_id)
    if names is None:
        return False
    for name in names:
        (upload_dir() / name).unlink(missing_ok=True)
    return True


def link_task(note_id: int, task_id: int) -> Note | None:
    if task_repository.get_task(task_id) is None:
        raise TaskNotFound
    return repository.link_task(note_id, task_id)


def unlink_task(note_id: int, task_id: int) -> Note | None:
    return repository.unlink_task(note_id, task_id)


def create_task_from_note(note_id: int, options: NoteToTask) -> Task | None:
    note = get_note(note_id)
    if note is None:
        return None
    description = "\n".join(
        "".join(span.text for span in block.spans) for block in note.content
    )
    task = task_service.create_task(TaskCreate(
        title=note.title, description=description, **options.model_dump(),
    ))
    repository.link_task(note_id, task.id)
    return task


_LIMITS = {
    "image/jpeg": 10 * 1024 * 1024,
    "image/png": 10 * 1024 * 1024,
    "image/gif": 10 * 1024 * 1024,
    "image/webp": 10 * 1024 * 1024,
    "audio/mpeg": 25 * 1024 * 1024,
    "audio/wav": 25 * 1024 * 1024,
    "audio/ogg": 25 * 1024 * 1024,
    "audio/mp4": 25 * 1024 * 1024,
    "audio/webm": 25 * 1024 * 1024,
}


def valid_media(data: bytes, media_type: str) -> bool:
    checks = {
        "image/jpeg": lambda b: b.startswith(b"\xff\xd8\xff"),
        "image/png": lambda b: b.startswith(b"\x89PNG\r\n\x1a\n"),
        "image/gif": lambda b: b.startswith((b"GIF87a", b"GIF89a")),
        "image/webp": lambda b: b.startswith(b"RIFF") and b[8:12] == b"WEBP",
        "audio/mpeg": lambda b: b.startswith(b"ID3") or (len(b) > 1 and b[0] == 0xff and b[1] & 0xe0 == 0xe0),
        "audio/wav": lambda b: b.startswith(b"RIFF") and b[8:12] == b"WAVE",
        "audio/ogg": lambda b: b.startswith(b"OggS"),
        "audio/mp4": lambda b: b[4:8] == b"ftyp",
        "audio/webm": lambda b: b.startswith(b"\x1a\x45\xdf\xa3"),
    }
    return media_type in checks and checks[media_type](data)


def save_attachment(note_id: int, filename: str, media_type: str, data: bytes):
    if repository.get_note(note_id) is None:
        return None
    directory = upload_dir()
    directory.mkdir(parents=True, exist_ok=True)
    storage_name = uuid4().hex
    path = directory / storage_name
    try:
        path.write_bytes(data)
        return repository.add_attachment(note_id, filename, media_type, len(data), storage_name)
    except Exception:
        path.unlink(missing_ok=True)
        raise


def delete_attachment(note_id: int, attachment_id: int) -> bool:
    name = repository.delete_attachment(note_id, attachment_id)
    if name is None:
        return False
    (upload_dir() / name).unlink(missing_ok=True)
    return True
