# Infrastructure Manifests

This directory contains the core Kubernetes infrastructure services managed by Argo CD via the App-of-Apps GitOps pattern.

---

## 🌐 Infrastructure Ingress Routing & External Access

Core platform services are exposed over standard HTTP (port `80`) and HTTPS (port `443`) via **Traefik Ingress Controller** using path-based URL suffixes (`http://<MASTER_PUBLIC_IP>/<SUFFIX>`):

| Service               | Namespace    | Ingress Path Suffix | Protocol | Access URL                                    |
| :-------------------- | :----------- | :------------------ | :------- | :-------------------------------------------- |
| **Argo CD UI**        | `argocd`     | `/argocd`           | HTTP     | `http://<MASTER_PUBLIC_IP>/argocd`            |
| **Grafana**           | `monitoring` | `/grafana`          | HTTP     | `http://<MASTER_PUBLIC_IP>/grafana`           |
| **Prometheus**        | `monitoring` | `/prometheus`       | HTTP     | `http://<MASTER_PUBLIC_IP>/prometheus`        |
| **Grafana Alloy UI**  | `monitoring` | `/alloy`            | HTTP     | `http://<MASTER_PUBLIC_IP>/alloy`            |
| **Traefik Dashboard** | `traefik`    | `/traefik-dashboard`| HTTP     | `http://<MASTER_PUBLIC_IP>/traefik-dashboard` |
| **OpenBao UI**        | `openbao`    | `/ui`               | HTTP     | `http://<MASTER_PUBLIC_IP>/ui`                |

---

## 📁 Directory Structure & Services

| Component                   | Description                                                                                                       |
| :-------------------------- | :---------------------------------------------------------------------------------------------------------------- |
| **`alloy`**                 | [Grafana Alloy](https://grafana.com/docs/alloy/latest/) telemetry agent for collecting logs, metrics, and traces. |
| **`argocd`**                | Argo CD core configuration, RBAC, ingress routing, and root application declarations.                             |
| **`cert-manager`**          | Certificate management for automated TLS issuance via Let's Encrypt / custom CAs.                                 |
| **`external-secrets`**      | External Secrets Operator integration for syncing secrets (e.g., from OpenBao / Vault).                           |
| **`kube-prometheus-stack`** | Monitoring stack including Prometheus Operator, Prometheus server, and Grafana.                                   |
| **`loki`**                  | High-performance log aggregation engine.                                                                          |
| **`metallb`**               | Bare-metal load balancer for provisioning `LoadBalancer` service types in K3s.                                    |
| **`namespaces`**            | Core Kubernetes namespace definitions (`monitoring`, `openbao`, `argocd`, `traefik`, etc.).                       |
| **`opentelemetry`**         | OpenTelemetry Collector and Operator setup for trace and metric processing.                                       |
| **`tempo`**                 | High-scale distributed tracing backend.                                                                           |
| **`traefik`**               | Ingress controller and API Gateway handling HTTP/HTTPS routing and NodePort access.                               |

---

## ⚙️ GitOps Deployment Strategy

- Each subdirectory contains standard Kubernetes manifests or Helm custom resource definitions.
- Argo CD synchronizes these components automatically based on the application manifests defined under `argocd/` and root bootstrap manifests.
- Secret values are injected dynamically using **External Secrets Operator** / **argocd-vault-plugin** to ensure zero plain-text secrets in Git.
