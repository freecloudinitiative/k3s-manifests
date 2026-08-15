# Free Cloud Initiative - K3s Manifests

This repository contains Kubernetes (K3s) manifests and Helm chart configurations managed via GitOps (ArgoCD) for the Free Cloud Initiative infrastructure and application stack.

## 🛠 Features & Components

- **GitOps Management**: Applications and infrastructure managed declaratively using ArgoCD.
- **Ingress & Routing**: Traefik Ingress Controller with custom middlewares (Authentication, Rate Limiting).
- **Security & TLS**: `cert-manager` for self-signed and Let's Encrypt SSL/TLS certificates.
- **Secrets Management**: External Secrets Operator syncing secrets securely from OpenBao (Vault).
- **Identity**: Authentik with a declarative public OIDC client for the frontend.
- **Platform Data**: CloudNativePG-managed, TLS-enabled PostgreSQL with separate application roles and databases.
- **Ephemeral Data**: Valkey (Redis protocol) for cache, distributed rate limits, and backend Pub/Sub.
- **Persistent Volumes**: Longhorn CSI storage with separate replicated and node-local storage classes.
- **Object Storage**: Garage provides a private, three-node S3-compatible object store.
- **Observability**: Complete monitoring & logging pipeline using `kube-prometheus-stack` (Prometheus & Grafana).

## 🚀 Getting Started

### Prerequisites

- Active **K3s** / Kubernetes cluster.
- **ArgoCD** installed and watching this repository (App-of-Apps pattern).
- `kubectl` and `helm` CLI tools installed locally.

### Deploying Workloads

ArgoCD automatically reconciles and syncs changes committed to this repository.

1. Ensure infrastructure dependencies are deployed via `infrastructure/`.
2. Apply application manifests or ArgoCD Application definitions located under `applications/`.

See [`infrastructure/README.md`](infrastructure/README.md) for the required
OpenBao bootstrap variables, component order, OIDC settings, and the mandatory
off-cluster PostgreSQL backup step.

## 📜 License

This project is part of the Free Cloud Initiative.
