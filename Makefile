SHELL := /bin/bash

TERRAFORM_VERSION ?= 1.14.8
TERRAGRUNT_VERSION ?= 1.1.4
TFLINT_VERSION ?= 0.64.0
IAC_TOOLS_IMAGE ?= gordonquantinfra-iac-tools:local
DOCKER_PLATFORM ?= linux/amd64
AWS_ACCOUNT_ID ?= 000000000000

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

TF_MODULE := WireGuardVPN/modules/wireguard
TG_ROOT := /workspace/WireGuardVPN

.PHONY: help docker-build format fmt format-check fmt-check lint validate check clean

help:
	@echo "Docker-based infrastructure quality targets:"
	@echo "  make format        Format Terraform and Terragrunt HCL"
	@echo "  make format-check  Check formatting without changing files"
	@echo "  make lint          Run TFLint"
	@echo "  make validate      Validate Terraform and Terragrunt"
	@echo "  make check         Run format-check, lint, and validate"

docker-build:
	$(DOCKER_BUILD)

format: docker-build
	$(DOCKER_RUN) terraform fmt -recursive $(TF_MODULE)
	$(DOCKER_RUN) terragrunt --working-dir $(TG_ROOT) hcl fmt

fmt: format

format-check: docker-build
	$(DOCKER_RUN) terraform fmt -recursive -check -diff $(TF_MODULE)
	$(DOCKER_RUN) terragrunt --working-dir $(TG_ROOT) hcl fmt --check --diff

fmt-check: format-check

lint: docker-build
	$(DOCKER_RUN) tflint --config=/workspace/.tflint.hcl --chdir=$(TF_MODULE)

validate: docker-build
	$(DOCKER_RUN) terraform -chdir=$(TF_MODULE) init -backend=false -input=false
	$(DOCKER_RUN) terraform -chdir=$(TF_MODULE) validate
	$(DOCKER_RUN) terragrunt --working-dir $(TG_ROOT) hcl validate \
		--inputs --strict --tf-path terraform

check: format-check lint validate

clean:
	@echo "Generated Terraform and Terragrunt directories are ignored by Git."
	@echo "Remove .terraform and .terragrunt-cache directories manually if needed."
