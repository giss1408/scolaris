"""Platform-team commands. The first director of a school is created here (not through the API): the platform team enrols her at auth,
then sends her the WhatsApp activation code from the auth back office.

    python -m app.cli create-school --name "Groupe Scolaire Les Palmiers" --city Abidjan --kind prive_laic \
        --director-name "Awa Koné" --director-phone 0701020304 --year 2026-2027 --starts 2026-09-14 --ends 2027-06-30
"""

import argparse
import asyncio
from datetime import date

from regisse_kit.phone import normalize_ci_phone

from app.config import get_settings
from app.db import SessionLocal
from app.models import AcademicYear, AuditLog, School, StaffMember
from app.services import auth_client


async def create_school(a: argparse.Namespace) -> None:
    phone = normalize_ci_phone(a.director_phone, allow_test_numbers=get_settings().test_numbers)
    uid = await auth_client.enrol_staff(phone=phone, display_name=a.director_name, role="director")
    async with SessionLocal() as db:
        school = School(name=a.name, kind=a.kind, city=a.city, code_mena=a.code_mena)
        db.add(school)
        await db.flush()
        db.add(StaffMember(school_id=school.id, auth_user_id=uid, display_name=a.director_name, role="director"))
        db.add(AcademicYear(school_id=school.id, label=a.year, starts_on=date.fromisoformat(a.starts), ends_on=date.fromisoformat(a.ends), is_current=True))
        db.add(AuditLog(school_id=school.id, action="school.created", entity="school", detail={"by": "cli"}))
        await db.commit()
        print(f"School {school.id} created. Director enrolled at auth: send her the WhatsApp activation code from the auth back office.")


def main() -> None:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("create-school")
    c.add_argument("--name", required=True)
    c.add_argument("--city")
    c.add_argument("--code-mena")
    c.add_argument("--kind", choices=["public", "prive_laic", "prive_confessionnel"], default="prive_laic")
    c.add_argument("--director-name", required=True)
    c.add_argument("--director-phone", required=True)
    c.add_argument("--year", required=True)
    c.add_argument("--starts", required=True)
    c.add_argument("--ends", required=True)
    args = p.parse_args()
    asyncio.run(create_school(args))


if __name__ == "__main__":
    main()
