# K3s GitOps Cluster Manifests

This repository manages the entire declarative infrastructure and application lifecycle for a high-availability **K3s Kubernetes cluster** using **Argo CD** and the **GitOps App-of-Apps pattern**.

---

## 🚀 Quick Start / Deployment

### 1. Configure Repository URL
Update the `repoURL` in the bootstrap manifests to point to your Git repository:
- [`infrastructure/argocd/root-app.yaml`](file:///Users/entelektuelmaganda/Repositories/freecloudinitiative/k3s-manifests/infrastructure/argocd/root-app.yaml)

### 2. Commit & Push Changes
```bash
git add .
git commit -m "Update repoURL for bootstrap"
git push origin main
```

### 3. Bootstrap Cluster
Apply the root Argo CD application to initiate GitOps reconciliation for all infrastructure and applications:
```bash
kubectl apply -f infrastructure/argocd/root-app.yaml
```

---

## 📄 Subdirectory Documentation

Detailed documentation for cluster infrastructure components and user applications can be found in their respective directories:

- [Infrastructure Documentation & NodePorts Access](file:///Users/entelektuelmaganda/Repositories/freecloudinitiative/k3s-manifests/infrastructure/README.md)
- [Applications Documentation](file:///Users/entelektuelmaganda/Repositories/freecloudinitiative/k3s-manifests/applications/README.md)
