# K3s GitOps Manifests

This repository manages cluster-wide infrastructure and workloads for a K3s cluster using Argo CD.

## How to Deploy

1. Update the `repoURL` in the bootstrap manifests to point to your Git repository URL:
   - `bootstrap/root-app.yaml`
   - `infrastructure/user-applications/app.yaml`
2. Push your changes to Git.
3. Bootstrap the cluster by applying the root application:
   ```bash
   kubectl apply -f bootstrap/root-app.yaml
   ```
