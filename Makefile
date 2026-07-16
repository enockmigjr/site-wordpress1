COMPOSE ?= docker compose
ENV_FILE ?= .env
WAIT_TIMEOUT ?= 180
BACKUP ?=
WP_ARGS ?= help
PUBLIC_URL ?=

COMPOSE_RUN = $(COMPOSE) --env-file $(ENV_FILE)

.DEFAULT_GOAL := help

.PHONY: help init secrets config build deploy verify status logs restart stop down cron wp backup restore-verify restore-test provider-status production-preflight

help:
	@echo "PhotoVault Docker"
	@echo ""
	@echo "  make init             Generate .env and the local provider-secrets file"
	@echo "  make config           Validate the resolved Docker Compose configuration"
	@echo "  make build            Build the WordPress and cron images"
	@echo "  make deploy           Build, start, wait for health, then verify WordPress"
	@echo "  make verify           Verify health, WordPress, theme and required plugins"
	@echo "  make status           Show service state"
	@echo "  make logs             Follow application logs"
	@echo "  make restart          Restart application services"
	@echo "  make stop             Stop services without deleting them"
	@echo "  make down             Stop and remove containers (data volume is retained)"
	@echo "  make cron             Run due WordPress cron events"
	@echo "  make wp WP_ARGS='...' Run a WP-CLI command"
	@echo "  make provider-status  Check Twilio and Resend configuration without secrets"
	@echo "  make production-preflight PUBLIC_URL=https://..."
	@echo "  make backup           Create a database and media snapshot"
	@echo "  make restore-verify BACKUP=name"
	@echo "  make restore-test BACKUP=name"

init:
	@if [ -e "$(ENV_FILE)" ]; then echo "$(ENV_FILE) already exists; leaving it unchanged."; else sh docker/scripts/init-env.sh; fi
	@if [ -e docker/wp-config-secrets.php ]; then echo "docker/wp-config-secrets.php already exists; leaving it unchanged."; else cp docker/wp-config-secrets.example.php docker/wp-config-secrets.php; fi

secrets:
	@if [ -e docker/wp-config-secrets.php ]; then echo "docker/wp-config-secrets.php already exists; leaving it unchanged."; else cp docker/wp-config-secrets.example.php docker/wp-config-secrets.php; fi

config:
	@test -s "$(ENV_FILE)" || (echo "Missing $(ENV_FILE). Run 'make init' first." >&2; exit 1)
	$(COMPOSE_RUN) config --quiet

build: config
	$(COMPOSE_RUN) build wordpress cron

deploy: config
	$(COMPOSE_RUN) up --build -d --remove-orphans --wait --wait-timeout $(WAIT_TIMEOUT)
	$(MAKE) verify ENV_FILE="$(ENV_FILE)"

verify: config
	$(COMPOSE_RUN) exec -T nginx wget -qO- http://127.0.0.1/healthz | grep -qx ok
	$(COMPOSE_RUN) exec -T wordpress wp --allow-root core is-installed --path=/var/www/html
	$(COMPOSE_RUN) exec -T wordpress wp --allow-root theme is-active PhotoVault --path=/var/www/html
	$(COMPOSE_RUN) exec -T wordpress wp --allow-root plugin is-active photovault-core --path=/var/www/html
	$(COMPOSE_RUN) exec -T wordpress wp --allow-root plugin is-active identity-security-kit --path=/var/www/html
	$(COMPOSE_RUN) exec -T wordpress wp --allow-root plugin is-active newsletter-campaign-kit --path=/var/www/html
	@echo "PhotoVault deployment verified."

provider-status: config
	$(COMPOSE_RUN) exec -T wordpress wp --allow-root eval-file /var/www/html/docker/scripts/provider-status.php --path=/var/www/html

production-preflight: verify
	@test -n "$(PUBLIC_URL)" || (echo "PUBLIC_URL is required (https://...)." >&2; exit 1)
	$(COMPOSE_RUN) exec -T -e PHOTOVAULT_REQUIRE_LIVE_PROVIDERS=1 wordpress wp --allow-root eval-file /var/www/html/docker/scripts/provider-status.php --path=/var/www/html
	$(COMPOSE_RUN) exec -T wordpress sh /var/www/html/docker/scripts/public-preflight.sh "$(PUBLIC_URL)"

status:
	$(COMPOSE_RUN) ps

logs:
	$(COMPOSE_RUN) logs --tail=150 -f nginx wordpress db cron

restart: config
	$(COMPOSE_RUN) restart nginx wordpress cron
	$(MAKE) verify ENV_FILE="$(ENV_FILE)"

stop:
	$(COMPOSE_RUN) stop

down:
	$(COMPOSE_RUN) down --remove-orphans

cron: config
	$(COMPOSE_RUN) exec -T cron wp --allow-root cron event run --due-now --path=/var/www/html

wp: config
	$(COMPOSE_RUN) exec wordpress wp --allow-root $(WP_ARGS) --path=/var/www/html

backup: config
	$(COMPOSE_RUN) --profile tools run --rm backup

restore-verify: config
	@test -n "$(BACKUP)" || (echo "BACKUP is required." >&2; exit 1)
	$(COMPOSE_RUN) --profile tools run --rm restore verify "$(BACKUP)"

restore-test: config
	@test -n "$(BACKUP)" || (echo "BACKUP is required." >&2; exit 1)
	$(COMPOSE_RUN) --profile tools run --rm restore test "$(BACKUP)"
