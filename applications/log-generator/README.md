# Log Generator Application (Flog)

This application deploys [flog](https://github.com/mingrammer/flog), a fake log generator for common log formats (Apache, RFC3164/RFC5424 Syslog, JSON, etc.) to test log collection pipelines (e.g. Promtail, Loki, Fluentd).

---

## ⚠️ Architecture Compatibility Note (ARM64 Support)

The upstream `mingrammer/flog:0.4.3` image on Docker Hub is compiled exclusively for **`linux/amd64`**. If deployed on an **ARM64** Kubernetes cluster (e.g., GCP Tau T2A, AWS Graviton, Apple Silicon, Raspberry Pi), the container fails with:

```text
exec /bin/flog: exec format error
```

To resolve this issue, `flog` must be compiled natively for **`linux/arm64`** and pushed to the cluster's internal Docker registry (`docker-registry`).

---

## 🛠️ Step-by-Step ARM64 Build & Deployment Guide

### 1. Build and Push the ARM64 Image to Internal Registry

Run these commands from a machine with access to your cluster:

```bash
# 1. Clone the flog source code repository
git clone https://github.com/mingrammer/flog.git
cd flog

# 2. Build for linux/arm64 and push to internal registry via NodePort 30500
docker buildx build --platform linux/arm64 \
  -t $(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'):30500/flog:0.4.3 \
  --push .
```

> **Note:** If running from outside the cluster network/VPN, use `ExternalIP` instead of `InternalIP`:
>
> ```bash
> docker buildx build --platform linux/arm64 \
>   -t $(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}'):30500/flog:0.4.3 \
>   --push .
> ```

---

### 2. Configure `values.yaml`

Ensure `applications/log-generator/values.yaml` points to the internal cluster registry DNS:

```yaml
image:
  repository: docker-registry.docker-registry.svc:5000/flog
  tag: 0.4.3
  pullPolicy: IfNotPresent

format: json
delay: 1s
loop: true
```

---

### 3. Verify Deployment

Verify that the pod starts cleanly:

```bash
kubectl get pods -n log-generator
kubectl logs -n log-generator -l app=log-generator -f
```
