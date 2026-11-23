import uuid
from datetime import date, timedelta

import pytest

from tests.conftest import make_school, make_staff, make_token

Y = date.today().year


async def setup_class(client, s, *, due_past=True):
    d = s["director"]
    room = (await client.post("/v1/classrooms", json={"year_id": s["year_id"], "level": "6e", "name": "6e 1"}, headers=d)).json()
    first = date.today() - timedelta(days=20) if due_past else date.today() + timedelta(days=30)
    r = await client.put("/v1/fees", headers=d, json={"year_id": s["year_id"], "level": "6e", "lines": [
        {"kind": "inscription", "label": "Inscription", "amount": 30000, "due_date": first.isoformat()},
        {"kind": "scolarite", "label": "1re tranche", "amount": 100000, "due_date": (first + timedelta(days=10)).isoformat()},
        {"kind": "scolarite", "label": "2e tranche", "amount": 100000, "due_date": (date.today() + timedelta(days=90)).isoformat()},
        {"kind": "cantine", "label": "Cantine", "amount": 25000, "due_date": first.isoformat(), "optional": True},
        {"kind": "coges", "label": "COGES non affectés", "amount": 5000, "due_date": first.isoformat(), "applies_to": "non_assigned"},
    ]})
    assert r.status_code == 200, r.text
    return room


def student(room, **kw):
    base = {"last_name": "Kouassi", "first_names": "Aya", "sex": "F", "enrollment": {"classroom_id": room["id"]},
            "contacts": [{"name": "Kouassi Paul", "relation": "pere", "phone": "07 01 02 03 04", "financial_responsible": True, "whatsapp_optin": True}]}
    base.update(kw)
    return base


async def test_requires_staff_token(client, school):
    assert (await client.get("/v1/me")).status_code == 401
    parent = {"Authorization": f"Bearer {make_token(uuid.uuid4(), 'parent', app_name='parent')}"}
    assert (await client.get("/v1/me", headers=parent)).status_code == 403
    stranger = {"Authorization": f"Bearer {make_token(uuid.uuid4(), 'director')}"}  # valid token, not a staff member of any school
    assert (await client.get("/v1/me", headers=stranger)).json()["detail"] == "not_staff"
    forced = {"Authorization": f"Bearer {make_token(school['director_uid'], 'director', mcp=True)}"}
    assert (await client.get("/v1/me", headers=forced)).json()["detail"] == "password_change_required"
    # role in token must match the role held here
    wrong = {"Authorization": f"Bearer {make_token(school['director_uid'], 'accountant')}"}
    assert (await client.get("/v1/me", headers=wrong)).status_code == 403
    me = (await client.get("/v1/me", headers=school["director"])).json()
    assert me["staff"]["role"] == "director" and me["current_year"]["label"] == "2026-2027" and "6e" in me["catalog"]["levels"]["college"]


async def test_enrol_student_and_account(client, school):
    room = await setup_class(client, school)
    r = await client.post("/v1/students", json=student(room), headers=school["secretary"])
    assert r.status_code == 201, r.text
    s = r.json()
    assert s["internal_number"] == "ELV-2026-000001" and s["last_name"] == "KOUASSI"
    acct = (await client.get(f"/v1/enrollments/{s['enrollment_id']}/account", headers=school["accountant"])).json()["account"]
    # non-assigned: inscription 30 000 + 2 x 100 000 + COGES 5 000; cantine is optional and not taken
    assert acct["total_due"] == 235_000
    assigned = (await client.post("/v1/students", json=student(room, last_name="Yao", assigned=True, contacts=[]), headers=school["secretary"])).json()
    assert (await client.get(f"/v1/enrollments/{assigned['enrollment_id']}/account", headers=school["accountant"])).json()["account"]["total_due"] == 230_000
    opt = (await client.post("/v1/students", json=student(room, last_name="Zadi", contacts=[], enrollment={"classroom_id": room["id"], "options": ["cantine"]}), headers=school["secretary"])).json()
    assert (await client.get(f"/v1/enrollments/{opt['enrollment_id']}/account", headers=school["accountant"])).json()["account"]["total_due"] == 260_000
    bad = await client.post("/v1/students", json=student(room, last_name="X", contacts=[], enrollment={"classroom_id": room["id"], "options": ["transport"]}), headers=school["secretary"])
    assert bad.json()["detail"] == "option_not_offered"


async def test_siblings_share_a_family_and_phone_is_normalised_and_encrypted(client, school):
    room = await setup_class(client, school)
    a = (await client.post("/v1/students", json=student(room), headers=school["secretary"])).json()
    b = (await client.post("/v1/students", json=student(room, first_names="Koffi", family_id=a["family_id"], contacts=[]), headers=school["secretary"])).json()
    assert a["family_id"] == b["family_id"]
    det = (await client.get(f"/v1/students/{a['id']}", headers=school["secretary"])).json()
    assert det["contacts"][0]["phone"] == "+2250701020304" and det["contacts"][0]["phone_masked"] != det["contacts"][0]["phone"] and [x["id"] for x in det["siblings"]] == [b["id"]]
    from sqlalchemy import text
    from app.db import engine
    async with engine.connect() as c:
        raw = (await c.execute(text("select phone_enc from contact limit 1"))).scalar()
    assert b"0701020304" not in bytes(raw)
    bad = await client.post("/v1/students", json=student(room, contacts=[{"name": "Bad Phone", "phone": "12345"}]), headers=school["secretary"])
    assert bad.json()["detail"] == "phone_invalid"


async def test_matricule_unique_per_school(client, school):
    room = await setup_class(client, school)
    assert (await client.post("/v1/students", json=student(room, matricule_mena="20123456a"), headers=school["secretary"])).status_code == 201
    dup = await client.post("/v1/students", json=student(room, last_name="Autre", matricule_mena="20123456A"), headers=school["secretary"])
    assert dup.status_code == 409 and dup.json()["detail"] == "matricule_already_used"


async def test_payment_receipt_numbers_partial_payment_and_idempotency(client, school):
    room = await setup_class(client, school)
    enr = (await client.post("/v1/students", json=student(room), headers=school["secretary"])).json()["enrollment_id"]
    h = school["accountant"]
    r1 = await client.post(f"/v1/enrollments/{enr}/payments", json={"amount": 50_000, "method": "especes"}, headers=h)
    assert r1.status_code == 201 and r1.json()["payment"]["receipt_number"] == "REC-2026-000001" and r1.json()["account"]["remaining"] == 185_000
    r2 = await client.post(f"/v1/enrollments/{enr}/payments", json={"amount": 10_000, "method": "wave", "reference": "WV123"}, headers=h)
    assert r2.json()["payment"]["receipt_number"] == "REC-2026-000002"
    # mobile money without the operator reference is refused
    assert (await client.post(f"/v1/enrollments/{enr}/payments", json={"amount": 1000, "method": "orange_money"}, headers=h)).json()["detail"] == "reference_required"
    # a retry with the same key records nothing new
    k = {"amount": 5000, "method": "especes", "idempotency_key": "retry-key-0001"}
    first = await client.post(f"/v1/enrollments/{enr}/payments", json=k, headers=h)
    again = await client.post(f"/v1/enrollments/{enr}/payments", json=k, headers=h)
    assert first.json()["payment"]["id"] == again.json()["payment"]["id"] and again.json()["account"]["remaining"] == 170_000
    assert (await client.post(f"/v1/enrollments/{enr}/payments", json={**k, "amount": 6000}, headers=h)).status_code == 409
    # the secretary cannot take money
    assert (await client.post(f"/v1/enrollments/{enr}/payments", json={"amount": 1000, "method": "especes"}, headers=school["secretary"])).status_code == 403
    rc = (await client.get(f"/v1/payments/{r1.json()['payment']['id']}/receipt", headers=h)).json()
    assert rc["number"] == "REC-2026-000001" and rc["student"]["classroom"] == "6e 1" and rc["school"]["name"] == "Ecole A" and rc["cashier"] == "Caissier"


async def test_cancel_payment_creates_credit_note_and_needs_fresh_password(client, school):
    room = await setup_class(client, school)
    enr = (await client.post("/v1/students", json=student(room), headers=school["secretary"])).json()["enrollment_id"]
    pay = (await client.post(f"/v1/enrollments/{enr}/payments", json={"amount": 30_000, "method": "especes"}, headers=school["accountant"])).json()["payment"]
    stale = {"Authorization": f"Bearer {make_token(await _uid(school['accountant']), 'accountant', auth_time=__import__('time').time() - 3600)}"}
    r = await client.post(f"/v1/payments/{pay['id']}/cancel", json={"reason": "Erreur de saisie"}, headers=stale)
    assert r.status_code == 403 and r.json()["detail"] == "step_up_required"
    fresh = school["accountant"]
    pytest.auth_calls["session_alive"] = False
    assert (await client.post(f"/v1/payments/{pay['id']}/cancel", json={"reason": "Erreur de saisie"}, headers=fresh)).json()["detail"] == "session_ended"
    pytest.auth_calls["session_alive"] = True
    ok = await client.post(f"/v1/payments/{pay['id']}/cancel", json={"reason": "Erreur de saisie"}, headers=fresh)
    assert ok.status_code == 201 and ok.json()["credit_note"]["amount"] == -30_000 and ok.json()["credit_note"]["receipt_number"] == "AV-2026-000001"
    assert ok.json()["account"]["credited"] == 0
    assert (await client.post(f"/v1/payments/{pay['id']}/cancel", json={"reason": "Encore"}, headers=fresh)).json()["detail"] == "already_cancelled"
    hist = (await client.get(f"/v1/enrollments/{enr}/account", headers=fresh)).json()["payments"]
    assert [(p["kind"], p["cancelled"]) for p in hist] == [("credit_note", False), ("payment", True)]  # nothing deleted


async def _uid(headers) -> uuid.UUID:
    import jwt

    return uuid.UUID(jwt.decode(headers["Authorization"][7:], options={"verify_signature": False})["sub"])


async def test_discount_director_only_capped_and_credited(client, school):
    room = await setup_class(client, school)
    enr = (await client.post("/v1/students", json=student(room), headers=school["secretary"])).json()["enrollment_id"]
    body = {"kind": "fratrie", "amount": 20_000, "reason": "Deuxième enfant"}
    assert (await client.post(f"/v1/enrollments/{enr}/discounts", json=body, headers=school["accountant"])).status_code == 403
    ok = await client.post(f"/v1/enrollments/{enr}/discounts", json=body, headers=school["director"])
    assert ok.status_code == 201 and ok.json()["account"]["remaining"] == 215_000
    too_much = await client.post(f"/v1/enrollments/{enr}/discounts", json={**body, "amount": 300_000}, headers=school["director"])
    assert too_much.json()["detail"] == "discount_exceeds_total"


async def test_arrears_grouped_by_family_and_dashboard(client, school):
    room = await setup_class(client, school)
    a = (await client.post("/v1/students", json=student(room), headers=school["secretary"])).json()
    await client.post("/v1/students", json=student(room, first_names="Koffi", family_id=a["family_id"], contacts=[]), headers=school["secretary"])
    other = (await client.post("/v1/students", json=student(room, last_name="Bamba", first_names="Ali", sex="M", contacts=[{"name": "Bamba Issa", "phone": "0505050505"}]), headers=school["secretary"])).json()
    # Bamba pays everything that is late (30 000 + 100 000 + 5 000)
    await client.post(f"/v1/enrollments/{other['enrollment_id']}/payments", json={"amount": 135_000, "method": "especes"}, headers=school["accountant"])
    rows = (await client.get(f"/v1/arrears?year_id={school['year_id']}", headers=school["accountant"])).json()
    assert len(rows) == 1  # one family, not two children, and Bamba is not late any more
    fam = rows[0]
    assert fam["family_name"] == "KOUASSI" and len(fam["children"]) == 2 and fam["overdue_total"] == 2 * 135_000
    assert fam["contact"]["phone"] == "+2250701020304" and fam["oldest_late_days"] >= 10
    dash = (await client.get(f"/v1/dashboard?year_id={school['year_id']}", headers=school["director"])).json()
    assert dash["collected_today"] == 135_000 and dash["collected_year"] == 135_000 and dash["students"] == 3 and dash["overdue_total"] == 270_000
    assert (await client.get(f"/v1/arrears?year_id={school['year_id']}", headers=school["secretary"])).status_code == 403


async def test_fee_schedule_locked_once_money_is_collected(client, school):
    room = await setup_class(client, school)
    enr = (await client.post("/v1/students", json=student(room), headers=school["secretary"])).json()["enrollment_id"]
    await client.post(f"/v1/enrollments/{enr}/payments", json={"amount": 1000, "method": "especes"}, headers=school["accountant"])
    r = await client.put("/v1/fees", headers=school["director"], json={"year_id": school["year_id"], "level": "6e", "lines": []})
    assert r.status_code == 409 and r.json()["detail"] == "fees_locked_by_payments"
    assert (await client.put("/v1/fees", headers=school["accountant"], json={"year_id": school["year_id"], "level": "5e", "lines": []})).status_code == 403


async def test_schools_are_isolated(client, school):
    room = await setup_class(client, school)
    s = (await client.post("/v1/students", json=student(room), headers=school["secretary"])).json()
    sid2, y2 = await make_school("Ecole B")
    other, _ = await make_staff(sid2, "director", "Autre directrice")
    assert (await client.get(f"/v1/students/{s['id']}", headers=other)).status_code == 404
    assert (await client.get(f"/v1/enrollments/{s['enrollment_id']}/account", headers=other)).status_code == 404
    assert (await client.post(f"/v1/enrollments/{s['enrollment_id']}/payments", json={"amount": 100, "method": "especes"}, headers=other)).status_code == 404
    assert (await client.get(f"/v1/students?year_id={school['year_id']}", headers=other)).json() == []
    assert (await client.get(f"/v1/arrears?year_id={school['year_id']}", headers=other)).json() == []
    assert (await client.post("/v1/students", json=student(room), headers=other)).status_code == 404  # classroom of another school


async def test_director_enrols_and_removes_staff(client, school):
    d = school["director"]
    r = await client.post("/v1/staff", json={"display_name": "Marie Caisse", "phone": "0707070707", "role": "accountant"}, headers=d)
    assert r.status_code == 201 and pytest.auth_calls["enrolled"] == [("+2250707070707", "Marie Caisse", "accountant")]
    assert (await client.post("/v1/staff", json={"display_name": "X Y", "phone": "0707070707", "role": "director"}, headers=d)).status_code == 422
    assert (await client.post("/v1/staff", json={"display_name": "Marie Caisse", "phone": "0707070707", "role": "accountant"}, headers=school["accountant"])).status_code == 403
    sid = r.json()["id"]
    assert (await client.delete(f"/v1/staff/{sid}", headers=d)).status_code == 200 and len(pytest.auth_calls["removed"]) == 1
    listing = (await client.get("/v1/staff", headers=d)).json()
    assert [x["active"] for x in listing if x["id"] == sid] == [False]
    assert (await client.delete(f"/v1/staff/{school_director_id(listing)}", headers=d)).json()["detail"] == "cannot_remove_director"


def school_director_id(listing):
    return next(x["id"] for x in listing if x["role"] == "director")


async def test_deactivated_staff_is_refused_even_with_a_valid_token(client, school):
    r = await client.post("/v1/staff", json={"display_name": "Marie Caisse", "phone": "0707070707", "role": "secretary"}, headers=school["director"])
    from sqlalchemy import select
    from app.db import SessionLocal
    from app.models import StaffMember

    async with SessionLocal() as db:
        s = await db.get(StaffMember, r.json()["id"])
        tok = {"Authorization": f"Bearer {make_token(s.auth_user_id, 'secretary')}"}
    assert (await client.get("/v1/me", headers=tok)).status_code == 200
    await client.delete(f"/v1/staff/{r.json()['id']}", headers=school["director"])
    assert (await client.get("/v1/me", headers=tok)).status_code == 403


async def test_health(client):
    assert (await client.get("/healthz")).status_code == 200
    assert (await client.get("/readyz")).json()["checks"]["db"] == "ok"
