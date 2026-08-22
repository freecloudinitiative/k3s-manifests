# k3s-manifests

## What Code Do

GitOps source of truth for the FCI Kubernetes cluster. Everything that runs in the cluster is declared here.

ArgoCD watches this repo. Any change pushed here is automatically applied to the cluster. Nothing runs in the cluster that isn't in this repo.

Three folders:

- **`infrastructure/`** — platform-level tools: ingress, TLS, storage, secrets, databases, observability, identity, image registry, policy engine.
- **`applications/`** — what ArgoCD is told: one `app.yaml` per FCI product service.
- **`charts/`** — what ArgoCD renders: application Helm charts. Empty until charts move here from service repos.

`applications/` and `infrastructure/` each contain one sub-folder per app. Each app has an `app.yaml` — an ArgoCD `Application` manifest that tells ArgoCD where to find the app's Helm chart or raw manifests. Application charts themselves live under `charts/<service>/`, not next to `app.yaml`.

## Why Need It

Bare-metal cluster has no cloud provider. Every piece of infrastructure (load balancer, TLS, storage, secrets, observability) must be explicitly installed and configured.

Having everything in one Git repo means:
- Single place to change anything.
- ArgoCD auto-syncs — no manual `kubectl apply`.
- Accidental drift gets self-healed automatically.
- Full cluster state is recoverable from this repo alone.

## Prerequisites

OpenBao is **not** deployed by this repo and must already be running, initialised, and unsealed
before the first ArgoCD sync.

- Its Service must resolve at `openbao-active.openbao.svc.cluster.local:8200` — this is hardcoded
  in [infrastructure/external-secrets/cluster-store.yaml](infrastructure/external-secrets/cluster-store.yaml)
  and must match whatever provisions OpenBao out of band.
- The `openbao` namespace and a Kubernetes auth role/mount granting the `external-secrets-openbao`
  ServiceAccount (namespace `external-secrets`) read access must exist in OpenBao — see
  [infrastructure/external-secrets/service-account.yaml](infrastructure/external-secrets/service-account.yaml)
  and [rbac.yaml](infrastructure/external-secrets/rbac.yaml).
- Every `ExternalSecret` in this repo fails closed (`SecretSyncedError`, indefinitely, with no other
  signal) without it, and every pod mounting a Secret then fails to start. See
  [ARCHITECTURE.md § Secret Flow](ARCHITECTURE.md) for the full key inventory to seed.

## How Start

This repo is not applied manually. The `ansible-automation` playbook bootstraps ArgoCD, which then picks up this repo automatically.

**Step 1 — Run the ansible-automation playbook.**

The `argocd-bootstrap` role (called from `playbook.yml`) does three things:
1. Waits for the ArgoCD `Application` CRD to be ready.
2. Renders `root-app.yaml` from the `root-app.yaml.j2` template.
3. Applies `root-app.yaml` to the cluster.

```bash
# From ansible-automation repo root
ansible-playbook playbook.yml --ask-vault-pass
```

**Step 2 — ArgoCD takes over.**

The `root-app` Application points ArgoCD at this repo:

- Source repo: `https://github.com/freecloudinitiative/k3s-manifests.git` (configured in `argocd-bootstrap/defaults/main.yml`)
- Watches two paths: `infrastructure/` (matches `*/app*.yaml` + `namespaces/*.yaml`) and `applications/` (matches `*/app*.yaml`)
- Sync: automated, prune, selfHeal

From this point, any push to this repo is applied to the cluster automatically.

**To add a new app after bootstrap:**

```bash
# 1. Create a folder under applications/ or infrastructure/
mkdir applications/my-service

# 2. Create app.yaml
cat > applications/my-service/app.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-service
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: 'https://github.com/freecloudinitiative/my-service.git'
    targetRevision: HEAD
    path: deploy
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: backend
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# 3. Push — ArgoCD picks it up within seconds
git add . && git commit -m "add my-service" && git push
```

**To validate charts and manifests locally:**

Install Helm, yamllint, kubeconform, and the helm-unittest plugin, then:

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest.git --version v1.1.2
# Helm 4: add --verify=false (git plugin installs have no GPG webhook).
make validate
```

`make validate` lints YAML, lints and renders every Helm chart, schema-checks rendered output with kubeconform, and runs helm-unittest suites under `charts/`. This repo is YAML-only — no Go, no `go.mod`. See [CHARTS.md](CHARTS.md) for the chart-authoring contract.

**To add a new namespace:**

```bash
cat > infrastructure/namespaces/my-namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: my-namespace
EOF
git add . && git commit -m "add my-namespace namespace" && git push
```

## Language

YAML. Helm charts and values files. Jinja2 templates (in the `cloudflared` inline chart). Makefile shells out to yamllint, helm, kubeconform, and helm-unittest. No Go.

## Folders

```
Makefile              Local validation: lint, template, schema, unittest.
CHARTS.md             Chart-authoring contract: where charts live, tests/, YAML-only rule.

charts/               Application Helm charts. Destination for service charts; empty until they move here.

infrastructure/
  namespaces/         Namespace definitions. Applied first (sync-wave -1).
  metallb/            Bare-metal load balancer (L2 mode, IP pool 192.168.1.100-120).
  cert-manager/       TLS certificate lifecycle. 3 issuers: self-signed, private CA, Let's Encrypt.
  longhorn/           Distributed block storage. 2 StorageClasses.
  traefik/            Ingress controller + routing rules for all UI paths.
  external-secrets/   Syncs secrets from OpenBao → Kubernetes Secrets.
  kyverno/            Policy admission controller.
  kyverno-policies/   4 cluster policies enforcing image pinning, resource limits, non-root, registry.
  platform-postgresql/ 3-instance CNPG Postgres cluster (shared by all platform services).
  valkey/             Redis-compatible cache with TLS + ACL.
  garage/             S3-compatible object storage, 3-replica distributed.
  authentik/          OIDC identity provider.
  cloudflared/        Cloudflare tunnel — exposes public endpoints without port forwarding.
  zot-registry/       OCI container image registry backed by Garage S3.
  argocd/             ArgoCD self-configuration (ArgoCD manages itself).
  kube-prometheus-stack/ Prometheus + Grafana + Alertmanager.
  loki/               Log aggregation.
  tempo/              Distributed tracing backend.
  opentelemetry/      OTel Collector — receives traces/logs, forwards to Tempo/Loki.
  alloy/              Grafana Alloy — cluster-wide log and metrics scraper.

applications/
  api-gateway/        Reverse proxy + auth gateway for all FCI backend services.
  compute-service/    VM lifecycle management service.
  database-service/   CNPG-backed database management service.
  iam-service/        Identity and access management service.
  storage-service/    Garage S3-backed object storage service.
  terminal-gateway/   WebSocket-to-Kubernetes exec terminal proxy.
```

## Read More

- [CHARTS.md](CHARTS.md) — where application charts live and how to validate them
- [APPS.md](APPS.md) — what each app does and its key configuration
- [ARCHITECTURE.md](ARCHITECTURE.md) — how all apps connect, sync order, secret flow, traffic flow
- [FILES.md](FILES.md) — every file, one line
