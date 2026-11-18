import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException
from pydantic import ValidationError

from backend import database
from backend.main import app, health
from backend.projects import repository as project_repository
from backend.projects import router as project_routes
from backend.projects.schemas import ProjectCreate
from backend.tasks import repository, router as routes
from backend.tasks.schemas import TaskCreate, TaskUpdate


class TasksApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        db_path = Path(self.temp.name) / "tasks.db"
        self.db_patch = patch.object(database, "DB_PATH", db_path)
        self.service_patch = patch.object(repository, "DB_PATH", db_path)
        self.project_patch = patch.object(project_repository, "DB_PATH", db_path)
        self.db_patch.start()
        self.service_patch.start()
        self.project_patch.start()
        database.init_db()

    def tearDown(self):
        self.project_patch.stop()
        self.service_patch.stop()
        self.db_patch.stop()
        self.temp.cleanup()

    def test_create_list_update_delete_and_persist(self):
        self.assertEqual(health(), {"status": "ok"})
        created = routes.create_task(TaskCreate(title="Test", description="Details"))
        self.assertEqual(created.status, "todo")
        database.init_db()  # Повторный запуск не стирает задачи.
        self.assertEqual([task.id for task in routes.get_tasks()], [created.id])
        updated = routes.update_task(created.id, TaskUpdate(status="done"))
        self.assertEqual(updated.status, "done")
        updated = routes.update_task(
            created.id, TaskUpdate(title="Renamed", description="Updated")
        )
        self.assertEqual((updated.title, updated.description, updated.status),
                         ("Renamed", "Updated", "done"))
        updated = routes.update_task(created.id, TaskUpdate(description=""))
        self.assertEqual(updated.description, "")
        self.assertEqual(routes.get_tasks()[0].title, "Renamed")
        self.assertIsNone(routes.delete_task(created.id))
        self.assertEqual(routes.get_tasks(), [])

    def test_validation_and_missing_tasks(self):
        with self.assertRaises(ValidationError):
            TaskCreate(title="")
        with self.assertRaises(ValidationError):
            TaskUpdate(status="doing")
        with self.assertRaises(ValidationError):
            TaskUpdate(title="")
        with self.assertRaises(ValidationError):
            TaskUpdate(title=None)
        with self.assertRaises(ValidationError):
            TaskUpdate()
        for operation in (
            lambda: routes.update_task(999, TaskUpdate(status="done")),
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
                ("get", "/projects"),
                ("post", "/projects"),
                ("delete", "/projects/{project_id}"),
            },
        )

    def test_delete_project_keeps_its_tasks_unassigned(self):
        project = project_routes.create_project(ProjectCreate(name="Coursework"))
        task = routes.create_task(TaskCreate(title="Draft", project_id=project.id))
        self.assertIsNone(project_routes.delete_project(project.id))
        self.assertEqual(project_routes.get_projects(), [])
        self.assertIsNone(routes.get_tasks()[0].project_id)
        self.assertEqual(routes.get_tasks()[0].id, task.id)
        with self.assertRaises(HTTPException) as raised:
            project_routes.delete_project(project.id)
        self.assertEqual(raised.exception.status_code, 404)

    def test_projects_and_task_assignment(self):
        self.assertEqual(project_routes.get_projects(), [])
        project = project_routes.create_project(ProjectCreate(name="  Учёба  "))
        self.assertEqual(project.name, "Учёба")
        other = project_routes.create_project(ProjectCreate(name="Работа"))
        unassigned = routes.create_task(TaskCreate(title="Без проекта"))
        assigned = routes.create_task(TaskCreate(title="Курсовая", project_id=project.id))
        self.assertIsNone(unassigned.project_id)
        self.assertEqual([item.id for item in routes.get_tasks(project.id)], [assigned.id])
        self.assertEqual(routes.get_tasks(other.id), [])
        moved = routes.update_task(assigned.id, TaskUpdate(project_id=other.id))
        self.assertEqual(moved.project_id, other.id)
        self.assertEqual(routes.get_tasks(project.id), [])
        cleared = routes.update_task(assigned.id, TaskUpdate(project_id=None))
        self.assertIsNone(cleared.project_id)
        self.assertEqual(len(routes.get_tasks()), 2)
        for operation in (
            lambda: routes.create_task(TaskCreate(title="Bad", project_id=999)),
            lambda: routes.update_task(assigned.id, TaskUpdate(project_id=999)),
        ):
            with self.assertRaises(HTTPException) as raised:
                operation()
            self.assertEqual(raised.exception.status_code, 404)
        with self.assertRaises(ValidationError):
            ProjectCreate(name="   ")

    def test_existing_database_migrates_without_losing_tasks(self):
        legacy_path = Path(self.temp.name) / "legacy.db"
        with closing(sqlite3.connect(legacy_path)) as conn:
            conn.execute(
                "CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL, "
                "description TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'todo')"
            )
            conn.execute(
                "INSERT INTO tasks (title, description, status) VALUES (?, ?, ?)",
                ("Old task", "Keep me", "done"),
            )
            conn.commit()
        with patch.object(database, "DB_PATH", legacy_path):
            database.init_db()
            database.init_db()
        with closing(sqlite3.connect(legacy_path)) as conn:
            self.assertEqual(
                conn.execute(
                    "SELECT title, description, status, project_id FROM tasks"
                ).fetchall(),
                [("Old task", "Keep me", "done", None)],
            )

if __name__ == "__main__":
    unittest.main()
