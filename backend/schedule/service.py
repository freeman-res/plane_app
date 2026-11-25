from datetime import date

from backend.projects.repository import project_exists
from backend.schedule import repository
from backend.schedule.schemas import (
    ScheduleCreate, ScheduleEntry, ScheduleOccurrence, ScheduleUpdate, check_interval,
)


class ProjectNotFound(Exception):
    pass


class InvalidInterval(Exception):
    pass


class InvalidOccurrence(Exception):
    pass


def list_entries(project_id: int | None = None) -> list[ScheduleEntry]:
    return repository.list_entries(project_id)


def get_entry(entry_id: int) -> ScheduleEntry | None:
    return repository.get_entry(entry_id)


def create_entry(payload: ScheduleCreate) -> ScheduleEntry:
    if payload.project_id is not None and not project_exists(payload.project_id):
        raise ProjectNotFound
    return repository.create_entry(payload)


def update_entry(entry_id: int, payload: ScheduleUpdate) -> ScheduleEntry | None:
    current = repository.get_entry(entry_id)
    if current is None:
        return None
    changes = payload.model_dump(exclude_unset=True)
    if changes.get("project_id") is not None and not project_exists(changes["project_id"]):
        raise ProjectNotFound
    merged = current.model_dump(exclude={"id", "excluded_dates"}) | changes
    try:
        check_interval(merged["first_date"], merged["ends_on"],
                       merged["start_time"], merged["end_time"])
    except ValueError:
        raise InvalidInterval from None
    return repository.update_entry(entry_id, changes)


def delete_entry(entry_id: int) -> bool:
    return repository.delete_entry(entry_id)


def is_occurrence(entry: ScheduleEntry, day: date) -> bool:
    if day < entry.first_date or (entry.ends_on is not None and day > entry.ends_on):
        return False
    elapsed = (day - entry.first_date).days
    return elapsed == 0 if entry.repeat_every_weeks == 0 else elapsed % (entry.repeat_every_weeks * 7) == 0


def exclude_occurrence(entry_id: int, day: date, excluded: bool) -> ScheduleEntry | None:
    entry = repository.get_entry(entry_id)
    if entry is None:
        return None
    if not is_occurrence(entry, day):
        raise InvalidOccurrence
    return repository.set_exception(entry_id, day, excluded)


def occurrences(start: date, end: date, project_id: int | None = None) -> list[ScheduleOccurrence]:
    result: list[ScheduleOccurrence] = []
    for entry in repository.list_entries(project_id):
        if entry.first_date > end or (entry.ends_on is not None and entry.ends_on < start):
            continue
        if entry.repeat_every_weeks == 0:
            days = [entry.first_date] if start <= entry.first_date <= end else []
        else:
            step = entry.repeat_every_weeks * 7
            offset = max(0, (start - entry.first_date).days)
            next_index = (offset + step - 1) // step
            next_ordinal = entry.first_date.toordinal() + next_index * step
            last_ordinal = min(end.toordinal(), entry.ends_on.toordinal()) if entry.ends_on else end.toordinal()
            days = []
            while next_ordinal <= last_ordinal:
                days.append(date.fromordinal(next_ordinal))
                next_ordinal += step
        skipped = set(entry.excluded_dates)
        result.extend(ScheduleOccurrence(
            schedule_id=entry.id, title=entry.title, description=entry.description,
            project_id=entry.project_id, date=day,
            start_time=entry.start_time, end_time=entry.end_time,
        ) for day in days if day not in skipped and
            (entry.ends_on is None or day <= entry.ends_on))
    return sorted(result, key=lambda item: (item.date, item.start_time, item.schedule_id))
