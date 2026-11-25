import asyncio
import json
import sqlite3
import tempfile
import unittest
from contextlib import closing
from datetime import date, timedelta
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException
from pydantic import ValidationError

from backend import database
from backend.main import app
from backend.notes import repository as note_repository
from backend.notes import router as notes
from backend.notes.schemas import NoteCreate, NoteToTask, NoteUpdate
from backend.projects import repository as project_repository
from backend.projects.router import create_project
from backend.projects.schemas import ProjectCreate
from backend.tasks import repository as task_repository
from backend.tasks.router import create_task, delete_task
from backend.tasks.schemas import TaskCreate


class FakeRequest:
    def __init__(self, media_type, data):
        self.headers = {"content-type": media_type}
        self.data = data

    async def stream(self):
        yield self.data


class NotesApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        path = Path(self.temp.name) / "tasks.db"
        self.patches = [
            patch.object(module, "DB_PATH", path)
            for module in (database, note_repository, project_repository, task_repository)
        ]
        for item in self.patches:
            item.start()
        database.init_db()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.temp.cleanup()

    def test_rich_text_crud_persistence_and_validation(self):
        content = [{
            "type": "heading",
            "spans": [{"text": "Идея", "font_family": "serif", "font_size": 22,
                       "bold": True, "color": "#112233"}],
        }]
        note = notes.create_note(NoteCreate(title="  Черновик  ", content=content))
        self.assertEqual(note.title, "Черновик")
        self.assertEqual(note.content[0].spans[0].font_family, "serif")
        database.init_db()
        self.assertEqual(notes.get_note(note.id).content, note.content)
        self.assertEqual([item.id for item in notes.list_notes()], [note.id])
        updated = notes.update_note(note.id, NoteUpdate(title=" Новое имя ", content=content))
        self.assertEqual(updated.title, "Новое имя")
        self.assertEqual(updated.content, note.content)
        self.assertEqual(notes.get_note(note.id).content, note.content)
        updated = notes.update_note(note.id, NoteUpdate(content=[]))
        self.assertEqual(updated.content, [])
        self.assertEqual(updated.created_at, note.created_at)
        notes.delete_note(note.id)
        self.assertEqual(notes.list_notes(), [])
        with self.assertRaises(HTTPException) as error:
            notes.get_note(note.id)
        self.assertEqual(error.exception.status_code, 404)
        for payload in (
            {"title": " ", "content": []},
            {"title": "x", "content": [{"spans": [{"text": "x", "font_size": 2}]}]},
            {"title": "x", "content": [{"spans": [{"text": "x", "color": "red"}]}]},
            {"title": "x", "content": [{"spans": [{"text": "x", "font_family": "other"}]}]},
        ):
            with self.assertRaises(ValidationError):
                NoteCreate.model_validate(payload)
        with self.assertRaises(ValidationError):
            NoteUpdate(content=None)
        with self.assertRaises(ValidationError):
            NoteUpdate()

    def test_patch_note_through_http(self):
        note = notes.create_note(NoteCreate(title="Before"))
        body = json.dumps({"title": "After", "content": [
            {"type": "paragraph", "spans": [
                {"text": "first", "font_family": "mono"},
                {"text": " second", "bold": True, "font_size": 18},
            ]},
        ]}).encode("utf-8")

        async def request():
            replies = []
            received = False

            async def receive():
                nonlocal received
                if not received:
                    received = True
                    return {"type": "http.request", "body": body, "more_body": False}
                await asyncio.sleep(3600)

            async def send(message):
                replies.append(message)

            await app({
                "type": "http", "asgi": {"version": "3.0"},
                "http_version": "1.1", "method": "PATCH", "scheme": "http",
                "path": f"/notes/{note.id}", "root_path": "", "query_string": b"",
                "headers": [(b"content-type", b"application/json")],
                "client": ("test", 1234), "server": ("test", 80),
            }, receive, send)
            return replies

        replies = asyncio.run(request())
        self.assertEqual(replies[0]["status"], 200)
        payload = json.loads(b"".join(
            part.get("body", b"") for part in replies if part["type"] == "http.response.body"
        ))
        self.assertEqual(payload["title"], "After")
        self.assertEqual(payload["content"][0]["spans"][1]["font_size"], 18)
        self.assertEqual(notes.get_note(note.id).content[0].spans[0].font_family, "mono")

    def test_task_links_conversion_and_cleanup(self):
        project = create_project(ProjectCreate(name="Coursework"))
        note = notes.create_note(NoteCreate(title="Research", content=[
            {"spans": [{"text": "Step 1"}]}, {"spans": [{"text": "Step 2"}]},
        ]))
        deadline = date.today() + timedelta(days=5)
        task = notes.create_task_from_note(note.id, NoteToTask(
            project_id=project.id, deadline=deadline, priority="high",
        ))
        self.assertEqual(task.description, "Step 1\nStep 2")
        self.assertEqual(task.priority, "high")
        self.assertEqual(task.deadline, deadline)
        self.assertEqual(notes.get_note(note.id).task_ids, [task.id])
        self.assertEqual(notes.list_notes(task_id=task.id)[0].id, note.id)
        self.assertEqual(notes.link_task(note.id, task.id).task_ids, [task.id])
        self.assertEqual(notes.unlink_task(note.id, task.id).task_ids, [])
        self.assertEqual(notes.link_task(note.id, task.id).task_ids, [task.id])
        delete_task(task.id)
        self.assertEqual(notes.get_note(note.id).task_ids, [])
        self.assertIsNotNone(notes.get_note(note.id))
        with self.assertRaises(HTTPException) as error:
            notes.link_task(note.id, 999)
        self.assertEqual(error.exception.status_code, 404)
        with self.assertRaises(HTTPException) as error:
            notes.create_task_from_note(note.id, NoteToTask(project_id=999))
        self.assertEqual(error.exception.status_code, 404)
        self.assertEqual(notes.get_note(note.id).task_ids, [])

    def test_upload_download_delete_and_invalid_media(self):
        note = notes.create_note(NoteCreate(title="Media"))
        png = b"\x89PNG\r\n\x1a\n" + b"data"
        item = asyncio.run(notes.upload_attachment(
            note.id, FakeRequest("image/png", png), "..\\photo.png",
        ))
        self.assertEqual(item.filename, "photo.png")
        self.assertEqual(item.size, len(png))
        self.assertEqual(notes.get_note(note.id).attachments, [item])
        response = notes.download_attachment(note.id, item.id)
        self.assertEqual(response.path.read_bytes(), png)
        sound = asyncio.run(notes.upload_attachment(
            note.id, FakeRequest("audio/wav", b"RIFF....WAVEdata"), "voice.wav",
        ))
        self.assertEqual(sound.media_type, "audio/wav")
        for media, data, status in (
            ("text/html", b"<script>x</script>", 415),
            ("image/png", b"not a png", 415),
            ("image/png", png * 2000000, 413),
        ):
            with self.assertRaises(HTTPException) as error:
                asyncio.run(notes.upload_attachment(
                    note.id, FakeRequest(media, data), "bad.dat",
                ))
            self.assertEqual(error.exception.status_code, status)
        notes.delete_attachment(note.id, item.id)
        self.assertFalse(response.path.exists())
        audio_path = notes.download_attachment(note.id, sound.id).path
        notes.delete_note(note.id)
        self.assertFalse(audio_path.exists())
        with closing(sqlite3.connect(database.DB_PATH)) as conn:
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM note_attachments").fetchone()[0], 0)


if __name__ == "__main__":
    unittest.main()
