from datetime import date, datetime, timezone

import pytest

from app import clock
from tests.test_academics import class_with_students
from tests.test_api import student
from tests.test_parent import parent_headers

TODAY = date(2026, 11, 23)  # a Monday, inside the school year of the test fixture (2026-09-14 .. 2027-06-30)
NEXT_MON = date(2026, 11, 30)


@pytest.fixture
def freeze(monkeypatch):
    def _set(d: date = TODAY, hour: int = 10):
        monkeypatch.setattr(clock, "now", lambda: datetime(d.year, d.month, d.day, hour, 0, tzinfo=timezone.utc))
    freeze_default = _set
    freeze_default()
    return _set


async def plan(client, s):
    """6e 1 with Prof Math's maths on Monday 08:00-09:00 and 14:00-15:00, Prof Francais's French Monday 10:00-11:00."""
    room, e, sub = await class_with_students(client, s)
    d = s["director"]
    math, fr = sub["staff"]["Prof Math"], sub["staff"]["Prof Francais"]
    ids = {}
    for key, body in (("m_am", (sub["maths"], "08:00", "09:00", math)), ("m_pm", (sub["maths"], "14:00", "15:00", math)), ("fr", (sub["fr"], "10:00", "11:00", fr))):
        r = await client.post(f"/v1/classrooms/{room['id']}/timetable/slots", json={"weekday": 1, "start": body[1], "end": body[2], "subject_id": body[0], "teacher_id": body[3]}, headers=d)
        assert r.status_code == 201, r.text
        ids[key] = r.json()["id"]
    return room, e, sub, ids


def cancel(client, h, slot, day=NEXT_MON, reason="maladie", note=None):
    return client.post(f"/v1/timetable/slots/{slot}/cancellations", json={"on_date": day.isoformat(), "reason": reason, "note": note}, headers=h)


async def test_a_teacher_cancels_one_session_with_a_reason(client, school, freeze):
    room, e, sub, ids = await plan(client, school)
    r = await cancel(client, school["teacher"], ids["m_am"], reason="maladie", note="Grippe")
    assert r.status_code == 201 and r.json() == {"slot_id": ids["m_am"], "date": "2026-11-30", "reason": "maladie", "note": "Grippe", "substitute": None, "families_notified": 0}  # no replacement, and the school did not switch automatic messages on
    # the period stays; only that date is cancelled (the same period next week is untouched)
    tt = (await client.get(f"/v1/classrooms/{room['id']}/timetable", headers=school["director"])).json()
    assert len(tt["slots"]) == 3 and tt["cancellations"] == [{"slot_id": ids["m_am"], "date": "2026-11-30", "reason": "maladie", "note": "Grippe"}]
    # restoring brings the session back
    assert (await client.delete(f"/v1/timetable/slots/{ids['m_am']}/cancellations/2026-11-30", headers=school["teacher"])).status_code == 200
    assert (await client.get(f"/v1/classrooms/{room['id']}/timetable", headers=school["director"])).json()["cancellations"] == []
    assert (await cancel(client, school["teacher"], ids["m_am"], reason="formation")).status_code == 201  # can be cancelled again


async def test_who_may_cancel_what(client, school, freeze):
    room, e, sub, ids = await plan(client, school)
    r = await cancel(client, school["teacher2"], ids["m_am"])  # Prof Francais, not her period
    assert r.status_code == 403 and r.json()["detail"] == "not_your_course"
    assert (await cancel(client, school["accountant"], ids["m_am"])).status_code == 403
    assert (await cancel(client, school["secretary"], ids["m_am"], reason="absence_autorisee")).status_code == 201  # on behalf of the teacher
    assert (await cancel(client, school["director"], ids["fr"], reason="formation")).status_code == 201
    # a teacher cannot undo a colleague's cancellation either
    assert (await client.delete(f"/v1/timetable/slots/{ids['fr']}/cancellations/2026-11-30", headers=school["teacher"])).status_code == 403
    assert (await cancel(client, school["teacher"], 99999)).status_code == 404


async def test_dates_are_checked(client, school, freeze):
    room, e, sub, ids = await plan(client, school)
    t = school["teacher"]
    r = await cancel(client, t, ids["m_am"], date(2026, 12, 1))  # a Tuesday
    assert r.status_code == 400 and r.json()["detail"] == "date_not_that_weekday" and "lundi" in r.json()["message"]
    assert (await cancel(client, t, ids["m_am"], date(2026, 11, 16))).json()["detail"] == "date_in_the_past"
    assert (await cancel(client, t, ids["m_am"], TODAY)).json()["detail"] == "course_already_over"  # 08:00-09:00 is over at 10:00
    assert (await cancel(client, t, ids["m_pm"], TODAY)).status_code == 201  # 14:00-15:00 is still ahead today
    assert (await cancel(client, t, ids["m_am"], date(2027, 7, 5))).json()["detail"] == "outside_school_year"  # a Monday, after the year ended
    # a reason "autre" must be explained; the others need no note
    assert (await cancel(client, t, ids["m_am"], reason="autre")).json()["detail"] == "note_required"
    assert (await cancel(client, t, ids["m_am"], reason="autre", note="  ")).json()["detail"] == "note_required"
    assert (await cancel(client, t, ids["m_am"], reason="autre", note="Décès dans la famille")).status_code == 201
    assert (await cancel(client, t, ids["m_am"], reason="rhume")).status_code == 422
    assert (await cancel(client, t, ids["m_am"], reason="maladie")).json()["detail"] == "session_already_cancelled"
    # restoring a date that has passed is refused; one that was never cancelled is unknown
    assert (await client.delete(f"/v1/timetable/slots/{ids['m_am']}/cancellations/2026-11-16", headers=t)).json()["detail"] == "date_in_the_past"
    assert (await client.delete(f"/v1/timetable/slots/{ids['m_am']}/cancellations/2026-12-07", headers=t)).status_code == 404


async def test_the_reason_stays_private(client, school, freeze):
    room, e, sub, ids = await plan(client, school)
    one = (await client.post("/v1/students", json=student(room, last_name="Traore", first_names="Fanta"), headers=school["secretary"])).json()
    await cancel(client, school["teacher"], ids["m_am"], reason="maladie", note="Grippe")
    # the director, the secretary and the teacher concerned see the reason...
    for who in ("director", "secretary", "teacher"):
        got = (await client.get(f"/v1/classrooms/{room['id']}/timetable", headers=school[who])).json()["cancellations"]
        assert got and got[0]["reason"] == "maladie" and got[0]["note"] == "Grippe", who
    # ...a colleague reading the same class timetable sees THAT it is cancelled, not why
    other = (await client.get(f"/v1/classrooms/{room['id']}/timetable", headers=school["teacher2"])).json()["cancellations"]
    assert other == [{"slot_id": ids["m_am"], "date": "2026-11-30"}]
    # parents see that the session is cancelled, never the reason
    week = (await client.get(f"/v1/parent/children/{one['enrollment_id']}/timetable", headers=parent_headers("+2250701020304"))).json()
    assert week["cancellations"] == [{"slot_id": ids["m_am"], "date": "2026-11-30"}]
    assert "Grippe" not in str(week) and "maladie" not in str(week)
    # her own week shows her reason
    mine = (await client.get("/v1/timetable/me", headers=school["teacher"])).json()["cancellations"]
    assert mine[0]["reason"] == "maladie"


async def test_the_administration_gets_the_list_and_a_message_for_the_families(client, school, freeze):
    room, e, sub, ids = await plan(client, school)
    await cancel(client, school["teacher"], ids["m_pm"], TODAY, "maladie", "Grippe")
    await cancel(client, school["teacher"], ids["m_am"], NEXT_MON, "formation")
    for who in ("director", "secretary"):
        rows = (await client.get("/v1/timetable/cancellations", headers=school[who])).json()
        assert [(r["date"], r["start"], r["subject"], r["classroom"], r["teacher"], r["reason"]) for r in rows] == [
            ("2026-11-23", "14:00", "Mathématiques", "6e 1", "Prof Math", "maladie"), ("2026-11-30", "08:00", "Mathématiques", "6e 1", "Prof Math", "formation")]
    msg = rows[0]["message"]
    assert "Mathématiques" in msg and "6e 1" in msg and "lundi 23/11" in msg and "14:00-15:00" in msg and "enseignant absent" in msg
    assert "maladie" not in msg and "Grippe" not in msg  # the message for families never carries the reason
    assert (await client.get("/v1/timetable/cancellations", headers=school["teacher"])).status_code == 403
    assert (await client.get("/v1/timetable/cancellations", headers=school["accountant"])).status_code == 403
    # yesterday's cancellations are not "upcoming"
    freeze(date(2026, 12, 1))
    assert (await client.get("/v1/timetable/cancellations", headers=school["director"])).json() == []


async def test_deleting_the_period_removes_its_cancellations_and_audit_is_kept(client, school, freeze):
    from sqlalchemy import func, select

    from app.db import SessionLocal
    from app.models import AuditLog, SlotCancellation

    room, e, sub, ids = await plan(client, school)
    await cancel(client, school["teacher"], ids["m_am"])
    await client.delete(f"/v1/timetable/slots/{ids['m_am']}/cancellations/2026-11-30", headers=school["teacher"])
    await cancel(client, school["teacher"], ids["m_pm"])
    await client.delete(f"/v1/timetable/slots/{ids['m_pm']}", headers=school["director"])
    async with SessionLocal() as db:
        assert await db.scalar(select(func.count()).select_from(SlotCancellation)) == 0
        actions = [a for (a,) in (await db.execute(select(AuditLog.action).where(AuditLog.action.like("timetable.session.%")).order_by(AuditLog.id))).all()]
    assert actions == ["timetable.session.cancelled", "timetable.session.restored", "timetable.session.cancelled"]


async def test_cancellations_are_isolated_between_schools(client, school, freeze):
    from tests.conftest import make_school, make_staff

    room, e, sub, ids = await plan(client, school)
    await cancel(client, school["teacher"], ids["m_am"])
    sid2, _ = await make_school("Ecole B")
    other, _ = await make_staff(sid2, "director", "Directrice B")
    assert (await cancel(client, other, ids["m_pm"])).status_code == 404
    assert (await client.delete(f"/v1/timetable/slots/{ids['m_am']}/cancellations/2026-11-30", headers=other)).status_code == 404
    assert (await client.get("/v1/timetable/cancellations", headers=other)).json() == []
