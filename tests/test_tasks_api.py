import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException
from pydantic import ValidationError

from backend import database
from backend.main import app, health
from backend.routes import tasks as routes
from backend.schemas import TaskCreate, TaskStatusUpdate
from backend.services import tasks as task_service


class TasksApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        db_path = Path(self.temp.name) / "tasks.db"
        self.db_patch = patch.object(database, "DB_PATH", db_path)
        self.service_patch = patch.object(task_service, "DB_PATH", db_path)
        self.db_patch.start()
        self.service_patch.start()
        database.init_db()

    def tearDown(self):
        self.service_patch.stop()
        self.db_patch.stop()
        self.temp.cleanup()

    def test_create_list_update_delete_and_persist(self):
        self.assertEqual(health(), {"status": "ok"})
        created = routes.create_task(TaskCreate(title="Test", description="Details"))
        self.assertEqual(created.status, "todo")
        database.init_db()  # Повторный запуск не стирает задачи.
        self.assertEqual([task.id for task in routes.get_tasks()], [created.id])
        updated = routes.update_task_status(created.id, TaskStatusUpdate(status="done"))
        self.assertEqual(updated.status, "done")
        self.assertIsNone(routes.delete_task(created.id))
        self.assertEqual(routes.get_tasks(), [])

    def test_validation_and_missing_tasks(self):
        with self.assertRaises(ValidationError):
            TaskCreate(title="")
        with self.assertRaises(ValidationError):
            TaskStatusUpdate(status="doing")
        for operation in (
            lambda: routes.update_task_status(999, TaskStatusUpdate(status="done")),
            lambda: routes.delete_task(999),
        ):
            with self.assertRaises(HTTPException) as raised:
                operation()
            self.assertEqual(raised.exception.status_code, 404)

    def test_documented_http_methods(self):
        methods = {
            (method, path)
            for path, spec in app.openapi()["paths"].items()
            for method in spec
        }
        self.assertEqual(
            methods,
            {
                ("get", "/health"),
                ("get", "/tasks"),
                ("post", "/tasks"),
                ("patch", "/tasks/{task_id}"),
                ("delete", "/tasks/{task_id}"),
            },
        )


if __name__ == "__main__":
    unittest.main()
