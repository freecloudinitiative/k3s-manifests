# ARCHITECTURE — How Apps Work Together

## Big Picture

```
  Git Push to k3s-manifests
          │
          ▼
       ArgoCD
    (watches this repo)
          │
          ├─── infrastructure/ ──► installs platform tools
          │                           (in wave order)
          │
          └─── applications/ ───► installs FCI services
                                      (charts in this repo)
```

ArgoCD syncs every 3 minutes and on any Git push. Drift from declared state is self-healed. Nothing runs in cluster unless declared in this repo.

---

## Application Image Promotion (Environment Strategy)

We employ a dual-registry strategy depending on the environment:

**1. Test / Pre-prod Environment (Current)**
In test environments where the cluster is still bootstrapping or lacks public tunneling, we use **GitHub Container Registry (GHCR)** (`ghcr.io/freecloudinitiative`). This avoids the chicken-and-egg problem where the cluster cannot pull images to start the registry that hosts those images.

**2. Production Environment (Planned)**
When moving to production, we will switch back to our self-hosted, air-gapped registry: **`registry.freecloudinitiative.com`** (powered by Zot and backed by Garage S3). 

`registry.freecloudinitiative.com` is behind Authentik SSO (ForwardAuth).
External Secrets Operator materializes `zot-registry-pull-credentials` in
`backend` and `frontend` from OpenBao `zot-registry/pull-username` and
`zot-registry/pull-password`. Applications pass that Secret as
`imagePullSecrets[0].name`.

Application images are promoted with static ArgoCD Helm parameters in each
`applications/<name>/app.yaml`. Parameter is part of Git history, so deploy
and rollback are ordinary reviewed commits. Builds use tags `sha-<commit SHA>`.

Publish must succeed before tag is promoted. Image-build workflow lives
outside this repo. Placeholder `sha-xxxxxxxxxxxx` plus automated sync **off**
on compute-service and iam-service leaves those Applications unsyncable
until a real image exists.

---

## Startup Order (ArgoCD Sync Waves)

Lower wave runs first. Application-level waves on `app.yaml` / `app-config.yaml`:

```
Wave  0  namespaces/*.yaml     ← Namespace objects (no Application)

Wave  1  cert-manager
         kyverno
         external-secrets      ← operator + ClusterSecretStore

Wave  2  longhorn
         loki
         kyverno-policies
         cloudnative-pg        ← operator before Cluster CRs

Wave  3  garage
         cert-manager-configs  ← issuers + CA cert

Wave  4  metallb
         platform-postgresql
         valkey
         zot-registry

Wave  5  authentik
         metallb-config        ← IP pool + L2Advertisement
         opentelemetry

Wave  6  alloy

Wave  8  tempo

Wave  9  traefik
         kube-prometheus-stack
         cloudflared

Wave 10  argocd app-config

applications/*                 ← no Application-level wave (default 0).
                                 CreateNamespace=true for backend / frontend.
                                 ExternalSecrets for those pods use resource
                                 wave -2 inside external-secrets Application.
```

Resource waves inside an Application (e.g. ExternalSecret `-2`, DatabaseRole `1`)
only order objects within that Application. They do not reorder Applications.

---

## Traffic Flow

### Public HTTPS (user-facing)

```
Internet
   │
   ▼
Cloudflare (DNS + CDN)
   │
   ├── auth.freecloudinitiative.com ──► Cloudflare Tunnel (cloudflared) ──► Authentik
   │
   └── freecloudinitiative.com ──► Cloudflare Tunnel ──► Traefik (websecure, TLS via
                                    letsencrypt-production) ──► frontend nginx (namespace:
                                    frontend) ──► api-gateway (namespace: backend) ──►
                                    {iam, compute, database, storage, terminal-gateway}
```

api-gateway and terminal-gateway have no Ingress. NetworkPolicies admit ingress
only from `frontend` (api-gateway) and `backend` (terminal-gateway). frontend
nginx proxies `/api/` and `/ws/` same-origin to api-gateway; api-gateway
proxies `/ws/terminal/` to terminal-gateway. frontend host is only public
entry for the product. Neither gateway is reachable from outside the cluster.

Apex DNS and the Cloudflare Tunnel ingress rule for `freecloudinitiative.com`
already exist in `terraform-cloudflare-infra` (`cloudflare_record.root` name
`@`, tunnel ingress `var.domain_name`) — this chart just needs to bind that
host for HTTP-01 ACME and real traffic to work.

### Internal HTTP (cluster LAN access)

```
Browser → Hostname via DNS
   │
   ▼
Traefik (DaemonSet on master node, hostPort 80/443)
   │
   ├── grafana.freecloudinitiative.com ──► Grafana (namespace: monitoring)
   ├── prometheus.freecloudinitiative.com ──► Prometheus (namespace: monitoring)
   ├── alloy.freecloudinitiative.com ──► Alloy UI (namespace: monitoring)
   │
   │   (internal_only in terraform-cloudflare-infra — unproxied RFC1918 A
   │    record, TLS via ca-cluster-issuer since Let's Encrypt HTTP-01 can't
   │    reach them; clients must trust the internal CA)
   ├── registry.freecloudinitiative.com ──► Zot Registry (namespace: zot-registry)
   │                                        (Traefik middleware: Authentik ForwardAuth)
   ├── argocd.freecloudinitiative.com ──► ArgoCD server (namespace: argocd)
   ├── longhorn.freecloudinitiative.com ──► Longhorn UI (namespace: longhorn-system)
   └── /traefik-dashboard ► Traefik internal API

UIs use subdomains on `websecure` (HTTPS) protected by Authentik ForwardAuth SSO.
```

OpenBao is not routed through this repo's Traefik. Out-of-band prerequisite
(see [README.md § Prerequisites](README.md)). This repo never creates its
namespace or Service.

### API Traffic (authenticated)

```
User browser / API client
   ▼
Cloudflare Tunnel → Traefik → frontend nginx → api-gateway (namespace: backend)
   │
   ├── validates OIDC token (Authentik JWKS, fetched in-cluster over
   │   authentik-server.authentik.svc.cluster.local:80 -> pod port 9000 —
   │   never via the public tunnel, since api-gateway has no port-443 egress)
   ├── mints internal JWT
   └── proxies to: iam-service / compute-service / database-service
                   storage-service / terminal-gateway
                   (all in namespace: backend)
```

---

## Secret Flow

All secrets live in OpenBao (Vault). Nothing sensitive is in Git.

```
OpenBao (openbao namespace)
   │
   ▼
external-secrets operator
   │
   ▼
ExternalSecret CR (in k3s-manifests)
   │  declares: which path in OpenBao, which keys, which Kubernetes Secret name
   ▼
Kubernetes Secret (in the target namespace)
   │
   ▼
Pod mounts or references Secret via env/volume
```

`ClusterSecretStore` authenticates to OpenBao using a Kubernetes ServiceAccount
token. OpenBao Kubernetes auth role grants access only to
`external-secrets-openbao` ServiceAccount (namespace `external-secrets`).

Store allow-list: `authentik`, `argocd`, `backend`, `frontend`, `zot-registry`,
`monitoring`, `platform-database`, `valkey`. `cloudflared` is not listed;
`cloudflared-tunnel-token` ExternalSecret in `cloudflared` cannot sync until
that namespace is added.

### Required OpenBao paths (KV v2, mount `secret`)

Seed these out of band before matching `ExternalSecret` can reach
`SecretSynced`. Missing key stays `SecretSyncedError` forever with no other signal.

| OpenBao path | Property | Consumed by | Target Kubernetes Secret |
|---|---|---|---|
| `secret/data/storage` | `postgresql-password` | `storage-role` + storage-service `DATABASE_URL` | `storage-postgresql-credentials` (platform-database), `storage-service-postgresql-credentials` (backend) |
| `secret/data/iam` | `postgresql-password` | `iam-role` + iam-service `DATABASE_URL` | `iam-postgresql-credentials` (platform-database), `iam-service-postgresql-credentials` (backend) |
| `secret/data/compute` | `postgresql-password` | `compute-role` + compute-service `DATABASE_URL` | `compute-postgresql-credentials` (platform-database), `compute-service-postgresql-credentials` (backend) |
| `secret/data/database` | `postgresql-password` | `database-role` + database-service `DATABASE_URL` | `database-postgresql-credentials` (platform-database), `database-service-config` (backend) |
| `secret/data/platform-postgresql` | `ca-cert` | Postgres TLS verify | `*-postgresql-ca-cert` / `platform-postgresql-ca-bundle` (backend) |
| `secret/data/platform-postgresql` | `password` | shared `platform` role | `platform-postgresql-credentials` (platform-database) |
| `secret/data/api-gateway` | `internal-public-key` | verifier services | `*-internal-public-key`, `internal-token-public-key` (backend) |
| `secret/data/api-gateway` | `internal-signing-key` | api-gateway token issuance | `api-gateway-signing-key` (backend) |
| `secret/data/terminal-gateway` | `internal-public-key` | iam + compute terminal-token verify | `terminal-gateway-public-key` (backend, shared) |
| `secret/data/terminal-gateway` | `internal-signing-key` | terminal-gateway token issuance | `terminal-gateway-signing-key` (backend) |
| `secret/data/valkey` | `password` | Valkey ACL + every backend client | `valkey-auth` (valkey); `valkey-password` / `*-valkey-password` (backend) |
| `secret/data/valkey` | `ca-cert` | Valkey TLS verify | `valkey-ca-cert` / `*-valkey-ca-cert` (backend) |
| `secret/data/zot-registry` | `pull-username`, `pull-password` | image pulls | `zot-registry-pull-credentials` (backend, frontend) |
| `secret/data/zot-registry` | `s3-access-key-id`, `s3-secret-access-key` | Zot Garage backend | `zot-s3-credentials` (zot-registry) |
| `secret/data/authentik` | `zot-oidc-secret` | Traefik registry SSO | `zot-oidc-secret` (zot-registry) |
| `secret/data/authentik` | `postgresql-password` | authentik pod + `DatabaseRole` | `authentik-config` (authentik), `authentik-postgresql-credentials` (platform-database) |
| `secret/data/authentik` | `secret-key` | authentik signing key | `authentik-config` (authentik) |
| `secret/data/authentik` | `bootstrap-email` | first-run bootstrap | `authentik-bootstrap` (authentik) |
| `secret/data/authentik` | `bootstrap-password` | first-run bootstrap | `authentik-bootstrap` (authentik) |
| `secret/data/authentik` | `admin-token` | iam-service Authentik user/group sync | `iam-service-authentik-token` (backend) |
| `secret/data/grafana` | `admin-user`, `admin-password` | Grafana admin | `grafana-secrets` (monitoring) |
| `secret/data/cloudflared` | `tunnel-token` | cloudflared tunnel | `cloudflared-tunnel-token` (cloudflared) |
| `secret/data/garage` | `storage-service-access-key`, `storage-service-secret-key` | storage-service S3 client | `storage-service-objectstore-credentials` (backend) |
| `secret/data/garage` | `ca-cert` | storage-service Garage TLS (mounted; unused while Garage is HTTP) | `storage-service-objectstore-credentials` (backend) |

`secret/data/database` / `postgresql-password` is shared: `DatabaseRole` copy in
`platform-database` and `database-service-config` in `backend`. Same pattern for
iam, compute, storage. `terminal-gateway-public-key` is one shared Secret for
both verifier services. `valkey-password` / `valkey-ca-cert` are shared by
api-gateway and database-service.

### CNPG same-namespace resolution rule

`DatabaseRole.spec.passwordSecret` is a same-namespace reference in
`platform-database`. Credential `ExternalSecret` in `backend` is invisible to
CNPG. All `*-postgresql-credentials` that feed a `DatabaseRole` live in
`platform-database`. Backend copies that pods mount are separate objects.

---

## Storage Flow

```
                  ┌─── Garage (S3) ────────────────────────────────────────┐
                  │  3 StatefulSet pods, one per node                      │
                  │  replicationFactor=3, consistencyMode=consistent        │
                  │  Longhorn longhorn-local PVC (1 replica — Garage       │
                  │  handles its own replication)                           │
                  │                                                          │
                  │  Used by:                                                │
                  │  ├─ zot-registry (bucket: zot-registry)                │
                  │  └─ storage-service (bucket: platform, customer data)   │
                  └──────────────────────────────────────────────────────────┘

                  ┌─── platform-postgresql (CNPG) ─────────────────────────┐
                  │  3 instances, one per node                              │
                  │  k3s local-path PVC (20 Gi each) — not Longhorn        │
                  │  Used by:                                                │
                  │  ├─ authentik (database: authentik)                    │
                  │  ├─ iam-service                                         │
                  │  ├─ compute-service                                     │
                  │  ├─ database-service                                    │
                  │  └─ storage-service                                     │
                  └──────────────────────────────────────────────────────────┘

                  ┌─── valkey ────────────────────────────────────────────┐
                  │  Single primary, no replicas, no persistence           │
                  │  TLS (cert-manager Certificate), ACL, maxmemory 192mb │
                  │  Used by:                                               │
                  │  ├─ api-gateway (rate limiting, JWKS cache)            │
                  │  ├─ terminal-gateway (session tickets)                 │
                  │  ├─ compute-service                                    │
                  │  ├─ iam-service                                        │
                  │  ├─ storage-service                                    │
                  │  └─ database-service                                   │
                  └──────────────────────────────────────────────────────────┘
```

---

## Observability Flow

```
FCI services (traces + logs) ──OTLP──► OpenTelemetry Collector
                                              │
                                    ┌─────────┴──────────┐
                                    ▼                     ▼
                                  Tempo                  Loki
                              (traces backend)       (log backend)
                                    │                     │
                                    └─────────┬───────────┘
                                              ▼
                                           Grafana
                                  (unified view at /grafana)
```

Most backend charts set
`opentelemetry-collector.monitoring.svc.cluster.local:4317`.
database-service sets `otel-collector.monitoring.svc.cluster.local:4317`.

Node-level logs and metrics flow through Alloy:

```
Node logs + pod stdout ──► Alloy (DaemonSet, one per node) ──► Loki
Node metrics ──► Alloy ──► Prometheus (via ServiceMonitor)
```

Services expose `/metrics`. Prometheus scrapes any `ServiceMonitor`.

---

## Network Isolation

Each namespace has NetworkPolicy rules. Traffic is deny-by-default. Only
declared paths are allowed.

Key rules:
- Valkey: `backend` namespace port 6379, `monitoring` port 9121 exporter.
- Garage: cluster-internal only (no external ingress).
- Authentik: cluster-internal + Cloudflare tunnel for public host.
- platform-postgresql: CNPG NetworkPolicy plus `networkpolicy.yaml`.
- api-gateway: ingress from `frontend` only; egress to `authentik` on pod port 9000 for JWKS.
- terminal-gateway: ingress from `backend` only.

---

## Why Built This Way

**GitOps (not manual kubectl)**: Single source of truth. Reproducible.
Auditable. No manual state drift.

**ArgoCD App of Apps**: One root Application (created by `ansible-automation`)
points at this repo. Each sub-folder is its own Application. Adding an app =
folder + `app.yaml` (+ chart files for FCI services). No root-level manifest
editing.

**Sync waves**: Resources must be created in dependency order. Waves enforce
this without `sleep`. ArgoCD waits for each Application wave to be healthy
before the next.

**OpenBao for secrets**: Secrets never touch Git. ExternalSecret objects
declare _what_ to sync, not values.

**MetalLB L2**: No cloud LB. L2 works on bare-metal LAN. One node owns IP
and ARP-replies; traffic enters that node then routes internally.

**Traefik DaemonSet on master (not Deployment)**: `hostPort` 80/443 binds
one pod per node. DaemonSet on control-plane nodes means one pod per master.
Second master adds second ingress point.

**Two Longhorn StorageClasses**: Self-replicating apps (Garage) do not need
Longhorn replication. `longhorn-local` (1 replica) halves storage overhead.
`longhorn-platform` (2 replicas) is for workloads that do not replicate
themselves. platform-postgresql uses k3s `local-path`, not either Longhorn
class.

**Cloudflared (no port forwarding)**: Nodes sit behind NAT. Tunnel is
outbound-only. Tunnel token is the only secret that enables public access.

---

## Where Apps Live When Running

| App | Namespace | Node affinity |
|---|---|---|
| traefik | `traefik` | master nodes only (DaemonSet) |
| cloudnative-pg | `cnpg-system` | any node |
| platform-postgresql | `platform-database` | all nodes, one per node (anti-affinity) |
| garage | `garage` | all nodes, one per node (anti-affinity) |
| valkey | `valkey` | any node |
| authentik | `authentik` | any node (hard anti-affinity between server pods) |
| cloudflared | `cloudflared` | any node |
| zot-registry | `zot-registry` | any node (tolerates `memory=limited`) |
| kube-prometheus-stack | `monitoring` | any node |
| loki | `monitoring` | any node |
| tempo | `monitoring` | any node |
| opentelemetry | `monitoring` | any node |
| alloy | `monitoring` | all nodes (DaemonSet) |
| api-gateway | `backend` | any node |
| compute-service | `backend` | any node |
| database-service | `backend` | any node |
| iam-service | `backend` | any node |
| storage-service | `backend` | any node |
| terminal-gateway | `backend` | any node |
| frontend | `frontend` | any node |
