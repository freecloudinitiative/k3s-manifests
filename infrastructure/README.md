# Infrastructure Manifests

This directory contains the core Kubernetes infrastructure services managed by Argo CD via the App-of-Apps GitOps pattern.

---

## 🌐 Infrastructure NodePorts & External Access

Core platform services are exposed via NodePort services for direct access via your K3s Master Node's Public IP (`http://<MASTER_PUBLIC_IP>:<NODE_PORT>`):

| Service | Namespace | NodePort | Protocol | Access URL |
| :--- | :--- | :--- | :--- | :--- |
| **Argo CD UI** | `argocd` | `30443` | HTTPS | `https://<MASTER_PUBLIC_IP>:30443` |
| **Grafana** | `monitoring` | `30001` | HTTP | `http://<MASTER_PUBLIC_IP>:30001` |
| **Prometheus** | `monitoring` | `30090` | HTTP | `http://<MASTER_PUBLIC_IP>:30090` |
| **OpenBao UI / API** | `openbao` | `30200` | HTTP | `http://<MASTER_PUBLIC_IP>:30200` |
| **Docker Registry API** | `docker-registry` | `30500` | HTTP | `http://<MASTER_PUBLIC_IP>:30500` |
| **Traefik Dashboard** | `traefik` | `30900` | HTTP | `http://<MASTER_PUBLIC_IP>:30900/dashboard/` |
| **Grafana Alloy UI** | `monitoring` | `31234` | HTTP | `http://<MASTER_PUBLIC_IP>:31234` |

---

## 📁 Directory Structure & Services

| Component | Description |
| :--- | :--- |
| **`alloy`** | [Grafana Alloy](https://grafana.com/docs/alloy/latest/) telemetry agent for collecting logs, metrics, and traces. |
| **`argocd`** | Argo CD core configuration, RBAC, ingress routing, and root application declarations. |
| **`cert-manager`** | Certificate management for automated TLS issuance via Let's Encrypt / custom CAs. |
| **`docker-registry`** | In-cluster Docker registry service for container image storage. |
| **`external-secrets`** | External Secrets Operator integration for syncing secrets (e.g., from OpenBao / Vault). |
| **`kube-prometheus-stack`** | Monitoring stack including Prometheus Operator, Prometheus server, and Grafana. |
| **`loki`** | High-performance log aggregation engine. |
| **`metallb`** | Bare-metal load balancer for provisioning `LoadBalancer` service types in K3s. |
| **`namespaces`** | Core Kubernetes namespace definitions (`monitoring`, `openbao`, `argocd`, `traefik`, etc.). |
| **`opentelemetry`** | OpenTelemetry Collector and Operator setup for trace and metric processing. |
| **`tempo`** | High-scale distributed tracing backend. |
| **`traefik`** | Ingress controller and API Gateway handling HTTP/HTTPS routing and NodePort access. |

---

## ⚙️ GitOps Deployment Strategy

- Each subdirectory contains standard Kubernetes manifests or Helm custom resource definitions.
- Argo CD synchronizes these components automatically based on the application manifests defined under `argocd/` and root bootstrap manifests.
- Secret values are injected dynamically using **External Secrets Operator** / **argocd-vault-plugin** to ensure zero plain-text secrets in Git.
