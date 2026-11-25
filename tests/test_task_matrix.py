import tempfile
import unittest
import sqlite3
from contextlib import closing
from datetime import date, timedelta
from pathlib import Path
from unittest.mock import patch

from backend import database
from backend.projects import repository as project_repository
from backend.projects.router import create_project
from backend.projects.schemas import ProjectCreate
from backend.tasks import repository as task_repository
from backend.tasks.router import create_task, get_task_matrix, update_task
from backend.tasks.schemas import TaskCreate, TaskUpdate


class TaskMatrixTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        path = Path(self.temp.name) / "tasks.db"
        self.patches = [patch.object(module, "DB_PATH", path) for module in (
            database, project_repository, task_repository,
        )]
        for item in self.patches:
            item.start()
        database.init_db()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.temp.cleanup()

    def test_four_quadrants_auto_deadline_manual_override_and_project_filter(self):
        today = date.today()
        project = create_project(ProjectCreate(name="Coursework"))
        other_project = create_project(ProjectCreate(name="Other"))
        a = create_task(TaskCreate(title="A", priority="high", urgent=True, project_id=project.id))
        b = create_task(TaskCreate(title="B", priority="high", urgent=False,
                                   deadline=today + timedelta(days=1), project_id=project.id))
        c = create_task(TaskCreate(title="C", priority="medium",
                                   deadline=today + timedelta(days=2), project_id=project.id))
        d = create_task(TaskCreate(title="D", priority="low",
                                   deadline=today + timedelta(days=3), project_id=project.id))
        create_task(TaskCreate(title="Finished", status="done", urgent=True,
                               priority="high", project_id=project.id))
        create_task(TaskCreate(title="Different project", urgent=True,
                               priority="high", project_id=other_project.id))
        database.init_db()
        matrix = get_task_matrix(project.id)
        self.assertEqual([task.id for task in matrix.urgent_important], [a.id])
        self.assertEqual([task.id for task in matrix.not_urgent_important], [b.id])
        self.assertEqual([task.id for task in matrix.urgent_not_important], [c.id])
        self.assertEqual([task.id for task in matrix.not_urgent_not_important], [d.id])
        self.assertTrue(matrix.urgent_not_important[0].is_urgent)
        self.assertEqual(matrix.urgent_not_important[0].matrix_quadrant,
                         "urgent_not_important")
        response = matrix.model_dump(mode="json")
        self.assertFalse(response["not_urgent_not_important"][0]["is_urgent"])
        changed = update_task(d.id, TaskUpdate(priority="high", urgent=True))
        self.assertEqual(changed.matrix_quadrant, "urgent_important")
        self.assertEqual([task.id for task in get_task_matrix(project.id).urgent_important],
                         [d.id, a.id])
        reset = update_task(b.id, TaskUpdate(urgent=None))
        self.assertIsNone(reset.urgent)
        self.assertTrue(reset.is_urgent)
        self.assertIn(b.id, [task.id for task in get_task_matrix(project.id).urgent_important])
        self.assertEqual(len(get_task_matrix().urgent_important), 4)

    def test_existing_tasks_gain_automatic_urgency_without_data_loss(self):
        old_path = Path(self.temp.name) / "old.db"
        with closing(sqlite3.connect(old_path)) as conn:
            conn.execute(
                "CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL, "
                "description TEXT NOT NULL, status TEXT NOT NULL)"
            )
            conn.execute("INSERT INTO tasks (title, description, status) "
                         "VALUES ('Existing', '', 'todo')")
            conn.commit()
        with patch.object(database, "DB_PATH", old_path), patch.object(
            task_repository, "DB_PATH", old_path,
        ):
            database.init_db()
            database.init_db()
            tasks = task_repository.list_tasks()
        self.assertEqual(len(tasks), 1)
        self.assertEqual(tasks[0].title, "Existing")
        self.assertIsNone(tasks[0].urgent)
        self.assertFalse(tasks[0].is_urgent)


if __name__ == "__main__":
    unittest.main()
