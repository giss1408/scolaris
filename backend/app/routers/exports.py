"""Statistics the education authorities (DRENA / IEPP) ask for: headcount by level, sex and "affecté" status; exam candidate lists."""

import csv
import io
from collections import defaultdict

from fastapi import APIRouter, Depends, Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.deps import Me, current_me
from app.levels import ALL_LEVELS
from app.models import AcademicYear, Classroom, Enrollment, School, Student
from app.errors import NotFound

router = APIRouter(prefix="/v1/exports", tags=["exports"])

# The exam a level sits at the end of: CEPE (CM2), BEPC (3e), BAC (Tle).
EXAM_OF_LEVEL = {"CM2": "CEPE", "3e": "BEPC", "Tle": "BAC"}


async def _year(db: AsyncSession, m: Me, year_id: int) -> AcademicYear:
    y = await db.scalar(select(AcademicYear).where(AcademicYear.id == year_id, AcademicYear.school_id == m.school_id))
    if y is None:
        raise NotFound("year_not_found")
    return y


def _csv(rows: list[list], header: list[str], name: str) -> Response:
    buf = io.StringIO()
    w = csv.writer(buf, delimiter=";")  # semicolon: what French-locale Excel opens directly
    w.writerow(header)
    w.writerows(rows)
    return Response(content="﻿" + buf.getvalue(), media_type="text/csv; charset=utf-8", headers={"Content-Disposition": f'attachment; filename="{name}"'})


@router.get("/headcount")
async def headcount(year_id: int, format: str = "json", m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)):
    m.require_role("director")
    year = await _year(db, m, year_id)
    rows = (await db.execute(
        select(Classroom.level, Student.sex, Student.assigned).join(Enrollment, Enrollment.classroom_id == Classroom.id).join(Student, Student.id == Enrollment.student_id)
        .where(Enrollment.school_id == m.school_id, Enrollment.year_id == year.id, Enrollment.status == "active")
    )).all()
    table: dict[str, dict[str, int]] = defaultdict(lambda: {"boys": 0, "girls": 0, "assigned": 0, "not_assigned": 0})
    for level, sex, assigned in rows:
        t = table[level]
        t["girls" if sex == "F" else "boys"] += 1
        t["assigned" if assigned else "not_assigned"] += 1
    out = [{"level": lv, **table[lv], "total": table[lv]["boys"] + table[lv]["girls"]} for lv in ALL_LEVELS if lv in table]
    total = {k: sum(r[k] for r in out) for k in ("boys", "girls", "assigned", "not_assigned", "total")}
    if format == "csv":
        school = await db.get(School, m.school_id)
        return _csv([[r["level"], r["boys"], r["girls"], r["total"], r["assigned"], r["not_assigned"]] for r in out] + [["TOTAL", total["boys"], total["girls"], total["total"], total["assigned"], total["not_assigned"]]],
                    ["Niveau", "Garçons", "Filles", "Total", "Affectés", "Non affectés"], f"effectifs-{school.code_mena or school.id}-{year.label}.csv")
    return {"year": year.label, "levels": out, "total": total}


@router.get("/exam-candidates")
async def exam_candidates(year_id: int, format: str = "json", m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)):
    """Pupils of the exam levels (CM2 -> CEPE, 3e -> BEPC, Tle -> BAC) with what the registration needs. A missing MENA matricule is flagged."""
    m.require_role("director", "secretary")
    year = await _year(db, m, year_id)
    rows = (await db.execute(
        select(Classroom.level, Classroom.name, Student).join(Enrollment, Enrollment.classroom_id == Classroom.id).join(Student, Student.id == Enrollment.student_id)
        .where(Enrollment.school_id == m.school_id, Enrollment.year_id == year.id, Enrollment.status == "active", Classroom.level.in_(list(EXAM_OF_LEVEL)))
        .order_by(Classroom.level, Student.last_name, Student.first_names)
    )).all()
    out = [{"exam": EXAM_OF_LEVEL[lv], "classroom": room, "last_name": s.last_name, "first_names": s.first_names, "sex": s.sex,
            "birth_date": s.birth_date.isoformat() if s.birth_date else None, "birth_place": s.birth_place, "matricule": s.matricule_mena,
            "missing": [k for k, v in (("matricule", s.matricule_mena), ("birth_date", s.birth_date), ("birth_place", s.birth_place)) if not v]} for lv, room, s in rows]
    if format == "csv":
        return _csv([[c["exam"], c["classroom"], c["last_name"], c["first_names"], c["sex"], c["birth_date"] or "", c["birth_place"] or "", c["matricule"] or "", ", ".join(c["missing"])] for c in out],
                    ["Examen", "Classe", "Nom", "Prénoms", "Sexe", "Date de naissance", "Lieu de naissance", "Matricule", "À compléter"], f"candidats-{year.label}.csv")
    return {"year": year.label, "candidates": out, "incomplete": sum(1 for c in out if c["missing"])}
