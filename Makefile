SHELL := /bin/bash
.PHONY: up down migrate test logs backup-db
COMPOSE = docker compose -f compose.platform.yaml
up:        ## build and start behind the shared Caddy (needs infra_net and .env.platform)
	$(COMPOSE) up -d --build --wait
down:
	$(COMPOSE) down
migrate:
	$(COMPOSE) exec web alembic upgrade head
test:      ## needs a Postgres on localhost:5440 (see backend/README.md)
	cd backend && python -m pytest -q
logs:
	$(COMPOSE) logs -f --tail=100 web
backup-db:
	cd ../platform/infra && scripts/backup.sh
