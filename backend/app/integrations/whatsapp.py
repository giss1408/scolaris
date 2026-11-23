"""WhatsApp Business Cloud API (official). Never an unofficial WhatsApp Web automation: it risks the number being banned.

Modes (SCO_WA_MODE): `log` records and sends nothing (default: dev, staging, tests); `live` calls the Cloud API.
Outside the 24-hour customer window only APPROVED TEMPLATES can be sent. We use ONE utility template with three variables, so a single
approval covers every notice (absence, cancelled course, substitute teacher, payment reminder):

    scolaris_information (category: UTILITY, language: fr)
    "Bonjour {{1}}, message de l'école {{2}} : {{3}} Merci de votre confiance."

Variables are single-line (Meta rejects newlines and runs of spaces in a template variable): see `clean`.
"""

import logging
import re
import uuid

import httpx

from app.config import get_settings

log = logging.getLogger("scolaris.whatsapp")

TEMPLATE_TEXT = "Bonjour {{1}}, message de l'école {{2}} : {{3}} Merci de votre confiance."


class WhatsAppError(Exception):
    """`permanent` errors (bad number, template not approved) are not retried; the others are."""

    def __init__(self, message: str, *, permanent: bool = False):
        super().__init__(message)
        self.permanent = permanent


def clean(value: str, limit: int = 600) -> str:
    """A template variable: one line, no tabs, no run of spaces, bounded."""
    return re.sub(r"\s+", " ", value or "").strip()[:limit]


def render(params: list[str]) -> str:
    """What the family reads (for the school's message log)."""
    text = TEMPLATE_TEXT
    for i, p in enumerate(params, start=1):
        text = text.replace("{{%d}}" % i, p)
    return text


async def send_template(to_e164: str, params: list[str], *, client: httpx.AsyncClient | None = None) -> str:
    """Send the template to a number; returns the provider's message id."""
    s = get_settings()
    if s.wa_mode == "log":
        log.info("whatsapp (log mode): message not sent")  # never the number nor the text
        return f"log-{uuid.uuid4().hex[:16]}"
    body = {
        "messaging_product": "whatsapp",
        "to": to_e164.lstrip("+"),
        "type": "template",
        "template": {"name": s.wa_template, "language": {"code": s.wa_language}, "components": [{"type": "body", "parameters": [{"type": "text", "text": clean(p)} for p in params]}]},
    }
    url = f"https://graph.facebook.com/{s.wa_api_version}/{s.wa_phone_number_id}/messages"
    own = client is None
    c = client or httpx.AsyncClient(timeout=10)
    try:
        r = await c.post(url, json=body, headers={"Authorization": f"Bearer {s.wa_token}"})
    except httpx.HTTPError:
        raise WhatsAppError("network") from None
    finally:
        if own:
            await c.aclose()
    if r.status_code == 200:
        try:
            return r.json()["messages"][0]["id"]
        except (KeyError, IndexError, ValueError):
            raise WhatsAppError("unusable answer") from None
    code = None
    try:
        code = r.json().get("error", {}).get("code")
    except ValueError:
        pass
    # 4xx other than rate limiting (429 / code 130429) and token problems: the message itself is wrong (number, template): do not retry
    permanent = r.status_code in (400, 404) and code not in (130429, 131056, 190)
    log.warning("whatsapp refused the message (status %s, code %s)", r.status_code, code)
    raise WhatsAppError(f"http {r.status_code} code {code}", permanent=permanent)
