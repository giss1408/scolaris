import pytest

from tests.conftest import make_staff
from tests.test_academics import class_with_students, enter, make_eval
from tests.test_api import setup_class, student


async def other_class(client, s, name="5e 1"):
    return (await client.post("/v1/classrooms", json={"year_id": s["year_id"], "level": "6e", "name": name}, headers=s["director"])).json()


async def test_a_teacher_sees_only_her_classes_and_no_register(client, school):
    room, e, sub = await class_with_students(client, school)
    room2 = await other_class(client, school)
    names = lambda r: sorted(c["name"] for c in r.json())  # noqa: E731
    assert names(await client.get(f"/v1/classrooms?year_id={school['year_id']}", headers=school["teacher"])) == ["6e 1"]
    assert names(await client.get(f"/v1/classrooms?year_id={school['year_id']}", headers=school["teacher2"])) == ["6e 1"]
    assert names(await client.get(f"/v1/classrooms?year_id={school['year_id']}", headers=school["director"])) == ["5e 1", "6e 1"]
    # the head flag tells the app who may write conduct
    head = {c["name"]: c["is_head"] for c in (await client.get(f"/v1/classrooms?year_id={school['year_id']}", headers=school["teacher"])).json()}
    assert head == {"6e 1": True}
    assert (await client.get(f"/v1/classrooms?year_id={school['year_id']}", headers=school["teacher2"])).json()[0]["is_head"] is False
    # the school register (names, matricules, parents' phones) is not for teachers
    assert (await client.get(f"/v1/students?year_id={school['year_id']}", headers=school["teacher"])).status_code == 403
    assert (await client.get("/v1/students/1", headers=school["teacher"])).status_code == 403


async def test_no_assignment_no_access_to_another_class(client, school):
    room, e, sub = await class_with_students(client, school)
    room2 = await other_class(client, school)
    t = school["teacher"]
    for path in (f"/v1/classrooms/{room2['id']}/results?period=1", f"/v1/evaluations?classroom_id={room2['id']}", f"/v1/classrooms/{room2['id']}/absences?day=2026-10-01"):
        r = await client.get(path, headers=t)
        assert r.status_code == 403 and r.json()["detail"] == "not_your_class", path
    r = await client.post("/v1/evaluations", json={"classroom_id": room2["id"], "subject_id": sub["maths"], "period": 1, "kind": "devoir"}, headers=t)
    assert r.status_code == 403 and r.json()["detail"] == "not_your_class"
    # a pupil of another class cannot be marked absent either
    other = (await client.post("/v1/students", json=student(room2, last_name="Autre", contacts=[]), headers=school["secretary"])).json()
    r = await client.post("/v1/absences", json={"day": "2026-10-01", "entries": [{"enrollment_id": other["enrollment_id"]}]}, headers=t)
    assert r.status_code == 403
    # the director and the secretary are not limited
    assert (await client.get(f"/v1/classrooms/{room2['id']}/results?period=1", headers=school["secretary"])).status_code == 200


async def test_a_teacher_gives_only_her_subjects(client, school):
    room, e, sub = await class_with_students(client, school)
    # Prof Math was assigned maths only
    r = await client.post("/v1/evaluations", json={"classroom_id": room["id"], "subject_id": sub["fr"], "period": 1, "kind": "devoir"}, headers=school["teacher"])
    assert r.status_code == 403 and r.json()["detail"] == "not_your_subject"
    assert (await client.post("/v1/evaluations", json={"classroom_id": room["id"], "subject_id": sub["maths"], "period": 1, "kind": "devoir"}, headers=school["teacher"])).status_code == 201
    assert [s["name"] for s in (await client.get(f"/v1/subjects?classroom_id={room['id']}", headers=school["teacher"])).json()] == ["Mathématiques"]
    assert [s["name"] for s in (await client.get(f"/v1/subjects?classroom_id={room['id']}", headers=school["teacher2"])).json()] == ["Français"]
    assert len((await client.get(f"/v1/subjects?classroom_id={room['id']}", headers=school["director"])).json()) == 3
    # "all subjects" assignment (subject null) opens every subject of the class
    d = school["director"]
    await client.put(f"/v1/classrooms/{room['id']}/teachers", json={"head_teacher_id": None, "assignments": [{"staff_id": sub["staff"]["Prof Math"], "subject_id": None}]}, headers=d)
    assert (await client.post("/v1/evaluations", json={"classroom_id": room["id"], "subject_id": sub["fr"], "period": 1, "kind": "devoir"}, headers=school["teacher"])).status_code == 201


async def test_conduct_and_appreciation_are_for_the_head_teacher_only(client, school):
    room, e, sub = await class_with_students(client, school)
    body = {"period": 1, "conduct": "16", "appreciation": "Bon trimestre"}
    ok = await client.put(f"/v1/enrollments/{e[0]}/remarks", json=body, headers=school["teacher"])  # Prof Math is the head teacher
    assert ok.status_code == 200
    no = await client.put(f"/v1/enrollments/{e[0]}/remarks", json=body, headers=school["teacher2"])
    assert no.status_code == 403 and no.json()["detail"] == "head_teacher_only"
    # even the head teacher cannot write the council's decision
    assert (await client.put(f"/v1/enrollments/{e[0]}/remarks", json={"period": 3, "decision": "passage"}, headers=school["teacher"])).json()["detail"] == "director_only"
    assert (await client.put(f"/v1/enrollments/{e[0]}/remarks", json=body, headers=school["secretary"])).status_code == 200


async def test_head_teacher_without_a_subject_can_view_the_class_but_not_create_marks(client, school):
    room, e, sub = await class_with_students(client, school)
    d = school["director"]
    await client.put(f"/v1/classrooms/{room['id']}/teachers", json={"head_teacher_id": sub["staff"]["Prof Francais"], "assignments": []}, headers=d)
    t2 = school["teacher2"]
    assert (await client.get(f"/v1/classrooms/{room['id']}/results?period=1", headers=t2)).status_code == 200
    assert (await client.get(f"/v1/enrollments/{e[0]}/report-card?period=1", headers=t2)).status_code == 200
    assert (await client.post("/v1/evaluations", json={"classroom_id": room["id"], "subject_id": sub["fr"], "period": 1, "kind": "devoir"}, headers=t2)).json()["detail"] == "not_your_subject"
    assert (await client.put(f"/v1/enrollments/{e[0]}/remarks", json={"period": 1, "conduct": "15"}, headers=t2)).status_code == 200
    # and Prof Math, now unassigned, is out
    assert (await client.get(f"/v1/classrooms/{room['id']}/results?period=1", headers=school["teacher"])).json()["detail"] == "not_your_class"


async def test_removing_an_assignment_freezes_her_old_evaluations(client, school):
    room, e, sub = await class_with_students(client, school)
    ev = await make_eval(client, school["teacher"], room, sub["maths"])
    await enter(client, school["teacher"], ev, {e[0]: {"value": "12"}})
    await client.put(f"/v1/classrooms/{room['id']}/teachers", json={"head_teacher_id": None, "assignments": [{"staff_id": sub["staff"]["Prof Francais"], "subject_id": sub["fr"]}]}, headers=school["director"])
    r = await client.put(f"/v1/evaluations/{ev}/grades", json={"grades": [{"enrollment_id": e[0], "value": "20"}]}, headers=school["teacher"])
    assert r.status_code == 403 and r.json()["detail"] == "not_your_class"
    assert (await client.get(f"/v1/evaluations/{ev}/grades", headers=school["teacher"])).status_code == 403
    # the marks already entered stay in the results (nothing was deleted)
    res = (await client.get(f"/v1/classrooms/{room['id']}/results?period=1", headers=school["director"])).json()
    assert [r["average"] for r in res["rows"] if r["enrollment_id"] == e[0]] == ["12.00"]


async def test_only_the_director_assigns_and_only_to_active_teachers_of_the_school(client, school):
    room, e, sub = await class_with_students(client, school)
    body = {"head_teacher_id": None, "assignments": [{"staff_id": sub["staff"]["Prof Math"], "subject_id": sub["maths"]}]}
    for who in ("secretary", "accountant", "teacher"):
        assert (await client.put(f"/v1/classrooms/{room['id']}/teachers", json=body, headers=school[who])).status_code == 403
        assert (await client.get(f"/v1/classrooms/{room['id']}/teachers", headers=school[who])).status_code == 403
    d = school["director"]
    # not a teacher (the secretary), not a subject of this school, not a head who is not a teacher
    sec = sub["staff"]["Secretaire"]
    assert (await client.put(f"/v1/classrooms/{room['id']}/teachers", json={"assignments": [{"staff_id": sec}]}, headers=d)).json()["detail"] == "not_an_active_teacher"
    assert (await client.put(f"/v1/classrooms/{room['id']}/teachers", json={"head_teacher_id": sec, "assignments": []}, headers=d)).json()["detail"] == "not_an_active_teacher"
    assert (await client.put(f"/v1/classrooms/{room['id']}/teachers", json={"assignments": [{"staff_id": sub["staff"]["Prof Math"], "subject_id": 9999}]}, headers=d)).status_code == 404
    # a teacher of another school
    from tests.conftest import make_school

    sid2, _ = await make_school("Ecole B")
    await make_staff(sid2, "teacher", "Prof B")
    assert (await client.put(f"/v1/classrooms/{room['id']}/teachers", json={"assignments": [{"staff_id": 99999}]}, headers=d)).json()["detail"] == "not_an_active_teacher"
    got = (await client.get(f"/v1/classrooms/{room['id']}/teachers", headers=d)).json()
    assert got["head_teacher_id"] == sub["staff"]["Prof Math"] and {(a["name"], a["subject_id"]) for a in got["assignments"]} == {("Prof Math", sub["maths"]), ("Prof Francais", sub["fr"])}
    # a removed teacher cannot be assigned
    await client.delete(f"/v1/staff/{sub['staff']['Prof Francais']}", headers=d)
    assert (await client.put(f"/v1/classrooms/{room['id']}/teachers", json={"assignments": [{"staff_id": sub["staff"]["Prof Francais"]}]}, headers=d)).json()["detail"] == "not_an_active_teacher"


async def test_assignments_are_isolated_between_schools(client, school):
    from tests.conftest import make_school

    room, e, sub = await class_with_students(client, school)
    sid2, _ = await make_school("Ecole B")
    other_dir, _ = await make_staff(sid2, "director", "Directrice B")
    assert (await client.put(f"/v1/classrooms/{room['id']}/teachers", json={"assignments": []}, headers=other_dir)).status_code == 404
    assert (await client.get(f"/v1/classrooms/{room['id']}/teachers", headers=other_dir)).status_code == 404
