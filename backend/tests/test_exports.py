from datetime import date

from tests.conftest import make_school, make_staff
from tests.test_api import student


async def test_headcount_by_level_sex_and_assigned_with_csv(client, school):
    d = school["director"]
    r6 = (await client.post("/v1/classrooms", json={"year_id": school["year_id"], "level": "6e", "name": "6e 1"}, headers=d)).json()
    cm2 = (await client.post("/v1/classrooms", json={"year_id": school["year_id"], "level": "CM2", "name": "CM2 A"}, headers=d)).json()
    for room, sex, assigned, n in ((r6, "F", True, "a"), (r6, "M", False, "b"), (r6, "F", False, "c"), (cm2, "M", True, "d")):
        await client.post("/v1/students", json=student(room, last_name=n, sex=sex, assigned=assigned, contacts=[]), headers=school["secretary"])
    j = (await client.get(f"/v1/exports/headcount?year_id={school['year_id']}", headers=d)).json()
    assert j["year"] == "2026-2027"
    assert j["levels"] == [{"level": "CM2", "boys": 1, "girls": 0, "assigned": 1, "not_assigned": 0, "total": 1}, {"level": "6e", "boys": 1, "girls": 2, "assigned": 1, "not_assigned": 2, "total": 3}]
    assert j["total"] == {"boys": 2, "girls": 2, "assigned": 2, "not_assigned": 2, "total": 4}
    csv = await client.get(f"/v1/exports/headcount?year_id={school['year_id']}&format=csv", headers=d)
    assert csv.headers["content-type"].startswith("text/csv") and "attachment" in csv.headers["content-disposition"]
    lines = csv.text.lstrip("﻿").splitlines()
    assert lines[0] == "Niveau;Garçons;Filles;Total;Affectés;Non affectés" and lines[-1] == "TOTAL;2;2;4;2;2"
    assert (await client.get(f"/v1/exports/headcount?year_id={school['year_id']}", headers=school["accountant"])).status_code == 403


async def test_exam_candidates_flag_missing_data_and_stay_in_the_school(client, school):
    d = school["director"]
    cm2 = (await client.post("/v1/classrooms", json={"year_id": school["year_id"], "level": "CM2", "name": "CM2 A"}, headers=d)).json()
    r6 = (await client.post("/v1/classrooms", json={"year_id": school["year_id"], "level": "6e", "name": "6e 1"}, headers=d)).json()
    await client.post("/v1/students", json=student(cm2, last_name="Complet", matricule_mena="20123456A", birth_date="2014-03-02", birth_place="Abidjan", contacts=[]), headers=school["secretary"])
    await client.post("/v1/students", json=student(cm2, last_name="Incomplet", contacts=[]), headers=school["secretary"])
    await client.post("/v1/students", json=student(r6, last_name="Sixieme", contacts=[]), headers=school["secretary"])  # not an exam level
    j = (await client.get(f"/v1/exports/exam-candidates?year_id={school['year_id']}", headers=school["secretary"])).json()
    assert [(c["exam"], c["last_name"], c["missing"]) for c in j["candidates"]] == [("CEPE", "COMPLET", []), ("CEPE", "INCOMPLET", ["matricule", "birth_date", "birth_place"])]
    assert j["incomplete"] == 1
    sid2, y2 = await make_school("Ecole B")
    other, _ = await make_staff(sid2, "director", "Autre")
    assert (await client.get(f"/v1/exports/exam-candidates?year_id={school['year_id']}", headers=other)).status_code == 404
    assert (await client.get(f"/v1/exports/exam-candidates?year_id={y2}", headers=other)).json()["candidates"] == []
