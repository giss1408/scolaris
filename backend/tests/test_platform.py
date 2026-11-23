import time
import uuid
from datetime import date, datetime, timezone

import pytest

from app import clock
from app.models import Subscription
from app.services.saas_billing import dues_until
from tests.conftest import make_school, make_staff, make_token
from tests.test_academics import class_with_students
from tests.test_api import student
from tests.test_parent import parent_headers

TODAY = date(2026, 11, 23)


@pytest.fixture
def freeze(monkeypatch):
    def _set(d: date = TODAY, hour: int = 10):
        monkeypatch.setattr(clock, "now", lambda: datetime(d.year, d.month, d.day, hour, 0, tzinfo=timezone.utc))

    _set()
    return _set


def admin(**kw) -> dict:
    kw.setdefault("amr", ("pwd", "totp"))
    return {"Authorization": "Bearer " + make_token(kw.pop("user", uuid.uuid4()), "platform_admin", app_name="admin", **kw)}


async def subscribe(client, sid, started="2026-09-14", amount=50000, day=5, grace=5):
    r = await client.put(f"/v1/platform/schools/{sid}/subscription", json={"monthly_amount": amount, "billing_day": day, "started_on": started, "grace_days": grace}, headers=admin())
    assert r.status_code == 200, r.text
    return r.json()


async def notice(client, sid, kind="reminder", **kw):
    return await client.post(f"/v1/platform/schools/{sid}/notices", json={"kind": kind, **kw}, headers=admin())


async def pay(client, sid, amount, **kw):
    return await client.post(f"/v1/platform/schools/{sid}/payments", json={"amount": amount, "method": "wave", "reference": "WV-1", **kw}, headers=admin())


def test_monthly_dues_start_on_the_first_billing_day_on_or_after_the_start_and_cross_years():
    sub = lambda started, day=5: Subscription(school_id=1, monthly_amount=1000, billing_day=day, started_on=started, grace_days=5)  # noqa: E731
    assert [d.due_date for d in dues_until(sub(date(2026, 9, 14)), date(2026, 11, 23))] == [date(2026, 10, 5), date(2026, 11, 5)]
    assert [d.due_date for d in dues_until(sub(date(2026, 11, 3)), date(2026, 11, 23))] == [date(2026, 11, 5)]  # started before the 5th: due this month
    assert [d.due_date for d in dues_until(sub(date(2026, 11, 20)), date(2027, 2, 10))] == [date(2026, 12, 5), date(2027, 1, 5), date(2027, 2, 5)]  # across the new year
    assert dues_until(sub(date(2026, 12, 1)), date(2026, 11, 23)) == []
    assert dues_until(sub(date(2026, 11, 5)), date(2026, 11, 5))[0].due_date == date(2026, 11, 5)


async def test_only_a_platform_admin_with_her_authenticator_code_gets_in(client, school, freeze):
    url = "/v1/platform/schools"
    assert (await client.get(url)).status_code == 401
    assert (await client.get(url, headers=admin())).status_code == 200
    assert (await client.get(url, headers=admin(amr=("pwd",)))).json()["detail"] == "totp_required"  # signed in without the second factor
    assert (await client.get(url, headers=school["director"])).json()["detail"] == "not_platform_admin"  # a school's director is not a platform admin
    assert (await client.get(url, headers={"Authorization": "Bearer " + make_token(uuid.uuid4(), "platform_admin", app_name="staff", amr=("pwd", "totp"))})).status_code == 403  # right role, wrong app
    assert (await client.get(url, headers=parent_headers("+2250701020304"))).status_code == 403
    assert (await client.get(url, headers=admin(mcp=True))).json()["detail"] == "password_change_required"


async def test_the_standing_of_a_school_follows_its_payments(client, school, freeze):
    sid = school["id"]
    s = await subscribe(client, sid)
    assert (s["billed"], s["remaining"], s["overdue_months"], s["oldest_late_days"], s["late"], s["next_due"]) == (100000, 100000, 2, 49, True, "2026-12-05")
    p = (await pay(client, sid, 50000)).json()
    assert (p["standing"]["remaining"], p["standing"]["overdue_months"], p["standing"]["oldest_late_days"], p["standing"]["late"]) == (50000, 1, 18, True)  # the oldest is paid first
    p = (await pay(client, sid, 50000)).json()
    assert (p["standing"]["remaining"], p["standing"]["late"], p["can_unblock"]) == (0, False, False)
    # within the grace period a school is not late
    freeze(date(2026, 12, 8))
    assert (await client.get(f"/v1/platform/schools/{sid}", headers=admin())).json()["subscription"]["late"] is False  # due Dec 5, 3 days ago, grace 5
    freeze(date(2026, 12, 12))
    assert (await client.get(f"/v1/platform/schools/{sid}", headers=admin())).json()["subscription"]["late"] is True
    # money rules
    assert (await pay(client, sid, 1000, method="bitcoin")).json()["detail"] == "method_invalid"
    sid2, _ = await make_school("Pilote")
    assert (await pay(client, sid2, 1000)).json()["detail"] == "no_subscription"
    assert (await client.put(f"/v1/platform/schools/{sid}/subscription", json={"monthly_amount": 0, "billing_day": 5, "started_on": "2026-09-14"}, headers=admin())).status_code == 422
    assert (await client.put(f"/v1/platform/schools/{sid}/subscription", json={"monthly_amount": 1000, "billing_day": 31, "started_on": "2026-09-14"}, headers=admin())).status_code == 422
    stale = admin(auth_time=time.time() - 3600)
    assert (await client.post(f"/v1/platform/schools/{sid}/payments", json={"amount": 1000, "method": "wave", "reference": "x"}, headers=stale)).json()["detail"] == "step_up_required"


async def test_a_school_without_a_subscription_is_never_late(client, school, freeze):
    rows = (await client.get("/v1/platform/schools", headers=admin())).json()
    assert rows[0]["subscription"] is None and rows[0]["status"] == "active"
    r = await notice(client, school["id"])
    assert r.status_code == 400 and r.json()["detail"] == "not_late"
    assert (await client.post(f"/v1/platform/schools/{school['id']}/block", json={"reason": "impayé"}, headers=admin())).json()["detail"] == "not_late"


async def test_reminders_are_shown_to_the_director_and_the_secretary_in_the_app(client, school, freeze):
    sid = school["id"]
    await subscribe(client, sid)
    r1 = await notice(client, sid)
    assert r1.status_code == 201 and "100" in r1.json()["text"].replace(" ", "") and "2 mensualités" in r1.json()["text"]
    for who in ("director", "secretary"):
        b = (await client.get("/v1/billing", headers=school[who])).json()
        assert b["status"] == "active" and [n["kind"] for n in b["notices"]] == ["reminder"] and b["standing"]["remaining"] == 100000 and b["notices"][0]["seen"] is False, who
        banner = (await client.get("/v1/me", headers=school[who])).json()["billing_banner"]
        assert banner["level"] == "late" and banner["unseen"] == 1 and "en retard" in banner["text"], who
    for who in ("teacher", "accountant"):  # not for the rest of the staff
        assert (await client.get("/v1/billing", headers=school[who])).status_code == 403
        assert (await client.get("/v1/me", headers=school[who])).json()["billing_banner"] is None
    # the director reads it: the platform team can see who has
    assert (await client.post(f"/v1/billing/notices/{r1.json()['id']}/seen", headers=school["director"])).status_code == 200
    assert (await client.post(f"/v1/billing/notices/{r1.json()['id']}/seen", headers=school["director"])).status_code == 200  # twice is fine
    seen = (await client.get(f"/v1/platform/schools/{sid}", headers=admin())).json()["notices"][0]
    assert (seen["seen_by"], seen["audience"]) == (1, 2)
    assert (await client.get("/v1/billing", headers=school["director"])).json()["notices"][0]["seen"] is True
    assert (await client.get("/v1/me", headers=school["director"])).json()["billing_banner"]["unseen"] == 0
    assert (await client.post("/v1/billing/notices/9999/seen", headers=school["director"])).status_code == 404
    # a paid-up school has no banner
    await pay(client, sid, 100000)
    assert (await client.get("/v1/me", headers=school["secretary"])).json()["billing_banner"]["level"] == "info"  # only the unseen notice remains
    await client.post(f"/v1/billing/notices/{r1.json()['id']}/seen", headers=school["secretary"])
    assert (await client.get("/v1/me", headers=school["secretary"])).json()["billing_banner"] is None


async def test_blocking_is_slow_by_design(client, school, freeze):
    sid = school["id"]
    await subscribe(client, sid)
    block = lambda **kw: client.post(f"/v1/platform/schools/{sid}/block", json={"reason": "Impayé depuis deux mois", **kw}, headers=admin())  # noqa: E731
    assert (await block()).json()["detail"] == "reminders_required"  # nothing was sent in the app yet
    # the final notice needs a reminder first, and a block date a week ahead
    assert (await notice(client, sid, "final_notice", block_on="2026-12-10")).json()["detail"] == "reminder_first"
    assert (await notice(client, sid)).status_code == 201
    assert (await notice(client, sid, "final_notice", block_on="2026-11-28")).json()["detail"] == "block_date_too_soon"
    assert (await notice(client, sid, "final_notice")).json()["detail"] == "block_date_too_soon"
    assert (await block()).json()["detail"] == "final_notice_required"
    fin = await notice(client, sid, "final_notice", block_on="2026-12-10")
    assert fin.status_code == 201 and "10/12/2026" in fin.json()["text"] and "suspendu" in fin.json()["text"]
    assert (await client.get("/v1/me", headers=school["director"])).json()["billing_banner"]["level"] == "final"
    assert (await block()).json()["detail"] == "block_date_not_reached"  # the school was promised until the 10th
    freeze(date(2026, 12, 10))
    # a fresh password is needed, and a live session
    assert (await client.post(f"/v1/platform/schools/{sid}/block", json={"reason": "Impayé"}, headers=admin(auth_time=time.time() - 3600))).json()["detail"] == "step_up_required"
    pytest.auth_calls["session_alive"] = False
    assert (await block()).json()["detail"] == "session_ended"
    pytest.auth_calls["session_alive"] = True
    assert (await block()).status_code == 200
    assert (await block()).json()["detail"] == "already_blocked"


async def test_paying_before_the_announced_date_stops_the_process(client, school, freeze):
    sid = school["id"]
    await subscribe(client, sid)
    await notice(client, sid)
    await notice(client, sid, "final_notice", block_on="2026-12-10")
    freeze(date(2026, 12, 10))
    await pay(client, sid, 150000)  # October, November and December
    r = await client.post(f"/v1/platform/schools/{sid}/block", json={"reason": "Impayé"}, headers=admin())
    assert r.status_code == 400 and r.json()["detail"] == "not_late"  # the notices stand, but there is nothing left to chase


async def _blocked(client, school, freeze):
    sid = school["id"]
    await subscribe(client, sid)
    await notice(client, sid)
    await notice(client, sid, "final_notice", block_on="2026-12-01")
    freeze(date(2026, 12, 2))
    r = await client.post(f"/v1/platform/schools/{sid}/block", json={"reason": "Impayé"}, headers=admin())
    assert r.status_code == 200, r.text


async def test_a_blocked_school_keeps_only_what_the_direction_needs_to_settle(client, school, freeze):
    room, e, sub = await class_with_students(client, school, names=("Aya",))
    await client.post("/v1/students", json=student(room, last_name="Traore", first_names="Fanta"), headers=school["secretary"])
    await _blocked(client, school, freeze)
    for who in ("director", "secretary"):
        h = school[who]
        me = await client.get("/v1/me", headers=h)
        assert me.status_code == 200 and me.json()["billing_banner"]["level"] == "blocked", who
        b = (await client.get("/v1/billing", headers=h)).json()
        assert b["status"] == "blocked" and "blocked" in [n["kind"] for n in b["notices"]]
        assert (await client.get("/v1/school/logo", headers=h)).status_code in (200, 404)  # allowed: not refused as blocked
        for path in (f"/v1/students?year_id={school['year_id']}", "/v1/subjects", f"/v1/classrooms?year_id={school['year_id']}", "/v1/messages"):
            r = await client.get(path, headers=h)
            assert r.status_code == 403 and r.json()["detail"] == "school_blocked", (who, path)
    for who in ("teacher", "accountant"):
        for path in ("/v1/me", "/v1/billing"):
            r = await client.get(path, headers=school[who])
            assert r.status_code == 403 and r.json()["detail"] == "school_blocked", (who, path)
    assert (await client.post("/v1/students", json=student(room), headers=school["director"])).json()["detail"] == "school_blocked"
    # parents: told, nothing else
    me = parent_headers("+2250701020304")
    kids = (await client.get("/v1/parent/children", headers=me)).json()
    assert kids[0]["blocked"] is True and kids[0]["balance"] == {"remaining": 0, "overdue": 0, "total_due": 0}
    enr = kids[0]["enrollment_id"]
    for path in (f"/v1/parent/children/{enr}/payments", f"/v1/parent/children/{enr}/report-card?period=1", f"/v1/parent/children/{enr}/timetable", f"/v1/parent/children/{enr}/absences"):
        r = await client.get(path, headers=me)
        assert r.status_code == 403 and r.json()["detail"] == "school_blocked", path
    assert (await client.post(f"/v1/parent/children/{enr}/absence-reports", json={"day": "2026-12-03", "reason": "maladie"}, headers=me)).json()["detail"] == "school_blocked"


async def test_a_blocked_school_sends_no_whatsapp(client, school, freeze):
    from app.db import SessionLocal
    from app.models import School
    from app.services import outbox

    room, e, sub = await class_with_students(client, school, names=("Aya",))
    st = (await client.post("/v1/students", json=student(room, last_name="Traore", first_names="Fanta"), headers=school["secretary"])).json()
    await client.put("/v1/school/settings", json={"auto_whatsapp": True}, headers=school["director"])
    await _blocked(client, school, freeze)
    async with SessionLocal() as db:
        assert await outbox.enqueue(db, school_id=school["id"], family_id=st["family_id"], kind="other", text="x", dedupe_key="blk", now=clock.now()) is None


async def test_unblocking_restores_everything_and_both_steps_are_audited(client, school, freeze):
    sid = school["id"]
    await _blocked(client, school, freeze)
    assert (await client.get(f"/v1/students?year_id={school['year_id']}", headers=school["director"])).status_code == 403
    paid = (await pay(client, sid, 200000)).json()
    assert paid["standing"]["remaining"] == 0 and paid["can_unblock"] is True  # the admin is told she can lift it
    assert (await client.post(f"/v1/platform/schools/{sid}/unblock", headers=admin(auth_time=time.time() - 3600))).json()["detail"] == "step_up_required"
    assert (await client.post(f"/v1/platform/schools/{sid}/unblock", headers=admin())).json() == {"status": "active"}
    assert (await client.post(f"/v1/platform/schools/{sid}/unblock", headers=admin())).json()["detail"] == "not_blocked"
    for who in ("director", "teacher", "accountant"):
        assert (await client.get("/v1/me", headers=school[who])).status_code == 200, who
    assert (await client.get(f"/v1/students?year_id={school['year_id']}", headers=school["secretary"])).status_code == 200
    assert "unblocked" in [n["kind"] for n in (await client.get("/v1/billing", headers=school["director"])).json()["notices"]]
    log = (await client.get(f"/v1/platform/audit?school_id={sid}", headers=admin())).json()
    assert [a["action"] for a in log][:2] == ["school.unblocked", "subscription.payment"] and "school.blocked" in [a["action"] for a in log]
    assert (await client.get("/v1/platform/audit", headers=school["director"])).status_code == 403


async def test_the_team_sees_the_late_schools_first(client, school, freeze):
    sid2, _ = await make_school("A l'heure")
    sid3, _ = await make_school("Bloquée")
    await subscribe(client, school["id"])
    await subscribe(client, sid2, started="2026-11-20")  # first instalment Dec 5: not due yet
    await subscribe(client, sid3, started="2026-09-14")
    await notice(client, sid3)
    await notice(client, sid3, "final_notice", block_on="2026-12-01")
    freeze(date(2026, 12, 2))
    await client.post(f"/v1/platform/schools/{sid3}/block", json={"reason": "Impayé"}, headers=admin())
    rows = (await client.get("/v1/platform/schools", headers=admin())).json()
    assert [(r["name"], r["status"]) for r in rows] == [("Bloquée", "blocked"), ("Ecole A", "active"), ("A l'heure", "active")]
    assert rows[1]["subscription"]["late"] is True and rows[2]["subscription"]["late"] is False
    assert rows[0]["reminders"] == 1 and rows[0]["final_notices"] == 1


async def test_a_schools_staff_cannot_reach_another_schools_billing(client, school, freeze):
    await subscribe(client, school["id"])
    await notice(client, school["id"])
    sid2, _ = await make_school("Ecole B")
    other, _ = await make_staff(sid2, "director", "Directrice B")
    b = (await client.get("/v1/billing", headers=other)).json()
    assert b["notices"] == [] and b["standing"] is None
    assert (await client.post(f"/v1/billing/notices/1/seen", headers=other)).status_code == 404  # A's notice is not B's
    assert (await client.get("/v1/platform/schools", headers=other)).status_code == 403
