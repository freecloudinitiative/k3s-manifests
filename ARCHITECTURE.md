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
                                      (from their own repos)
```

ArgoCD syncs every 3 minutes and on any Git push. Any drift from declared state is self-healed. Nothing can run in the cluster unless it is declared in this repo or in one of the application repos.

---

## Startup Order (ArgoCD Sync Waves)

Sync waves control order. Lower wave number runs first. Apps with no annotation run in wave `0` or after dependencies are healthy.

```
Wave -1  namespaces/          ← all namespaces created first

Wave  0  metallb               ← LB needed before any LoadBalancer Service
         cert-manager          ← TLS needed before any cert
         longhorn              ← storage needed before any PVC
         kyverno               ← policies in before workloads

Wave  1  cert-manager issuers  ← self-signed CA issuer
         cluster-issuer-ca     ← private CA issuer (depends on root cert)
         external-secrets      ← secrets operator in before secrets needed
         metallb config        ← IP pool + L2 advertisement

Wave  3+ traefik               ← ingress after storage and TLS ready
         platform-postgresql   ← DB after storage ready
         valkey                ← cache after namespaces ready
         garage                ← S3 after storage ready

Wave  5+ authentik             ← OIDC after Postgres, TLS, and secrets ready
         cloudflared           ← tunnel after secrets ready
         zot-registry          ← registry after Garage ready
         monitoring stack      ← observability after all platform up

applications/*                 ← FCI services after all infrastructure up
```

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
   └── registry.freecloudinitiative.com ──► Cloudflare Tunnel ──► Zot Registry
                                                                  (Traefik middleware: auth)
```

### Internal HTTP (cluster LAN access)

```
Browser → master-node-IP:80
   │
   ▼
Traefik (DaemonSet on master node, hostPort 80/443)
   │
   ├── /frontend       ──► frontend pod (namespace: frontend)
   ├── /grafana        ──► Grafana (namespace: monitoring)
   ├── /prometheus     ──► Prometheus (namespace: monitoring)
   ├── /alloy          ──► Alloy UI (namespace: monitoring)
   ├── /argocd         ──► ArgoCD server (namespace: argocd)
   ├── /traefik-dashboard ► Traefik internal API
   └── /ui, /v1        ──► OpenBao (namespace: openbao)
```

### API Traffic (authenticated)

```
User browser / API client
   ▼
Cloudflare Tunnel → Traefik → api-gateway (namespace: backend)
   │
   ├── validates OIDC token (Authentik JWKS)
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

`ClusterSecretStore` authenticates to OpenBao using a Kubernetes ServiceAccount token. OpenBao has a Kubernetes auth role that grants access only to the `external-secrets-openbao` service account.

### Required OpenBao paths (KV v2, mount `secret`)

The following paths must be seeded **out of band** before the corresponding `ExternalSecret` objects can reach `SecretSynced`. An `ExternalSecret` pointing at a missing key stays `SecretSyncedError` forever with no other signal.

| OpenBao path | Property | Consumed by | Target Kubernetes Secret |
|---|---|---|---|
| `secret/data/storage` | `postgresql-password` | `storage-role` DatabaseRole | `storage-postgresql-credentials` (platform-database) |
| `secret/data/iam` | `postgresql-password` | `iam-role` DatabaseRole | `iam-postgresql-credentials` (platform-database) |
| `secret/data/compute` | `postgresql-password` | `compute-role` DatabaseRole | `compute-postgresql-credentials` (platform-database) |
| `secret/data/database` | `postgresql-password` | `database-role` DatabaseRole | `database-postgresql-credentials` (platform-database) |
| `secret/data/platform-postgresql` | `ca-cert` | TLS verification | service CA bundles (backend) |
| `secret/data/database` | `postgresql-password` | database-service pod DATABASE_URL | `database-service-config` (backend) |
| `secret/data/api-gateway` | `internal-public-key` | database-service token verification | `internal-token-public-key` (backend) |

Note: `secret/data/database / postgresql-password` is shared between the `database-role` DatabaseRole
(platform-database, PR-02) and the `database-service-config` ExternalSecret (backend, PR-03). Both
read the same OpenBao key; the DatabaseRole copy feeds CNPG role creation, the backend copy feeds the
pod's `DATABASE_URL` environment variable.

### CNPG same-namespace resolution rule

`DatabaseRole.spec.passwordSecret` is resolved as a **same-namespace** reference in the namespace where the `DatabaseRole` CR reconciles — the `platform-postgresql` Argo Application's destination, `platform-database`. A credential `ExternalSecret` placed in `backend` is invisible to CNPG and the role's password silently never updates. All `*-postgresql-credentials` Secrets that feed a `DatabaseRole` must therefore live in `platform-database`. Backend-namespace copies that service pods actually mount are separate `ExternalSecret` objects (PR-03, PR-04).


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
                  │  └─ storage-service (customer buckets)                  │
                  └──────────────────────────────────────────────────────────┘

                  ┌─── platform-postgresql (CNPG) ─────────────────────────┐
                  │  3 instances, one per node                              │
                  │  Longhorn local-path PVC (20 Gi each)                  │
                  │  Used by:                                                │
                  │  ├─ authentik (database: authentik)                    │
                  │  ├─ iam-service                                         │
                  │  ├─ compute-service                                     │
                  │  ├─ database-service                                    │
                  │  └─ storage-service                                     │
                  └──────────────────────────────────────────────────────────┘

                  ┌─── valkey ────────────────────────────────────────────┐
                  │  Single primary, no replicas, no persistence           │
                  │  TLS, ACL, maxmemory 192mb (allkeys-lfu)              │
                  │  Used by:                                               │
                  │  ├─ api-gateway (rate limiting, JWKS cache)            │
                  │  └─ terminal-gateway (session tickets)                 │
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

Node-level logs and metrics flow through Alloy:

```
Node logs + pod stdout ──► Alloy (DaemonSet, one per node) ──► Loki
Node metrics ──► Alloy ──► Prometheus (via ServiceMonitor)
```

All services expose a `/metrics` endpoint. Prometheus scrapes any resource with a `ServiceMonitor` CR.

---

## Network Isolation

Each namespace has NetworkPolicy rules. Traffic is deny-by-default. Only declared paths are allowed.

Key rules:
- Valkey: accepts only from `backend` namespace (port 6379) and `monitoring` (port 9121 exporter).
- Garage: cluster-internal only (no external ingress).
- Authentik: cluster-internal + Cloudflare tunnel ingress for public endpoint.
- platform-postgresql: CNPG manages NetworkPolicy. Only service accounts from the same cluster can connect.

---

## Why Built This Way

**GitOps (not manual kubectl)**: Single source of truth. Reproducible. Auditable. No manual state drift.

**ArgoCD App of Apps**: One root Application (created by `ansible-automation`) points to this repo. Each sub-folder is its own Application. Adding an app = adding a folder + `app.yaml`. No root-level manifest editing.

**Sync waves**: Kubernetes resources must be created in dependency order. Waves enforce this without hard-coded `sleep` delays or complex scripting. ArgoCD waits for each wave to be healthy before starting the next.

**OpenBao for secrets**: Secrets never touch Git. ExternalSecret objects in Git declare _what_ to sync but not _the values_. Zero secret exposure from repo access.

**MetalLB L2**: No cloud LB available. L2 mode works on any bare-metal LAN with no external controller needed. L2 means one node owns the IP and ARP-replies; traffic enters that node then routes internally.

**Traefik DaemonSet on master (not Deployment)**: `hostPort` 80/443 can only bind on one pod per node. DaemonSet scoped to control-plane nodes means exactly one pod per master. Adding a second master automatically adds a second ingress point.

**Two Longhorn StorageClasses**: Self-replicating apps (Garage, Valkey) don't need Longhorn replication — they replicate data themselves. Using `longhorn-local` (1 replica) halves storage overhead. Platform databases use `longhorn-platform` (2 replicas) for safety.

**Cloudflared (no port forwarding)**: Bare-metal nodes are behind NAT. Cloudflare Tunnel creates an outbound-only tunnel — no inbound firewall ports needed. The tunnel token is the only secret that enables public access.

---

## Where Apps Live When Running

| App | Namespace | Node affinity |
|---|---|---|
| traefik | `traefik` | master nodes only (DaemonSet) |
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
