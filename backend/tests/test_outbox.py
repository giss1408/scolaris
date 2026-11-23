import hashlib
import hmac
import json
from datetime import date, datetime, timedelta, timezone

import httpx
import pytest
from sqlalchemy import select

from app import clock
from app.config import get_settings
from app.db import SessionLocal
from app.integrations import whatsapp
from app.models import Contact, OutboundMessage, School
from app.security import encrypt, phone_hash
from app.services import outbox, scheduler
from tests.test_api import setup_class, student

MON_10H = datetime(2026, 11, 23, 10, 0, tzinfo=timezone.utc)  # a Monday


async def one_family(client, s, optin=True, channel="whatsapp"):
    rooms = (await client.get(f"/v1/classrooms?year_id={s['year_id']}", headers=s["director"])).json()
    room = rooms[0] if rooms else await setup_class(client, s)  # the same class serves every family of the test
    st = (await client.post("/v1/students", json=student(room, last_name=f"Fam{len(rooms)}x{id(object()) % 1000}", contacts=[{"name": "Kouassi Paul", "relation": "pere", "phone": "0701020304", "whatsapp_optin": optin, "financial_responsible": True, "preferred_channel": channel}]), headers=s["secretary"])).json()
    return room, st


async def switch_on(school_id):
    async with SessionLocal() as db:
        (await db.get(School, school_id)).auto_whatsapp = True
        await db.commit()


async def enqueue(school_id, family_id, key="k1", text="Le cours est annulé.", now=MON_10H, kind="other", on=True):
    if on:
        await switch_on(school_id)
    async with SessionLocal() as db:
        m = await outbox.enqueue(db, school_id=school_id, family_id=family_id, kind=kind, text=text, dedupe_key=key, now=now)
        await db.commit()
        return m


def live(monkeypatch, handler):
    s = get_settings()
    for k, v in dict(wa_mode="live", wa_token="tok-123456789012345678901234", wa_phone_number_id="123456", wa_app_secret="appsecret-1234567890", wa_verify_token="verify-me").items():
        monkeypatch.setattr(s, k, v)
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


async def test_opted_in_family_is_queued_others_are_skipped_for_a_phone_call(client, school):
    room, st = await one_family(client, school)
    m = await enqueue(school["id"], st["family_id"])
    assert m.status == "queued" and m.to_phone_enc is not None and m.params[:2] == ["Kouassi Paul", "Ecole A"]
    assert "Bonjour Kouassi Paul, message de l'école Ecole A : Le cours est annulé." in m.preview
    # idempotent: the same notice is never queued twice
    assert await enqueue(school["id"], st["family_id"]) is None
    # no opt-in: nothing is sent, the staff are told to call
    room2, st2 = await one_family(client, school, optin=False)
    skipped = await enqueue(school["id"], st2["family_id"], key="k2")
    assert skipped.status == "skipped" and skipped.detail == "no_whatsapp_optin" and skipped.to_phone_enc is None
    sms = await enqueue(school["id"], (await one_family(client, school, channel="appel"))[1]["family_id"], key="k3")
    assert sms.status == "skipped"  # prefers phone calls


async def test_hours_and_sunday_hold_messages_until_the_next_window(client, school):
    room, st = await one_family(client, school)
    night = datetime(2026, 11, 23, 21, 30, tzinfo=timezone.utc)
    sunday = datetime(2026, 11, 29, 11, 0, tzinfo=timezone.utc)
    early = datetime(2026, 11, 24, 5, 0, tzinfo=timezone.utc)
    assert outbox.next_window(MON_10H) == MON_10H
    assert outbox.next_window(night) == datetime(2026, 11, 24, 7, 0, tzinfo=timezone.utc)
    assert outbox.next_window(sunday) == datetime(2026, 11, 30, 7, 0, tzinfo=timezone.utc)
    assert outbox.next_window(early) == datetime(2026, 11, 24, 7, 0, tzinfo=timezone.utc)
    assert outbox.next_window(datetime(2026, 11, 28, 22, 0, tzinfo=timezone.utc)) == datetime(2026, 11, 30, 7, 0, tzinfo=timezone.utc)  # Saturday night -> Monday
    m = await enqueue(school["id"], st["family_id"], now=night)
    assert m.next_attempt_at == datetime(2026, 11, 24, 7, 0, tzinfo=timezone.utc)
    async with SessionLocal() as db:
        assert (await outbox.deliver_due(db, night))["held"] == 1  # outside the window: nothing leaves
        assert (await db.get(OutboundMessage, m.id)).status == "queued"


async def test_nothing_is_queued_unless_the_director_switched_automatic_sending_on(client, school):
    room, st = await one_family(client, school)
    assert await enqueue(school["id"], st["family_id"], on=False) is None
    async with SessionLocal() as db:
        assert (await db.scalars(select(OutboundMessage))).all() == []
    await client.put("/v1/school/settings", json={"auto_whatsapp": True}, headers=school["director"])
    assert (await enqueue(school["id"], st["family_id"], on=False)).status == "queued"
    # a blocked school sends nothing either
    async with SessionLocal() as db:
        (await db.get(School, school["id"])).status = "blocked"
        await db.commit()
    assert await enqueue(school["id"], st["family_id"], key="k-blocked", on=False) is None


async def test_log_mode_records_without_calling_anyone(client, school, monkeypatch):
    room, st = await one_family(client, school)
    m = await enqueue(school["id"], st["family_id"])
    called = []

    async def boom(*a, **k):
        called.append(1)

    monkeypatch.setattr(httpx.AsyncClient, "post", boom)
    async with SessionLocal() as db:
        assert (await outbox.deliver_due(db, MON_10H))["sent"] == 1
        row = await db.get(OutboundMessage, m.id)
    assert row.status == "sent" and row.provider_id.startswith("log-") and called == []


async def test_live_mode_sends_the_approved_template_with_clean_variables(client, school, monkeypatch):
    room, st = await one_family(client, school)
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["url"], seen["auth"], seen["body"] = str(request.url), request.headers["authorization"], json.loads(request.content)
        return httpx.Response(200, json={"messages": [{"id": "wamid.ABC"}]})

    http = live(monkeypatch, handler)
    m = await enqueue(school["id"], st["family_id"], text="Ligne 1\n\nLigne   2")
    async with SessionLocal() as db:
        assert (await outbox.deliver_due(db, MON_10H, client=http))["sent"] == 1
        row = await db.get(OutboundMessage, m.id)
    assert row.status == "sent" and row.provider_id == "wamid.ABC"
    assert seen["url"] == "https://graph.facebook.com/v21.0/123456/messages" and seen["auth"] == "Bearer tok-123456789012345678901234"
    b = seen["body"]
    assert b["to"] == "2250701020304" and b["type"] == "template" and b["template"]["name"] == "scolaris_information" and b["template"]["language"] == {"code": "fr"}
    assert [p["text"] for p in b["template"]["components"][0]["parameters"]] == ["Kouassi Paul", "Ecole A", "Ligne 1 Ligne 2"]  # one line, no runs of spaces


async def test_temporary_errors_are_retried_with_backoff_then_give_up_permanent_ones_do_not(client, school, monkeypatch):
    room, st = await one_family(client, school)
    room2, st2 = await one_family(client, school)
    state = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        if body["to"].endswith("0304") and state["n"] >= 0:
            state["n"] += 1
            return httpx.Response(500, json={"error": {"code": 1}})
        return httpx.Response(200, json={"messages": [{"id": "x"}]})

    http = live(monkeypatch, handler)
    m = await enqueue(school["id"], st["family_id"])
    async with SessionLocal() as db:
        s1 = await outbox.deliver_due(db, MON_10H, client=http)
        row = await db.get(OutboundMessage, m.id)
        assert s1["retry"] == 1 and row.status == "queued" and row.attempts == 1 and row.next_attempt_at == MON_10H + timedelta(minutes=5)
        assert (await outbox.deliver_due(db, MON_10H + timedelta(minutes=1), client=http))["sent"] == 0  # not due yet
        for i in range(1, 4):
            await outbox.deliver_due(db, MON_10H + timedelta(hours=i), client=http)
        row = await db.get(OutboundMessage, m.id)
        await db.refresh(row)
    assert row.status == "failed" and row.attempts == outbox.MAX_ATTEMPTS and row.detail.startswith("http 500")

    def refuse(request: httpx.Request) -> httpx.Response:
        return httpx.Response(400, json={"error": {"code": 132001, "message": "template not found"}})

    m2 = await enqueue(school["id"], st2["family_id"], key="k9")
    async with SessionLocal() as db:
        out = await outbox.deliver_due(db, MON_10H, client=live(monkeypatch, refuse))
        row = await db.get(OutboundMessage, m2.id)
    assert out["failed"] == 1 and row.status == "failed" and row.attempts == 1  # a wrong template or number is final: no retries


def signed(secret: str, body: bytes) -> dict:
    return {"X-Hub-Signature-256": "sha256=" + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest(), "Content-Type": "application/json"}


async def test_the_webhook_verifies_its_signature_and_moves_statuses_forward_only(client, school, monkeypatch):
    s = get_settings()
    for k, v in dict(wa_app_secret="appsecret-1234567890", wa_verify_token="verify-me").items():
        monkeypatch.setattr(s, k, v)
    room, st = await one_family(client, school)
    await switch_on(school["id"])
    async with SessionLocal() as db:
        m = await outbox.enqueue(db, school_id=school["id"], family_id=st["family_id"], kind="other", text="x", dedupe_key="w1", now=MON_10H)
        m.status, m.provider_id = "sent", "wamid.W1"
        await db.commit()
    # handshake
    ok = await client.get("/webhooks/whatsapp", params={"hub.mode": "subscribe", "hub.verify_token": "verify-me", "hub.challenge": "1234"})
    assert ok.status_code == 200 and ok.text == "1234"
    assert (await client.get("/webhooks/whatsapp", params={"hub.mode": "subscribe", "hub.verify_token": "nope", "hub.challenge": "1"})).status_code == 403

    def post(status, secret="appsecret-1234567890", pid="wamid.W1", errors=None):
        body = json.dumps({"entry": [{"changes": [{"value": {"statuses": [{"id": pid, "status": status, **({"errors": errors} if errors else {})}]}}]}]}).encode()
        return client.post("/webhooks/whatsapp", content=body, headers=signed(secret, body))

    async def status():
        async with SessionLocal() as db:
            return (await db.scalar(select(OutboundMessage.status).where(OutboundMessage.provider_id == "wamid.W1")))

    assert (await post("read", secret="wrong-secret")).status_code == 403 and await status() == "sent"  # an unsigned post changes nothing
    assert (await client.post("/webhooks/whatsapp", content=b"{}")).status_code == 403
    assert (await post("delivered")).json()["handled"] == 1 and await status() == "delivered"
    assert (await post("read")).json()["handled"] == 1 and await status() == "read"
    await post("delivered")  # a late, out-of-order receipt never undoes `read`
    assert await status() == "read"
    assert (await post("sent", pid="unknown")).json()["handled"] == 0
    await post("failed", errors=[{"title": "Message undeliverable"}])
    assert await status() == "failed"


async def test_the_school_sees_the_log_and_who_must_be_phoned(client, school):
    room, st = await one_family(client, school)
    room2, st2 = await one_family(client, school, optin=False)
    await enqueue(school["id"], st["family_id"], key="a")
    await enqueue(school["id"], st2["family_id"], key="b")
    for who in ("director", "accountant", "secretary"):
        got = (await client.get("/v1/messages", headers=school[who])).json()
        assert got["summary"] == {"queued": 1, "skipped": 1} and len(got["items"]) == 2, who
    todo = (await client.get("/v1/messages?status=failed,skipped", headers=school["director"])).json()["items"]
    assert [(i["status"], i["needs_call"], i["detail"]) for i in todo] == [("skipped", True, "no_whatsapp_optin")]
    assert (await client.get("/v1/messages", headers=school["teacher"])).status_code == 403
    # another school sees nothing of it
    from tests.conftest import make_school, make_staff

    sid2, _ = await make_school("Ecole B")
    other, _ = await make_staff(sid2, "director", "Autre")
    assert (await client.get("/v1/messages", headers=other)).json()["items"] == []


async def test_only_the_director_switches_automatic_sending(client, school):
    assert (await client.put("/v1/school/settings", json={"auto_whatsapp": True}, headers=school["secretary"])).status_code == 403
    assert (await client.put("/v1/school/settings", json={"auto_whatsapp": True}, headers=school["director"])).json() == {"auto_whatsapp": True, "whatsapp_phone": None}


async def test_the_scheduler_sends_reminders_only_for_schools_that_opted_in_and_never_twice(client, school, monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: MON_10H)
    d = school["director"]
    room = (await client.post("/v1/classrooms", json={"year_id": school["year_id"], "level": "6e", "name": "6e 1"}, headers=d)).json()
    await client.put("/v1/fees", headers=d, json={"year_id": school["year_id"], "level": "6e", "lines": [{"kind": "scolarite", "label": "1re tranche", "amount": 100000, "due_date": "2026-11-16"}]})
    await client.post("/v1/students", json=student(room), headers=school["secretary"])  # Kouassi, opted in, 7 days late
    async with SessionLocal() as db:
        assert (await scheduler.auto_reminders(db, MON_10H)) == 0  # the school did not opt in
    await client.put("/v1/school/settings", json={"auto_whatsapp": True}, headers=d)
    out = await scheduler.tick(MON_10H)
    assert out["auto_queued"] == 1 and out["sent"] == 1
    async with SessionLocal() as db:
        msgs = (await db.scalars(select(OutboundMessage))).all()
    assert len(msgs) == 1 and msgs[0].kind == "reminder" and msgs[0].status == "sent" and "100" in msgs[0].preview
    again = await scheduler.tick(MON_10H + timedelta(hours=1))
    assert again["auto_queued"] == 0 and again["sent"] == 0  # planned once, sent once
    # the reminder shows as handed over, not waiting for a person
    assert (await client.get("/v1/reminders", headers=school["accountant"])).json()["items"] == []


async def test_a_half_configured_live_channel_refuses_to_start(monkeypatch):
    from app.config import Settings

    base = dict(field_encryption_key="e" * 32 and "ZXpOb3RSZWFsbHlSYW5kb21LZXlCeXRlczEyMzQ1Njc=", hash_key="aGFzaGtleWJ5dGVzMTIzNDU2Nzg5MDEyMzQ1Njc4OTA=", database_url="postgresql://x@h/d")
    with pytest.raises(ValueError, match="wa_mode=live needs"):
        Settings(wa_mode="live", **base)
    Settings(wa_mode="live", wa_token="t", wa_phone_number_id="1", wa_app_secret="s", wa_verify_token="v", **base)
