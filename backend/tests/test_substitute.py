from datetime import date, datetime, timezone

import pytest
from sqlalchemy import select

from app import clock
from app.db import SessionLocal
from app.models import OutboundMessage
from tests.test_academics import class_with_students
from tests.test_api import student
from tests.test_parent import parent_headers

TODAY = date(2026, 11, 23)  # Monday
NEXT = date(2026, 11, 30)


@pytest.fixture
def freeze(monkeypatch):
    def _set(d: date = TODAY, hour: int = 7):
        monkeypatch.setattr(clock, "now", lambda: datetime(d.year, d.month, d.day, hour, 0, tzinfo=timezone.utc))

    _set()
    return _set


async def setup(client, s):
    """6e 1: Prof Math's maths on Monday 08:00-09:00; Prof Francais is free then and gives French in the class; a family that opted in to WhatsApp."""
    room, e, sub = await class_with_students(client, s, names=("Aya",))
    d = s["director"]
    await client.put("/v1/school/settings", json={"auto_whatsapp": True}, headers=d)
    math, fr = sub["staff"]["Prof Math"], sub["staff"]["Prof Francais"]
    slot = (await client.post(f"/v1/classrooms/{room['id']}/timetable/slots", json={"weekday": 1, "start": "08:00", "end": "09:00", "subject_id": sub["maths"], "teacher_id": math}, headers=d)).json()["id"]
    kid = (await client.post("/v1/students", json=student(room, last_name="Traore", first_names="Fanta"), headers=s["secretary"])).json()["enrollment_id"]
    return room, sub, slot, kid, math, fr


def cancel(client, h, slot, day=NEXT, **extra):
    return client.post(f"/v1/timetable/slots/{slot}/cancellations", json={"on_date": day.isoformat(), "reason": "maladie", **extra}, headers=h)


async def sent():
    async with SessionLocal() as db:
        return [m.preview for m in (await db.scalars(select(OutboundMessage).order_by(OutboundMessage.id))).all()]


async def test_the_direction_names_a_replacement_when_the_course_is_cancelled(client, school, freeze):
    room, sub, slot, kid, math, fr = await setup(client, school)
    r = await cancel(client, school["director"], slot, substitute_staff_id=fr)
    assert r.status_code == 201 and r.json()["substitute"] == "Prof Francais" and r.json()["families_notified"] >= 1
    # the families are told twice at most: "cancelled", then "taught by"
    texts = await sent()
    assert any("est annulé (enseignant absent)" in t for t in texts) and any("sera tenu par Prof Francais" in t for t in texts)
    assert not any("maladie" in t.lower() for t in texts)  # the reason never goes to families
    # everyone sees WHO replaces her; only the administration and the teacher see why
    for who in ("director", "secretary", "teacher", "teacher2"):
        tt = (await client.get(f"/v1/classrooms/{room['id']}/timetable", headers=school[who])).json()
        assert tt["cancellations"][0]["substitute"] == "Prof Francais", who
    parent = (await client.get(f"/v1/parent/children/{kid}/timetable", headers=parent_headers("+2250701020304"))).json()
    assert parent["cancellations"] == [{"slot_id": slot, "date": "2026-11-30", "substitute": "Prof Francais", "substitute_id": fr}]
    # the replacement sees the session in her own week, with its date
    mine = (await client.get("/v1/timetable/me", headers=school["teacher2"])).json()
    assert [(x["date"], x["classroom"], x["subject"], x["start"]) for x in mine["substitutions"]] == [("2026-11-30", "6e 1", "Mathématiques", "08:00")]
    assert (await client.get("/v1/timetable/me", headers=school["teacher"])).json()["substitutions"] == []


async def test_only_the_direction_chooses_and_the_choice_is_checked(client, school, freeze):
    room, sub, slot, kid, math, fr = await setup(client, school)
    assert (await cancel(client, school["teacher"], slot, substitute_staff_id=fr)).json()["detail"] == "director_only"  # the absent teacher does not pick her own replacement
    assert (await cancel(client, school["director"], slot, substitute_staff_id=sub["staff"]["Secretaire"])).json()["detail"] == "not_an_active_teacher"
    assert (await cancel(client, school["director"], slot, substitute_staff_id=math)).json()["detail"] == "substitute_is_the_teacher"
    # she cancels herself first, the direction names the replacement afterwards
    assert (await cancel(client, school["teacher"], slot)).status_code == 201
    url = f"/v1/timetable/slots/{slot}/cancellations/{NEXT}/substitute"
    for who in ("teacher", "accountant"):
        assert (await client.put(url, json={"staff_id": fr}, headers=school[who])).status_code == 403
    ok = await client.put(url, json={"staff_id": fr}, headers=school["secretary"])
    assert ok.status_code == 200 and ok.json()["substitute"] == "Prof Francais"
    assert any("sera tenu par Prof Francais" in t for t in await sent())
    # a replacement can be withdrawn
    assert (await client.put(url, json={"staff_id": None}, headers=school["director"])).json()["substitute"] is None
    assert (await client.get("/v1/timetable/me", headers=school["teacher2"])).json()["substitutions"] == []
    assert (await client.put(f"/v1/timetable/slots/{slot}/cancellations/2026-12-07/substitute", json={"staff_id": fr}, headers=school["director"])).status_code == 404  # nothing cancelled that day


async def test_the_replacement_must_be_free(client, school, freeze):
    room, sub, slot, kid, math, fr = await setup(client, school)
    d = school["director"]
    room2 = (await client.post("/v1/classrooms", json={"year_id": school["year_id"], "level": "6e", "name": "6e 2"}, headers=d)).json()
    await client.put(f"/v1/classrooms/{room2['id']}/teachers", json={"assignments": [{"staff_id": fr, "subject_id": sub["fr"]}, {"staff_id": math, "subject_id": sub["maths"]}]}, headers=d)
    busy = await client.post(f"/v1/classrooms/{room2['id']}/timetable/slots", json={"weekday": 1, "start": "08:30", "end": "09:30", "subject_id": sub["fr"], "teacher_id": fr}, headers=d)
    assert busy.status_code == 201
    r = await cancel(client, d, slot, substitute_staff_id=fr)
    assert r.status_code == 409 and r.json()["detail"] == "teacher_busy" and "6e 2" in r.json()["message"]
    # if HER own course is cancelled that day, she is free to replace
    await cancel(client, d, busy.json()["id"])
    assert (await cancel(client, d, slot, substitute_staff_id=fr)).status_code == 201
    # and she cannot cover two classes at the same time
    room3 = (await client.post("/v1/classrooms", json={"year_id": school["year_id"], "level": "6e", "name": "6e 3"}, headers=d)).json()
    other = (await client.post(f"/v1/classrooms/{room3['id']}/timetable/slots", json={"weekday": 1, "start": "08:00", "end": "09:00", "subject_id": sub["maths"], "teacher_id": None}, headers=d)).json()["id"]
    r = await cancel(client, d, other, substitute_staff_id=fr)
    assert r.status_code == 409 and "remplace déjà" in r.json()["message"]


async def test_the_replacement_calls_the_roll_that_day_only(client, school, freeze):
    room, sub, slot, kid, math, fr = await setup(client, school)
    d = school["director"]
    freeze(TODAY, hour=7)
    await cancel(client, d, slot, TODAY, substitute_staff_id=fr)
    t2 = school["teacher2"]
    got = await client.get(f"/v1/timetable/slots/{slot}/roll?on_date={TODAY}", headers=t2)
    assert got.status_code == 200 and len(got.json()["rows"]) == 2  # Aya and Fanta
    saved = await client.put(f"/v1/timetable/slots/{slot}/roll", json={"on_date": TODAY.isoformat(), "entries": [{"enrollment_id": kid, "kind": "absence"}]}, headers=t2)
    assert saved.status_code == 200 and saved.json()["recorded"] == 1
    # the absent teacher herself has no roll to call: her session is cancelled and covered
    assert (await client.get(f"/v1/timetable/slots/{slot}/roll?on_date={TODAY}", headers=school["teacher"])).json()["detail"] == "session_cancelled"
    # a teacher who is not the replacement stays out
    from tests.conftest import make_staff

    stranger, _ = await make_staff(school["id"], "teacher", "Prof Externe")
    assert (await client.get(f"/v1/timetable/slots/{slot}/roll?on_date={TODAY}", headers=stranger)).json()["detail"] == "not_your_course"


async def test_removing_the_cancellation_removes_the_replacement(client, school, freeze):
    room, sub, slot, kid, math, fr = await setup(client, school)
    await cancel(client, school["director"], slot, substitute_staff_id=fr)
    assert (await client.delete(f"/v1/timetable/slots/{slot}/cancellations/{NEXT}", headers=school["director"])).status_code == 200
    assert (await client.get("/v1/timetable/me", headers=school["teacher2"])).json()["substitutions"] == []
    assert (await client.get(f"/v1/classrooms/{room['id']}/timetable", headers=school["director"])).json()["cancellations"] == []


async def test_the_administration_list_names_the_replacement(client, school, freeze):
    room, sub, slot, kid, math, fr = await setup(client, school)
    await cancel(client, school["director"], slot, substitute_staff_id=fr)
    row = (await client.get("/v1/timetable/cancellations", headers=school["director"])).json()[0]
    assert row["substitute"] == "Prof Francais" and row["teacher"] == "Prof Math"


async def test_replacements_are_isolated_between_schools(client, school, freeze):
    from tests.conftest import make_school, make_staff

    room, sub, slot, kid, math, fr = await setup(client, school)
    await cancel(client, school["director"], slot)
    sid2, _ = await make_school("Ecole B")
    other, _ = await make_staff(sid2, "director", "Directrice B")
    assert (await client.put(f"/v1/timetable/slots/{slot}/cancellations/{NEXT}/substitute", json={"staff_id": fr}, headers=other)).status_code == 404


async def test_the_direction_and_secretary_can_list_the_teachers_to_pick_a_replacement(client, school):
    for who in ("director", "secretary"):
        assert [t["name"] for t in (await client.get("/v1/teachers", headers=school[who])).json()] == ["Prof Francais", "Prof Math"]
    for who in ("teacher", "accountant"):
        assert (await client.get("/v1/teachers", headers=school[who])).status_code == 403
