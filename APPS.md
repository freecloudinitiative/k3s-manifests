# APPS — What Apps Do

---

## Infrastructure

### namespaces

Creates all Kubernetes namespaces before any other app deploys. ArgoCD sync-wave `-1` ensures these exist first.

Namespaces: `authentik`, `cert-manager`, `cloudflared`, `cnpg-system`, `frontend`, `garage`, `kyverno`, `longhorn-system`, `metallb-system`, `monitoring`, `platform-database`, `traefik`, `valkey`, `zot-registry`.

---

### metallb

**What**: Bare-metal load balancer. Allows `type: LoadBalancer` Services to get real IP addresses on the local network.

**Config**:
- IP pool: `192.168.1.100–192.168.1.120` (L2 advertisement)
- Mode: L2 — announces IPs via ARP on the local network

**Why not cloud LB**: No cloud provider. MetalLB fills the gap for bare-metal.

---

### cert-manager

**What**: Issues and renews TLS certificates automatically.

**Config — three issuers**:

| Issuer | Name | Used for |
|---|---|---|
| Self-signed (bootstrap) | `selfsigned` | Creates the private CA root certificate |
| Private CA | `ca-cluster-issuer` | Signs internal service certificates (OpenBao, Valkey, Postgres) |
| Let's Encrypt production | `letsencrypt-production` | Signs public-facing certs (Authentik, Zot Registry) |

**Sync-wave ordering**: issuer `0`, then CA cert `0`, then `ca-cluster-issuer` `1`. Other apps that need the CA wait for `ca-cluster-issuer` to be ready.

---

### longhorn

**What**: Distributed replicated block storage. Provides `PersistentVolume` support across nodes.

**Config — two StorageClasses**:

| Class | Replicas | Used for |
|---|---|---|
| `longhorn-platform` | 2 | Platform services (HA volumes) |
| `longhorn-local` | 1 (strict-local) | Self-replicating apps (Garage, Valkey) that handle their own HA |

Both: `reclaimPolicy: Retain` (volumes survive pod deletion), `allowVolumeExpansion: true`.

---

### traefik

**What**: Ingress controller. Routes all HTTP/HTTPS traffic into the cluster.

**Config**:
- Deployed as **DaemonSet** (not Deployment) on master nodes only — binds `hostPort: 80` and `hostPort: 443` directly on the host. One pod per node; scales automatically as masters are added.
- Tolerates master node taint.
- Default `IngressClass` for the cluster.
- Middleware chain `public-chain`: security-headers → rate-limit.

**Path routing** (all under master node IP):

| Path | Destination |
|---|---|
| `/grafana` | Grafana (monitoring) |
| `/prometheus` | Prometheus (monitoring) |
| `/alloy` | Alloy UI (monitoring) |
| `/argocd` | ArgoCD UI (argocd) |
| `/traefik-dashboard` | Traefik dashboard (traefik) |

Public endpoints (Authentik, Zot Registry, frontend) route via Cloudflare + Let's Encrypt TLS, each
on its own host (`auth.`, `registry.`, `frontend.freecloudinitiative.com`) rather than a path prefix
on this table.

---

### external-secrets

**What**: Syncs secrets stored in OpenBao (Vault) into Kubernetes `Secret` objects.

**Config**:
- One `ClusterSecretStore` named `openbao-store`. Connects to `openbao-active.openbao.svc.cluster.local:8200` using Kubernetes service account auth.
- Store restricted to allowed namespaces: `authentik`, `backend`, `frontend`, `zot-registry`, `monitoring`, `platform-database`, `valkey`.

**ExternalSecrets managed**:

| Secret | Namespace | Content |
|---|---|---|
| `authentik-config` | `authentik` | Authentik secret key + Postgres password |
| `cloudflared-tunnel-token` | `cloudflared` | Cloudflare tunnel token |
| `gateway-secrets` | `backend` | API gateway signing keys |
| `grafana-secrets` | `monitoring` | Grafana admin credentials |
| `storage-credentials` | `backend` | Garage S3 credentials for storage service |
| `terminal-secrets` | `backend` | Terminal gateway signing keys |
| `valkey-auth` | `valkey` | Valkey ACL password |
| `storage-postgresql-credentials` | `platform-database` | CNPG `storage` role password (feeds `storage-role` DatabaseRole) |
| `iam-postgresql-credentials` | `platform-database` | CNPG `iam` role password (feeds `iam-role` DatabaseRole) |
| `compute-postgresql-credentials` | `platform-database` | CNPG `compute` role password (feeds `compute-role` DatabaseRole) |
| `database-postgresql-credentials` | `platform-database` | CNPG `database` role password (feeds `database-role` DatabaseRole) |
| `zot-registry-pull-credentials` | `backend` | Docker registry credentials for FCI application image pulls |
| `zot-registry-pull-credentials` | `frontend` | Docker registry credentials for the frontend image pull |

**Namespace rule**: CNPG resolves `DatabaseRole.spec.passwordSecret` in the namespace where the `DatabaseRole` reconciles (`platform-database`). Secrets that feed a `DatabaseRole` must live in `platform-database`, not `backend`. Backend-namespace copies for pod consumption are separate `ExternalSecret` objects (PR-03, PR-04).

---

### kyverno

**What**: Kubernetes admission policy engine. Validates and mutates resources on admission.

Deployed as a standalone Helm chart. Policies are in the `kyverno-policies` app.

---

### kyverno-policies

**What**: Cluster-wide admission policies.

| Policy | Mode | Rule |
|---|---|---|
| `disallow-latest-tag` | Audit | All container images must have an explicit tag or digest. `latest` rejected. |
| `require-requests-limits` | Audit | All containers must declare CPU and memory `requests` and `limits`. |
| `require-run-as-non-root` | Audit | All containers must run as non-root (`runAsNonRoot: true`). |
| `restrict-image-registries` | Audit | Container images must come from approved registries only. |

All policies in `Audit` mode — log violations but do not block. Can be switched to `Enforce` when stable.

---

### platform-postgresql

**What**: Shared Postgres cluster for all FCI platform services. Managed by CloudNativePG (CNPG).

**Config**:
- 3 instances, one per worker node (required anti-affinity — pods cannot share a node).
- Tolerates `memory=limited:NoSchedule` so all 3 nodes are eligible.
- TLS enforced (`hostnossl reject`), password auth `scram-sha-256`.
- `superuserAccess: false` — no superuser login.
- Storage: `local-path`, 20 Gi per instance.
- `max_connections: 200`, `shared_buffers: 256MB`.
- `primaryUpdateMethod: switchover` — zero-downtime updates.
- Pod monitor enabled (Prometheus scrapes CNPG exporter).

Databases sharing this cluster: `platform` (default), `authentik`. The four FCI backend services (iam, compute, database, storage) all share the `platform` database separated by schema, not by separate databases.

**DatabaseRoles** (connection-limit total: 185 of 200; 15 reserved for CNPG superuser/replication/pg_monitor):

| Role | Schema | `connectionLimit` | Credentials Secret (platform-database) |
|---|---|---|---|
| `platform` | — | 80 | `platform-postgresql-credentials` |
| `authentik` | — | 60 | `authentik-postgresql-credentials` |
| `storage` | `storage` | 30 | `storage-postgresql-credentials` |
| `iam` | `iam` | 5 | `iam-postgresql-credentials` |
| `compute` | `compute` | 5 | `compute-postgresql-credentials` |
| `database` | `database` | 5 | `database-postgresql-credentials` |

Per-service limit arithmetic: `DB_MAX_CONNS` (5) × 1 replica = **5**.

---

### valkey

**What**: Redis-compatible in-memory cache. Used by api-gateway (rate limiting, caching) and other FCI services.

**Config**:
- Single primary, no replicas (`replica.enabled: false`). Persistence disabled — cache-only.
- TLS enabled (cert from private CA via ExternalSecret `valkey-server-tls`).
- ACL: `default` user with read/write/pubsub/scripting permissions. No `FLUSHALL`, `CONFIG`, `DEBUG`, `SHUTDOWN`.
- `maxmemory: 192mb`, `maxmemory-policy: allkeys-lfu` — evicts least-frequently-used keys under memory pressure.
- NetworkPolicy: ingress only from `backend` namespace (port 6379) and `monitoring` (port 9121 for exporter).
- Prometheus exporter with ServiceMonitor.

---

### garage

**What**: S3-compatible distributed object storage. Backend for Zot registry and `storage-service`.

**Config**:
- 3-node StatefulSet, `replicationFactor: 3`, `consistencyMode: consistent`.
- One pod per worker node (required anti-affinity). Tolerates `memory=limited:NoSchedule`.
- Storage per node: 100 Gi data + 2 Gi metadata (Longhorn `longhorn-local` — 1 replica because Garage replicates itself).
- Region: `fci-local`.
- S3 API accessible in-cluster only (`ingress.s3.api.enabled: false`). Not exposed publicly.
- Prometheus ServiceMonitor enabled.

---

### authentik

**What**: OIDC identity provider. All user authentication in FCI goes through Authentik.

**Config**:
- 2 server replicas, 2 worker replicas. Pod anti-affinity (hard).
- Backed by `platform-postgresql` (`authentik` database). Connects with TLS (`verify-full`), mounts CA cert.
- Secrets from OpenBao via ExternalSecret.
- Public endpoint: `https://auth.freecloudinitiative.com` — TLS from Let's Encrypt via `cert-manager`.
- Ingress routed through Traefik `websecure` entrypoint with security headers middleware.
- Outpost discovery disabled. Built-in Postgres disabled (uses platform cluster).
- Blueprint configmap for OIDC client setup.

---

### cloudflared

**What**: Cloudflare Tunnel daemon. Exposes cluster endpoints to the internet without opening firewall ports.

**Config**:
- 2 replicas.
- Tunnel token never stored in Git — comes from OpenBao via ExternalSecret.
- Routes traffic to Traefik (HTTP) or directly to services via tunnel configuration in Cloudflare dashboard.

---

### zot-registry

**What**: OCI-compliant container image registry. FCI services pull their images from here.

**Config**:
- Single replica.
- Backend storage: Garage S3 (`garage.garage.svc.cluster.local:3900`, bucket `zot-registry`, region `fci-local`).
- S3 credentials from Kubernetes Secret (ExternalSecret).
- Public endpoint: `https://registry.freecloudinitiative.com` — TLS from Let's Encrypt.
- Authentication via Traefik middleware `registry-auth`.
- GC enabled, 24h delay.
- Prometheus metrics at `/metrics`.

---

### argocd

**What**: ArgoCD self-configuration. ArgoCD manages its own ConfigMaps and settings through GitOps.

**Config**:
- `argocd-cm.yaml`: resource health checks, custom resource exclusions.
- `argocd-cmd-params-cm.yaml`: server flags.
- `app-config.yaml`: ArgoCD `AppProject` settings.

---

### kube-prometheus-stack

**What**: Prometheus + Grafana + Alertmanager monitoring stack.

**Config**:
- Prometheus: 14-day retention, 10 Gi PVC (`local-path`). Scrapes all ServiceMonitors in the cluster.
- Grafana: admin credentials from OpenBao ExternalSecret. 3 pre-configured datasources: Prometheus, Loki, Tempo.
- Exposed via Traefik at `/grafana` and `/prometheus`.
- Prometheus exposed at `/prometheus`.

---

### loki

**What**: Log aggregation backend. Receives logs from Alloy and OTel Collector. Queried by Grafana.

**Config**:
- Single binary mode, 1 replica.
- Storage: filesystem, `local-path` 10 Gi PVC.
- No auth (`auth_enabled: false`) — cluster-internal only.

---

### tempo

**What**: Distributed tracing backend. Receives traces from OTel Collector. Queried by Grafana.

**Config**: Single binary mode. Receives OTLP over gRPC (port 4317).

---

### opentelemetry

**What**: OTel Collector. Central telemetry router — receives traces and logs from all FCI services, forwards to Tempo and Loki.

**Config**:
- Receives: OTLP gRPC (4317) + OTLP HTTP (4318).
- Traces pipeline: OTel → Tempo (`tempo.monitoring.svc.cluster.local:4317`).
- Logs pipeline: OTel → Loki (`loki-gateway.monitoring.svc.cluster.local:80`).
- Batch processor: 1 s timeout, 256 items.
- Memory limiter: 80% limit.

---

### alloy

**What**: Grafana Alloy — runs on each node, scrapes node metrics and pod logs, ships to Loki/Prometheus.

---

---

## Applications

### api-gateway

**What**: HTTP reverse proxy and auth gateway for all FCI backend services. Deployed from `applications/api-gateway` Helm chart.

**Namespace**: `backend`. **Sync**: auto, prune, selfHeal, ServerSideApply.

**Image**: `registry.freecloudinitiative.com/api-gateway:sha-0ac98efb497a`.

---

### compute-service

**What**: VM lifecycle management service. Deployed from `compute-service` repo.

**Namespace**: `backend`. Same sync policy.

**Image**: `registry.freecloudinitiative.com/compute-service:sha-xxxxxxxxxxxx` (placeholder; the Application will not sync until a real image is published).

**Secrets contract (namespace `backend`)**:

| Secret | Key | Consumed as / required mount path | Source |
|---|---|---|---|
| `compute-service-postgresql-credentials` | `url` | `DATABASE_URL` via `secretKeyRef`; URL requires CA at `/etc/compute-service/postgres/ca.crt` | OpenBao `compute/postgresql-password` |
| `compute-service-postgresql-ca-cert` | `ca.crt` | volume at `/etc/compute-service/postgres/ca.crt` | OpenBao `platform-postgresql/ca-cert` |
| `compute-service-valkey-password` | `password` | `VALKEY_PASSWORD` via `secretKeyRef` | OpenBao `valkey/password` |
| `compute-service-valkey-ca-cert` | `ca.crt` | volume at `/etc/compute-service/valkey/ca.crt` | OpenBao `valkey/ca-cert` |
| `compute-service-internal-public-key` | `internal-public.pem` | volume at `/etc/fci/keys/internal-token-public.pem` | OpenBao `api-gateway/internal-public-key` |
| `terminal-gateway-public-key` (shared) | `internal-public.pem` | volume at `/etc/fci/keys/terminal-gateway-public.pem` | OpenBao `terminal-gateway/internal-public-key`; defined once in `external-secret-terminal.yaml` |

The Postgres and Valkey CA paths are part of the chart contract: the future compute-service chart
must mount the corresponding keys at exactly these paths. Until that chart exists, this Application
is expected to remain in `ComparisonError`; staging these inert ExternalSecrets does not cause that
pre-existing failure.

---

### database-service

**What**: Database cluster (CNPG) management service. Deployed from `applications/database-service` Helm chart.

**Namespace**: `backend`. Same sync policy.

**Image**: `ghcr.io/freecloudinitiative/database-service:sha-f247d60ac4de`. The registry-coordinate correction is tracked separately in PR-15.

**Secrets (namespace `backend`)**:

| Secret | Key | Consumed as | Source |
|---|---|---|---|
| `database-service-config` | `DATABASE_URL` | `secretKeyRef` env | ExternalSecret → OpenBao `database/postgresql-password`; connection string templated with `sslrootcert=/certs/platform-postgresql/ca.crt` |
| `platform-postgresql-ca-bundle` | `ca.crt` | volume at `/certs/platform-postgresql/ca.crt` | ExternalSecret → OpenBao `platform-postgresql/ca-cert` (same key as `storage-service-postgresql-ca-cert`) |
| `internal-token-public-key` | `internal-public.pem` | volume at `/etc/fci/internal-token/internal-public.pem` | ExternalSecret → OpenBao `api-gateway/internal-public-key` (public half of api-gateway's Ed25519 signing key) |

**ExternalSecrets** (defined in `infrastructure/external-secrets/external-secret-database.yaml`):
- `database-service-config` (namespace `backend`, wave `-2`)
- `database-service-postgresql-ca-cert` → target `platform-postgresql-ca-bundle` (namespace `backend`, wave `-2`)
- `database-service-internal-public-key` → target `internal-token-public-key` (namespace `backend`, wave `-2`)

**Follow-up**: `internal-token-public-key` does not follow the `database-service-*` naming convention used by other backend services. Renaming requires a coordinated change in the `database-service` chart repo.


### iam-service

**What**: Identity and access management service. Deployed from `iam-service` repo.

**Namespace**: `backend`. Same sync policy.

**Image**: `registry.freecloudinitiative.com/iam-service:sha-xxxxxxxxxxxx` (placeholder; the Application will not sync until a real image is published).

**Secrets contract (namespace `backend`)**:

| Secret | Key | Consumed as / required mount path | Source |
|---|---|---|---|
| `iam-service-postgresql-credentials` | `url` | `DATABASE_URL` via `secretKeyRef`; URL requires CA at `/etc/iam-service/postgres/ca.crt` | OpenBao `iam/postgresql-password` |
| `iam-service-postgresql-ca-cert` | `ca.crt` | volume at `/etc/iam-service/postgres/ca.crt` | OpenBao `platform-postgresql/ca-cert` |
| `iam-service-internal-public-key` | `internal-public.pem` | volume at `/etc/fci/keys/internal-token-public.pem` | OpenBao `api-gateway/internal-public-key` |
| `terminal-gateway-public-key` (shared) | `internal-public.pem` | volume at `/etc/fci/keys/terminal-gateway-public.pem` | OpenBao `terminal-gateway/internal-public-key`; defined once in `external-secret-terminal.yaml` |

The Postgres CA path is part of the chart contract: the future iam-service chart must mount `ca.crt`
at exactly this path. Until that chart exists, this Application is expected to remain in
`ComparisonError`; staging these inert ExternalSecrets does not cause that pre-existing failure.

---

### storage-service

**What**: Object storage management service. Deployed from `applications/storage-service` Helm chart, uses Garage as S3 backend.

**Namespace**: `backend`. Same sync policy.

**Image**: `registry.freecloudinitiative.com/storage-service:sha-2f2daba0c43e`.

---

### terminal-gateway

**What**: WebSocket-to-Kubernetes exec terminal proxy. Deployed from `applications/terminal-gateway` Helm chart.

**Namespace**: `backend`. Same sync policy.

**Image**: `registry.freecloudinitiative.com/terminal-gateway:sha-e3c09b7baefc`.

---

### frontend

**What**: React single-page application and web console. Deployed from `applications/frontend` Helm chart, served via nginx.

**Namespace**: `frontend`. Same sync policy.

**Image**: `registry.freecloudinitiative.com/frontend:sha-7eefcc02593a`.

---

## External Prerequisites

### OpenBao

**What**: Secret store that every `ExternalSecret` in this repo reads from. Not a managed
application — no `Application`, namespace, or chart for it exists in this repo. It must be running,
initialised, and unsealed out of band before the first ArgoCD sync. See
[README.md § Prerequisites](README.md) for what it must expose and
[ARCHITECTURE.md § Secret Flow](ARCHITECTURE.md) for the full key inventory.
