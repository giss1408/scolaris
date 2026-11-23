# Scolaris

School management SaaS for Côte d'Ivoire (see the `gestion-scolaire-ci` skill). Product on the shared platform (`../platform`): own database `db_scolaris`, sign-in only through the `auth` service (SSO), imports only `regisse_kit`.

## Built
- **Slice 1, school and money:** years, classrooms, fee schedule per level (optional services, "affecté" fees), students with families and contacts (phones encrypted), enrolment, payments (cash, Wave, Orange Money, MTN, Moov, transfer, cheque) with gapless receipt numbers and idempotency, cancellations as credit notes, director-granted discounts, arrears grouped by family, dashboard, staff enrolment.
- **Slice 2, grades:** subjects and coefficients per level, evaluations (/20 or /10, normalised), mark entry by teachers (own evaluations only), validation/lock by the director, averages with coefficients (absent is not a zero), ranks with ties ("2e ex"), honours with school thresholds, report cards (conduct, appreciation, sanction, council decision, absences), roll call.
- **Slice 3, reminders:** the J-5 / J+3 / J+10 / J+20 / escalation scenario, one message per family, no Sunday, one per week, stops on payment, promises to pay, WhatsApp only with opt-in (otherwise a phone call), idempotent planning; a person sends each message through a prepared `wa.me` link (no WhatsApp Business API on the platform yet) and marks it sent; recovered-after-reminder summary.
- **Slice 4, parents and authorities:** parent space (children in any school holding her verified number: balance, receipts, report cards, absences), DRENA exports (headcount by level/sex/affecté, exam candidate lists CEPE/BEPC/BAC, CSV).
- **Timetable:** weekly periods per class (Monday-Saturday: day, hours, subject, teacher, room), built by the director or the secretary; nothing overlaps in a class, for a teacher (any class) or in a room, and a clash is refused with a sentence naming it; a teacher can only be placed in a class and subject she is assigned to (a period keeps its place, without a teacher, when she is unassigned or removed); teachers read their own week and their classes, parents read their child's class.
- **Cancelling a session:** the teacher of a period (or the director / secretary on her behalf) cancels ONE session, a date, with a reason (illness, authorised absence, training, other + note), within the school year and not once it is over; it can be restored until the day has passed. The administration gets the list of upcoming cancelled courses with the real reason and a ready message for the families; parents and the other teachers only see that the session is cancelled, never why (a teacher's illness is her own business).
- Roles: director, accountant, secretary, teacher (staff app) and parent. Server-enforced; the app hides what a role cannot do.

## Not built (needs outside accounts or a bigger decision)
WhatsApp Cloud API sending and delivery statuses; Mobile Money payment links and webhooks (an aggregator account: CinetPay, PayDunya, FedaPay); offline mode with sync; PDF generation (receipts, report cards: they are shown on screen and shared as text); parent push notifications; textbook, staff payroll, canteen/transport; ARTCI declaration; production settings and store builds.

## Layout
- `backend/`: FastAPI + Postgres (Alembic). `make test` needs a Postgres on localhost:5440 (`docker run -d -p 5440:5432 -e POSTGRES_USER=scolaris -e POSTGRES_PASSWORD=scolaris -e POSTGRES_DB=scolaris postgres:17-alpine`).
- `app/`: Flutter app for the school's staff (`flutter run --dart-define-from-file=env/staging.json`). `flutter test`, `flutter analyze`.
- `brand/`: logo (SVG); `app/tool/` renders the launcher icons.
- `compose.platform.yaml`, `platform.env.defaults`: deployment on the platform.

## Run on the platform (local)
```
platform/infra/scripts/new-product.sh scolaris --max-body 6MB
platform/infra/scripts/add-service-key.sh scolaris
platform/infra/scripts/make-product-env.sh scolaris scolaris/.env.platform --defaults scolaris/platform.env.defaults
(cd platform/auth && docker compose -f compose.platform.yaml up -d --build)   # auth knows the `scolaris` product
make up
bash platform/tests/e2e_scolaris.sh       # real chain: auth -> director -> scolaris -> the app's Dart code
```
First school: `docker exec scolaris-web python -m app.cli create-school --name ... --director-name ... --director-phone ... --year 2026-2027 --starts 2026-09-14 --ends 2027-06-30`, then the platform team sends the WhatsApp activation code from the auth back office.

## Roles and permissions
Enforced by the server on every request (the app only hides what a role can never do). Every row of data belongs to one school.

| | Director | Accountant | Secretary | Teacher | Parent |
|---|---|---|---|---|---|
| School register (students, contacts, parents' phones) | read/write | read | read/write | **no** | her own children only |
| Money: payments, balances, receipts, arrears, reminders | all | collect, read, remind | **no** | **no** | her own children's balance and receipts |
| Cancel a payment, grant a discount | yes, with a fresh password | no | no | no | no |
| Set-up (years, classes, fees, subjects, coefficients, team) | yes | no | classes only | no | no |
| Assign teachers to classes and subjects, name head teachers | yes | no | no | no | no |
| Grades: create an evaluation, enter marks | any class | no | any class | **only her assigned class and subject**, only her own evaluations, only while assigned | no |
| Lock / unlock an evaluation | yes | no | no | no | no |
| Results and report cards of a class | all | no | all | her classes (assigned or head) | her own children (no class figures) |
| Conduct and appreciation | yes | no | yes | **only as head teacher of that class** | no |
| Sanction and council decision | yes | no | no | no | no |
| Roll call | any class | no | any class | her classes | read her child's absences |
| Timetable: build and edit | yes | no | yes | no (reads her own week and her classes) | reads her child's class timetable |
| Cancel / restore one session of a course | any | no | any | **her own periods only** | no (sees "Cours annulé", never the reason) |
| See the reason of a cancellation | yes | no | yes | only for her own periods | **never** |
| DRENA exports | headcount + exam candidates | no | exam candidates | no | no |

Teacher assignment: the director links a teacher to a class for one subject, or for all the subjects she gives there. A head teacher (professeur principal) sees the whole class and writes conduct and appreciation, but can only create marks in the subjects she is assigned. Removing an assignment closes the class to her at once; the marks she already entered stay in the results.
