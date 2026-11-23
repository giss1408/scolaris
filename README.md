# Scolaris

School management SaaS for Côte d'Ivoire (see the `gestion-scolaire-ci` skill). Product on the shared platform (`../platform`): own database `db_scolaris`, sign-in only through the `auth` service (SSO), imports only `regisse_kit`.

## Built
- **Slice 1, school and money:** years, classrooms, fee schedule per level (optional services, "affecté" fees), students with families and contacts (phones encrypted), enrolment, payments (cash, Wave, Orange Money, MTN, Moov, transfer, cheque) with gapless receipt numbers and idempotency, cancellations as credit notes, director-granted discounts, arrears grouped by family, dashboard, staff enrolment.
- **Slice 2, grades:** subjects and coefficients per level, evaluations (/20 or /10, normalised), mark entry by teachers (own evaluations only), validation/lock by the director, averages with coefficients (absent is not a zero), ranks with ties ("2e ex"), honours with school thresholds, report cards (conduct, appreciation, sanction, council decision, absences), roll call.
- **Slice 3, reminders:** the J-5 / J+3 / J+10 / J+20 / escalation scenario, one message per family, no Sunday, one per week, stops on payment, promises to pay, WhatsApp only with opt-in (otherwise a phone call), idempotent planning; a person sends each message through a prepared `wa.me` link (no WhatsApp Business API on the platform yet) and marks it sent; recovered-after-reminder summary.
- **Slice 4, parents and authorities:** parent space (children in any school holding her verified number: balance, receipts, report cards, absences), DRENA exports (headcount by level/sex/affecté, exam candidate lists CEPE/BEPC/BAC, CSV).
- Roles: director, accountant, secretary, teacher (staff app) and parent. Server-enforced; the app hides what a role cannot do.

## Not built (needs outside accounts or a bigger decision)
WhatsApp Cloud API sending and delivery statuses; Mobile Money payment links and webhooks (an aggregator account: CinetPay, PayDunya, FedaPay); offline mode with sync; PDF generation (receipts, report cards: they are shown on screen and shared as text); parent push notifications; timetable, textbook, staff payroll, canteen/transport; ARTCI declaration; production settings and store builds.

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

## Roles
`director` (everything; fresh password for discounts and cancellations), `accountant` (collect, arrears, reminders, dashboard), `secretary` (students, classrooms, grades, roll call; no money), `teacher` (grades and roll call only), `parent` (her own children, read-only). Enforced by the server; the app hides what a role cannot do.
