import sqlite3
import tempfile
import unittest
from contextlib import closing
from datetime import date, time
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException
from pydantic import ValidationError

from backend import database
from backend.projects import repository as project_repository
from backend.projects import router as projects
from backend.projects.schemas import ProjectCreate
from backend.schedule import repository as schedule_repository
from backend.schedule import router as schedule
from backend.schedule.schemas import ScheduleCreate, ScheduleUpdate
from backend.tasks import repository as task_repository
from backend.tasks import router as tasks
from backend.tasks.schemas import TaskCreate


class ScheduleApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        db_path = Path(self.temp.name) / "tasks.db"
        self.patches = [patch.object(module, "DB_PATH", db_path) for module in (
            database, project_repository, schedule_repository, task_repository,
        )]
        for item in self.patches:
            item.start()
        database.init_db()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.temp.cleanup()

    def test_weekly_and_alternating_weeks_in_calendar(self):
        project = projects.create_project(ProjectCreate(name="University"))
        first = schedule.create_schedule(ScheduleCreate(
            title="Math", project_id=project.id, first_date=date(2026, 11, 2),
            start_time=time(10), end_time=time(11), repeat_every_weeks=2,
        ))
        second = schedule.create_schedule(ScheduleCreate(
            title="Informatics", project_id=project.id, first_date=date(2026, 11, 9),
            start_time=time(10), end_time=time(11), repeat_every_weeks=2,
        ))
        weekly = schedule.create_schedule(ScheduleCreate(
            title="English", first_date=date(2026, 11, 2),
            start_time=time(8), end_time=time(9), ends_on=date(2026, 11, 16),
        ))
        one_off = schedule.create_schedule(ScheduleCreate(
            title="Exam", first_date=date(2026, 11, 6),
            start_time=time(12), end_time=time(13), repeat_every_weeks=0,
        ))
        database.init_db()  # Migration is safe to run on an existing database.
        self.assertEqual([entry.id for entry in schedule.list_schedule()],
                         [weekly.id, first.id, one_off.id, second.id])
        slots = schedule.get_occurrences(date(2026, 11, 1), date(2026, 11, 30))
        self.assertEqual(
            [(slot.date.day, slot.title) for slot in slots],
            [(2, "English"), (2, "Math"), (6, "Exam"), (9, "English"),
             (9, "Informatics"), (16, "English"), (16, "Math"),
             (23, "Informatics"), (30, "Math")],
        )
        self.assertEqual(
            [(slot.date.day, slot.title) for slot in schedule.get_occurrences(
                date(2026, 11, 1), date(2026, 11, 30), project.id,
            )],
            [(2, "Math"), (9, "Informatics"), (16, "Math"),
             (23, "Informatics"), (30, "Math")],
        )
        task = tasks.create_task(TaskCreate(
            title="Homework", project_id=project.id,
            start_date=date(2026, 11, 2), deadline=date(2026, 11, 9),
        ))
        old_calendar = tasks.get_calendar(2026, 11, project.id)
        self.assertEqual([day.date.day for day in old_calendar.days], [9])
        self.assertEqual(old_calendar.days[0].schedule, [])
        shown = tasks.get_calendar(2026, 11, project.id, include_schedule=True)
        self.assertEqual([day.date.day for day in shown.days], [2, 9, 16, 23, 30])
        self.assertEqual(shown.days[1].tasks[0].id, task.id)
        self.assertEqual(shown.days[1].schedule[0].title, "Informatics")

    def test_skip_restore_edit_delete_and_project_deletion(self):
        project = projects.create_project(ProjectCreate(name="Course"))
        item = schedule.create_schedule(ScheduleCreate(
            title="Lecture", project_id=project.id, first_date=date(2026, 11, 2),
            start_time=time(10), end_time=time(11), repeat_every_weeks=2,
        ))
        self.assertEqual(schedule.get_schedule(item.id).title, "Lecture")
        self.assertEqual(schedule.skip_occurrence(item.id, date(2026, 11, 16)).excluded_dates,
                         [date(2026, 11, 16)])
        self.assertEqual(schedule.skip_occurrence(item.id, date(2026, 11, 16)).excluded_dates,
                         [date(2026, 11, 16)])
        self.assertEqual([item.date.day for item in schedule.get_occurrences(
            date(2026, 11, 1), date(2026, 11, 30))], [2, 30])
        schedule.restore_occurrence(item.id, date(2026, 11, 16))
        self.assertEqual([item.date.day for item in schedule.get_occurrences(
            date(2026, 11, 1), date(2026, 11, 30))], [2, 16, 30])
        schedule.skip_occurrence(item.id, date(2026, 11, 16))
        changed = schedule.update_schedule(item.id, ScheduleUpdate(
            title="Seminar", start_time=time(11), end_time=time(12),
            repeat_every_weeks=1, ends_on=date(2026, 11, 23),
        ))
        self.assertEqual(changed.excluded_dates, [])
        self.assertEqual([item.date.day for item in schedule.get_occurrences(
            date(2026, 11, 1), date(2026, 11, 30))], [2, 9, 16, 23])
        self.assertEqual(changed.title, "Seminar")
        projects.delete_project(project.id)
        self.assertIsNone(schedule.get_schedule(item.id).project_id)
        schedule.delete_schedule(item.id)
        self.assertEqual(schedule.list_schedule(), [])
        with closing(sqlite3.connect(database.DB_PATH)) as conn:
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM schedule_exceptions").fetchone()[0], 0)

    def test_validation_and_missing_entries(self):
        data = {"title": "Pair", "first_date": "2026-11-02",
                "start_time": "10:00", "end_time": "11:00"}
        for values in (
            {"title": "   "}, {"start_time": "12:00"},
            {"ends_on": "2026-11-01"}, {"repeat_every_weeks": 3},
            {"start_time": "10:00+03:00"},
        ):
            with self.assertRaises(ValidationError):
                ScheduleCreate.model_validate(data | values)
        with self.assertRaises(ValidationError):
            ScheduleUpdate()
        with self.assertRaises(ValidationError):
            ScheduleUpdate(first_date=None)
        with self.assertRaises(HTTPException) as error:
            schedule.create_schedule(ScheduleCreate.model_validate(data | {"project_id": 999}))
        self.assertEqual(error.exception.status_code, 404)
        item = schedule.create_schedule(ScheduleCreate.model_validate(data))
        for operation, status in (
            (lambda: schedule.skip_occurrence(item.id, date(2026, 11, 3)), 422),
            (lambda: schedule.update_schedule(item.id, ScheduleUpdate(end_time=time(9))), 422),
            (lambda: schedule.update_schedule(item.id, ScheduleUpdate(ends_on=date(2026, 11, 1))), 422),
            (lambda: schedule.get_occurrences(date(2026, 11, 3), date(2026, 11, 2)), 422),
            (lambda: schedule.get_occurrences(date(2026, 1, 1), date(2027, 2, 1)), 422),
            (lambda: schedule.get_schedule(999), 404),
            (lambda: schedule.delete_schedule(999), 404),
        ):
            with self.assertRaises(HTTPException) as error:
                operation()
            self.assertEqual(error.exception.status_code, status)
        self.assertEqual(schedule.get_schedule(item.id).end_time, time(11))
        self.assertEqual(schedule.get_occurrences(
            date(9999, 12, 30), date(9999, 12, 31),
        ), [])


if __name__ == "__main__":
    unittest.main()
