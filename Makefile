# =============================================================================
# Makefile — thin wrapper around scripts/ (macOS / Linux / WSL / Git Bash)
# -----------------------------------------------------------------------------
# Every target simply runs the matching script, so you can equally call
# `bash scripts/<name>.sh` directly. Windows users: use the scripts from
# Git Bash, or install make (choco install make).
#
#   make doctor      check installed tools
#   make up          create the kind cluster
#   make deploy      build app image + apply ALL manifests
#   make load        send traffic to the demo app
#   make validate    verify the repository (same check as CI)
#   make down        remove deployed components (keeps the cluster)
#   make destroy     delete the cluster entirely
# =============================================================================
SHELL := /usr/bin/env bash

.PHONY: help doctor validate up deploy load cleanup destroy port-forward

help:
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

doctor:      ## check installed tools
	bash scripts/doctor.sh

validate:    ## verify the repository (YAML/JSON/scripts/Go)
	bash scripts/validate.sh

up:          ## create the kind cluster
	bash scripts/cluster-up.sh

deploy:      ## build app image + apply all manifests
	bash scripts/deploy.sh

load:        ## send traffic to the demo app (port-forward first)
	bash scripts/generate-load.sh

cleanup:     ## remove deployed components, keep the cluster
	bash scripts/cleanup.sh

destroy:     ## delete the kind cluster
	bash scripts/cluster-down.sh

port-forward: ## open a UI tunnel: make port-forward SERVICE=grafana
	bash scripts/port-forward.sh $(SERVICE)
