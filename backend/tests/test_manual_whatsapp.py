from datetime import date, datetime, timezone
from urllib.parse import parse_qs, urlparse

import pytest
from sqlalchemy import select

from app import clock
from app.db import SessionLocal
from app.models import Contact, OutboundMessage, School
from app.services import outbox
from app.services.reminders import compose
from tests.conftest import make_school, make_staff
from tests.test_api import setup_class, student

MON_10H = datetime(2026, 11, 23, 10, 0, tzinfo=timezone.utc)


@pytest.fixture
def freeze(monkeypatch):
    def _set(h=MON_10H):
        monkeypatch.setattr(clock, "now", lambda: h)

    _set()
    return _set


async def family(client, s, optin=True, name="Kouassi Paul", phone="0701020304", last="Kouassi"):
    rooms = (await client.get(f"/v1/classrooms?year_id={s['year_id']}", headers=s["director"])).json()
    room = rooms[0] if rooms else await setup_class(client, s)
    st = (await client.post("/v1/students", json=student(room, last_name=last, contacts=[{"name": name, "relation": "pere", "phone": phone, "whatsapp_optin": optin, "financial_responsible": True}]), headers=s["secretary"])).json()
    return st


async def notice(school_id, family_id, key="k1", text="Le cours est annulé.", now=MON_10H):
    async with SessionLocal() as db:
        m = await outbox.enqueue(db, school_id=school_id, family_id=family_id, kind="cancellation", text=text, dedupe_key=key, now=now)
        await db.commit()
        return m


async def set_number(client, s, number="07 05 06 07 08"):
    return await client.put("/v1/school/settings", json={"whatsapp_phone": number}, headers=s["director"])


async def test_without_the_schools_number_nothing_is_composed_and_with_it_messages_wait_for_a_person(client, school, freeze):
    st = await family(client, school)
    assert await notice(school["id"], st["family_id"]) is None  # no number entered, automatic sending off
    r = await set_number(client, school)
    assert r.status_code == 200 and r.json() == {"auto_whatsapp": False, "whatsapp_phone": "+2250705060708"}  # normalised to the international form
    m = await notice(school["id"], st["family_id"])
    assert m.status == "to_send" and m.to_phone_enc is not None and m.next_attempt_at is None
    async with SessionLocal() as db:
        assert (await outbox.deliver_due(db, MON_10H))["sent"] == 0  # the background sender never touches a message a person must forward


async def test_the_secretary_forwards_it_from_the_schools_whatsapp_with_one_tap(client, school, freeze):
    st = await family(client, school)
    await set_number(client, school)
    await notice(school["id"], st["family_id"])
    for who in ("secretary", "director", "accountant"):
        got = (await client.get("/v1/messages/to-send", headers=school[who])).json()
        assert got["school_phone"] == "+2250705060708" and got["can_send_now"] is True and len(got["items"]) == 1, who
    item = (await client.get("/v1/messages/to-send", headers=school["secretary"])).json()["items"][0]
    url = urlparse(item["wa_link"])
    assert url.netloc == "wa.me" and url.path == "/2250701020304"  # the PARENT's number: WhatsApp opens on the school's phone with the message ready
    sent_text = parse_qs(url.query)["text"][0]
    assert sent_text == item["text"] and "Bonjour Kouassi Paul" in sent_text and "Ecole A" in sent_text and "Le cours est annulé." in sent_text
    assert (await client.get("/v1/messages/to-send", headers=school["teacher"])).status_code == 403
    # "I forwarded it": a second tap changes nothing, and it leaves the waiting list
    assert (await client.post(f"/v1/messages/{item['id']}/sent", headers=school["secretary"])).json() == {"ok": True, "changed": True}
    assert (await client.post(f"/v1/messages/{item['id']}/sent", headers=school["secretary"])).json() == {"ok": True, "changed": False}
    assert (await client.get("/v1/messages/to-send", headers=school["secretary"])).json()["items"] == []
    log = (await client.get("/v1/messages", headers=school["director"])).json()
    assert log["summary"] == {"sent": 1} and log["items"][0]["status"] == "sent"
    async with SessionLocal() as db:
        row = (await db.scalars(select(OutboundMessage))).one()
    assert row.sent_by is not None and row.sent_at == MON_10H


async def test_a_message_can_be_set_aside_and_the_hours_are_flagged(client, school, freeze):
    st = await family(client, school)
    await set_number(client, school)
    m = await notice(school["id"], st["family_id"])
    freeze(datetime(2026, 11, 29, 11, 0, tzinfo=timezone.utc))  # a Sunday
    assert (await client.get("/v1/messages/to-send", headers=school["secretary"])).json()["can_send_now"] is False
    freeze(datetime(2026, 11, 23, 21, 0, tzinfo=timezone.utc))
    assert (await client.get("/v1/messages/to-send", headers=school["secretary"])).json()["can_send_now"] is False
    assert (await client.post(f"/v1/messages/{m.id}/skip", headers=school["secretary"])).json()["changed"] is True
    assert (await client.post(f"/v1/messages/{m.id}/sent", headers=school["secretary"])).json()["changed"] is False  # already set aside
    assert (await client.get("/v1/messages/to-send", headers=school["secretary"])).json()["items"] == []


async def test_families_who_did_not_agree_are_listed_to_phone_not_to_forward(client, school, freeze):
    yes = await family(client, school, last="Oui")
    no = await family(client, school, optin=False, name="Bamba Issa", phone="0505050505", last="Non")
    await set_number(client, school)
    await notice(school["id"], yes["family_id"], "a")
    skipped = await notice(school["id"], no["family_id"], "b")
    assert skipped.status == "skipped" and skipped.detail == "no_whatsapp_optin"
    assert [i["family"] for i in (await client.get("/v1/messages/to-send", headers=school["secretary"])).json()["items"]] == ["OUI"]
    todo = (await client.get("/v1/messages?status=failed,skipped", headers=school["secretary"])).json()["items"]
    assert [(i["family"], i["needs_call"]) for i in todo] == [("NON", True)]


async def test_a_parent_who_says_stop_is_not_written_to_again(client, school, freeze):
    st = await family(client, school)
    await set_number(client, school)
    await notice(school["id"], st["family_id"], "a")
    async with SessionLocal() as db:
        contact_id = (await db.scalar(select(Contact.id)))
    for who in ("teacher",):
        assert (await client.put(f"/v1/contacts/{contact_id}/optin", json={"whatsapp_optin": False}, headers=school[who])).status_code == 403
    r = await client.put(f"/v1/contacts/{contact_id}/optin", json={"whatsapp_optin": False}, headers=school["secretary"])
    assert r.json() == {"whatsapp_optin": False, "cancelled_messages": 1}  # what was waiting is cancelled at once
    assert (await client.get("/v1/messages/to-send", headers=school["secretary"])).json()["items"] == []
    later = await notice(school["id"], st["family_id"], "b")
    assert later.status == "skipped" and later.detail == "no_whatsapp_optin"  # and nothing new is composed for her
    detail = (await client.get(f"/v1/students/{st['id']}", headers=school["secretary"])).json()
    assert detail["contacts"][0]["whatsapp_optin"] is False and detail["contacts"][0]["id"] == contact_id
    assert (await client.put(f"/v1/contacts/{contact_id}/optin", json={"whatsapp_optin": True}, headers=school["director"])).json()["whatsapp_optin"] is True  # she agrees again
    assert (await notice(school["id"], st["family_id"], "c")).status == "to_send"
    other, _ = await make_staff((await make_school("Ecole B"))[0], "director", "Directrice B")
    assert (await client.put(f"/v1/contacts/{contact_id}/optin", json={"whatsapp_optin": False}, headers=other)).status_code == 404


async def test_only_the_director_sets_a_valid_number_and_can_remove_it(client, school, freeze):
    for who in ("secretary", "accountant", "teacher"):
        assert (await client.put("/v1/school/settings", json={"whatsapp_phone": "0705060708"}, headers=school[who])).status_code == 403, who
    assert (await set_number(client, school, "12345")).json()["detail"] == "phone_invalid"
    assert (await client.put("/v1/school/settings", json={"whatsapp_phone": "0705060708", "bogus": 1}, headers=school["director"])).status_code == 422
    assert (await set_number(client, school, "+225 05 06 07 08 09")).json()["whatsapp_phone"] == "+2250506070809"
    me = (await client.get("/v1/me", headers=school["director"])).json()["school"]
    assert me["whatsapp_phone"] == "+2250506070809"
    # setting only the automatic switch leaves the number alone
    assert (await client.put("/v1/school/settings", json={"auto_whatsapp": True}, headers=school["director"])).json() == {"auto_whatsapp": True, "whatsapp_phone": "+2250506070809"}
    assert (await set_number(client, school, "")).json()["whatsapp_phone"] is None
    assert (await client.get("/v1/me", headers=school["director"])).json()["school"]["whatsapp_phone"] is None


async def test_what_is_waiting_is_counted_for_the_staff_who_forward_it(client, school, freeze):
    st = await family(client, school)
    await set_number(client, school)
    await notice(school["id"], st["family_id"])
    for who, expected in (("director", 1), ("secretary", 1), ("accountant", 1), ("teacher", 0)):
        assert (await client.get("/v1/me", headers=school[who])).json()["school"]["messages_to_send"] == expected, who


async def test_automatic_mode_still_queues_for_the_background_sender(client, school, freeze):
    st = await family(client, school)
    await set_number(client, school)
    await client.put("/v1/school/settings", json={"auto_whatsapp": True}, headers=school["director"])
    assert (await notice(school["id"], st["family_id"])).status == "queued"  # the director chose automatic sending: manual forwarding is not used


async def test_a_blocked_school_composes_nothing(client, school, freeze):
    st = await family(client, school)
    await set_number(client, school)
    async with SessionLocal() as db:
        (await db.get(School, school["id"])).status = "blocked"
        await db.commit()
    assert await notice(school["id"], st["family_id"]) is None


async def test_replies_go_to_the_schools_own_number_in_the_reminder_texts():
    from app.services.billing import Line
    from app.services.reminders import FamilyLine

    line = FamilyLine(1, "Fanta KOUASSI", "6e 1", Line(1, "scolarite", "1re tranche", 100000, date(2026, 11, 3), 0, 100000, 20))
    for step in ("late_10", "late_20"):
        text, _ = compose(step, parent="Paul", school="Ecole A", lines=[line], phone="+2250705060708")
        assert "+2250705060708" in text and "Répondez à ce message" not in text, step  # never "reply here" to a number nobody reads
    text, _ = compose("late_10", parent="Paul", school="Ecole A", lines=[line], phone=None)
    assert "Contactez l'économat" in text


async def test_manual_messages_are_isolated_between_schools(client, school, freeze):
    st = await family(client, school)
    await set_number(client, school)
    m = await notice(school["id"], st["family_id"])
    sid2, _ = await make_school("Ecole B")
    other, _ = await make_staff(sid2, "secretary", "Secrétaire B")
    assert (await client.get("/v1/messages/to-send", headers=other)).json()["items"] == []
    assert (await client.post(f"/v1/messages/{m.id}/sent", headers=other)).status_code == 404
    assert (await client.post(f"/v1/messages/{m.id}/skip", headers=other)).status_code == 404
