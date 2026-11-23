import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from regisse_kit.health import health_router
from sqlalchemy import text

from app.config import get_settings
from app.db import SessionLocal
from app.errors import install_error_handlers
from app.routers import money, school, students

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")


async def _check_db() -> None:
    async with SessionLocal() as s:
        await s.execute(text("select 1"))


def create_app() -> FastAPI:
    s = get_settings()
    app = FastAPI(title="Scolaris API", version="0.1.0", docs_url=None if s.env == "prod" else "/docs", redoc_url=None, openapi_url=None if s.env == "prod" else "/openapi.json")
    if s.cors_origins:
        app.add_middleware(CORSMiddleware, allow_origins=s.cors_origins, allow_methods=["*"], allow_headers=["*"])
    install_error_handlers(app)
    app.include_router(health_router({"db": _check_db}))
    for r in (school.router, students.router, money.router):
        app.include_router(r)
    return app


app = create_app()
