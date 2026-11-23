"""The WhatsApp webhook (public, no login): Meta checks it with a handshake, then posts delivery receipts. Every post is verified by its HMAC
signature over the RAW body before anything is read; an unsigned or wrongly signed post changes nothing."""

import json

from fastapi import APIRouter, Depends, Query, Request, Response
from regisse_kit.webhooks import verify_hmac_sha256
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db import get_session
from app.errors import Forbidden
from app.services import outbox

router = APIRouter(tags=["webhooks"])


@router.get("/webhooks/whatsapp")
async def verify(hub_mode: str | None = Query(default=None, alias="hub.mode"), hub_verify_token: str | None = Query(default=None, alias="hub.verify_token"), hub_challenge: str | None = Query(default=None, alias="hub.challenge")) -> Response:
    s = get_settings()
    import hmac

    if hub_mode == "subscribe" and s.wa_verify_token and hub_verify_token and hmac.compare_digest(hub_verify_token, s.wa_verify_token) and hub_challenge:
        return Response(content=hub_challenge, media_type="text/plain")
    raise Forbidden("bad_verify_token")


@router.post("/webhooks/whatsapp")
async def receive(request: Request, db: AsyncSession = Depends(get_session)) -> dict:
    s = get_settings()
    raw = await request.body()
    if not verify_hmac_sha256(request.headers.get("X-Hub-Signature-256"), raw, s.wa_app_secret):
        raise Forbidden("bad_signature")
    try:
        payload = json.loads(raw)
    except ValueError:
        return {"ok": True, "handled": 0}
    handled = 0
    for entry in payload.get("entry", []):
        for change in entry.get("changes", []):
            for st in (change.get("value") or {}).get("statuses", []):
                pid, status = st.get("id"), st.get("status")
                if not pid or status not in ("sent", "delivered", "read", "failed"):
                    continue
                err = (st.get("errors") or [{}])[0].get("title")
                handled += int(await outbox.apply_status(db, pid, status, err))
    return {"ok": True, "handled": handled}
