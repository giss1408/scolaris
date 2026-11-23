# Scolaris

School management SaaS for Côte d'Ivoire (see the `gestion-scolaire-ci` skill). Product on the shared platform (`../platform`): own database `db_scolaris`, sign-in only through the `auth` service (SSO), imports only `regisse_kit`.

## Slice 1 (built)
School set-up (years, classrooms, fee schedule per level with optional services and "affecté" fees), students with families and contacts (phones encrypted), enrolment, payments (cash, Wave, Orange Money, MTN, Moov, transfer, cheque) with gapless receipt numbers and idempotency, cancellations as credit notes, director-granted discounts, arrears grouped by family, dashboard, staff enrolment (director, accountant, secretary).
Not yet: grades and report cards, attendance, WhatsApp reminders (Cloud API), Mobile Money payment links, parent app, offline mode, PDF receipts, exports for DRENA.

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
`director` (everything, step-up for discounts and cancellations), `accountant` (collect, arrears, dashboard), `secretary` (students, classrooms; no money). Enforced by the server; the app hides what a role cannot do.
