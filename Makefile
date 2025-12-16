# K3D Cluster Manager Makefile

# Variables
CLUSTER_NAME ?= k3d-argocd-sandbox
K3S_MANIFEST_PATH := $(shell pwd)/k3s
K3S_STORAGE_PATH := $(shell pwd)/k3s-storage
REGISTRY_DOCKERHUB_CACHE := $(shell pwd)/registry/dockerhub
REGISTRY_GHCR_CACHE := $(shell pwd)/registry/ghcr
REGISTRY_QUAY_CACHE := $(shell pwd)/registry/quay
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

# All targets
.PHONY: help init init-dirs setup create delete recreate cleanup start stop status \
	helm argo port argo-pw grafana-pw argo-bs test ss-key ss ctx vault vault-cfg

# Default target - show help
help:
	@echo "$(CYAN)╔══════════════════════════════════════════════════════════════╗$(RESET)"
	@echo "$(CYAN)║                    $(YELLOW)K3D Cluster Manager$(CYAN)                       ║$(RESET)"
	@echo "$(CYAN)╚══════════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@echo "$(GREEN)Usage:$(RESET) make $(PURPLE){target}$(RESET)"
	@echo ""
	@echo "$(YELLOW)Cluster Management:$(RESET)"
	@echo "  $(PURPLE)init$(RESET)       $(GRAY)└─$(RESET) Create directories and configure registries"
	@echo "  $(PURPLE)init-dirs$(RESET)  $(GRAY)└─$(RESET) Create necessary directories"
	@echo "  $(PURPLE)setup$(RESET)      $(GRAY)└─$(RESET) Create proxy registries"
	@echo "  $(PURPLE)create$(RESET)     $(GRAY)└─$(RESET) Create K3D cluster with all configurations"
	@echo "  $(PURPLE)delete$(RESET)     $(GRAY)└─$(RESET) Delete cluster (keep registries)"
	@echo "  $(PURPLE)recreate$(RESET)   $(GRAY)└─$(RESET) Recreate cluster (keep registries)"
	@echo "  $(PURPLE)cleanup$(RESET)    $(GRAY)└─$(RESET) Delete everything including registries"
	@echo "  $(PURPLE)start$(RESET)      $(GRAY)└─$(RESET) Start cluster"
	@echo "  $(PURPLE)stop$(RESET)       $(GRAY)└─$(RESET) Stop cluster"
	@echo "  $(PURPLE)status$(RESET)     $(GRAY)└─$(RESET) Show cluster and container status"
	@echo ""
	@echo "$(YELLOW)ArgoCD:$(RESET)"
	@echo "  $(PURPLE)helm$(RESET)       $(GRAY)└─$(RESET) Add and update ArgoCD Helm repository"
	@echo "  $(PURPLE)argo$(RESET)       $(GRAY)└─$(RESET) Deploy ArgoCD via Helm"
	@echo "  $(PURPLE)port$(RESET)       $(GRAY)└─$(RESET) Port forward ArgoCD server (localhost:9999)"
	@echo "  $(PURPLE)argo-bs$(RESET)    $(GRAY)└─$(RESET) Bootstrap ArgoCD"
	@echo "  $(PURPLE)argo-pw$(RESET)    $(GRAY)└─$(RESET) Get ArgoCD admin password"
	@echo "  $(PURPLE)grafana-pw$(RESET) $(GRAY)└─$(RESET) Get Grafana admin password"
	@echo ""
	@echo "$(YELLOW)Secrets:$(RESET)"
	@echo "  $(PURPLE)ss-key$(RESET)     $(GRAY)└─$(RESET) Get sealed secrets public key"
	@echo "  $(PURPLE)ss$(RESET)         $(GRAY)└─$(RESET) Create sealed secrets"
	@echo "  $(PURPLE)vault$(RESET)      $(GRAY)└─$(RESET) Init & unseal Vault cluster in 'workload' namespace"
	@echo "  $(PURPLE)vault-cfg$(RESET)  $(GRAY)└─$(RESET) Configure Vault: enable Kubernetes auth, create policies and roles"
	@echo ""
	@echo "$(YELLOW)Testing:$(RESET)"
	@echo "  $(PURPLE)test$(RESET)       $(GRAY)└─$(RESET) Test applications (http://localhost:8090)"
	@echo ""
	@echo "$(YELLOW)Help:$(RESET)"
	@echo "  $(PURPLE)help$(RESET)       $(GRAY)└─$(RESET) Show this help message"
	@echo ""
	@echo "$(RED)Example:$(RESET) make $(PURPLE)init$(RESET)"
	@echo ""
	@echo "$(YELLOW)Environment variables:$(RESET)"
	@echo "  $(PURPLE)CLUSTER_NAME$(RESET)              $(GRAY)└─$(RESET) Cluster name (default: k3d-argocd-sandbox)"
	@echo "  $(PURPLE)K3S_MANIFEST_PATH$(RESET)         $(GRAY)└─$(RESET) Path to k3s manifests (default: ./k3s)"
	@echo "  $(PURPLE)K3S_STORAGE_PATH$(RESET)          $(GRAY)└─$(RESET) Path to storage (default: ./k3s-storage)"
	@echo "  $(PURPLE)REGISTRY_DOCKERHUB_CACHE$(RESET)  $(GRAY)└─$(RESET) Docker Hub cache path (default: ./registry/dockerhub)"
	@echo "  $(PURPLE)REGISTRY_GHCR_CACHE$(RESET)       $(GRAY)└─$(RESET) GitHub Container Registry cache path (default: ./registry/ghcr)"
	@echo "  $(PURPLE)REGISTRY_QUAY_CACHE$(RESET)       $(GRAY)└─$(RESET) Quay.io cache path (default: ./registry/quay)"
	@echo "  $(PURPLE)REGISTRY_GITLAB_CACHE$(RESET)     $(GRAY)└─$(RESET) GitLab cache path (default: ./registry/gitlab)"
	@echo "  $(PURPLE)REGISTRY_LOCAL_CACHE$(RESET)      $(GRAY)└─$(RESET) Local registry cache path (default: ./registry/local)"
	@echo ""

# ============================================================================
# Cluster Management Targets
# ============================================================================

# Create necessary directories
init-dirs:
	@echo "Creating necessary directories..."
	@mkdir -p $(REGISTRY_DOCKERHUB_CACHE)
	@mkdir -p $(REGISTRY_GHCR_CACHE)
	@mkdir -p $(REGISTRY_QUAY_CACHE)
	@mkdir -p $(REGISTRY_GITLAB_CACHE)
	@mkdir -p $(REGISTRY_LOCAL_CACHE)
	@mkdir -p $(K3S_STORAGE_PATH)
	@echo "Directories created!"

# Full initialization (create directories + configure registries)
init: init-dirs setup
	@echo "Initialization complete!"

# Create proxy registries for Docker Hub, GHCR, GitLab, and local registry
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
	@if ! docker ps | grep -q "k3d-quay-io"; then \
		echo "Creating Quay.io proxy registry..."; \
		docker run -d --rm \
			--name k3d-quay-io \
			--network k3d-network \
			-v ${REGISTRY_QUAY_CACHE}:/var/lib/registry \
			-p 5002:5000 \
			-e OTEL_TRACES_EXPORTER=none \
			-e REGISTRY_PROXY_REMOTEURL=https://quay.io \
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
	@docker stop k3d-quay-io 2>/dev/null || true
	@docker stop k3d-gitlab-com 2>/dev/null || true
	@docker stop k3d-local-registry 2>/dev/null || true

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

# ============================================================================
# Kubernetes Context Target
# ============================================================================

# Set kubectl context to k3d cluster
ctx:
	@kubectl config use-context k3d-$(CLUSTER_NAME)

# ============================================================================
# ArgoCD Targets
# ============================================================================

# Add and update ArgoCD Helm repository
helm: ctx
	@echo "Adding ArgoCD Helm repository..."
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo update argo

# Deploy ArgoCD via Helm
argo: ctx
	@echo "Deploying ArgoCD..."
	helm install argocd argo/argo-cd -n argocd --version 9.1.4 --create-namespace -f argocd/values.yaml

# Bootstrap ArgoCD
argo-bs: ctx
	@echo "Bootstrap ArgoCD..."
	kubectl apply -f argocd/bootstrap.yaml

# Port forward ArgoCD server
port: ctx
	@echo "Port forwarding ArgoCD server..."
	kubectl port-forward svc/argocd-server -n argocd 9999:80

# Get ArgoCD admin password
argo-pw: ctx
	@echo "Getting ArgoCD admin password..."
	kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d

# Get Grafana admin password
grafana-pw: ctx
	@echo "Getting Grafana admin password..."
	kubectl get secret -n workload vica-metrics-stack-grafana -o json | jq -r '.data["admin-password"]' | base64 -d

# ============================================================================
# Secrets Targets
# ============================================================================

# Init & unseal Vault cluster in 'workload' namespace using stored keys
vault: ctx
	@echo "Initializing and unsealing Vault cluster in 'workload' namespace..."
	@mkdir -p .debug
	@VAULT_KEYS_FILE=.debug/vault-workload-keys.json; \
	if [ ! -f $$VAULT_KEYS_FILE ]; then \
		echo "Vault keys file not found, initializing Vault and saving keys to $$VAULT_KEYS_FILE..."; \
		kubectl exec vault-0 -n workload -- vault operator init \
			-key-shares=4 \
			-key-threshold=2 \
			-format=json > $$VAULT_KEYS_FILE; \
	else \
		echo "Using existing Vault keys from $$VAULT_KEYS_FILE"; \
	fi; \
	KEY1=$$(jq -r '.unseal_keys_b64[0]' $$VAULT_KEYS_FILE); \
	KEY2=$$(jq -r '.unseal_keys_b64[1]' $$VAULT_KEYS_FILE); \
	echo "Unsealing vault-0..."; \
	kubectl exec vault-0 -n workload -- vault operator unseal $$KEY1; \
	kubectl exec vault-0 -n workload -- vault operator unseal $$KEY2; \
	echo "Joining vault-1 to raft cluster..."; \
	kubectl exec -ti vault-1 -n workload -- vault operator raft join http://vault-0.vault-internal.workload:8200; \
	echo "Unsealing vault-1..."; \
	kubectl exec vault-1 -n workload -- vault operator unseal $$KEY1; \
	kubectl exec vault-1 -n workload -- vault operator unseal $$KEY2; \
	echo "Joining vault-2 to raft cluster..."; \
	kubectl exec -ti vault-2 -n workload -- vault operator raft join http://vault-0.vault-internal.workload:8200; \
	echo "Unsealing vault-2..."; \
	kubectl exec vault-2 -n workload -- vault operator unseal $$KEY1; \
	kubectl exec vault-2 -n workload -- vault operator unseal $$KEY2; \
	echo "Vault cluster is initialized and unsealed."

# Configure Vault: enable Kubernetes auth, create policies and roles
vault-cfg: ctx
	@./extra/vault/vault-cfg.sh

# Get sealed secrets public key
ss-key: ctx
	@echo "Get sealed secrets public key..."
	kubectl -n workload get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o jsonpath='{.items[0].data.tls\.crt}' | base64 -d > ./secrets/in-cluster/ss-pub-key.pem

# Create sealed secrets
ss:
	@echo "Creating sealed secrets..."
	@cd $(shell pwd)/secrets && chmod +x create_secrets.sh && ./create_secrets.sh

# ============================================================================
# Testing Targets
# ============================================================================

# Test applications
test:
	@echo "Testing applications..."
	curl http://localhost:8090/