SHELL := /bin/bash

TERRAFORM_VERSION ?= 1.14.8
TERRAGRUNT_VERSION ?= 1.1.4
TFLINT_VERSION ?= 0.64.0
IAC_TOOLS_IMAGE ?= gordonquantinfra-iac-tools:local
DOCKER_PLATFORM ?= linux/amd64
AWS_ACCOUNT_ID ?= 491117466808
AWS_REGION ?= us-east-1
WIREGUARD_CLIENT_CONFIG ?= /etc/wireguard/wg0.conf
WIREGUARD_CLIENT_INTERFACE ?= wg0
WIREGUARD_TG_DIR ?= WireGuardVPN/environments/prod/wireguard
WIREGUARD_POST_DEPLOY_TIMEOUT ?= 900
WIREGUARD_SERVER_PUBLIC_KEY ?=
GORDONQUANT_SERVICE_DIR ?= GordonQuant/environments/prod/service
GORDONQUANT_SERVICE_CHECK_TIMEOUT ?= 900
GORDONQUANT_WIREGUARD_ROUTE_STATE ?= $(GORDONQUANT_SERVICE_DIR)/.wireguard-route
GORDONQUANT_LEGACY_WIREGUARD_ROUTES ?= 172.31.0.0/20,172.31.16.0/20

DOCKER_BUILD := docker build \
	--platform $(DOCKER_PLATFORM) \
	--build-arg TERRAFORM_VERSION=$(TERRAFORM_VERSION) \
	--build-arg TERRAGRUNT_VERSION=$(TERRAGRUNT_VERSION) \
	--build-arg TFLINT_VERSION=$(TFLINT_VERSION) \
	--tag $(IAC_TOOLS_IMAGE) \
	.docker/iac

DOCKER_RUN := docker run --rm \
	--platform $(DOCKER_PLATFORM) \
	--user $$(id -u):$$(id -g) \
	--env AWS_ACCOUNT_ID=$(AWS_ACCOUNT_ID) \
	--env HOME=/tmp \
	--volume "$(CURDIR):/workspace" \
	--workdir /workspace \
	$(IAC_TOOLS_IMAGE)

WIREGUARD_TF_MODULE := WireGuardVPN/modules/wireguard
WIREGUARD_TG_ROOT := /workspace/WireGuardVPN
GORDONQUANT_TF_MODULES := GordonQuant/modules/ec2-service GordonQuant/modules/public-alb
GORDONQUANT_TG_ROOT := /workspace/GordonQuant

.PHONY: help docker-build format fmt format-check fmt-check lint validate check \
	gordonquant-service-check gordonquant-service-session \
	wireguard-post-deploy wireguard-gordonquant-routes wireguard-gordonquant-sync clean

help:
	@echo "Docker-based infrastructure quality targets:"
	@echo "  make format        Format Terraform and Terragrunt HCL"
	@echo "  make format-check  Check formatting without changing files"
	@echo "  make lint          Run TFLint"
	@echo "  make validate      Validate Terraform and Terragrunt"
	@echo "  make check         Run format-check, lint, and validate"
	@echo "  make gordonquant-service-check    Wait for SSM and verify cloud-init, Docker, and app health"
	@echo "  make gordonquant-service-session  Open an interactive SSM session on the persistent instance"
	@echo "  make wireguard-post-deploy        Sync server key, GordonQuant route, NordVPN, then restart wg0"
	@echo "  make wireguard-gordonquant-routes  Show the persistent GordonQuant instance VPN route"
	@echo "  make wireguard-gordonquant-sync    Sync the instance route, NordVPN allowlist, and WireGuard"

docker-build:
	$(DOCKER_BUILD)

format: docker-build
	$(DOCKER_RUN) terraform fmt -recursive $(WIREGUARD_TF_MODULE) $(GORDONQUANT_TF_MODULES)
	$(DOCKER_RUN) terragrunt --working-dir $(WIREGUARD_TG_ROOT) hcl fmt
	$(DOCKER_RUN) terragrunt --working-dir $(GORDONQUANT_TG_ROOT) hcl fmt

fmt: format

format-check: docker-build
	$(DOCKER_RUN) terraform fmt -recursive -check -diff $(WIREGUARD_TF_MODULE) $(GORDONQUANT_TF_MODULES)
	$(DOCKER_RUN) terragrunt --working-dir $(WIREGUARD_TG_ROOT) hcl fmt --check --diff
	$(DOCKER_RUN) terragrunt --working-dir $(GORDONQUANT_TG_ROOT) hcl fmt --check --diff

fmt-check: format-check

lint: docker-build
	$(DOCKER_RUN) tflint --config=/workspace/.tflint.hcl --chdir=$(WIREGUARD_TF_MODULE)
	$(DOCKER_RUN) tflint --config=/workspace/.tflint.hcl --chdir=GordonQuant/modules/ec2-service
	$(DOCKER_RUN) tflint --config=/workspace/.tflint.hcl --chdir=GordonQuant/modules/public-alb

validate: docker-build
	$(DOCKER_RUN) bash -n scripts/check-gordonquant-service.sh
	$(DOCKER_RUN) bash -n scripts/get-wireguard-server-public-key.sh
	$(DOCKER_RUN) bash -n scripts/sync-nordvpn-allowlist.sh
	$(DOCKER_RUN) bash -n scripts/sync-wireguard-routes.sh
	$(DOCKER_RUN) bash -n GordonQuant/modules/ec2-service/user_data.sh.tftpl
	$(DOCKER_RUN) terraform -chdir=$(WIREGUARD_TF_MODULE) init -backend=false -input=false
	$(DOCKER_RUN) terraform -chdir=$(WIREGUARD_TF_MODULE) validate
	$(DOCKER_RUN) terraform -chdir=GordonQuant/modules/ec2-service init -backend=false -input=false
	$(DOCKER_RUN) terraform -chdir=GordonQuant/modules/ec2-service validate
	$(DOCKER_RUN) terraform -chdir=GordonQuant/modules/public-alb init -backend=false -input=false
	$(DOCKER_RUN) terraform -chdir=GordonQuant/modules/public-alb validate
	$(DOCKER_RUN) terragrunt --working-dir $(WIREGUARD_TG_ROOT) hcl validate \
		--inputs --strict --tf-path terraform
	$(DOCKER_RUN) terragrunt --working-dir $(GORDONQUANT_TG_ROOT) hcl validate \
		--inputs --strict --tf-path terraform

check: format-check lint validate

gordonquant-service-check:
	@set -euo pipefail; \
	instance_id="$$(terragrunt --working-dir "$(GORDONQUANT_SERVICE_DIR)" output -raw instance_id)"; \
	service_port="$$(terragrunt --working-dir "$(GORDONQUANT_SERVICE_DIR)" output -raw service_port)"; \
	./scripts/check-gordonquant-service.sh \
		--instance-id "$${instance_id}" \
		--region "$(AWS_REGION)" \
		--service-port "$${service_port}" \
		--timeout "$(GORDONQUANT_SERVICE_CHECK_TIMEOUT)"

gordonquant-service-session:
	@set -euo pipefail; \
	instance_id="$$(terragrunt --working-dir "$(GORDONQUANT_SERVICE_DIR)" output -raw instance_id)"; \
	aws ssm start-session --region "$(AWS_REGION)" --target "$${instance_id}"

wireguard-post-deploy:
	@set -euo pipefail; \
	instance_id="$$(terragrunt --working-dir "$(WIREGUARD_TG_DIR)" output -raw instance_id)"; \
	server_public_key="$$(./scripts/get-wireguard-server-public-key.sh \
		--instance-id "$${instance_id}" \
		--region "$(AWS_REGION)" \
		--timeout "$(WIREGUARD_POST_DEPLOY_TIMEOUT)")"; \
	$(MAKE) --no-print-directory wireguard-gordonquant-sync \
		WIREGUARD_SERVER_PUBLIC_KEY="$${server_public_key}"; \
	sudo wg show "$(WIREGUARD_CLIENT_INTERFACE)"; \
	echo "WireGuard post-deploy configuration completed for $${instance_id}."

wireguard-gordonquant-routes:
	@set -euo pipefail; \
	private_ip="$$(terragrunt --working-dir "$(GORDONQUANT_SERVICE_DIR)" output -raw private_ip)"; \
	route="$${private_ip}/32"; \
	echo "Persistent GordonQuant WireGuard route: $${route}"; \
	echo "Client config: $(WIREGUARD_CLIENT_CONFIG)"; \
	echo "NordVPN allowlist command:"; \
	echo "  nordvpn allowlist add subnet $${route}"

wireguard-gordonquant-sync:
	@set -euo pipefail; \
	private_ip="$$(terragrunt --working-dir "$(GORDONQUANT_SERVICE_DIR)" output -raw private_ip)"; \
	if [[ ! "$${private_ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$$ ]]; then \
		echo "Invalid private_ip output: $${private_ip}" >&2; \
		exit 1; \
	fi; \
	route="$${private_ip}/32"; \
	previous_route=""; \
	if [[ -f "$(GORDONQUANT_WIREGUARD_ROUTE_STATE)" ]]; then \
		previous_route="$$(<"$(GORDONQUANT_WIREGUARD_ROUTE_STATE)")"; \
	fi; \
	remove_routes="$(GORDONQUANT_LEGACY_WIREGUARD_ROUTES)"; \
	if [[ -n "$${previous_route}" ]]; then \
		remove_routes="$${remove_routes},$${previous_route}"; \
	fi; \
	key_arguments=(); \
	if [[ -n "$(WIREGUARD_SERVER_PUBLIC_KEY)" ]]; then \
		key_arguments=(--peer-public-key "$(WIREGUARD_SERVER_PUBLIC_KEY)"); \
	fi; \
	sudo ./scripts/sync-wireguard-routes.sh \
		--config "$(WIREGUARD_CLIENT_CONFIG)" \
		--interface "$(WIREGUARD_CLIENT_INTERFACE)" \
		--routes "$${route}" \
		--remove-routes "$${remove_routes}" \
		--restart \
		"$${key_arguments[@]}"; \
	./scripts/sync-nordvpn-allowlist.sh \
		--add "10.8.0.0/24,$${route}" \
		--remove "$${remove_routes}"; \
	printf '%s\n' "$${route}" >"$(GORDONQUANT_WIREGUARD_ROUTE_STATE)"; \
	echo "WireGuard and NordVPN now allow the persistent GordonQuant instance at $${route}."

clean:
	@echo "Generated Terraform and Terragrunt directories are ignored by Git."
	@echo "Remove .terraform and .terragrunt-cache directories manually if needed."
