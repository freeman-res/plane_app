import sqlite3
import tempfile
import unittest
from contextlib import closing
from datetime import date
from pathlib import Path
from unittest.mock import patch

from pydantic import ValidationError

from backend import database
from backend.projects import repository as projects
from backend.projects import router as project_routes
from backend.projects.schemas import ProjectCreate
from backend.tasks import repository as tasks
from backend.tasks import router as task_routes
from backend.tasks.schemas import TaskCreate, TaskUpdate


class TaskMoscowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "tasks.db"
        self.patches = [
            patch.object(database, "DB_PATH", self.path),
            patch.object(projects, "DB_PATH", self.path),
            patch.object(tasks, "DB_PATH", self.path),
        ]
        for item in self.patches:
            item.start()
        database.init_db()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.temp.cleanup()

    def test_grouped_by_project_and_reclassified_without_changing_other_fields(self):
        project = project_routes.create_project(ProjectCreate(name="Team"))
        other = project_routes.create_project(ProjectCreate(name="Other"))
        must = task_routes.create_task(TaskCreate(
            title="Required", project_id=project.id, moscow="must",
            priority="high", deadline=date(2030, 1, 2),
        ))
        undecided = task_routes.create_task(TaskCreate(
            title="Unclassified", project_id=project.id,
        ))
        task_routes.create_task(TaskCreate(
            title="Other project", project_id=other.id, moscow="should",
        ))
        task_routes.create_task(TaskCreate(
            title="Finished", project_id=project.id, moscow="wont", status="done",
        ))
        group = task_routes.get_task_moscow(project.id)
        self.assertEqual([item.id for item in group.must], [must.id])
        self.assertEqual([item.id for item in group.unassigned], [undecided.id])
        self.assertEqual(group.should, [])
        self.assertEqual(group.wont, [])

        changed = task_routes.update_task(must.id, TaskUpdate(moscow="could"))
        self.assertEqual((changed.status, changed.priority, changed.deadline),
                         (must.status, must.priority, must.deadline))
        self.assertEqual([item.id for item in task_routes.get_task_moscow(project.id).could], [must.id])
        self.assertIsNone(task_routes.update_task(must.id, TaskUpdate(moscow=None)).moscow)
        self.assertEqual(len(task_routes.get_task_moscow(project.id).unassigned), 2)
        database.init_db()  # Repeated startup preserves categories and task data.
        self.assertIsNone(tasks.get_task(must.id).moscow)

    def test_migrates_existing_database_without_assigning_categories(self):
        with closing(sqlite3.connect(self.path)) as conn:
            with conn:
                conn.execute("DROP TABLE tasks")
                conn.execute("CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL, "
                             "description TEXT NOT NULL, status TEXT NOT NULL, "
                             "project_id INTEGER, start_date TEXT, deadline TEXT, "
                             "priority TEXT, urgent INTEGER)")
                conn.execute("INSERT INTO tasks VALUES "
                             "(1, 'Old', '', 'todo', NULL, '2026-11-21', NULL, 'high', NULL)")
        database.init_db()
        self.assertIsNone(tasks.get_task(1).moscow)
        self.assertEqual(task_routes.update_task(1, TaskUpdate(moscow="wont")).moscow, "wont")
        self.assertEqual([item.id for item in task_routes.get_task_moscow().wont], [1])

    def test_unknown_category_is_rejected(self):
        with self.assertRaises(ValidationError):
            TaskCreate(title="Bad", moscow="later")
        with self.assertRaises(ValidationError):
            TaskUpdate(moscow="later")


if __name__ == "__main__":
    unittest.main()
