# k3d-argocd-sandbox

A sandbox environment with k3d and ArgoCD to learn and experiment with GitOps capabilities.

This project provides a complete local Kubernetes development environment using k3d (Kubernetes in Docker) with ArgoCD for continuous deployment. It includes proxy registries for Docker Hub, GHCR, Quay.io, and GitLab, as well as a self-managed ArgoCD setup using the App of Apps pattern with workload applications including monitoring, logging, and secrets management.

## Prerequisites

- [Docker](https://docs.docker.com/) installed and running
- [k3d](https://k3d.io/) installed (`brew install k3d` or follow [k3d installation guide](https://k3d.io/))
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- [helm](https://helm.sh/docs/) installed
- [kubeseal](https://github.com/bitnami-labs/sealed-secrets) installed (required for creating sealed secrets)
  - macOS: `brew install kubeseal`
  - Linux: Download from [releases page](https://github.com/bitnami-labs/sealed-secrets/releases)
  - Or install via Krew: `kubectl krew install sealed-secrets`
- [k9s](https://k9scli.io/) or [Lens](https://k8slens.dev/) (optional, for cluster visualization)
- [git-crypt](https://github.com/AGWA/git-crypt) (required for secrets management)

## Deployment Process

Follow these steps in order to set up and deploy the complete environment.

### Step 1: Initialize Environment

```sh
make init
```

**What it does:**

- Creates necessary directories for registry caches and k3s storage
- Sets up proxy registries for Docker Hub, GHCR, Quay.io, GitLab, and a local registry
- Creates a Docker network (`k3d-network`) for registry communication

**Result:**

- Directories created: `registry/dockerhub`, `registry/ghcr`, `registry/quay`, `registry/gitlab`, `registry/local`, `k3s-storage`
- Five proxy registry containers running:
  - `k3d-docker-io` on port 5000 (Docker Hub proxy)
  - `k3d-ghcr-io` on port 5001 (GHCR proxy)
  - `k3d-quay-io` on port 5002 (Quay.io proxy)
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
- Installs ArgoCD version 9.1.4 in the `argocd` namespace
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
- Use this password to log in to ArgoCD UI at [http://localhost:9999](http://localhost:9999)
- Username: `admin`
- Password: (the output from this command)

### Step 7: Bootstrap ArgoCD Applications

```sh
make argo-bs
```

**What it does:**

- Deploys the bootstrap Application that uses the App of Apps pattern
- The bootstrap Application references `argocd/config` in the Git repository (branch: `library`)
- This triggers the deployment of:
  - **Self-managed ArgoCD configuration** (`argocd/self`) - ArgoCD managing itself
  - **Workload applications** (`argocd/workload`) - Monitoring, logging, and secrets management stack

**Result:**

- ArgoCD Application `argocd-bootstrap` is created in the `argocd` namespace
- ArgoCD will sync and deploy applications using the App of Apps pattern
- The following workload components will be deployed:
  - **Sealed Secrets Controller** - For managing encrypted secrets in Git
  - **Reloader** - Automatically reload pods when ConfigMaps or Secrets change
  - **Fluent Bit** - Log collection and forwarding
  - **Victoria Logs Single** - Centralized log aggregation
  - **Victoria Metrics Stack** - Metrics collection and visualization (includes Grafana)
- You can monitor the deployment in the ArgoCD UI

### Step 8: Set Up Sealed Secrets

```sh
make ss-key
```

**What it does:**

- Retrieves the public key from the Sealed Secrets controller running in the `workload` namespace
- Saves it to `secrets/in-cluster/ss-pub-key.pem`
- This key is used to encrypt secrets before committing them to Git

**Result:**

- Public key file `secrets/in-cluster/ss-pub-key.pem` is created
- This key is safe to commit to Git (it's public and used for encryption only)

### Step 9: Create Sealed Secrets

```sh
git-crypt unlock
make ss
```

**What it does:**

- Executes the `secrets/create_secrets.sh` script
- Reads secrets from the `secrets/in-cluster/workload/vault/` directory
- Encrypts them using the Sealed Secrets public key
- Creates SealedSecret resources that can be safely committed to Git

**Result:**

- SealedSecret resources are created in the cluster
- The Sealed Secrets controller will decrypt them and create regular Kubernetes secrets
- Secrets are now managed through GitOps

### Step 10: Access Grafana

After the Victoria Metrics Stack is deployed, you can access Grafana:

```sh
make grafana-pw
```

**What it does:**

- Retrieves the Grafana admin password from the `workload` namespace

**Result:**

- Displays the Grafana admin password
- Access Grafana at [http://localhost:3000](http://localhost:3000)
- Username: `admin`
- Password: (the output from this command)

## Architecture Overview

### Cluster Components

- **K3D Cluster**: Single-node Kubernetes cluster (1 server, 0 agents) running k3s v1.31.5
- **Proxy Registries**: Local caching proxies for faster image pulls:
  - Docker Hub (port 5000)
  - GitHub Container Registry (port 5001)
  - Quay.io (port 5002)
  - GitLab (port 5005)
  - Local registry (port 5010)
- **ArgoCD**: GitOps continuous deployment tool (version 9.1.4)
- **Sealed Secrets**: Encrypted secrets that can be safely stored in Git

### Application Patterns

The project uses the **App of Apps** pattern with two main application groups:

1. **Self-Managed ArgoCD** (`argocd/self`): ArgoCD managing its own configuration
2. **Workload Applications** (`argocd/workload`): Production-ready stack including:
   - **Sealed Secrets Controller**: Encrypted secrets management
   - **Reloader**: Automatic pod reloading on ConfigMap/Secret changes
   - **Fluent Bit**: Log collection and forwarding
   - **Victoria Logs Single**: Centralized log aggregation and storage
   - **Victoria Metrics Stack**: Metrics collection, storage, and visualization (includes Grafana)

### Port Mappings

- `80`: HTTP traffic (loadbalancer)
- `443`: HTTPS traffic (loadbalancer)
- `3000`: Grafana (mapped from 30030)
- `5000`: Docker Hub registry proxy
- `5001`: GHCR registry proxy
- `5002`: Quay.io registry proxy
- `5005`: GitLab registry proxy
- `5010`: Local registry
- `8080`: Frontend service (mapped from 30080)
- `8090`: Backend service (mapped from 30090)
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
make argo-bs     # Bootstrap ArgoCD applications (App of Apps)
make port        # Port-forward ArgoCD UI
make argo-pw     # Get ArgoCD admin password
make grafana-pw  # Get Grafana admin password
```

### Secrets Management

```sh
make ss-key      # Get sealed secrets public key
make ss          # Create sealed secrets from encrypted files
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

### ArgoCD UI not accessible at http://localhost:9999

```sh
kubectl get svc -n argocd
make port
```

### Applications not syncing

```sh
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd
kubectl get pods -n workload
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

## Documentation References

### Core Tools

- **[k3d](https://k3d.io/)** - Kubernetes in Docker, lightweight wrapper to run k3s in Docker
  - Official documentation: [https://k3d.io/](https://k3d.io/)

- **[k3s](https://k3s.io/)** - Lightweight Kubernetes distribution
  - Official documentation: [https://docs.k3s.io/](https://docs.k3s.io/)

- **[ArgoCD](https://argo-cd.readthedocs.io/)** - Declarative GitOps continuous delivery tool
  - Official documentation: [https://argo-cd.readthedocs.io/](https://argo-cd.readthedocs.io/)

### Kubernetes Tools

- **[kubectl](https://kubernetes.io/docs/reference/kubectl/)** - Kubernetes command-line tool
  - Official documentation: [https://kubernetes.io/docs/reference/kubectl/](https://kubernetes.io/docs/reference/kubectl/)
  - Installation guide: [https://kubernetes.io/docs/tasks/tools/](https://kubernetes.io/docs/tasks/tools/)

- **[Helm](https://helm.sh/)** - The Kubernetes Package Manager
  - Official documentation: [https://helm.sh/docs/](https://helm.sh/docs/)

### Additional Tools

- **[Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)** - Encrypted Kubernetes secrets
  - GitHub repository: [https://github.com/bitnami-labs/sealed-secrets](https://github.com/bitnami-labs/sealed-secrets)
  - kubeseal CLI: Used to encrypt secrets using the Sealed Secrets controller public key

- **[git-crypt](https://github.com/AGWA/git-crypt)** - Transparent git file encryption
  - GitHub repository: [https://github.com/AGWA/git-crypt](https://github.com/AGWA/git-crypt)

- **[k9s](https://k9scli.io/)** - Terminal UI for Kubernetes
  - Official documentation: [https://k9scli.io/](https://k9scli.io/)

- **[Lens](https://k8slens.dev/)** - Kubernetes IDE
  - Official documentation: [https://docs.k8slens.dev/](https://docs.k8slens.dev/)
