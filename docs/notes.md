# Заметки: API и хранение

Заметки работают в том же FastAPI и SQLite, что задачи. При запуске сервера `init_db()` создаёт таблицы `notes`, `note_tasks` и `note_attachments`; существующие задачи не изменяются. Текст и оформление записываются в JSON в таблице `notes`. Фотографии и аудио хранятся в `backend/uploads/`, а в SQLite лежат их метаданные. Каталог исключён из Git. Для переноса данных нужны и база `backend/tasks.db`, и каталог `backend/uploads/`.

## Методы

| Метод | Адрес | Назначение |
| --- | --- | --- |
| `GET` | `/notes` | Все заметки; `?task_id=1` оставляет связанные с задачей |
| `POST` | `/notes` | Создать заметку |
| `GET` | `/notes/{id}` | Получить заметку с `task_ids` и `attachments` |
| `PATCH` | `/notes/{id}` | Изменить заголовок или текст |
| `DELETE` | `/notes/{id}` | Удалить заметку и её файлы |
| `PUT` | `/notes/{id}/tasks/{task_id}` | Связать заметку и существующую задачу |
| `DELETE` | `/notes/{id}/tasks/{task_id}` | Убрать связь |
| `POST` | `/notes/{id}/create-task` | Создать задачу из заметки и связать их |
| `POST` | `/notes/{id}/attachments?filename=photo.png` | Загрузить бинарное тело фотографии или аудио |
| `GET` | `/notes/{id}/attachments/{attachment_id}` | Скачать вложение |
| `DELETE` | `/notes/{id}/attachments/{attachment_id}` | Удалить вложение |

Пример создания заметки в `/docs`:

```json
{
  "title": "Идея для курсовой",
  "content": [
    {"type": "heading", "spans": [{"text": "План", "font_family": "serif", "font_size": 22, "bold": true}]},
    {"type": "paragraph", "spans": [{"text": "Добавить календарь", "font_family": "sans", "font_size": 14, "color": "#345678"}]}
  ]
}
```

Один блок может содержать несколько фрагментов (`spans`) с разным оформлением. Типы блоков: `paragraph`, `heading`, `bullet`, `numbered`. Шрифты: `sans`, `serif`, `mono`; размер 8–48; также доступны `bold`, `italic`, `underline` и цвет `#RRGGBB`. Интерфейс Flutter сам выбирает конкретные гарнитуры и отображает эти параметры. В ответе есть даты `created_at`, `updated_at`, связанные задачи и список вложений.

Чтобы создать задачу из заметки, передайте в `POST /notes/{id}/create-task`, например:

```json
{"project_id": null, "status": "todo", "start_date": "2026-11-19", "deadline": "2026-11-25", "priority": "high"}
```

Если даты не заданы, началом будет сегодняшняя дата сервера, а дедлайна не будет. Заголовок и обычный текст копируются в задачу; заметка остаётся, их связь записывается. Последующие изменения заметки не меняют задачу автоматически.

Загрузка вложения использует **сырое содержимое файла в теле запроса**, не `multipart/form-data`. Пример в PowerShell:

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/notes/1/attachments?filename=photo.png" -InFile "C:\Users\user\Pictures\photo.png" -ContentType "image/png"
```

Допускаются JPEG, PNG, GIF, WebP до 10 МиБ и MP3, WAV, OGG, M4A/MP4, WebM аудио до 25 МиБ. Проверяются заголовки файлов, но это не полноценная проверка медиаконтента. HTML-файлы пока не принимаются: хранение форматированного текста в ограниченной структуре исключает выполнение вставленного HTML и скриптов.

Это **backend API**. Экран заметок, выбор шрифтов, прикрепление файлов и переходы по связям во Flutter надо подключить отдельно.
