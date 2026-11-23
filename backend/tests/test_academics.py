from datetime import date

from tests.test_api import setup_class, student


async def class_with_students(client, s, names=("Aya", "Koffi", "Mariam", "Yao")):
    room = await setup_class(client, s)
    ids = []
    for n in names:
        r = (await client.post("/v1/students", json=student(room, first_names=n, last_name=n.upper(), contacts=[]), headers=s["secretary"])).json()
        ids.append(r["enrollment_id"])
    d = s["director"]
    maths = (await client.post("/v1/subjects", json={"name": "Mathématiques"}, headers=d)).json()["id"]
    fr = (await client.post("/v1/subjects", json={"name": "Français"}, headers=d)).json()["id"]
    sport = (await client.post("/v1/subjects", json={"name": "EPS"}, headers=d)).json()["id"]
    await client.put("/v1/coefficients", json={"year_id": s["year_id"], "level": "6e", "lines": [{"subject_id": maths, "coef": 3}, {"subject_id": fr, "coef": 2}, {"subject_id": sport, "coef": 0}]}, headers=d)
    # Prof Math gives maths (and is the head teacher), Prof Francais gives French: nobody teaches a class she was not assigned
    staff = {x["name"]: x["id"] for x in (await client.get("/v1/staff", headers=d)).json()}
    r = await client.put(f"/v1/classrooms/{room['id']}/teachers", json={"head_teacher_id": staff["Prof Math"], "assignments": [
        {"staff_id": staff["Prof Math"], "subject_id": maths}, {"staff_id": staff["Prof Francais"], "subject_id": fr}]}, headers=d)
    assert r.status_code == 200, r.text
    return room, ids, {"maths": maths, "fr": fr, "sport": sport, "staff": staff}


async def make_eval(client, headers, room, subject, period=1, kind="devoir", max_score=20):
    r = await client.post("/v1/evaluations", json={"classroom_id": room["id"], "subject_id": subject, "period": period, "kind": kind, "max_score": max_score}, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["id"]


async def enter(client, headers, ev, values):
    r = await client.put(f"/v1/evaluations/{ev}/grades", json={"grades": [{"enrollment_id": e, **v} for e, v in values.items()]}, headers=headers)
    assert r.status_code == 200, r.text


async def test_results_rank_ties_honours_and_unentered_subjects(client, school):
    room, e, sub = await class_with_students(client, school)
    t = school["teacher"]
    m1 = await make_eval(client, t, room, sub["maths"])
    f1 = await make_eval(client, school["teacher2"], room, sub["fr"])
    await enter(client, t, m1, {e[0]: {"value": "18"}, e[1]: {"value": "12"}, e[2]: {"value": "12"}, e[3]: {"absent": True}})
    await enter(client, school["teacher2"], f1, {e[0]: {"value": "14"}, e[1]: {"value": "12"}, e[2]: {"value": "12"}, e[3]: {"value": "9"}})
    res = (await client.get(f"/v1/classrooms/{room['id']}/results?period=1", headers=school["secretary"])).json()
    rows = {r["enrollment_id"]: r for r in res["rows"]}
    assert rows[e[0]]["average"] == "16.40"  # (18*3 + 14*2) / 5
    assert rows[e[0]]["honour"] == "felicitations" and rows[e[0]]["rank"] == {"position": 1, "tie": False, "of": 4}
    assert rows[e[1]]["average"] == rows[e[2]]["average"] == "12.00"
    assert rows[e[1]]["rank"]["position"] == 2 and rows[e[1]]["rank"]["tie"] and rows[e[2]]["rank"]["tie"]
    assert rows[e[1]]["honour"] == "tableau_honneur"
    # absent in maths: only French counts for him (9/20), he is ranked 4th, not 3rd
    assert rows[e[3]]["average"] == "9.00" and rows[e[3]]["rank"]["position"] == 4 and rows[e[3]]["passes"] is False
    assert res["highest"] == "16.40" and res["lowest"] == "9.00"
    # EPS has coefficient 0: listed, never counted
    assert [s["coef"] for s in res["subjects"] if s["name"] == "EPS"] == [0]


async def test_grades_out_of_10_are_normalised_and_bounded(client, school):
    room, e, sub = await class_with_students(client, school)
    ev = await make_eval(client, school["director"], room, sub["maths"], max_score=10)
    bad = await client.put(f"/v1/evaluations/{ev}/grades", json={"grades": [{"enrollment_id": e[0], "value": "11"}]}, headers=school["director"])
    assert bad.status_code == 400 and bad.json()["detail"] == "grade_above_max"
    await enter(client, school["director"], ev, {e[0]: {"value": "8"}})
    row = [r for r in (await client.get(f"/v1/classrooms/{room['id']}/results?period=1", headers=school["director"])).json()["rows"] if r["enrollment_id"] == e[0]][0]
    assert row["average"] == "16.00"


async def test_teacher_edits_only_her_evaluations_and_locking_freezes_marks(client, school):
    room, e, sub = await class_with_students(client, school)
    ev = await make_eval(client, school["teacher"], room, sub["maths"])
    assert (await client.put(f"/v1/evaluations/{ev}/grades", json={"grades": [{"enrollment_id": e[0], "value": "10"}]}, headers=school["teacher2"])).json()["detail"] == "not_your_evaluation"
    await enter(client, school["teacher"], ev, {e[0]: {"value": "10"}})
    assert (await client.post(f"/v1/evaluations/{ev}/lock", headers=school["teacher"])).status_code == 403  # validation is the direction's
    assert (await client.post(f"/v1/evaluations/{ev}/lock", headers=school["director"])).json()["locked"] is True
    locked = await client.put(f"/v1/evaluations/{ev}/grades", json={"grades": [{"enrollment_id": e[0], "value": "15"}]}, headers=school["teacher"])
    assert locked.status_code == 409 and locked.json()["detail"] == "evaluation_locked"
    assert (await client.post(f"/v1/evaluations/{ev}/unlock", headers=school["director"])).json()["locked"] is False
    await enter(client, school["teacher"], ev, {e[0]: {"value": "15"}})
    got = (await client.get(f"/v1/evaluations/{ev}/grades", headers=school["teacher"])).json()
    assert [r["value"] for r in got["rows"] if r["enrollment_id"] == e[0]] == ["15.00"]
    # blank removes the mark
    await enter(client, school["teacher"], ev, {e[0]: {}})
    assert [r["value"] for r in (await client.get(f"/v1/evaluations/{ev}/grades", headers=school["teacher"])).json()["rows"] if r["enrollment_id"] == e[0]] == [None]


async def test_money_is_closed_to_teachers_and_academics_to_accountants(client, school):
    room, e, sub = await class_with_students(client, school)
    for who in ("teacher", "secretary"):
        assert (await client.get(f"/v1/enrollments/{e[0]}/account", headers=school[who])).status_code == 403
        assert (await client.get("/v1/payments/1/receipt", headers=school[who])).status_code == 403
    assert (await client.post(f"/v1/enrollments/{e[0]}/payments", json={"amount": 1000, "method": "especes"}, headers=school["teacher"])).status_code == 403
    assert (await client.get(f"/v1/arrears?year_id={school['year_id']}", headers=school["teacher"])).status_code == 403
    assert (await client.get(f"/v1/classrooms/{room['id']}/results?period=1", headers=school["accountant"])).status_code == 403
    assert (await client.post("/v1/subjects", json={"name": "Dessin"}, headers=school["secretary"])).status_code == 403


async def test_report_card_annual_average_conduct_absences_and_director_only_decision(client, school):
    room, e, sub = await class_with_students(client, school)
    for period, mark in ((1, "10"), (2, "14"), (3, None)):
        if mark:
            ev = await make_eval(client, school["director"], room, sub["maths"], period=period)
            await enter(client, school["director"], ev, {e[0]: {"value": mark}})
    card = (await client.get(f"/v1/enrollments/{e[0]}/report-card?period=0", headers=school["director"])).json()
    assert card["average"] == "12.00" and card["rank"]["position"] == 1 and card["honour"] == "tableau_honneur"
    assert [l["subject"] for l in card["lines"]] == ["Français", "Mathématiques"]  # EPS (coef 0, no marks) is left off; French has a coefficient but no mark yet
    ok = await client.put(f"/v1/enrollments/{e[0]}/remarks", json={"period": 1, "conduct": "17.5", "appreciation": "Élève sérieuse"}, headers=school["teacher"])
    assert ok.status_code == 200
    assert (await client.put(f"/v1/enrollments/{e[0]}/remarks", json={"period": 3, "decision": "passage"}, headers=school["teacher"])).json()["detail"] == "director_only"
    assert (await client.put(f"/v1/enrollments/{e[0]}/remarks", json={"period": 3, "decision": "passage", "sanction": "blame"}, headers=school["director"])).status_code == 200
    await client.post("/v1/absences", json={"day": date.today().isoformat(), "entries": [{"enrollment_id": e[0], "kind": "absence"}, {"enrollment_id": e[1], "kind": "retard"}]}, headers=school["secretary"])
    await client.post("/v1/absences", json={"day": date(2026, 10, 1).isoformat(), "entries": [{"enrollment_id": e[0], "kind": "absence", "justified": True, "reason": "Malade"}]}, headers=school["secretary"])
    c1 = (await client.get(f"/v1/enrollments/{e[0]}/report-card?period=1", headers=school["director"])).json()
    assert c1["conduct"] == "17.50" and c1["appreciation"] == "Élève sérieuse"
    assert c1["absences"] == {"days_unjustified": 1, "days_justified": 1, "late": 0, "courses_missed": 0}
    c3 = (await client.get(f"/v1/enrollments/{e[0]}/report-card?period=3", headers=school["director"])).json()
    assert c3["decision"] == "passage" and c3["sanction"] == "blame" and c3["average"] is None  # no marks yet: no average, no rank
    assert c3["rank"] is None


async def test_roll_call_updates_instead_of_duplicating_and_can_replace(client, school):
    room, e, sub = await class_with_students(client, school)
    day = date.today().isoformat()
    await client.post("/v1/absences", json={"day": day, "entries": [{"enrollment_id": e[0]}, {"enrollment_id": e[1]}]}, headers=school["teacher"])
    await client.post("/v1/absences", json={"day": day, "entries": [{"enrollment_id": e[0], "justified": True, "reason": "Rendez-vous médical"}]}, headers=school["teacher"])
    rows = (await client.get(f"/v1/classrooms/{room['id']}/absences?day={day}", headers=school["teacher"])).json()
    assert len(rows) == 2 and [r["justified"] for r in rows if r["enrollment_id"] == e[0]] == [True]
    await client.post("/v1/absences", json={"day": day, "classroom_id": room["id"], "replace": True, "entries": [{"enrollment_id": e[2]}]}, headers=school["teacher"])
    assert [r["enrollment_id"] for r in (await client.get(f"/v1/classrooms/{room['id']}/absences?day={day}", headers=school["teacher"])).json()] == [e[2]]


async def test_academic_data_is_isolated_between_schools(client, school):
    from tests.conftest import make_school, make_staff

    room, e, sub = await class_with_students(client, school)
    sid2, _ = await make_school("Ecole B")
    other, _ = await make_staff(sid2, "director", "Autre")
    assert (await client.get(f"/v1/classrooms/{room['id']}/results?period=1", headers=other)).status_code == 404
    assert (await client.get(f"/v1/enrollments/{e[0]}/report-card?period=1", headers=other)).status_code == 404
    assert (await client.post("/v1/evaluations", json={"classroom_id": room["id"], "subject_id": sub["maths"], "period": 1, "kind": "devoir"}, headers=other)).status_code == 404
    assert (await client.get("/v1/subjects", headers=other)).json() == []
