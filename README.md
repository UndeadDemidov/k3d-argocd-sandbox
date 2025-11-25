# k3d-argocd-sandbox

A sandbox environment with k3d and ArgoCD to learn and experiment with GitOps capabilities.

This project provides a complete local Kubernetes development environment using k3d (Kubernetes in Docker) with ArgoCD for continuous deployment. It includes proxy registries for Docker Hub, GHCR, and GitLab, as well as examples of both managed and unmanaged ArgoCD applications.

## Prerequisites

- Docker installed and running
- k3d installed (`brew install k3d` or follow [k3d installation guide](https://k3d.io/))
- kubectl installed
- helm installed
- k9s or Lens (optional, for cluster visualization)

## Deployment Process

Follow these steps in order to set up and deploy the complete environment.

### Step 1: Initialize Environment

```sh
make init
```

**What it does:**

- Creates necessary directories for registry caches and k3s storage
- Sets up proxy registries for Docker Hub, GHCR, GitLab, and a local registry
- Creates a Docker network (`k3d-network`) for registry communication

**Result:**

- Directories created: `registry/dockerhub`, `registry/ghcr`, `registry/gitlab`, `registry/local`, `k3s-storage`
- Four proxy registry containers running:
  - `k3d-docker-io` on port 5000 (Docker Hub proxy)
  - `k3d-ghcr-io` on port 5001 (GHCR proxy)
  - `k3d-gitlab-com` on port 5005 (GitLab proxy)
  - `k3d-local-registry` on port 5010 (local registry)
- Docker network `k3d-network` created

### Step 2: Create K3D Cluster

```sh
make create
```

**What it does:**

- Creates a k3d Kubernetes cluster named `k3d-argocd-sandbox`
- Configures the cluster to use the proxy registries created in step 1
- Mounts k3s manifests and storage volumes
- Exposes ports for services (80, 443, 8080, 8090, 3000, 9999)

**Result:**

- K3D cluster `k3d-argocd-sandbox` is running
- Cluster is configured with registry mirrors for faster image pulls
- You can verify the cluster with `kubectl get nodes`
- Use `k9s` or Lens to explore the cluster

### Step 3: Verify Cluster

```sh
kubectl get nodes
```

**Expected output:**

```text
NAME                      STATUS   ROLES           AGE   VERSION
k3d-k3d-argocd-sandbox-server-0   Ready    control-plane   1m   v1.31.5+k3s1
```

### Step 4: Deploy ArgoCD

```sh
make argo
```

**What it does:**

- Adds the ArgoCD Helm repository
- Installs ArgoCD version 7.3.9 in the `argocd` namespace
- Creates the `argocd` namespace if it doesn't exist

**Result:**

- ArgoCD is being deployed to the cluster
- ArgoCD components (server, repo-server, application-controller, etc.) are starting
- Wait for all pods to be ready: `kubectl get pods -n argocd -w`

**Wait for ArgoCD to be fully started:**

```sh
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

**Result:**

- All ArgoCD pods are running and ready
- ArgoCD server is accessible within the cluster

### Step 5: Access ArgoCD UI

```sh
make port
```

**What it does:**

- Creates a port-forward from localhost:9999 to the ArgoCD server service (port 80)

**Result:**

- ArgoCD UI is accessible at `http://localhost:9999`
- The port-forward runs in the foreground (keep the terminal open)
- In another terminal, get the admin password (next step)

### Step 6: Get ArgoCD Admin Password

```sh
make argo-pw
```

**What it does:**

- Retrieves the initial admin password from the `argocd-initial-admin-secret` secret
- Decodes the base64-encoded password

**Result:**

- Displays the admin password in the terminal
- Use this password to log in to ArgoCD UI at `http://localhost:9999`
- Username: `admin`
- Password: (the output from this command)

### Step 7: Deploy Unmanaged Applications

```sh
make unmanaged
```

**What it does:**

- Creates the `unmanaged` namespace
- Creates an ArgoCD AppProject named `unmanaged`
- Deploys an Application of Applications (App of Apps) pattern
- The App of Apps references the `argocd/unmanaged/Applications` directory in the Git repository

**Result:**

- ArgoCD Application `unmanaged` is created in the `argocd` namespace
- ArgoCD will sync applications from the Git repository
- Applications will be deployed to the `unmanaged` namespace
- You can see the sync status in the ArgoCD UI

### Step 8: Test Unmanaged Applications

```sh
make test
```

**What it does:**

- Tests the unmanaged applications by making a curl request to `http://localhost:8090/`

**Result:**

- If successful, returns a response from the http-echo service
- The service is accessible on port 8090 (mapped from cluster port 30090)
- This confirms that the unmanaged applications are working correctly

### Step 9: Deploy Managed Applications

```sh
make managed
```

**What it does:**

- Deploys the bootstrap Application that uses the App of Apps pattern
- The bootstrap Application references `argocd/managed/config` in the Git repository
- This triggers the deployment of managed ArgoCD applications including:
  - Self-managed ArgoCD configuration
  - Workload applications with sealed secrets

**Result:**

- ArgoCD Application `argocd-bootstrap-managed` is created
- ArgoCD will sync and deploy managed applications
- The App of Apps pattern will create child applications
- You can monitor the deployment in the ArgoCD UI

### Step 10: Set Up Sealed Secrets

```sh
make ss-key
```

**What it does:**

- Retrieves the public key from the Sealed Secrets controller
- Saves it to `secrets/managed/ss-pub-key.pem`
- This key is used to encrypt secrets before committing them to Git

**Result:**

- Public key file `secrets/managed/ss-pub-key.pem` is created
- This key is safe to commit to Git (it's public and used for encryption only)

### Step 11: Create Sealed Secrets

```sh
git-crypt unlock
make ss
```

**What it does:**

- Executes the `secrets/create_secrets.sh` script
- Reads secrets from the `secrets/managed/workload/vault/` directory
- Encrypts them using the Sealed Secrets public key
- Creates SealedSecret resources that can be safely committed to Git

**Result:**

- SealedSecret resources are created in the cluster
- The Sealed Secrets controller will decrypt them and create regular Kubernetes secrets
- Secrets are now managed through GitOps

### Step 12: Verify Sealed Secrets

```sh
make ss-show
```

**What it does:**

- Retrieves the `managed-secret-example` secret from the `managed` namespace
- Decodes and displays the password value

**Result:**

- Shows the decrypted password from the secret
- Confirms that Sealed Secrets are working correctly
- The secret was created from the SealedSecret resource

## Architecture Overview

### Cluster Components

- **K3D Cluster**: Single-node Kubernetes cluster (1 server, 0 agents)
- **Proxy Registries**: Local caching proxies for faster image pulls
- **ArgoCD**: GitOps continuous deployment tool
- **Sealed Secrets**: Encrypted secrets that can be safely stored in Git

### Application Patterns

1. **Unmanaged Applications**: Applications deployed via ArgoCD but not managed by ArgoCD itself
2. **Managed Applications**: Applications deployed using the App of Apps pattern, including self-managed ArgoCD configuration

### Port Mappings

- `80`: HTTP traffic (loadbalancer)
- `443`: HTTPS traffic (loadbalancer)
- `8080`: Frontend service (mapped from 30080)
- `8090`: Backend service (mapped from 30090)
- `3000`: Grafana (mapped from 30030)
- `9999`: ArgoCD UI port-forward

## Useful Commands

### Cluster Management

```sh
make status      # Show cluster and container status
make start       # Start the cluster
make stop        # Stop the cluster
make delete      # Delete the cluster (keeps registries)
make recreate    # Recreate the cluster (keeps registries)
make cleanup     # Delete everything including registries
```

### ArgoCD Management

```sh
make helm        # Add/update ArgoCD Helm repository
make argo        # Deploy ArgoCD
make port        # Port-forward ArgoCD UI
make argo-pw     # Get admin password
```

## Troubleshooting

### ArgoCD pods not ready

```sh
kubectl get pods -n argocd
kubectl describe pod <pod-name> -n argocd
kubectl logs <pod-name> -n argocd
```

### Registry issues

```sh
docker ps | grep k3d-
make status
```

### Cluster not accessible

```sh
kubectl cluster-info
kubectl get nodes
```

## Cleanup

To completely remove the environment:

```sh
make cleanup
```

This will:

- Delete the k3d cluster
- Stop and remove all proxy registry containers
- Remove cluster storage (but keeps registry caches for faster rebuilds)
