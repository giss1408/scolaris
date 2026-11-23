import uuid
from datetime import date, timedelta

from tests.conftest import make_school, make_staff, make_token
from tests.test_academics import class_with_students, enter, make_eval
from tests.test_api import student


def parent_headers(phone_e164: str) -> dict:
    tok = make_token(uuid.uuid4(), "parent", app_name="parent")
    import jwt

    claims = jwt.decode(tok, options={"verify_signature": False})
    claims["ph"] = f"tel:{phone_e164}"
    from tests.conftest import _PEM

    return {"Authorization": "Bearer " + jwt.encode(claims, _PEM, algorithm="EdDSA", headers={"kid": "k1"})}


async def test_a_parent_sees_only_her_own_children_by_phone(client, school):
    room, enrs, sub = await class_with_students(client, school, names=("Aya", "Koffi"))
    # students from class_with_students have no contacts: give Aya's family a parent
    one = (await client.post("/v1/students", json=student(room, last_name="Traore", first_names="Fanta"), headers=school["secretary"])).json()
    mine = parent_headers("+2250701020304")  # the phone of the contact created by `student()`
    kids = (await client.get("/v1/parent/children", headers=mine)).json()
    assert [k["name"] for k in kids] == ["Fanta TRAORE"] and kids[0]["school"] == "Ecole A" and kids[0]["classroom"] == "6e 1"
    assert kids[0]["balance"]["total_due"] == 235000 and kids[0]["balance"]["remaining"] == 235000
    stranger = parent_headers("+2250909090909")
    assert (await client.get("/v1/parent/children", headers=stranger)).json() == []
    # another family's child: 404, never revealed
    for path in (f"/v1/parent/children/{enrs[0]}/report-card?period=1", f"/v1/parent/children/{enrs[0]}/payments", f"/v1/parent/children/{enrs[0]}/absences"):
        assert (await client.get(path, headers=mine)).status_code == 404, path
    assert (await client.get(f"/v1/parent/children/{one['enrollment_id']}/payments", headers=stranger)).status_code == 404


async def test_parent_sees_payments_report_card_without_class_figures_and_absences(client, school):
    room, enrs, sub = await class_with_students(client, school, names=("Aya",))
    one = (await client.post("/v1/students", json=student(room, last_name="Traore", first_names="Fanta"), headers=school["secretary"])).json()
    ev = await make_eval(client, school["director"], room, sub["maths"])
    await enter(client, school["director"], ev, {one["enrollment_id"]: {"value": "15"}})
    await client.post(f"/v1/enrollments/{one['enrollment_id']}/payments", json={"amount": 30000, "method": "especes"}, headers=school["accountant"])
    await client.post("/v1/absences", json={"day": date.today().isoformat(), "entries": [{"enrollment_id": one["enrollment_id"]}]}, headers=school["secretary"])
    me = parent_headers("+2250701020304")
    pays = (await client.get(f"/v1/parent/children/{one['enrollment_id']}/payments", headers=me)).json()
    assert [(p["amount"], p["receipt_number"]) for p in pays] == [(30000, "REC-2026-000001")]
    card = (await client.get(f"/v1/parent/children/{one['enrollment_id']}/report-card?period=1", headers=me)).json()
    assert card["average"] == "15.00" and "class_average" not in card and "highest" not in card and all("class_average" not in l for l in card["lines"])
    ab = (await client.get(f"/v1/parent/children/{one['enrollment_id']}/absences", headers=me)).json()
    assert len(ab) == 1 and ab[0]["justified"] is False


async def test_parent_endpoints_refuse_staff_tokens_and_staff_endpoints_refuse_parents(client, school):
    assert (await client.get("/v1/parent/children", headers=school["director"])).status_code == 403  # a staff token is not a parent
    me = parent_headers("+2250701020304")
    assert (await client.get("/v1/me", headers=me)).status_code == 403
    assert (await client.get("/v1/students?year_id=1", headers=me)).status_code == 403
    assert (await client.get("/v1/parent/children")).status_code == 401


async def test_a_parent_with_children_in_two_schools_sees_both(client, school):
    room, enrs, sub = await class_with_students(client, school, names=("Aya",))
    await client.post("/v1/students", json=student(room, last_name="Traore", first_names="Fanta"), headers=school["secretary"])
    # a second school that also recorded the same parent number
    from tests.test_api import setup_class

    sid2, y2 = await make_school("Ecole B")
    d2, _ = await make_staff(sid2, "director", "Directeur B")
    s2 = {"id": sid2, "year_id": y2, "director": d2, "secretary": d2}
    room2 = await setup_class(client, s2)
    await client.post("/v1/students", json=student(room2, last_name="Traore", first_names="Moussa"), headers=d2)
    kids = (await client.get("/v1/parent/children", headers=parent_headers("+2250701020304"))).json()
    assert sorted((k["school"], k["name"]) for k in kids) == [("Ecole A", "Fanta TRAORE"), ("Ecole B", "Moussa TRAORE")]
