# K3s GitOps Manifests

This repository manages cluster-wide infrastructure and workloads for a K3s cluster using Argo CD.

## Repository Structure

* **`bootstrap/`**: Contains the root application (`root-app.yaml`) to initialize GitOps.
* **`infrastructure/`**: Deploys platform charts via Argo CD Applications:
  * Cert-Manager, Kyverno, Sealed Secrets, Linkerd (Service Mesh).
  * Prometheus, Grafana, Loki, Tempo, OpenTelemetry (Monitoring Stack).
  * Gitea, Harbor (Git and Registry).
* **`applications/`**: Holds custom workloads (e.g., the `sample-app` Helm chart).

## How to Deploy

1. Update the `repoURL` in the bootstrap manifests to point to your Git repository:
   - `bootstrap/root-app.yaml`
   - `infrastructure/user-applications.yaml`
2. Push your changes to Git.
3. Bootstrap the cluster by applying the root application:
   ```bash
   kubectl apply -f bootstrap/root-app.yaml
   ```