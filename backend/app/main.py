from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from regisse_kit.headers import install_security_headers
from regisse_kit.health import health_router
from regisse_kit.observability import install_observability
from sqlalchemy import text

from app.config import get_settings
from app.db import SessionLocal
from app.errors import install_error_handlers
from app.routers import academics, exports, money, parent, reminders, school, students, timetable


async def _check_db() -> None:
    async with SessionLocal() as s:
        await s.execute(text("select 1"))


def create_app() -> FastAPI:
    s = get_settings()
    app = FastAPI(title="Scolaris API", version="0.1.0", docs_url=None if s.env == "prod" else "/docs", redoc_url=None, openapi_url=None if s.env == "prod" else "/openapi.json")
    if s.cors_origins:
        app.add_middleware(CORSMiddleware, allow_origins=s.cors_origins, allow_methods=["*"], allow_headers=["*"])
    install_security_headers(app, prod=s.env == "prod")
    # JSON logs with phone numbers and tokens masked, request ids, metrics by route template, /metrics only with METRICS token (never via Caddy)
    install_observability(app, "scolaris", metrics_token=s.metrics_token or None)
    install_error_handlers(app)
    app.include_router(health_router({"db": _check_db}))
    for r in (school.router, students.router, money.router, academics.router, reminders.router, parent.router, exports.router, timetable.router):
        app.include_router(r)
    return app


app = create_app()
