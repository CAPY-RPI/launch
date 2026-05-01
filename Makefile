.PHONY: all run up down restart pull logs config ps terraform-init terraform-apply terraform-destroy scripts setup-gatus

all: run

run: terraform-apply up

up: scripts
	docker compose up -d

down:
	docker compose down

down-v:
	docker compose down -v

reset: down-v up

restart:
	docker compose restart

pull:
	docker compose pull

logs:
	docker compose logs -f

config:
	docker compose config

ps:
	docker compose ps

include .env
export TF_VAR_cloudflare_api_token=$(CLOUDFLARE_API_TOKEN)
export TF_VAR_cloudflare_account_id=$(CLOUDFLARE_ACCOUNT_ID)
export TF_VAR_cloudflare_zone_id=$(CLOUDFLARE_ZONE_ID)
export TF_VAR_domain_name=$(DOMAIN_NAME)
export TF_VAR_tunnel_name=$(CLOUDFLARE_TUNNEL_NAME)

TF := terraform -chdir=terraform

terraform-init:
	$(TF) init

terraform-fmt:
	$(TF) fmt

terraform-validate: terraform-init
	$(TF) validate

terraform-plan: terraform-init
	$(TF) plan

terraform-apply: terraform-init
	$(TF) apply -auto-approve
	$(TF) output -json | uv run --project scripts scripts/generate_envs.py

terraform-destroy:
	$(TF) destroy -auto-approve

terraform-reset:
	$(MAKE) terraform-destroy
	$(MAKE) terraform-apply

scripts: setup-gatus

setup-gatus:
	uv run --project scripts scripts/generate_endpoints.py

