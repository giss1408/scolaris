from datetime import date, datetime, timedelta, timezone

import pytest

from app import clock
from tests.test_api import student


def at(d: date, hour: int = 10) -> datetime:
    return datetime(d.year, d.month, d.day, hour, 0, tzinfo=timezone.utc)


@pytest.fixture
def freeze(monkeypatch):
    def _set(d: date, hour: int = 10):
        monkeypatch.setattr(clock, "now", lambda: at(d, hour))
    return _set


FIRST_DUE = date(2026, 10, 5)  # a Monday


async def set_up(client, s, freeze):
    """6e with one 100 000 line due on FIRST_DUE; a family of two children with an opted-in WhatsApp parent."""
    d = s["director"]
    room = (await client.post("/v1/classrooms", json={"year_id": s["year_id"], "level": "6e", "name": "6e 1"}, headers=d)).json()
    await client.put("/v1/fees", headers=d, json={"year_id": s["year_id"], "level": "6e", "lines": [{"kind": "scolarite", "label": "1re tranche", "amount": 100000, "due_date": FIRST_DUE.isoformat()}]})
    a = (await client.post("/v1/students", json=student(room), headers=s["secretary"])).json()
    b = (await client.post("/v1/students", json=student(room, first_names="Koffi", family_id=a["family_id"], contacts=[]), headers=s["secretary"])).json()
    return room, a, b


async def due(client, h):
    return (await client.get("/v1/reminders", headers=h)).json()


async def test_scenario_steps_one_message_per_family_and_idempotent(client, school, freeze):
    room, a, b = await set_up(client, school, freeze)
    h = school["accountant"]
    freeze(FIRST_DUE - timedelta(days=5))
    r = await due(client, h)
    assert [i["step"] for i in r["items"]] == ["before"] and r["planned"] == 1
    item = r["items"][0]
    assert "Aya" in item["text"] and "Koffi" in item["text"] and "200" in item["text"].replace(" ", "")  # ONE message for both children, total of both
    assert item["channel"] == "whatsapp" and item["wa_link"].startswith("https://wa.me/2250701020304?text=") and item["can_send_now"] is True
    again = await due(client, h)  # the planner can run as often as it likes
    assert again["planned"] == 0 and len(again["items"]) == 1
    assert (await client.post(f"/v1/reminders/{item['id']}/sent", headers=h)).json()["changed"] is True
    assert (await client.post(f"/v1/reminders/{item['id']}/sent", headers=h)).json()["changed"] is False  # a second tap changes nothing
    # J-5 -> J+3 is 8 days later: a new week, the first late reminder is allowed
    freeze(FIRST_DUE + timedelta(days=3))
    r = await due(client, h)
    assert [i["step"] for i in r["items"]] == ["late_3"]
    assert "n'est pas encore réglée" in r["items"][0]["text"] and "ne pas tenir compte" in r["items"][0]["text"]
    await client.post(f"/v1/reminders/{r['items'][0]['id']}/sent", headers=h)
    # one reminder per family per week: at J+10 (9 h) it is under 7 days since the one sent at J+3 (10 h)
    freeze(FIRST_DUE + timedelta(days=10), hour=9)
    assert (await due(client, h))["items"] == []
    freeze(FIRST_DUE + timedelta(days=11))
    assert [i["step"] for i in (await due(client, h))["items"]] == ["late_10"]


async def test_stops_when_paid_and_never_on_sunday_or_in_grace(client, school, freeze):
    room, a, b = await set_up(client, school, freeze)
    h = school["accountant"]
    freeze(FIRST_DUE + timedelta(days=2))
    assert (await due(client, h))["items"] == []  # 1-2 days late: grace, no message
    freeze(FIRST_DUE + timedelta(days=6))  # Sunday 11 Oct? FIRST_DUE is Monday: +6 = Sunday
    assert (FIRST_DUE + timedelta(days=6)).weekday() == 6
    assert (await due(client, h))["items"] == []
    freeze(FIRST_DUE + timedelta(days=7))
    items = (await due(client, h))["items"]
    assert [i["step"] for i in items] == ["late_3"]
    # payment of everything late: the planned reminder disappears at the next run
    for enr in (a["enrollment_id"], b["enrollment_id"]):
        await client.post(f"/v1/enrollments/{enr}/payments", json={"amount": 100000, "method": "especes"}, headers=h)
    r = await due(client, h)
    assert r["items"] == [] and r["skipped_stale"] == 1


async def test_step_jumps_to_the_current_one_and_escalates_to_direction_only(client, school, freeze):
    room, a, b = await set_up(client, school, freeze)
    freeze(FIRST_DUE + timedelta(days=12))
    items = (await due(client, school["accountant"]))["items"]
    assert [i["step"] for i in items] == ["late_10"]  # no J+3 message first: only the step she is at
    assert "échéancier" in items[0]["text"]
    await client.post(f"/v1/reminders/{items[0]['id']}/sent", headers=school["accountant"])
    freeze(FIRST_DUE + timedelta(days=32))
    assert (await due(client, school["accountant"]))["items"] == []  # the escalation is for the director, not the accountant
    esc = (await due(client, school["director"]))["items"]
    assert [i["step"] for i in esc] == ["escalate"] and esc[0]["channel"] == "direction" and esc[0]["wa_link"] is None
    assert "La direction décide" in esc[0]["text"]  # nothing is done to the pupil automatically


async def test_promise_pauses_reminders_until_the_date_then_resumes(client, school, freeze):
    room, a, b = await set_up(client, school, freeze)
    h = school["accountant"]
    freeze(FIRST_DUE + timedelta(days=4))
    assert (await client.post(f"/v1/families/{a['family_id']}/promises", json={"amount": 100000, "promised_for": (FIRST_DUE + timedelta(days=10)).isoformat()}, headers=h)).status_code == 201
    assert (await due(client, h))["items"] == []
    freeze(FIRST_DUE + timedelta(days=11))  # promised date passed, still unpaid: the promise is broken and reminders resume
    items = (await due(client, h))["items"]
    assert [i["step"] for i in items] == ["late_10"]


async def test_channel_follows_optin_and_window_and_roles(client, school, freeze):
    room, a, b = await set_up(client, school, freeze)
    other = (await client.post("/v1/students", json=student(room, last_name="Bamba", contacts=[{"name": "Bamba Issa", "phone": "0505050505", "whatsapp_optin": False}]), headers=school["secretary"])).json()
    freeze(FIRST_DUE + timedelta(days=4), hour=21)
    items = (await due(client, school["accountant"]))["items"]
    by = {i["family_name"]: i for i in items}
    assert by["BAMBA"]["channel"] == "appel" and by["BAMBA"]["wa_link"] is None  # no opt-in: a phone call, never a WhatsApp message
    assert by["KOUASSI"]["channel"] == "whatsapp" and by["KOUASSI"]["can_send_now"] is False  # 21 h: outside 7-20 h
    assert (await client.get("/v1/reminders", headers=school["secretary"])).status_code == 403
    assert (await client.get("/v1/reminders", headers=school["teacher"])).status_code == 403


async def test_summary_counts_what_was_recovered_after_the_reminder(client, school, freeze):
    room, a, b = await set_up(client, school, freeze)
    h = school["accountant"]
    freeze(FIRST_DUE + timedelta(days=4))
    item = (await due(client, h))["items"][0]
    await client.post(f"/v1/reminders/{item['id']}/sent", headers=h)
    freeze(FIRST_DUE + timedelta(days=5))
    import asyncio
    await asyncio.sleep(0.01)
    await client.post(f"/v1/enrollments/{a['enrollment_id']}/payments", json={"amount": 60000, "method": "especes"}, headers=h)
    s = (await client.get("/v1/reminders/summary", headers=h)).json()
    assert s["sent"] == 1 and s["families_reminded"] == 1 and s["recovered_after_reminder"] == 60000


async def test_reminders_are_isolated_between_schools(client, school, freeze):
    from tests.conftest import make_school, make_staff

    room, a, b = await set_up(client, school, freeze)
    freeze(FIRST_DUE + timedelta(days=4))
    item = (await due(client, school["accountant"]))["items"][0]
    sid2, y2 = await make_school("Ecole B")
    other, _ = await make_staff(sid2, "accountant", "Autre")
    assert (await due(client, other))["items"] == []
    assert (await client.post(f"/v1/reminders/{item['id']}/sent", headers=other)).status_code == 404
    assert (await client.post(f"/v1/families/{a['family_id']}/promises", json={"amount": 1, "promised_for": "2026-12-01"}, headers=other)).status_code == 404
