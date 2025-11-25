# K3D Cluster Manager Makefile

# Variables
CLUSTER_NAME ?= k3d-argocd-sandbox
K3S_MANIFEST_PATH := $(shell pwd)/k3s-manifests
K3S_STORAGE_PATH := $(shell pwd)/k3s-storage
REGISTRY_DOCKERHUB_CACHE := $(shell pwd)/registry/dockerhub
REGISTRY_GHCR_CACHE := $(shell pwd)/registry/ghcr
REGISTRY_GITLAB_CACHE := $(shell pwd)/registry/gitlab
REGISTRY_LOCAL_CACHE := $(shell pwd)/registry/local

# Colors for output
CYAN = \033[1;36m
YELLOW = \033[1;33m
GREEN = \033[1;32m
RED = \033[1;31m
PURPLE = \033[1;35m
GRAY = \033[2;37m
RESET = \033[0m

# Main targets
.PHONY: help setup create delete recreate cleanup

# Default target - show help
help:
	@echo "$(CYAN)╔══════════════════════════════════════════════════════════════╗$(RESET)"
	@echo "$(CYAN)║                    $(YELLOW)K3D Cluster Manager$(CYAN)                       ║$(RESET)"
	@echo "$(CYAN)╚══════════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@echo "$(GREEN)Usage:$(RESET) make $(PURPLE){setup|create|delete|recreate|cleanup|help}$(RESET)"
	@echo ""
	@echo "$(YELLOW)Commands:$(RESET)"
	@echo "  $(PURPLE)setup$(RESET)      $(GRAY)└─$(RESET) Create proxy registries"
	@echo "  $(PURPLE)init$(RESET)       $(GRAY)└─$(RESET) Create necessary directories and configure registries"
	@echo "  $(PURPLE)create$(RESET)     $(GRAY)└─$(RESET) Create K3D cluster with all configurations"
	@echo "  $(PURPLE)delete$(RESET)     $(GRAY)└─$(RESET) Delete cluster (keep registries)"
	@echo "  $(PURPLE)recreate$(RESET)   $(GRAY)└─$(RESET) Recreate cluster (keep registries)"
	@echo "  $(PURPLE)cleanup$(RESET)    $(GRAY)└─$(RESET) Delete everything including registries"
	@echo "  $(PURPLE)help$(RESET)       $(GRAY)└─$(RESET) Show this help message"
	@echo ""
	@echo "$(RED)Example:$(RESET) make $(PURPLE)setup$(RESET)"
	@echo ""
	@echo "$(YELLOW)Environment variables:$(RESET)"
	@echo "  $(PURPLE)CLUSTER_NAME$(RESET)              $(GRAY)└─$(RESET) Cluster name (default: local)"
	@echo "  $(PURPLE)K3S_MANIFEST_PATH$(RESET)         $(GRAY)└─$(RESET) Path to manifests (default: ./k3s-manifests)"
	@echo "  $(PURPLE)K3S_STORAGE_PATH$(RESET)          $(GRAY)└─$(RESET) Path to storage (default: ./k3s-storage)"
	@echo "  $(PURPLE)REGISTRY_DOCKERHUB_CACHE$(RESET)  $(GRAY)└─$(RESET) Docker Hub cache path (default: ./registry/dockerhub)"
	@echo "  $(PURPLE)REGISTRY_GHCR_CACHE$(RESET)       $(GRAY)└─$(RESET) GitHub Container Registry (GHCR) cache path (default: ./registry/ghcr)"
	@echo "  $(PURPLE)REGISTRY_GITLAB_CACHE$(RESET)     $(GRAY)└─$(RESET) GitLab cache path (default: ./registry/gitlab)"
	@echo "  $(PURPLE)REGISTRY_LOCAL_CACHE$(RESET)      $(GRAY)└─$(RESET) Local registry cache path (default: ./registry/local)"
	@echo ""

# Create proxy registries for Docker Hub and GitLab
setup:
	@echo "Setting up persistent registries..."
	@docker network inspect k3d-network >/dev/null 2>&1 || docker network create k3d-network
	@if ! docker ps | grep -q "k3d-docker-io"; then \
		echo "Creating Docker Hub proxy registry..."; \
		docker run -d --rm \
			--name k3d-docker-io \
			--network k3d-network \
			-v ${REGISTRY_DOCKERHUB_CACHE}:/var/lib/registry \
			-p 5000:5000 \
			-e OTEL_TRACES_EXPORTER=none \
			-e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io \
			registry:3; \
	fi
	@if ! docker ps | grep -q "k3d-ghcr-io"; then \
		echo "Creating GHCR proxy registry..."; \
		docker run -d --rm \
			--name k3d-ghcr-io \
			--network k3d-network \
			-v ${REGISTRY_GHCR_CACHE}:/var/lib/registry \
			-p 5001:5000 \
			-e OTEL_TRACES_EXPORTER=none \
			-e REGISTRY_PROXY_REMOTEURL=https://ghcr.io \
			registry:3; \
	fi
	@if ! docker ps | grep -q "k3d-gitlab-com"; then \
		echo "Creating GitLab proxy registry..."; \
		docker run -d --rm \
			--name k3d-gitlab-com \
			--network k3d-network \
			-v ${REGISTRY_GITLAB_CACHE}:/var/lib/registry \
			-p 5005:5000 \
			-e OTEL_TRACES_EXPORTER=none \
			-e REGISTRY_PROXY_REMOTEURL=https://registry.gitlab.com \
			registry:3; \
	fi
	@if ! k3d registry list | grep -q "k3d-local-registry"; then \
		echo "Creating local registry..."; \
		k3d registry create local-registry \
			-i registry:3 \
			-p 5010 \
			--default-network k3d-network \
			-v ${REGISTRY_LOCAL_CACHE}:/var/lib/registry; \
	fi
	@echo "Registries are ready!"

# Create cluster
create:
	@echo "Creating cluster..."
	@K3D_FIX_DNS=0 k3d cluster create --config $(CLUSTER_NAME).yaml

# Delete cluster
delete:
	@echo "Deleting cluster..."
	@k3d cluster delete $(CLUSTER_NAME) 2>/dev/null || true
	@echo "Deleting cluster storage..."
	@rm -rf $(K3S_STORAGE_PATH)/*

# Recreate cluster
recreate: delete create

# Full cleanup (cluster + registries)
cleanup:
	@echo "Cleaning up everything including registries..."
	@$(MAKE) delete
	@docker stop k3d-docker-io 2>/dev/null || true
	@docker stop k3d-ghcr-io 2>/dev/null || true
	@docker stop k3d-gitlab-com 2>/dev/null || true

# Additional useful targets
.PHONY: start stop status logs

# Start cluster
start:
	@echo "Starting cluster..."
	@k3d cluster start $(CLUSTER_NAME)

# Stop cluster
stop:
	@echo "Stopping cluster..."
	@k3d cluster stop $(CLUSTER_NAME)

# Cluster status
status:
	@echo "Cluster status:"
	@k3d cluster list
	@echo ""
	@echo "Container status:"
	@docker ps | awk 'NR==1 || /k3d-/'

# Create directories for registry caches
.PHONY: init-dirs

init-dirs:
	@echo "Creating necessary directories..."
	@mkdir -p $(REGISTRY_DOCKERHUB_CACHE)
	@mkdir -p $(REGISTRY_GHCR_CACHE)
	@mkdir -p $(REGISTRY_GITLAB_CACHE)
	@mkdir -p $(REGISTRY_LOCAL_CACHE)
	@mkdir -p $(K3S_STORAGE_PATH)
	@echo "Directories created!"

# Full initialization (create directories + configure registries)
.PHONY: init

init: init-dirs setup
	@echo "Initialization complete!" 