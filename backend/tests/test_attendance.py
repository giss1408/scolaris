from datetime import date, datetime, timedelta, timezone

import pytest
from sqlalchemy import select

from app import clock
from app.db import SessionLocal
from app.models import Absence, OutboundMessage
from tests.test_academics import class_with_students
from tests.test_api import student
from tests.test_parent import parent_headers

MON = date(2026, 11, 23)  # a Monday inside the school year of the fixture


@pytest.fixture
def freeze(monkeypatch):
    def _set(d: date = MON, hour: int = 10):
        monkeypatch.setattr(clock, "now", lambda: datetime(d.year, d.month, d.day, hour, 0, tzinfo=timezone.utc))

    _set()
    return _set


async def setup(client, s):
    """6e 1 with Prof Math's maths on Monday 08:00-09:00, and two pupils whose parent (07 01 02 03 04) opted in to WhatsApp."""
    room, e, sub = await class_with_students(client, s, names=("Aya",))
    d = s["director"]
    await client.put("/v1/school/settings", json={"auto_whatsapp": True}, headers=d)  # the school lets Scolaris tell parents on WhatsApp
    slot = (await client.post(f"/v1/classrooms/{room['id']}/timetable/slots", json={"weekday": 1, "start": "08:00", "end": "09:00", "subject_id": sub["maths"], "teacher_id": sub["staff"]["Prof Math"]}, headers=d)).json()["id"]
    kids = {}
    for first in ("Fanta", "Moussa"):
        kids[first] = (await client.post("/v1/students", json=student(room, last_name="Traore", first_names=first), headers=s["secretary"])).json()["enrollment_id"]
    return room, sub, slot, kids


def roll(client, h, slot, entries, day=MON):
    return client.put(f"/v1/timetable/slots/{slot}/roll", json={"on_date": day.isoformat(), "entries": entries}, headers=h)


async def messages():
    async with SessionLocal() as db:
        return (await db.scalars(select(OutboundMessage).order_by(OutboundMessage.id))).all()


async def test_the_teacher_calls_the_roll_of_her_period_and_parents_are_told_once(client, school, freeze):
    room, sub, slot, kids = await setup(client, school)
    t = school["teacher"]
    got = (await client.get(f"/v1/timetable/slots/{slot}/roll?on_date={MON}", headers=t)).json()["rows"]
    assert len(got) == 3 and {r["status"] for r in got} == {"present"}  # everyone is present until she says otherwise
    r = await roll(client, t, slot, [{"enrollment_id": kids["Fanta"], "kind": "absence"}, {"enrollment_id": kids["Moussa"], "kind": "retard"}])
    assert r.status_code == 200 and r.json() == {"recorded": 2, "notified": 2}
    by = {x["enrollment_id"]: x for x in (await client.get(f"/v1/timetable/slots/{slot}/roll?on_date={MON}", headers=t)).json()["rows"]}
    assert (by[kids["Fanta"]]["status"], by[kids["Moussa"]]["status"]) == ("absence", "retard")
    msgs = await messages()
    previews = sorted(m.preview for m in msgs)
    assert "Fanta TRAORE a été noté(e) absent(e) au cours de Mathématiques (08:00-09:00) le 23/11." in previews[0] + previews[1]
    assert any("Moussa TRAORE a été noté(e) en retard au cours de Mathématiques" in p for p in previews) and all(m.kind == "absence" and m.status == "queued" for m in msgs)
    # the same roll again: nobody is told twice
    assert (await roll(client, t, slot, [{"enrollment_id": kids["Fanta"], "kind": "absence"}, {"enrollment_id": kids["Moussa"], "kind": "retard"}])).json()["notified"] == 0
    # a change (late -> absent) is new information; a pupil no longer listed is present again
    again = await roll(client, t, slot, [{"enrollment_id": kids["Fanta"], "kind": "absence"}, {"enrollment_id": kids["Moussa"], "kind": "absence", "justified": True}])
    assert again.json()["notified"] == 1
    cleared = await roll(client, t, slot, [{"enrollment_id": kids["Fanta"], "kind": "absence"}])
    by = {x["enrollment_id"]: x for x in (await client.get(f"/v1/timetable/slots/{slot}/roll?on_date={MON}", headers=t)).json()["rows"]}
    assert cleared.status_code == 200 and by[kids["Moussa"]]["status"] == "present"
    assert len(await messages()) == 3


async def test_who_may_call_which_roll_and_when(client, school, freeze):
    room, sub, slot, kids = await setup(client, school)
    body = [{"enrollment_id": kids["Fanta"]}]
    assert (await roll(client, school["teacher2"], slot, body)).json()["detail"] == "not_your_course"  # another teacher's period
    assert (await roll(client, school["accountant"], slot, body)).status_code == 403
    t = school["teacher"]
    assert (await roll(client, t, slot, body, MON - timedelta(days=7))).json()["detail"] == "only_today"  # a teacher cannot backdate
    assert (await roll(client, t, slot, body, MON + timedelta(days=7))).json()["detail"] == "date_in_the_future"
    assert (await roll(client, t, slot, body, MON + timedelta(days=1))).json()["detail"] == "date_not_that_weekday"
    # the direction can fix a recent day, not an old one
    assert (await roll(client, school["director"], slot, body, MON - timedelta(days=7))).status_code == 200
    assert (await roll(client, school["secretary"], slot, body, MON - timedelta(days=28))).status_code == 200
    assert (await roll(client, school["secretary"], slot, body, MON - timedelta(days=35))).json()["detail"] == "date_too_old"
    # only pupils of this class
    other = (await client.post("/v1/classrooms", json={"year_id": school["year_id"], "level": "6e", "name": "6e 2"}, headers=school["director"])).json()
    stranger = (await client.post("/v1/students", json=student(other, last_name="Autre", contacts=[]), headers=school["secretary"])).json()["enrollment_id"]
    assert (await roll(client, t, slot, [{"enrollment_id": stranger}])).json()["detail"] == "student_not_in_class"


async def test_a_cancelled_session_has_no_roll(client, school, freeze):
    freeze(MON, hour=7)  # before the 08:00 course: it can still be cancelled today
    room, sub, slot, kids = await setup(client, school)
    done = await client.post(f"/v1/timetable/slots/{slot}/cancellations", json={"on_date": MON.isoformat(), "reason": "maladie"}, headers=school["director"])
    assert done.status_code == 201
    for who in ("teacher", "director"):
        r = await roll(client, school[who], slot, [{"enrollment_id": kids["Fanta"]}])
        assert r.status_code == 400 and r.json()["detail"] == "session_cancelled", who


async def test_course_absences_are_apart_from_day_absences(client, school, freeze):
    room, sub, slot, kids = await setup(client, school)
    # whole-day absence by the existing roll call + one period missed during the course, same pupil, same day: both are kept
    await client.post("/v1/absences", json={"day": MON.isoformat(), "entries": [{"enrollment_id": kids["Fanta"], "kind": "absence"}]}, headers=school["secretary"])
    await roll(client, school["teacher"], slot, [{"enrollment_id": kids["Fanta"], "kind": "absence"}])
    async with SessionLocal() as db:
        rows = (await db.scalars(select(Absence).where(Absence.enrollment_id == kids["Fanta"]))).all()
    assert sorted((a.slot, a.slot_id is not None) for a in rows) == [("cours", True), ("jour", False)]
    # the course roll shows the pupil was absent all day; the day-level list does not mix the two
    row = [r for r in (await client.get(f"/v1/timetable/slots/{slot}/roll?on_date={MON}", headers=school["teacher"])).json()["rows"] if r["enrollment_id"] == kids["Fanta"]][0]
    assert row["absent_all_day"] is True and row["status"] == "absence"
    day_list = (await client.get(f"/v1/classrooms/{room['id']}/absences?day={MON}", headers=school["secretary"])).json()
    assert [(a["slot"]) for a in day_list] == ["jour"]
    # replacing the day roll call does not erase the course roll
    await client.post("/v1/absences", json={"day": MON.isoformat(), "classroom_id": room["id"], "replace": True, "entries": []}, headers=school["secretary"])
    async with SessionLocal() as db:
        assert [a.slot for a in (await db.scalars(select(Absence).where(Absence.enrollment_id == kids["Fanta"]))).all()] == ["cours"]
    # the report card counts days and, apart, the periods missed
    card = (await client.get(f"/v1/enrollments/{kids['Fanta']}/report-card?period=1", headers=school["director"])).json()
    assert card["absences"] == {"days_unjustified": 0, "days_justified": 0, "late": 0, "courses_missed": 1}


async def test_the_day_roll_call_now_tells_parents_too(client, school, freeze):
    room, sub, slot, kids = await setup(client, school)
    r = await client.post("/v1/absences", json={"day": MON.isoformat(), "entries": [{"enrollment_id": kids["Fanta"], "kind": "absence"}]}, headers=school["secretary"])
    assert r.json() == {"recorded": 1, "notified": 1}
    assert "à l'école le 23/11" in (await messages())[0].preview
    assert (await client.post("/v1/absences", json={"day": MON.isoformat(), "entries": [{"enrollment_id": kids["Fanta"], "kind": "absence", "justified": True}]}, headers=school["secretary"])).json()["notified"] == 0
    past = await client.post("/v1/absences", json={"day": (MON - timedelta(days=3)).isoformat(), "entries": [{"enrollment_id": kids["Moussa"], "kind": "absence"}]}, headers=school["secretary"])
    assert past.json()["notified"] == 0  # a correction for a past day is not announced as news


async def test_a_parent_reports_a_day_and_the_school_sees_it(client, school, freeze):
    room, sub, slot, kids = await setup(client, school)
    me = parent_headers("+2250701020304")
    url = f"/v1/parent/children/{kids['Fanta']}/absence-reports"
    r = await client.post(url, json={"day": MON.isoformat(), "reason": "maladie", "note": "Palu"}, headers=me)
    assert r.status_code == 201 and r.json() == {"day": "2026-11-23", "reason": "maladie", "note": "Palu"}
    # reporting the same day again updates it (no duplicate)
    await client.post(url, json={"day": MON.isoformat(), "reason": "rendez_vous"}, headers=me)
    assert [(x["day"], x["reason"]) for x in (await client.get(url, headers=me)).json()] == [("2026-11-23", "rendez_vous")]
    # the teacher of the class, the secretary and the director see it; so does the roll call next to the pupil
    for who in ("teacher", "secretary", "director"):
        got = (await client.get(f"/v1/classrooms/{room['id']}/absence-reports?day={MON}", headers=school[who])).json()
        assert [(g["name"], g["reason"]) for g in got] == [("TRAORE Fanta", "rendez_vous")], who
    row = [x for x in (await client.get(f"/v1/timetable/slots/{slot}/roll?on_date={MON}", headers=school["teacher"])).json()["rows"] if x["enrollment_id"] == kids["Fanta"]][0]
    assert row["reported"] == {"reason": "rendez_vous", "note": None} and row["status"] == "present"  # it informs the roll, it does not mark the pupil
    assert [(x["classroom"], x["name"]) for x in (await client.get("/v1/absence-reports", headers=school["secretary"])).json()] == [("6e 1", "TRAORE Fanta")]
    assert (await client.get("/v1/absence-reports", headers=school["teacher"])).status_code == 403
    # a parent who reported is not sent "your child was absent"
    assert (await roll(client, school["teacher"], slot, [{"enrollment_id": kids["Fanta"]}, {"enrollment_id": kids["Moussa"]}])).json() == {"recorded": 2, "notified": 1}
    # she changes her mind
    assert (await client.delete(f"{url}/{MON}", headers=me)).status_code == 200
    assert (await client.get(url, headers=me)).json() == []
    assert (await client.delete(f"{url}/{MON}", headers=me)).status_code == 404


async def test_the_days_a_parent_may_report_and_who_may_report(client, school, freeze):
    room, sub, slot, kids = await setup(client, school)
    me = parent_headers("+2250701020304")
    url = f"/v1/parent/children/{kids['Fanta']}/absence-reports"
    ok = lambda day, **kw: client.post(url, json={"day": day.isoformat(), "reason": "famille", **kw}, headers=me)  # noqa: E731
    assert (await ok(MON - timedelta(days=3))).status_code == 201  # to explain a recent day
    assert (await ok(MON - timedelta(days=4))).json()["detail"] == "day_out_of_range"
    assert (await ok(MON + timedelta(days=14))).status_code == 201
    assert (await ok(MON + timedelta(days=15))).json()["detail"] == "day_out_of_range"
    assert (await ok(date(2026, 11, 29))).json()["detail"] == "no_school_on_sunday"
    assert (await client.post(url, json={"day": MON.isoformat(), "reason": "autre"}, headers=me)).json()["detail"] == "note_required"
    assert (await client.post(url, json={"day": MON.isoformat(), "reason": "caprice"}, headers=me)).status_code == 422
    assert (await client.delete(f"{url}/{MON - timedelta(days=1)}", headers=me)).json()["detail"] == "date_in_the_past"
    # another parent, or a child of another family: nothing is revealed
    assert (await client.post(url, json={"day": MON.isoformat(), "reason": "famille"}, headers=parent_headers("+2250909090909"))).status_code == 404
    assert (await client.post(url, json={"day": MON.isoformat(), "reason": "famille"}, headers=school["director"])).status_code == 403


async def test_a_parent_sees_the_course_where_her_child_was_noted_absent(client, school, freeze):
    room, sub, slot, kids = await setup(client, school)
    await roll(client, school["teacher"], slot, [{"enrollment_id": kids["Fanta"], "kind": "absence"}])
    await client.post("/v1/absences", json={"day": MON.isoformat(), "entries": [{"enrollment_id": kids["Fanta"], "kind": "retard"}]}, headers=school["secretary"])
    rows = (await client.get(f"/v1/parent/children/{kids['Fanta']}/absences", headers=parent_headers("+2250701020304"))).json()
    assert sorted((r["slot"], (r["course"] or {}).get("subject")) for r in rows) == [("cours", "Mathématiques"), ("jour", None)]


async def test_attendance_is_isolated_between_schools(client, school, freeze):
    from tests.conftest import make_school, make_staff

    room, sub, slot, kids = await setup(client, school)
    sid2, _ = await make_school("Ecole B")
    other, _ = await make_staff(sid2, "director", "Directrice B")
    assert (await client.get(f"/v1/timetable/slots/{slot}/roll?on_date={MON}", headers=other)).status_code == 404
    assert (await roll(client, other, slot, [])).status_code == 404
    assert (await client.get("/v1/absence-reports", headers=other)).json() == []
    assert (await client.get(f"/v1/classrooms/{room['id']}/absence-reports?day={MON}", headers=other)).status_code == 404
