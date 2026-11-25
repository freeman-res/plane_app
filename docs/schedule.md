# Повторяющееся расписание

Расписание хранится отдельно от задач в таблицах `schedule_entries` и `schedule_exceptions` существующей базы SQLite. Запись описывает занятие: название, описание, дату **первого** занятия, время начала и конца, необязательный проект и дату окончания серии. Время местное, без часового пояса; занятие должно закончиться в тот же день. Все повторения вычисляются по диапазону дат, отдельные строки для бесконечных будущих занятий не создаются.

`repeat_every_weeks` принимает `0` для одного занятия, `1` для каждой недели и `2` для каждой второй недели. День недели задаётся полем `first_date`. Чтобы чередовать два предмета по понедельникам, создайте две записи с интервалом `2` и первыми датами с разницей в 7 дней.

Пример для PowerShell (первая неделя: матан, вторая: информатика):

```powershell
$first = @{ title = "Матан"; first_date = "2026-11-02"; start_time = "10:00"; end_time = "11:00"; repeat_every_weeks = 2 } | ConvertTo-Json
$second = @{ title = "Информатика"; first_date = "2026-11-09"; start_time = "10:00"; end_time = "11:00"; repeat_every_weeks = 2 } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/schedule" -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($first))
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/schedule" -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($second))
```

| Метод | Адрес | Результат |
| --- | --- | --- |
| `GET` | `/schedule` | Список записей; `?project_id=1` фильтрует по проекту |
| `POST` | `/schedule` | Создать запись |
| `GET` | `/schedule/{id}` | Посмотреть запись и отменённые даты |
| `PATCH` | `/schedule/{id}` | Изменить запись; `ends_on: null` убирает дату окончания |
| `DELETE` | `/schedule/{id}` | Удалить запись |
| `GET` | `/schedule/occurrences?start=2026-11-01&end=2026-11-30` | Фактические занятия за период, максимум 366 дней; возможен `project_id` |
| `PUT` | `/schedule/{id}/exceptions/2026-11-16` | Пропустить конкретное занятие |
| `DELETE` | `/schedule/{id}/exceptions/2026-11-16` | Вернуть пропущенное занятие |

При изменении `first_date`, `repeat_every_weeks` или `ends_on` список пропущенных дат очищается, потому что период повторения изменился. При удалении проекта записи расписания сохраняются и становятся записями без проекта.

Календарь задач `GET /tasks/calendar?year=2026&month=11&include_schedule=true` возвращает и задачи, и занятия. У каждого дня есть отдельные массивы `tasks` и `schedule`. Без `include_schedule=true` календарь показывает только задачи. Так интерфейс Flutter может дать пользователю переключатель расписания, не меняя сами записи. Экран настройки расписания и переключатель во Flutter подключаются к этому API отдельно.
