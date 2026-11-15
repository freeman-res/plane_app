from fastapi import FastAPI

from backend.database import init_db
from backend.routes.tasks import router as tasks_router


app = FastAPI()
init_db()
app.include_router(tasks_router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
