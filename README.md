# k3s-manifests

## What Code Do

GitOps source of truth for FCI Kubernetes cluster. Everything that runs in
cluster is declared here.

ArgoCD watches this repo. Any change pushed here is applied. Nothing runs
that is not in this repo.

Two folders:

- **`infrastructure/`** — platform tools: ingress, TLS, storage, secrets,
  databases, observability, identity, image registry, policy engine.
- **`applications/`** — FCI product services. Each folder is an ArgoCD
  `app.yaml` plus the Helm chart it renders.

`applications/` and `infrastructure/` each contain one sub-folder per app.
Each app has an `app.yaml` — ArgoCD `Application` that tells ArgoCD where
to find Helm chart or raw manifests. Application charts live next to
`app.yaml` under `applications/<service>/`. No `charts/` directory.

## Why Need It

Bare-metal cluster has no cloud provider. Every infrastructure piece (load
balancer, TLS, storage, secrets, observability) must be installed and
configured here.

One Git repo means:
- Single place to change anything.
- ArgoCD auto-syncs — no manual `kubectl apply`.
- Accidental drift is self-healed.
- Full cluster state is recoverable from this repo alone.

## Container Registry Strategy

All platform workloads pull from the private GitHub Container Registry
organization at `ghcr.io/freecloudinitiative`. External Secrets materializes
`ghcr-pull-credentials` in `backend` and `frontend` from OpenBao.

## Prerequisites

### OpenBao

OpenBao **is** deployed by this repo (via ArgoCD), but it must be manually
initialised and unsealed after the first sync before `external-secrets` can connect.

- Service must resolve at
  `openbao-active.openbao.svc.cluster.local:8200` — hardcoded in
  [infrastructure/external-secrets/cluster-store.yaml](infrastructure/external-secrets/cluster-store.yaml)
  and must match whatever provisions OpenBao out of band.
- `openbao` namespace and a Kubernetes auth role/mount granting
  `external-secrets-openbao` ServiceAccount (namespace `external-secrets`)
  read access must exist in OpenBao — see
  [infrastructure/external-secrets/service-account.yaml](infrastructure/external-secrets/service-account.yaml)
  and [rbac.yaml](infrastructure/external-secrets/rbac.yaml).
- Every `ExternalSecret` in this repo fails closed (`SecretSyncedError`,
  indefinitely, with no other signal) without it, and every pod mounting a
  Secret then fails to start. See
  [ARCHITECTURE.md § Secret Flow](ARCHITECTURE.md) for the key inventory
  to seed.

### Garage

Garage is deployed by ArgoCD, but serves no data until cluster layout is
applied. Bucket `platform` and storage-service key must also exist. Key needs
read/write access on bucket. Access-key ID and secret must exactly match
`GARAGE_ACCESS_KEY` and `GARAGE_SECRET_KEY` values seeded to OpenBao by
`ansible-automation`. Legacy names `GARAGE_STORAGE_SERVICE_ACCESS_KEY` and
`GARAGE_STORAGE_SERVICE_SECRET_KEY` remain accepted.

Export same values, then run bootstrap after Garage pods become Ready:

```bash
./scripts/garage-bootstrap.sh
```

Readiness probe issues `HeadBucket` against configured `OBJECT_STORE_BUCKET`.
Without bootstrap, `storage-service` stays `NotReady`; it does not serve failing
calls. `/api/buckets` and `/api/networks` have no healthy endpoint, and
`compute-service` cannot resolve a backup bucket. Run
`scripts/garage-bootstrap.sh` after Garage pods become Ready, before
`storage-service` is expected to serve.

## How Start

This repo is not applied manually. `ansible-automation` playbook bootstraps
ArgoCD, which then picks up this repo.

**Step 1 — Run ansible-automation playbook.**

`argocd-bootstrap` role (from `playbook.yml`) does three things:
1. Waits for ArgoCD `Application` CRD to be ready.
2. Renders `root-app.yaml` from `root-app.yaml.j2`.
3. Applies `root-app.yaml` to cluster.

```bash
# From ansible-automation repo root
ansible-playbook playbook.yml --ask-vault-pass
```

**Step 2 — ArgoCD takes over.**

`root-app` Application points ArgoCD at this repo:

- Source repo: `https://github.com/freecloudinitiative/k3s-manifests.git`
  (configured in `argocd-bootstrap/defaults/main.yml`)
- Watches two paths: `infrastructure/` (matches `*/app*.yaml` +
  `namespaces/*.yaml`) and `applications/` (matches `*/app*.yaml`)
- Sync: automated, prune, selfHeal

Sync is automated for subsequent pushes, but two manual gates below block first bring-up.

**Step 3 — Unseal OpenBao.**

OpenBao deployed by ArgoCD, but manually initialised and unsealed before `external-secrets` connects. Every `ExternalSecret` fails closed until then, and every pod mounting a Secret fails to start. See [OpenBao](#openbao) for details.

**Step 4 — Bootstrap Garage.**

- Wait for Garage StatefulSet, 3 Ready pods (`GARAGE_EXPECTED_REPLICAS=3`).
- Export `GARAGE_ACCESS_KEY` and `GARAGE_SECRET_KEY`, matching values seeded to OpenBao.
- Run `./scripts/garage-bootstrap.sh` (idempotent).
- `storage-service` readiness probe is `HeadBucket` on bucket `platform`. Until bootstrap succeeds, `storage-service` stays `NotReady`, `/api/buckets` and `/api/networks` have no healthy endpoint, and `compute-service` cannot resolve a backup bucket.
- See [Garage](#garage) for details.

**Step 5 — Verify.**

Check cluster status before declaring bring-up complete:

```bash
kubectl -n backend get deploy
kubectl -n backend get pods -l app.kubernetes.io/name=storage-service
kubectl -n argocd get applications.argoproj.io
```

Expect `storage-service` Ready 1/1, all Applications `Synced` and `Healthy`.

**To add a new FCI service after bootstrap:**

```bash
# 1. Create folder under applications/
mkdir applications/my-service

# 2. Add Helm chart (Chart.yaml, values.yaml, templates/) and app.yaml
#    pointing at this repo, path applications/my-service.
#    See applications/api-gateway/app.yaml for the shape.

# 3. Push — ArgoCD picks it up within seconds
git add . && git commit -m "add my-service" && git push
```

**To validate charts and manifests locally:**

Install Helm, yamllint, kubeconform, and helm-unittest plugin, then:

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest.git --version v1.1.2
# Helm 4: add --verify=false (git plugin installs have no GPG webhook).
make validate
```

`make validate` lints YAML, lints and renders every Helm chart under
`infrastructure/` and `applications/`, schema-checks rendered output with
kubeconform, and runs helm-unittest suites if any `tests/` directory
exists. This repo is YAML-only — no Go, no `go.mod`. See
[CHARTS.md](CHARTS.md) for chart-authoring contract.

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

`external-secrets` is created by `CreateNamespace=true` on its Application,
not by a file in `namespaces/`.

## Language

YAML. Helm charts and values files. Makefile shells out to yamllint, helm,
kubeconform, and helm-unittest. No Go.

## Folders

```
Makefile              Local validation: lint, template, schema, unittest.
CHARTS.md             Chart-authoring contract: where charts live, tests/, YAML-only rule.
caveman.md            Terse writing rules for these docs.

infrastructure/
  namespaces/         Namespace definitions. Sync-wave 0 on each object.
  metallb/            Bare-metal load balancer (L2 mode, IP pool 192.168.1.100-120).
  cert-manager/       TLS certificate lifecycle. 3 issuers: self-signed, private CA, Let's Encrypt.
  longhorn/           Distributed block storage. 2 StorageClasses.
  traefik/            Ingress controller + routing rules for LAN UI paths.
  external-secrets/   Syncs secrets from OpenBao → Kubernetes Secrets.
  cloudnative-pg/     CloudNativePG operator (chart 0.29.0).
  kyverno/            Policy admission controller.
  kyverno-policies/   5 cluster policies: 4 Audit + restrict-compute-service-rbac-writes Enforce.
  platform-postgresql/ 3-instance CNPG Postgres cluster (local-path, shared by platform services).
  valkey/             Redis-compatible cache with TLS + ACL.
  garage/             S3-compatible object storage, 3-replica distributed.
  authentik/          OIDC identity provider.
  cloudflared/        Cloudflare tunnel — public endpoints without port forwarding.
  argocd/             ArgoCD self-configuration (ArgoCD manages itself).
  kube-prometheus-stack/ Prometheus + Grafana + Alertmanager.
  loki/               Log aggregation.
  tempo/              Distributed tracing backend.
  opentelemetry/      OTel Collector — receives traces/logs, forwards to Tempo/Loki.
  alloy/              Grafana Alloy — cluster-wide log and metrics scraper.

applications/
  api-gateway/        Reverse proxy + auth gateway. Chart in this folder.
  compute-service/    VM lifecycle management. Chart in this folder.
  database-service/   CNPG-backed database management. Chart in this folder.
  iam-service/        Identity and access management. Chart in this folder.
  storage-service/    Garage S3-backed object storage service. Chart in this folder.
  terminal-gateway/   WebSocket-to-Kubernetes exec terminal proxy. Chart in this folder.
  frontend/           React SPA + nginx. Chart in this folder. Namespace frontend.
```

## Read More

- [CHARTS.md](CHARTS.md) — where application charts live and how to validate them
- [APPS.md](APPS.md) — what each app does and its key configuration
- [ARCHITECTURE.md](ARCHITECTURE.md) — how all apps connect, sync order, secret flow, traffic flow
- [FILES.md](FILES.md) — every file, one line
