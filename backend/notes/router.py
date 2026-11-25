from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import FileResponse

from backend.notes import repository, service
from backend.notes.schemas import Attachment, Note, NoteCreate, NoteToTask, NoteUpdate
from backend.tasks.schemas import Task
from backend.tasks.service import ProjectNotFound


router = APIRouter()


@router.get("/notes", response_model=list[Note])
def list_notes(task_id: int | None = None) -> list[Note]:
    return service.list_notes(task_id)


@router.post("/notes", response_model=Note, status_code=201)
def create_note(payload: NoteCreate) -> Note:
    return service.create_note(payload)


@router.get("/notes/{note_id}", response_model=Note)
def get_note(note_id: int) -> Note:
    note = service.get_note(note_id)
    if note is None:
        raise HTTPException(status_code=404, detail="Note not found")
    return note


@router.patch("/notes/{note_id}", response_model=Note)
def update_note(note_id: int, payload: NoteUpdate) -> Note:
    note = service.update_note(note_id, payload)
    if note is None:
        raise HTTPException(status_code=404, detail="Note not found")
    return note


@router.delete("/notes/{note_id}", status_code=204)
def delete_note(note_id: int) -> None:
    if not service.delete_note(note_id):
        raise HTTPException(status_code=404, detail="Note not found")


@router.put("/notes/{note_id}/tasks/{task_id}", response_model=Note)
def link_task(note_id: int, task_id: int) -> Note:
    try:
        note = service.link_task(note_id, task_id)
    except service.TaskNotFound:
        raise HTTPException(status_code=404, detail="Task not found") from None
    if note is None:
        raise HTTPException(status_code=404, detail="Note not found")
    return note


@router.delete("/notes/{note_id}/tasks/{task_id}", response_model=Note)
def unlink_task(note_id: int, task_id: int) -> Note:
    note = service.unlink_task(note_id, task_id)
    if note is None:
        raise HTTPException(status_code=404, detail="Note not found")
    return note


@router.post("/notes/{note_id}/create-task", response_model=Task, status_code=201)
def create_task_from_note(note_id: int, payload: NoteToTask) -> Task:
    try:
        task = service.create_task_from_note(note_id, payload)
    except ProjectNotFound:
        raise HTTPException(status_code=404, detail="Project not found") from None
    if task is None:
        raise HTTPException(status_code=404, detail="Note not found")
    return task


@router.post("/notes/{note_id}/attachments", response_model=Attachment, status_code=201)
async def upload_attachment(
    note_id: int, request: Request,
    filename: Annotated[str, Query(min_length=1, max_length=255)],
) -> Attachment:
    if service.get_note(note_id) is None:
        raise HTTPException(status_code=404, detail="Note not found")
    media_type = request.headers.get("content-type", "").lower().strip()
    limit = service._LIMITS.get(media_type)
    if limit is None:
        raise HTTPException(status_code=415, detail="Unsupported image or audio type")
    chunks = bytearray()
    async for chunk in request.stream():
        if len(chunks) + len(chunk) > limit:
            raise HTTPException(status_code=413, detail="Attachment too large")
        chunks.extend(chunk)
    if not service.valid_media(chunks, media_type):
        raise HTTPException(status_code=415, detail="File contents do not match media type")
    safe_name = filename.replace("\\", "/").split("/")[-1].strip()
    if not safe_name or safe_name in {".", ".."}:
        raise HTTPException(status_code=422, detail="Invalid filename")
    result = service.save_attachment(note_id, safe_name, media_type, chunks)
    if result is None:
        raise HTTPException(status_code=404, detail="Note not found")
    return result


@router.get("/notes/{note_id}/attachments/{attachment_id}")
def download_attachment(note_id: int, attachment_id: int) -> FileResponse:
    item = repository.get_attachment(note_id, attachment_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Attachment not found")
    metadata, name = item
    path = service.upload_dir() / name
    if not path.is_file():
        raise HTTPException(status_code=404, detail="Attachment file not found")
    return FileResponse(path, media_type=metadata.media_type, filename=metadata.filename)


@router.delete("/notes/{note_id}/attachments/{attachment_id}", status_code=204)
def delete_attachment(note_id: int, attachment_id: int) -> None:
    if not service.delete_attachment(note_id, attachment_id):
        raise HTTPException(status_code=404, detail="Attachment not found")
