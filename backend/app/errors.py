from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from regisse_kit.observability import security_event


class DomainError(Exception):
    status_code = 400

    def __init__(self, code: str, message: str | None = None):
        super().__init__(code)
        self.code, self.message = code, message


class BadRequest(DomainError):
    status_code = 400


class Unauthorized(DomainError):
    status_code = 401


class Forbidden(DomainError):
    status_code = 403


class NotFound(DomainError):
    status_code = 404

    def __init__(self, code: str = "not_found", message: str | None = None):
        super().__init__(code, message)


class Conflict(DomainError):
    status_code = 409


class Unavailable(DomainError):
    status_code = 503


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(DomainError)
    async def _domain(_: Request, exc: DomainError) -> JSONResponse:
        if exc.status_code in (401, 403, 429):
            # `code` is one of our own constants (never user input): a safe, bounded label (step_up_required, session_ended, wrong_app...)
            security_event("scolaris", f"{exc.status_code}_{exc.code}")
        body = {"detail": exc.code}
        if exc.message:
            body["message"] = exc.message
        return JSONResponse(status_code=exc.status_code, content=body)
