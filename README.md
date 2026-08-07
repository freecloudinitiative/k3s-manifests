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

## Infrastructure Services External Access (NodePorts)

All core infrastructure services are exposed via NodePort services. You can access them directly using your Master Node's Public IP (`http://<MASTER_PUBLIC_IP>:<NODE_PORT>`):

| Service | Namespace | NodePort | Protocol | Description & Access URL |
| :--- | :--- | :--- | :--- | :--- |
| **Argo CD UI** | `argocd` | `30443` | HTTPS | `https://<MASTER_PUBLIC_IP>:30443` |
| **Grafana** | `monitoring` | `30001` | HTTP | `http://<MASTER_PUBLIC_IP>:30001` |
| **Prometheus** | `monitoring` | `30090` | HTTP | `http://<MASTER_PUBLIC_IP>:30090` |
| **OpenBao UI/API** | `openbao` | `30200` | HTTP | `http://<MASTER_PUBLIC_IP>:30200` |
| **Docker Registry API** | `docker-registry` | `30500` | HTTP | `http://<MASTER_PUBLIC_IP>:30500` |
| **Traefik Dashboard** | `traefik` | `30900` | HTTP | `http://<MASTER_PUBLIC_IP>:30900/dashboard/` |
| **Grafana Alloy UI** | `monitoring` | `31234` | HTTP | `http://<MASTER_PUBLIC_IP>:31234` |

