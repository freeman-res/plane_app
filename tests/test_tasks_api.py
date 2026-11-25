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
            TaskCreate(title="Bad", status="doing")
        with self.assertRaises(ValidationError):
            TaskCreate(title="Bad", priority="urgent")
        with self.assertRaises(ValidationError):
            TaskCreate(title="Bad", deadline="2026-02-30")
        with self.assertRaises(ValidationError):
            TaskCreate(
                title="Bad", start_date=date(2026, 12, 20),
                deadline=date(2026, 12, 15),
            )
        with self.assertRaises(ValidationError):
            TaskUpdate(start_date=None)
        with self.assertRaises(ValidationError):
            TaskUpdate(priority=None)
        with self.assertRaises(ValidationError):
            TaskUpdate(status=None)
        for tags in ([""], ["  "], ["X", "x"], ["x" * 33], ["x"] * 21):
            with self.assertRaises(ValidationError):
                TaskCreate(title="Bad", tags=tags)
        with self.assertRaises(ValidationError):
            TaskUpdate(tags=None)
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

    def test_task_stages_deadline_and_priority_round_trip(self):
        created = routes.create_task(
            TaskCreate.model_validate_json(
                '{"title":"Prepare report","status":"in_progress",'
                '"start_date":"2026-12-01",'
                '"deadline":"2026-12-15","priority":"high"}'
            )
        )
        self.assertEqual(created.status, "in_progress")
        self.assertEqual(created.deadline, date(2026, 12, 15))
        self.assertEqual(created.priority, "high")
        self.assertEqual(created.start_date, date(2026, 12, 1))
        self.assertEqual(routes.get_tasks()[0], created)
        self.assertEqual(
            routes.get_tasks()[0].model_dump(mode="json")["deadline"],
            "2026-12-15",
        )

        updated = routes.update_task(
            created.id,
            TaskUpdate(status="done", deadline=date(2026, 12, 20), priority="low"),
        )
        self.assertEqual(
            (updated.status, updated.deadline, updated.priority),
            ("done", date(2026, 12, 20), "low"),
        )
        updated = routes.update_task(
            created.id, TaskUpdate.model_validate_json('{"deadline":null}')
        )
        self.assertIsNone(updated.deadline)
        self.assertEqual(updated.status, "done")
        self.assertEqual(updated.priority, "low")
        self.assertEqual(routes.get_tasks()[0], updated)
        default = routes.create_task(TaskCreate(title="Default"))
        self.assertEqual(default.priority, "medium")
        self.assertEqual(default.start_date, date.today())
        self.assertEqual(routes.get_tasks()[-1].start_date, date.today())

        with closing(sqlite3.connect(database.DB_PATH)) as conn:
            row = conn.execute(
                "SELECT status, deadline, priority FROM tasks WHERE id = ?",
                (created.id,),
            ).fetchone()
        self.assertEqual(row, ("done", None, "low"))

    def test_start_date_and_deadline_must_form_a_valid_interval(self):
        task = routes.create_task(
            TaskCreate(
                title="Interval", start_date=date(2026, 11, 1),
                deadline=date(2026, 11, 20),
            )
        )
        for update in (
            TaskUpdate(start_date=date(2026, 11, 21)),
            TaskUpdate(deadline=date(2026, 10, 31)),
        ):
            with self.assertRaises(HTTPException) as raised:
                routes.update_task(task.id, update)
            self.assertEqual(raised.exception.status_code, 422)
            self.assertEqual(routes.get_tasks()[0].deadline, date(2026, 11, 20))
        changed = routes.update_task(
            task.id,
            TaskUpdate(start_date=date(2026, 12, 1), deadline=date(2026, 12, 10)),
        )
        self.assertEqual(changed.start_date, date(2026, 12, 1))
        self.assertEqual(changed.deadline, date(2026, 12, 10))

    def test_sorting_and_calendar_for_all_tasks_and_project(self):
        project = project_routes.create_project(ProjectCreate(name="Coursework"))
        other = project_routes.create_project(ProjectCreate(name="Other"))
        common = {"start_date": date(2026, 11, 1), "project_id": project.id}
        low = routes.create_task(TaskCreate(title="Low", deadline=date(2026, 12, 5),
                                           priority="low", **common))
        high_late = routes.create_task(TaskCreate(title="High late", deadline=date(2026, 12, 20),
                                                 priority="high", **common))
        high_early = routes.create_task(TaskCreate(title="High early", deadline=date(2026, 12, 5),
                                                  priority="high", **common))
        undated = routes.create_task(TaskCreate(title="Undated", priority="medium", **common))
        other_task = routes.create_task(TaskCreate(
            title="Other", project_id=other.id, start_date=date(2026, 11, 1),
            deadline=date(2026, 12, 8), priority="high",
        ))
        self.assertEqual(
            [task.id for task in routes.get_tasks(sort_by="priority")],
            [high_early.id, other_task.id, high_late.id, undated.id, low.id],
        )
        self.assertEqual(
            [task.id for task in routes.get_tasks(project.id, sort_by="priority")],
            [high_early.id, high_late.id, undated.id, low.id],
        )
        self.assertEqual(
            [task.id for task in routes.get_tasks(sort_by="deadline")],
            [high_early.id, low.id, other_task.id, high_late.id, undated.id],
        )
        self.assertEqual(
            [task.id for task in routes.get_tasks(project.id, sort_by="deadline",
                                                  descending=True)],
            [high_late.id, high_early.id, low.id, undated.id],
        )
        calendar = routes.get_calendar(2026, 12)
        self.assertEqual(
            [(day.date.isoformat(), [task.id for task in day.tasks])
             for day in calendar.days],
            [("2026-12-05", [high_early.id, low.id]),
             ("2026-12-08", [other_task.id]),
             ("2026-12-20", [high_late.id])],
        )
        self.assertEqual(
            [task.id for day in routes.get_calendar(2026, 12, project.id).days
             for task in day.tasks],
            [high_early.id, low.id, high_late.id],
        )
        self.assertEqual(routes.get_calendar(2026, 11).days, [])

    def test_tags_create_replace_clear_and_delete(self):
        task = routes.create_task(
            TaskCreate(title="Draft", tags=["  Course  ", "Urgent", "Учёба"])
        )
        self.assertEqual(task.tags, ["Course", "Urgent", "Учёба"])
        self.assertEqual(routes.get_tasks()[0].tags, ["Course", "Urgent", "Учёба"])
        self.assertEqual(repository.get_task(task.id).tags, ["Course", "Urgent", "Учёба"])
        self.assertEqual(routes.get_tasks(tag="учёба")[0].id, task.id)
        self.assertEqual(
            routes.update_task(task.id, TaskUpdate(tags=["Final"])).tags,
            ["Final"],
        )
        self.assertEqual(routes.get_tasks(tag="Course"), [])
        self.assertEqual(routes.get_tasks(tag="final")[0].id, task.id)
        self.assertEqual(routes.update_task(task.id, TaskUpdate(tags=[])).tags, [])
        self.assertEqual(routes.get_tasks()[0].tags, [])
        routes.update_task(task.id, TaskUpdate(tags=["To delete"]))
        routes.delete_task(task.id)
        with closing(sqlite3.connect(database.DB_PATH)) as conn:
            self.assertEqual(
                conn.execute("SELECT COUNT(*) FROM task_tags").fetchone()[0], 0
            )

    def test_tags_combine_with_project_status_priority_and_sorting(self):
        project = project_routes.create_project(ProjectCreate(name="One"))
        other = project_routes.create_project(ProjectCreate(name="Two"))
        common = {"start_date": date(2026, 11, 1)}
        first = routes.create_task(TaskCreate(
            title="Early", project_id=project.id, status="todo", priority="high",
            deadline=date(2026, 12, 3), tags=["Study", "Important"], **common,
        ))
        second = routes.create_task(TaskCreate(
            title="Later", project_id=project.id, status="todo", priority="high",
            deadline=date(2026, 12, 12), tags=["study"], **common,
        ))
        routes.create_task(TaskCreate(
            title="Different status", project_id=project.id, status="done",
            priority="high", tags=["study"], **common,
        ))
        routes.create_task(TaskCreate(
            title="Different priority", project_id=project.id, status="todo",
            priority="low", tags=["study"], **common,
        ))
        routes.create_task(TaskCreate(
            title="Different project", project_id=other.id, status="todo",
            priority="high", tags=["study"], **common,
        ))
        self.assertEqual(
            [task.id for task in routes.get_tasks(
                project.id, sort_by="deadline", status="todo",
                priority="high", tag=" STUDY ",
            )],
            [first.id, second.id],
        )
        self.assertEqual(
            [task.id for task in routes.get_tasks(tag="Important")], [first.id]
        )
        self.assertEqual(
            routes.get_calendar(2026, 12, project.id).days[0].tasks[0].tags,
            ["Study", "Important"],
        )

    def test_overdue_tasks_can_be_rescheduled_or_deleted(self):
        today = date.today()
        past = today - timedelta(days=2)
        future = today + timedelta(days=3)
        project = project_routes.create_project(ProjectCreate(name="One"))
        overdue = routes.create_task(TaskCreate(
            title="Overdue", project_id=project.id,
            start_date=past - timedelta(days=1), deadline=past,
            status="in_progress", tags=["Urgent"],
        ))
        another = routes.create_task(TaskCreate(
            title="Another overdue", start_date=past, deadline=past,
        ))
        routes.create_task(TaskCreate(
            title="Completed", start_date=past, deadline=past, status="done",
        ))
        routes.create_task(TaskCreate(title="Due today", deadline=today))
        routes.create_task(TaskCreate(title="Future", deadline=future))
        routes.create_task(TaskCreate(title="No deadline"))

        self.assertTrue(overdue.is_overdue)
        self.assertTrue(another.is_overdue)
        self.assertTrue(routes.get_tasks()[0].model_dump(mode="json")["is_overdue"])
        self.assertEqual(
            [task.id for task in routes.get_overdue_tasks()],
            [overdue.id, another.id],
        )
        self.assertEqual(
            [task.id for task in routes.get_tasks(project.id, tag="urgent", overdue=True)],
            [overdue.id],
        )
        self.assertEqual(len(routes.get_tasks(overdue=False)), 4)

        moved = routes.update_task(overdue.id, TaskUpdate(deadline=future))
        self.assertFalse(moved.is_overdue)
        self.assertEqual([task.id for task in routes.get_overdue_tasks()], [another.id])
        routes.delete_task(another.id)
        self.assertEqual(routes.get_overdue_tasks(), [])

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
                ("get", "/tasks/calendar"),
                ("get", "/tasks/overdue"),
                ("get", "/tasks/matrix"),
                ("get", "/tasks/moscow"),
                ("post", "/tasks"),
                ("patch", "/tasks/{task_id}"),
                ("delete", "/tasks/{task_id}"),
                ("get", "/projects"),
                ("post", "/projects"),
                ("delete", "/projects/{project_id}"),
                ("get", "/notes"),
                ("post", "/notes"),
                ("get", "/notes/{note_id}"),
                ("patch", "/notes/{note_id}"),
                ("delete", "/notes/{note_id}"),
                ("put", "/notes/{note_id}/tasks/{task_id}"),
                ("delete", "/notes/{note_id}/tasks/{task_id}"),
                ("post", "/notes/{note_id}/create-task"),
                ("post", "/notes/{note_id}/attachments"),
                ("get", "/notes/{note_id}/attachments/{attachment_id}"),
                ("delete", "/notes/{note_id}/attachments/{attachment_id}"),
                ("get", "/schedule"),
                ("post", "/schedule"),
                ("get", "/schedule/occurrences"),
                ("get", "/schedule/{entry_id}"),
                ("patch", "/schedule/{entry_id}"),
                ("delete", "/schedule/{entry_id}"),
                ("put", "/schedule/{entry_id}/exceptions/{day}"),
                ("delete", "/schedule/{entry_id}/exceptions/{day}"),
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
                    "SELECT title, description, status, project_id, start_date, deadline, priority "
                    "FROM tasks"
                ).fetchall(),
                [("Old task", "Keep me", "done", None, date.today().isoformat(),
                  None, "medium")],
            )
            self.assertEqual(
                conn.execute("SELECT COUNT(*) FROM task_tags").fetchone()[0], 0
            )

    def test_project_era_database_migrates_without_losing_tasks(self):
        old_path = Path(self.temp.name) / "old_projects.db"
        with closing(sqlite3.connect(old_path)) as conn:
            conn.execute(
                "CREATE TABLE projects (id INTEGER PRIMARY KEY, name TEXT NOT NULL)"
            )
            conn.execute("INSERT INTO projects (id, name) VALUES (1, 'Coursework')")
            conn.execute(
                "CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL, "
                "description TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'todo', "
                "project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL)"
            )
            conn.execute(
                "INSERT INTO tasks (title, description, status, project_id) "
                "VALUES ('First', '', 'todo', 1)"
            )
            conn.commit()
        with patch.object(database, "DB_PATH", old_path):
            database.init_db()
            database.init_db()
        with closing(sqlite3.connect(old_path)) as conn:
            self.assertEqual(
                conn.execute(
                    "SELECT title, project_id, status, start_date, deadline, priority FROM tasks"
                ).fetchall(),
                [("First", 1, "todo", date.today().isoformat(), None, "medium")],
            )

    def test_migration_preserves_past_deadline_and_priority(self):
        old_path = Path(self.temp.name) / "previous_version.db"
        with closing(sqlite3.connect(old_path)) as conn:
            conn.execute(
                "CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL, "
                "description TEXT NOT NULL, status TEXT NOT NULL, "
                "project_id INTEGER, deadline TEXT, priority TEXT NOT NULL)"
            )
            conn.execute(
                "INSERT INTO tasks (title, description, status, deadline, priority) "
                "VALUES ('Past', '', 'done', '2025-01-10', 'high')"
            )
            conn.commit()
        with patch.object(database, "DB_PATH", old_path), patch.object(
            repository, "DB_PATH", old_path
        ):
            database.init_db()
            database.init_db()
            task = repository.list_tasks()[0]
        self.assertEqual(task.start_date, date(2025, 1, 10))
        self.assertEqual(task.deadline, date(2025, 1, 10))
        self.assertEqual(task.priority, "high")

    def test_existing_tag_table_gains_unicode_search_key(self):
        old_path = Path(self.temp.name) / "old_tags.db"
        with closing(sqlite3.connect(old_path)) as conn:
            conn.execute(
                "CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL, "
                "description TEXT NOT NULL, status TEXT NOT NULL, project_id INTEGER, "
                "start_date TEXT, deadline TEXT, priority TEXT NOT NULL)"
            )
            conn.execute(
                "CREATE TABLE task_tags (task_id INTEGER NOT NULL, name TEXT NOT NULL, "
                "position INTEGER NOT NULL, PRIMARY KEY(task_id, name))"
            )
            conn.execute(
                "INSERT INTO tasks VALUES (1, 'Old', '', 'todo', NULL, "
                "'2026-11-01', NULL, 'medium')"
            )
            conn.execute("INSERT INTO task_tags VALUES (1, 'Учёба', 0)")
            conn.commit()
        with patch.object(database, "DB_PATH", old_path), patch.object(
            repository, "DB_PATH", old_path
        ):
            database.init_db()
            database.init_db()
            self.assertEqual(repository.list_tasks(tag="учёба")[0].tags, ["Учёба"])

if __name__ == "__main__":
    unittest.main()
