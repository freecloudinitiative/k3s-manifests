# Application Manifests

FCI product workloads. Each folder is an ArgoCD `Application` plus the Helm
chart it renders. Source is this repo (`applications/<name>`), not the
service GitHub repo.

## Applications

- **api-gateway**: HTTP reverse proxy + auth gateway. Auto-sync on.
- **compute-service**: VM lifecycle. Auto-sync off until a real image tag exists.
- **database-service**: Customer CNPG management. Auto-sync on. Image still `ghcr.io`.
- **iam-service**: Identity and access management. Auto-sync off until a real image tag exists.
- **storage-service**: Garage S3-backed object storage management. Auto-sync on.
- **terminal-gateway**: WebSocket-to-Kubernetes exec proxy. Auto-sync on.
- **frontend**: React SPA + nginx. Namespace `frontend`. Auto-sync on.

Image tag is a Helm parameter on each `app.yaml`. See
[ARCHITECTURE.md § Application Image Promotion](../ARCHITECTURE.md).
Secret contracts live in [APPS.md](../APPS.md).
