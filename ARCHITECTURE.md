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

Platform images are stored in the private GitHub Container Registry
organization at `ghcr.io/freecloudinitiative`. External Secrets Operator
materializes `ghcr-pull-credentials` in `backend` and `frontend` from OpenBao
`ghcr-registry/ghcr-username` and `ghcr-registry/ghcr-token`. Applications
pass that Secret as `imagePullSecrets[0].name`.

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
         external-secrets      ← operator and CRDs only

Wave  2  longhorn
         loki
         kyverno-policies
         cloudnative-pg        ← operator before Cluster CRs

Wave  3  external-secrets-config ← OpenBao store + ExternalSecrets
         cert-manager-configs    ← issuers + CA cert

Wave  4  garage
         metallb
         platform-postgresql
         valkey

Wave  5  authentik
         metallb-config        ← IP pool + L2Advertisement
         opentelemetry

Wave  6  alloy

Wave  8  tempo

Wave  9  traefik
         kube-prometheus-stack
         cloudflared

Wave 10  argocd app-config

Wave 11  applications/*            ← every FCI service Application. Above
                                     argocd app-config (10) so all
                                     infrastructure Applications exist first:
                                     External Secrets (1) must be running
                                     before any service Secret can sync, and
                                     platform-postgresql (4) before any
                                     service opens a pool. backend / frontend
                                     namespaces stay wave 0 in
                                     namespaces/*.yaml. CreateNamespace=true
                                     remains on each Application as fallback.
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
   ├── argocd.freecloudinitiative.com ──► ArgoCD server (namespace: argocd)
   ├── longhorn.freecloudinitiative.com ──► Longhorn UI (namespace: longhorn-system)
   └── /traefik-dashboard ► Traefik internal API

UIs use subdomains on `websecure` (HTTPS) protected by Authentik ForwardAuth SSO.
```

OpenBao is not routed through this repo's Traefik. It is installed, initialized,
unsealed, and seeded entirely by `ansible-automation` before ArgoCD ever syncs
(see [README.md § Prerequisites](README.md)) — this repo never creates its
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

Store allow-list: `authentik`, `argocd`, `backend`, `cloudflared`, `frontend`,
`garage`, `monitoring`, `platform-database`, `valkey`.

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
| `secret/data/ghcr-registry` | `ghcr-username`, `ghcr-token` | image pulls | `ghcr-pull-credentials` (backend, frontend) |
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
                  │  Used by storage-service (bucket: platform, customer data)│
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

Each namespace has NetworkPolicy rules. Ingress is deny-by-default and only
declared paths are allowed. compute-service, storage-service, and
terminal-gateway deliberately leave egress unrestricted: k3s kube-router
rejects Service ClusterIP traffic before namespaceSelector/ipBlock peers match,
which otherwise blocks DNS, the Kubernetes API, Valkey, and Garage. Their
documented egress allowlists remain in the charts behind
`networkPolicy.restrictEgress` for a future CNI migration.

Key rules:
- Valkey and Garage keep namespace-selected NetworkPolicy peers and add only
  the private `10.1.1.0/24` node-overlay CIDR because k3s SNATs valid cross-node
  Service traffic before kube-router evaluates those peers. Valkey additionally
  requires TLS/ACL authentication.
- Authentik: cluster-internal + Cloudflare tunnel for public host.
- platform-postgresql: CNPG NetworkPolicy plus `networkpolicy.yaml`.
- api-gateway: ingress from `frontend` only; egress to `authentik` on pod port 9000 for JWKS.
- terminal-gateway: ingress from `backend` only.
- Longhorn: an Argo CD Sync hook labels Ansible's `node-tier` workers for
  default-disk creation before the chart reconciles; no manual node labeling is
  required after a rebuild.

**Cluster CIDR coupling**: `applications/storage-service/values.yaml`'s
`clusterCIDRs.pod`/`clusterCIDRs.service`, and the `networkPolicy.kubernetesAPIServerCIDR`
value in each of `storage-service`, `compute-service`, `database-service`, and
`terminal-gateway`, are all derived from the same underlying fact — the real
k3s cluster's pod and service CIDRs. They must be changed together: if the
cluster's CIDRs ever change (a re-install with explicit `--cluster-cidr`/
`--service-cidr` flags, for example), update all five values in the same PR.
Confirmed 2026-08-29 that the deployed cluster runs k3s's compiled-in defaults
(`10.42.0.0/16` pod, `10.43.0.0/16` service) — `ansible-automation/roles/k3s-master-setup`
passes neither flag to the install script. `storage-service` additionally reads
`clusterCIDRs` at runtime to refuse a customer VPC that overlaps either range
(`storage-service/internal/service/network.go`) and to validate generated
NetworkPolicy output never names a protected range as a customer peer
(`storage-service/internal/projection`) — both checks fail open (accept a range
they should refuse) if these values are narrower than the real cluster.

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
