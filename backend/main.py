from fastapi import FastAPI

from backend.database import init_db
from backend.notes.router import router as notes_router
from backend.projects.router import router as projects_router
from backend.schedule.router import router as schedule_router
from backend.tasks.router import router as tasks_router


app = FastAPI()
init_db()
app.include_router(tasks_router)
app.include_router(projects_router)
app.include_router(notes_router)
app.include_router(schedule_router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
