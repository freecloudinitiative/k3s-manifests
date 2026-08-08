# Application Manifests

This directory contains user-facing application workloads and synthetic workload generators deployed to the K3s cluster.

## Applications Overview

| Application | Type | Description |
| :--- | :--- | :--- |
| **`backend`** | Helm Chart / Manifests | Core API backend service providing application logic and nodeport endpoints. |
| **`frontend`** | Helm Chart / Manifests | User web interface connected to the backend service. |
| **`log-generator`** | Workload Generator | Synthetic application continuously emitting structured logs for Loki & Grafana testing. |
| **`metric-generator`** | Workload Generator | Synthetic workload exposing Prometheus metrics to validate observability pipelines. |

## Deployment & Argo CD Sync

- Applications in this directory are managed by Argo CD through the `applications` App-of-Apps manifest.
- Each workload utilizes Helm charts or raw Kubernetes manifests with automated deployment triggers on Git commits.
