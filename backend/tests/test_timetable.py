from tests.conftest import make_school, make_staff
from tests.test_academics import class_with_students
from tests.test_api import setup_class, student
from tests.test_parent import parent_headers


def slot(sub, day=1, start="08:00", end="09:00", teacher=None, room=None):
    return {"weekday": day, "start": start, "end": end, "subject_id": sub, "teacher_id": teacher, "room": room}


async def add(client, h, room, body):
    return await client.post(f"/v1/classrooms/{room['id']}/timetable/slots", json=body, headers=h)


async def test_build_a_week_and_read_it_back_in_order(client, school):
    room, e, sub = await class_with_students(client, school)
    d, math, fr = school["director"], sub["staff"]["Prof Math"], sub["staff"]["Prof Francais"]
    r = await add(client, d, room, slot(sub["maths"], 1, "08:00", "09:00", math, "A1"))
    assert r.status_code == 201 and r.json()["subject"] == "Mathématiques" and r.json()["teacher"] == "Prof Math" and r.json()["room"] == "A1" and r.json()["start"] == "08:00"
    await add(client, d, room, slot(sub["fr"], 1, "09:00", "10:00", fr))  # back to back is allowed
    await add(client, d, room, slot(sub["maths"], 3, "10:15", "12:15", math))
    await add(client, d, room, slot(sub["sport"], 1, "07:00", "08:00"))  # no teacher yet
    got = (await client.get(f"/v1/classrooms/{room['id']}/timetable", headers=d)).json()
    assert [(s["weekday"], s["start"]) for s in got["slots"]] == [(1, "07:00"), (1, "08:00"), (1, "09:00"), (3, "10:15")]
    assert got["editable"] is True and {t["name"]: t["subject_ids"] for t in got["teachers"]} == {"Prof Math": [sub["maths"]], "Prof Francais": [sub["fr"]]}


async def test_input_is_validated(client, school):
    room, e, sub = await class_with_students(client, school)
    d, math = school["director"], sub["staff"]["Prof Math"]
    bad = await add(client, d, room, slot(sub["maths"], 1, "10:00", "09:00"))
    assert bad.status_code == 400 and bad.json()["detail"] == "end_before_start"
    assert (await add(client, d, room, slot(sub["maths"], 1, "09:00", "09:00"))).status_code == 400
    assert (await add(client, d, room, slot(sub["maths"], 7))).status_code == 422  # no Sunday
    assert (await add(client, d, room, slot(sub["maths"], 0))).status_code == 422
    assert (await add(client, d, room, slot(9999))).status_code == 404
    # a teacher must be assigned to this class AND this subject
    r = await add(client, d, room, slot(sub["fr"], teacher=math))
    assert r.status_code == 400 and r.json()["detail"] == "teacher_not_assigned"
    assert (await add(client, d, room, slot(sub["maths"], teacher=sub["staff"]["Secretaire"]))).json()["detail"] == "teacher_not_assigned"
    # "all subjects" assignment opens every subject for that teacher
    await client.put(f"/v1/classrooms/{room['id']}/teachers", json={"assignments": [{"staff_id": math, "subject_id": None}]}, headers=d)
    assert (await add(client, d, room, slot(sub["fr"], teacher=math))).status_code == 201


async def test_nothing_overlaps_in_a_class_a_teacher_or_a_room(client, school):
    room, e, sub = await class_with_students(client, school)
    d, math = school["director"], sub["staff"]["Prof Math"]
    room2 = (await client.post("/v1/classrooms", json={"year_id": school["year_id"], "level": "6e", "name": "6e 2"}, headers=d)).json()
    await client.put(f"/v1/classrooms/{room2['id']}/teachers", json={"assignments": [{"staff_id": math, "subject_id": sub["maths"]}]}, headers=d)
    assert (await add(client, d, room, slot(sub["maths"], 2, "08:00", "10:00", math, "Salle 3"))).status_code == 201
    r = await add(client, d, room, slot(sub["fr"], 2, "09:00", "11:00"))  # same class, overlapping
    assert r.status_code == 409 and r.json()["detail"] == "class_overlap" and "08:00" in r.json()["message"]
    r = await add(client, d, room2, slot(sub["maths"], 2, "09:30", "10:30", math))  # same teacher, another class
    assert r.status_code == 409 and r.json()["detail"] == "teacher_busy" and "6e 1" in r.json()["message"]
    r = await add(client, d, room2, slot(sub["maths"], 2, "08:30", "09:30", None, "salle 3"))  # same room (case does not matter)
    assert r.status_code == 409 and r.json()["detail"] == "room_busy"
    # another day, or just after, is fine; a free room is fine
    assert (await add(client, d, room2, slot(sub["maths"], 3, "08:00", "10:00", math, "Salle 3"))).status_code == 201
    assert (await add(client, d, room2, slot(sub["maths"], 2, "10:00", "11:00", math, "Salle 3"))).status_code == 201


async def test_who_may_read_and_who_may_write(client, school):
    room, e, sub = await class_with_students(client, school)
    room2 = (await client.post("/v1/classrooms", json={"year_id": school["year_id"], "level": "6e", "name": "6e 2"}, headers=school["director"])).json()
    s1 = await add(client, school["secretary"], room, slot(sub["maths"], 1, "08:00", "09:00"))  # the secretary builds timetables too
    assert s1.status_code == 201
    # accountant: nothing; teacher: reads her own class only, never writes
    assert (await client.get(f"/v1/classrooms/{room['id']}/timetable", headers=school["accountant"])).status_code == 403
    assert (await add(client, school["accountant"], room, slot(sub["maths"], 2))).status_code == 403
    mine = (await client.get(f"/v1/classrooms/{room['id']}/timetable", headers=school["teacher"])).json()
    assert len(mine["slots"]) == 1 and mine["editable"] is False and "teachers" not in mine
    assert (await client.get(f"/v1/classrooms/{room2['id']}/timetable", headers=school["teacher"])).json()["detail"] == "not_your_class"
    assert (await add(client, school["teacher"], room, slot(sub["maths"], 2))).status_code == 403
    assert (await client.delete(f"/v1/timetable/slots/{s1.json()['id']}", headers=school["teacher"])).status_code == 403
    assert (await client.delete(f"/v1/timetable/slots/{s1.json()['id']}", headers=school["secretary"])).status_code == 200
    assert (await client.get(f"/v1/classrooms/{room['id']}/timetable", headers=school["director"])).json()["slots"] == []


async def test_a_teachers_own_week_across_classes(client, school):
    room, e, sub = await class_with_students(client, school)
    d, math, fr = school["director"], sub["staff"]["Prof Math"], sub["staff"]["Prof Francais"]
    room2 = (await client.post("/v1/classrooms", json={"year_id": school["year_id"], "level": "6e", "name": "6e 2"}, headers=d)).json()
    await client.put(f"/v1/classrooms/{room2['id']}/teachers", json={"assignments": [{"staff_id": math, "subject_id": sub["maths"]}]}, headers=d)
    await add(client, d, room, slot(sub["maths"], 1, "08:00", "09:00", math))
    await add(client, d, room2, slot(sub["maths"], 1, "10:00", "11:00", math))
    await add(client, d, room, slot(sub["fr"], 1, "09:00", "10:00", fr))
    week = (await client.get("/v1/timetable/me", headers=school["teacher"])).json()["slots"]
    assert [(s["classroom"], s["start"]) for s in week] == [("6e 1", "08:00"), ("6e 2", "10:00")]  # hers only, in order
    assert [s["classroom"] for s in (await client.get("/v1/timetable/me", headers=school["teacher2"])).json()["slots"]] == ["6e 1"]
    assert (await client.get("/v1/timetable/me", headers=d)).json()["detail"] == "staff_id_required"
    assert len((await client.get(f"/v1/timetable/me?staff_id={math}", headers=d)).json()["slots"]) == 2
    assert (await client.get("/v1/timetable/me", headers=school["accountant"])).status_code == 403
    assert (await client.get("/v1/timetable/me?staff_id=99999", headers=d)).status_code == 404


async def test_an_unassigned_or_removed_teacher_leaves_the_period_in_place(client, school):
    room, e, sub = await class_with_students(client, school)
    d, math, fr = school["director"], sub["staff"]["Prof Math"], sub["staff"]["Prof Francais"]
    a = (await add(client, d, room, slot(sub["maths"], 1, "08:00", "09:00", math))).json()
    b = (await add(client, d, room, slot(sub["fr"], 1, "09:00", "10:00", fr))).json()
    # the director takes maths away from Prof Math: his period stays, without a teacher
    await client.put(f"/v1/classrooms/{room['id']}/teachers", json={"assignments": [{"staff_id": fr, "subject_id": sub["fr"]}]}, headers=d)
    by = {s["id"]: s for s in (await client.get(f"/v1/classrooms/{room['id']}/timetable", headers=d)).json()["slots"]}
    assert by[a["id"]]["teacher"] is None and by[a["id"]]["subject"] == "Mathématiques" and by[b["id"]]["teacher"] == "Prof Francais"
    # removing a member of staff frees her periods too
    await client.delete(f"/v1/staff/{fr}", headers=d)
    by = {s["id"]: s for s in (await client.get(f"/v1/classrooms/{room['id']}/timetable", headers=d)).json()["slots"]}
    assert by[b["id"]]["teacher"] is None
    assert (await client.get("/v1/timetable/me", headers=school["teacher2"])).status_code == 403  # removed: no longer a valid staff token


async def test_parent_sees_her_childs_class_timetable_only(client, school):
    room, e, sub = await class_with_students(client, school, names=("Aya",))
    d = school["director"]
    one = (await client.post("/v1/students", json=student(room, last_name="Traore", first_names="Fanta"), headers=school["secretary"])).json()
    await add(client, d, room, slot(sub["maths"], 2, "08:00", "09:00", sub["staff"]["Prof Math"], "A1"))
    me = parent_headers("+2250701020304")
    week = (await client.get(f"/v1/parent/children/{one['enrollment_id']}/timetable", headers=me)).json()["slots"]
    assert [(s["weekday"], s["subject"], s["teacher"], s["room"]) for s in week] == [(2, "Mathématiques", "Prof Math", "A1")]
    assert (await client.get(f"/v1/parent/children/{one['enrollment_id']}/timetable", headers=parent_headers("+2250909090909"))).status_code == 404
    assert (await client.get(f"/v1/parent/children/{e[0]}/timetable", headers=me)).status_code == 404  # a child of another family


async def test_timetables_are_isolated_between_schools(client, school):
    room, e, sub = await class_with_students(client, school)
    s1 = (await add(client, school["director"], room, slot(sub["maths"], 1, "08:00", "09:00"))).json()
    sid2, y2 = await make_school("Ecole B")
    other, _ = await make_staff(sid2, "director", "Directrice B")
    assert (await client.get(f"/v1/classrooms/{room['id']}/timetable", headers=other)).status_code == 404
    assert (await add(client, other, room, slot(sub["maths"], 2))).status_code == 404
    assert (await client.delete(f"/v1/timetable/slots/{s1['id']}", headers=other)).status_code == 404
    # the same hours in another school are no clash
    s2 = {"id": sid2, "year_id": y2, "director": other, "secretary": other}
    room_b = await setup_class(client, s2)
    subj_b = (await client.post("/v1/subjects", json={"name": "Maths"}, headers=other)).json()["id"]
    assert (await add(client, other, room_b, slot(subj_b, 1, "08:00", "09:00", None, "A1"))).status_code == 201
