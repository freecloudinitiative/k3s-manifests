# APPS — What Apps Do

---

## Infrastructure

### namespaces

Creates Kubernetes namespaces. Each YAML carries sync-wave `0`. Root app includes `namespaces/*.yaml`. No dedicated `Application`.

Namespaces in this folder: `authentik`, `cert-manager`, `cloudflared`, `cnpg-system`, `frontend`, `garage`, `kyverno`, `longhorn-system`, `metallb-system`, `monitoring`, `platform-database`, `traefik`, `valkey`, `zot-registry`.

`backend` and `external-secrets` are not here. Those Applications set `CreateNamespace=true`. `argocd` and `openbao` come from bootstrap / out-of-band.

---

### metallb

**What**: Bare-metal load balancer. `type: LoadBalancer` Services get LAN IPs.

**Config**:
- IP pool: `192.168.1.100–192.168.1.120` (L2 advertisement)
- Mode: L2 — ARP on local network

**Why not cloud LB**: No cloud provider. MetalLB fills that gap.

---

### cert-manager

**What**: Issues and renews TLS certificates.

**Config — three issuers**:

| Issuer | Name | Used for |
|---|---|---|
| Self-signed (bootstrap) | `selfsigned-cluster-issuer` | Private CA root certificate |
| Private CA | `ca-cluster-issuer` | Internal service certs (OpenBao, Valkey, Postgres) |
| Let's Encrypt production | `letsencrypt-production` | Public certs (Authentik, Zot Registry, frontend) |

**Sync-wave**: `cert-manager` Application `1`. Issuer/CA YAMLs wave `1`. `cert-manager-configs` Application `3`.

---

### longhorn

**What**: Distributed replicated block storage. `PersistentVolume` across nodes.

**Config — two StorageClasses**:

| Class | Replicas | Used for |
|---|---|---|
| `longhorn-platform` | 2 | Platform services (HA volumes) |
| `longhorn-local` | 1 (strict-local) | Self-replicating apps (Garage) that handle own HA |

Both: `reclaimPolicy: Retain`, `allowVolumeExpansion: true`.

---

### traefik

**What**: Ingress controller. Routes HTTP/HTTPS into cluster.

**Config**:
- **DaemonSet** on control-plane nodes — `hostPort: 80` and `hostPort: 443`. One pod per master.
- Tolerates master / control-plane taint.
- Default `IngressClass`.
- Middleware chain `public-chain`: security-headers → rate-limit.

**Path routing** (master node IP):

| Path | Destination |
|---|---|
| `/grafana` | Grafana (monitoring) |
| `/prometheus` | Prometheus (monitoring) |
| `/alloy` | Alloy UI (monitoring) |
| `/argocd` | ArgoCD UI (argocd) |
| `/traefik-dashboard` | Traefik dashboard (traefik) |

Public hosts use Cloudflare + Let's Encrypt TLS, not a path prefix: `auth.`, `registry.`, `frontend.freecloudinitiative.com`.

---

### cloudnative-pg

**What**: CloudNativePG operator. Reconciles `Cluster`, `Database`, `DatabaseRole`.

**Config**:
- Upstream chart `cloudnative-pg` `0.29.0`.
- Namespace `cnpg-system`. Sync-wave `2`.
- Must be healthy before `platform-postgresql` (wave `4`) can apply CRs.

---

### external-secrets

**What**: Syncs OpenBao (Vault) secrets into Kubernetes `Secret` objects.

**Config**:
- One `ClusterSecretStore` named `openbao-store`. Server `https://openbao-active.openbao.svc.cluster.local:8200`. Kubernetes SA auth, role `external-secrets`.
- Store `conditions.namespaces`: `authentik`, `backend`, `frontend`, `zot-registry`, `monitoring`, `platform-database`, `valkey`.
- `cloudflared` is not on that list. `cloudflared-tunnel-token` ExternalSecret still lives in `cloudflared` — store will refuse it until `cloudflared` is added.

**ExternalSecrets** (Kubernetes Secret name = target unless noted):

| Secret | Namespace | Content |
|---|---|---|
| `authentik-config` | `authentik` | Authentik secret key + Postgres password |
| `authentik-bootstrap` | `authentik` | Bootstrap email + password |
| `authentik-postgresql-credentials` | `platform-database` | Authentik `DatabaseRole` password |
| `platform-postgresql-credentials` | `platform-database` | Shared `platform` role password |
| `cloudflared-tunnel-token` | `cloudflared` | Cloudflare tunnel token |
| `api-gateway-signing-key` | `backend` | API gateway Ed25519 signing key |
| `valkey-password` | `backend` | Shared Valkey password (api-gateway + database-service) |
| `valkey-ca-cert` | `backend` | Shared Valkey CA (api-gateway + database-service) |
| `grafana-secrets` | `monitoring` | Grafana admin credentials |
| `valkey-auth` | `valkey` | Valkey ACL password (`default` key) |
| `storage-postgresql-credentials` | `platform-database` | CNPG `storage` role password |
| `storage-service-postgresql-credentials` | `backend` | storage-service `DATABASE_URL` (`url`) |
| `storage-service-postgresql-ca-cert` | `backend` | Postgres CA |
| `storage-service-valkey-password` | `backend` | storage-service Valkey password |
| `storage-service-valkey-ca-cert` | `backend` | storage-service Valkey CA |
| `storage-service-internal-public-key` | `backend` | api-gateway public key |
| `storage-service-objectstore-credentials` | `backend` | Garage S3 keys + CA |
| `iam-postgresql-credentials` | `platform-database` | CNPG `iam` role password |
| `iam-service-postgresql-credentials` | `backend` | iam-service `DATABASE_URL` (`url`) |
| `iam-service-postgresql-ca-cert` | `backend` | Postgres CA |
| `iam-service-internal-public-key` | `backend` | api-gateway public key |
| `iam-service-valkey-password` | `backend` | iam-service Valkey password |
| `iam-service-valkey-ca-cert` | `backend` | iam-service Valkey CA |
| `compute-postgresql-credentials` | `platform-database` | CNPG `compute` role password |
| `compute-service-postgresql-credentials` | `backend` | compute-service `DATABASE_URL` (`url`) |
| `compute-service-postgresql-ca-cert` | `backend` | Postgres CA |
| `compute-service-valkey-password` | `backend` | compute-service Valkey password |
| `compute-service-valkey-ca-cert` | `backend` | compute-service Valkey CA |
| `compute-service-internal-public-key` | `backend` | api-gateway public key |
| `database-postgresql-credentials` | `platform-database` | CNPG `database` role password |
| `database-service-config` | `backend` | database-service `DATABASE_URL` (key `DATABASE_URL`) |
| `platform-postgresql-ca-bundle` | `backend` | Postgres CA for database-service |
| `internal-token-public-key` | `backend` | api-gateway public key (database-service name) |
| `terminal-gateway-signing-key` | `backend` | terminal-gateway signing key |
| `terminal-gateway-public-key` | `backend` | Shared public half (iam + compute) |
| `terminal-gateway-valkey-password` | `backend` | terminal-gateway Valkey password |
| `terminal-gateway-valkey-ca-cert` | `backend` | terminal-gateway Valkey CA |
| `zot-registry-pull-credentials` | `backend` | Docker pull creds for FCI images |
| `zot-registry-pull-credentials` | `frontend` | Docker pull creds for frontend image |
| `zot-s3-credentials` | `zot-registry` | Garage S3 for Zot (defined in `zot-registry/external-secrets.yaml`) |
| `zot-registry-auth` | `zot-registry` | htpasswd for Traefik registry-auth |

**Namespace rule**: CNPG resolves `DatabaseRole.spec.passwordSecret` in namespace where `DatabaseRole` reconciles (`platform-database`). Secrets that feed a `DatabaseRole` must live in `platform-database`. Backend copies for pods are separate `ExternalSecret` objects.

---

### kyverno

**What**: Kubernetes admission policy engine. Validates and mutates on admission.

Standalone Helm chart. Policies live in `kyverno-policies` app.

---

### kyverno-policies

**What**: Cluster-wide admission policies.

| Policy | Mode | Rule |
|---|---|---|
| `disallow-latest-tag` | Audit | Images must have explicit tag or digest. `latest` rejected. |
| `require-requests-limits` | Audit | Containers must declare CPU and memory `requests` and `limits`. |
| `require-run-as-non-root` | Audit | Containers must run as non-root (`runAsNonRoot: true`). |
| `restrict-image-registries` | Audit | Images must come from approved registries. |
| `restrict-compute-service-rbac-writes` | Enforce | compute-service may write Roles / RoleBindings / Namespaces only in `fci-cust-*`, and only approved role/subject pairings. |

Four Audit policies log, do not block. `restrict-compute-service-rbac-writes` uses per-rule `failureAction: Enforce`.

---

### platform-postgresql

**What**: Shared Postgres cluster for FCI platform services. Managed by CloudNativePG.

**Config**:
- 3 instances, one per worker (required anti-affinity).
- Tolerates `memory=limited:NoSchedule`.
- TLS enforced (`hostnossl reject`), password auth `scram-sha-256`.
- `enableSuperuserAccess: false`.
- Storage: `local-path`, 20 Gi per instance. Not Longhorn.
- `max_connections: 200`, `shared_buffers: 256MB`.
- `primaryUpdateMethod: switchover`.
- PodMonitor enabled.

Databases: `platform` (default), `authentik`. Four FCI backend services share `platform` database, separated by schema.

**DatabaseRoles** (CR `connectionLimit` total: 185 of 200; 15 reserved for CNPG superuser / replication / pg_monitor):

| Role | Schema | `connectionLimit` | Credentials Secret (platform-database) |
|---|---|---|---|
| `platform` | — | 80 | `platform-postgresql-credentials` |
| `authentik` | — | 60 | `authentik-postgresql-credentials` |
| `storage` | `storage` | 30 | `storage-postgresql-credentials` |
| `iam` | `iam` | 5 | `iam-postgresql-credentials` |
| `compute` | `compute` | 5 | `compute-postgresql-credentials` |
| `database` | `database` | 5 | `database-postgresql-credentials` |

Role comments still say `DB_MAX_CONNS` (5) × 1 replica = 5. Charts now set `replicaCount: 2` and `DB_MAX_CONNS: 10` (compute, iam, storage hardcoded; database-service `config.databaseMaxConnections: 10`). Role limits and chart pools do not match.

---

### valkey

**What**: Redis-compatible in-memory cache. Used by api-gateway, terminal-gateway, compute-service, iam-service, storage-service, database-service.

**Config**:
- Single primary, no replicas (`replica.enabled: false`). Persistence off — cache only.
- TLS from cert-manager `Certificate` `valkey-server` → Secret `valkey-server-tls` (private CA). Not an ExternalSecret.
- ACL: `default` user read/write/pubsub/scripting. No `FLUSHALL`, `CONFIG`, `DEBUG`, `SHUTDOWN`.
- `maxmemory: 192mb`, `maxmemory-policy: allkeys-lfu`.
- NetworkPolicy: ingress from `backend` (6379) and `monitoring` (9121 exporter).
- Prometheus exporter + ServiceMonitor.

---

### garage

**What**: S3-compatible distributed object storage. Backend for Zot registry and `storage-service`.

**Config**:
- 3-node StatefulSet, `replicationFactor: 3`, `consistencyMode: consistent`.
- One pod per worker (required anti-affinity). Tolerates `memory=limited:NoSchedule`.
- Storage per node: 100 Gi data + 2 Gi metadata (`longhorn-local` — 1 replica; Garage replicates itself).
- Region: `fci-local`.
- S3 API in-cluster only (`ingress.s3.api.enabled: false`).
- Prometheus ServiceMonitor enabled.

---

### authentik

**What**: OIDC identity provider. All user auth goes through Authentik.

**Config**:
- 2 server replicas, 2 worker replicas. Hard pod anti-affinity.
- Backed by `platform-postgresql` (`authentik` database). TLS `verify-full`, CA mount.
- Secrets from OpenBao via ExternalSecret.
- Public endpoint: `https://auth.freecloudinitiative.com` — Let's Encrypt via cert-manager.
- Ingress on Traefik `websecure` + security-headers middleware.
- Outpost discovery disabled. Built-in Postgres disabled.
- `blueprint.yaml` ConfigMap exists. `values.yaml` sets `blueprints.configMaps: []` — Authentik does not load it.

---

### cloudflared

**What**: Cloudflare Tunnel daemon. Public endpoints without inbound firewall ports.

**Config**:
- 2 replicas. Image `cloudflare/cloudflared:2026.8.2`.
- Tunnel token never in Git — OpenBao via ExternalSecret `cloudflared-tunnel-token`.
- Routes to Traefik. Tunnel DNS lives in `terraform-cloudflare-infra`, not this repo.

---

### zot-registry

**What**: OCI container image registry. FCI services pull images from here.

**Config**:
- Single replica.
- Backend: Garage S3 (`garage.garage.svc.cluster.local:3900`, bucket `zot-registry`, region `fci-local`).
- S3 credentials from ExternalSecret `zot-s3-credentials`.
- Public endpoint: `https://registry.freecloudinitiative.com` — Let's Encrypt.
- Auth via Traefik middleware `zot-registry-registry-auth`.
- GC enabled, 24h delay.
- Prometheus metrics at `/metrics`.

---

### argocd

**What**: ArgoCD self-configuration. ArgoCD manages own ConfigMaps through GitOps.

**Config**:
- `argocd-cm.yaml`: resource health checks, custom resource exclusions.
- `argocd-cmd-params-cm.yaml`: server flags.
- `app-config.yaml`: ArgoCD `AppProject` settings. Sync-wave `10`.

---

### kube-prometheus-stack

**What**: Prometheus + Grafana + Alertmanager.

**Config**:
- Prometheus: 14-day retention, 10 Gi PVC (`local-path`). Scrapes all ServiceMonitors.
- Grafana: admin credentials from OpenBao ExternalSecret. Four datasources: Prometheus, Loki, Tempo, Alloy.
- Exposed via Traefik at `/grafana` and `/prometheus`.

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

**Config**: Single binary, 1 replica. OTLP gRPC 4317 + HTTP 4318. `local-path` 10 Gi PVC.

---

### opentelemetry

**What**: OTel Collector. Central telemetry router — traces and logs from FCI services, forward to Tempo and Loki.

**Config**:
- Receives: OTLP gRPC (4317) + OTLP HTTP (4318).
- Traces: OTel → Tempo (`tempo.monitoring.svc.cluster.local:4317`).
- Logs: OTel → Loki (`loki-gateway.monitoring.svc.cluster.local:80`).
- Batch: 1 s timeout, 256 items.
- Memory limiter: 80% limit.
- Extra Service `opentelemetry-collector-external` (LoadBalancer) on 4317/4318/8888.

Chart Service name expected by most backends: `opentelemetry-collector.monitoring.svc.cluster.local:4317`. database-service `values.yaml` still sets `otel-collector.monitoring.svc.cluster.local:4317` — that hostname does not match this Service.

---

### alloy

**What**: Grafana Alloy — one per node. Scrapes node metrics and pod logs, ships to Loki / Prometheus.

---

---

## Applications

All seven Applications source `https://github.com/freecloudinitiative/k3s-manifests.git` at `applications/<name>`. Charts live next to `app.yaml`. Helm parameters set `image.tag` and `imagePullSecrets[0].name=zot-registry-pull-credentials`.

---

### api-gateway

**What**: HTTP reverse proxy and auth gateway for FCI backend services.

**Namespace**: `backend`. **Sync**: auto, prune, selfHeal, ServerSideApply.

**Image**: `registry.freecloudinitiative.com/api-gateway:sha-0ac98efb497a`. `replicaCount: 2`.

**Secrets (namespace `backend`)**:

| Secret | Key | Consumed as | Source |
|---|---|---|---|
| `api-gateway-signing-key` | `internal-signing.key` | volume `/etc/fci/keys/internal-signing.key` | OpenBao `api-gateway/internal-signing-key` |
| `valkey-password` | `password` | `VALKEY_PASSWORD` | OpenBao `valkey/password` |
| `valkey-ca-cert` | `ca.crt` | volume `/etc/fci/tls/ca.crt` | OpenBao `valkey/ca-cert` |

No Ingress. NetworkPolicy admits `frontend` only.

---

### compute-service

**What**: VM lifecycle management. Chart at `applications/compute-service`.

**Namespace**: `backend`. **Sync**: automated **off**. Placeholder tag would ImagePullBackOff if auto-sync ran.

**Image**: `registry.freecloudinitiative.com/compute-service:sha-xxxxxxxxxxxx`. Re-enable `syncPolicy.automated` when real tag exists. `replicaCount: 2`. `DB_MAX_CONNS: 10`.

**Secrets (namespace `backend`)**:

| Secret | Key | Consumed as | Source |
|---|---|---|---|
| `compute-service-postgresql-credentials` | `url` | `DATABASE_URL`; URL CA path `/etc/compute-service/postgres/ca.crt` | OpenBao `compute/postgresql-password` |
| `compute-service-postgresql-ca-cert` | `ca.crt` | volume `/etc/compute-service/postgres` | OpenBao `platform-postgresql/ca-cert` |
| `compute-service-valkey-password` | `password` | `VALKEY_PASSWORD` | OpenBao `valkey/password` |
| `compute-service-valkey-ca-cert` | `ca.crt` | volume `/etc/compute-service/valkey/ca.crt` | OpenBao `valkey/ca-cert` |
| `compute-service-internal-public-key` | `internal-public.pem` | `/etc/compute-service/internal/internal-public.pem` | OpenBao `api-gateway/internal-public-key` |
| `terminal-gateway-public-key` (shared) | `internal-public.pem` | `/etc/compute-service/terminal-gateway/terminal-gateway-public.pem` | OpenBao `terminal-gateway/internal-public-key`; owned by `external-secret-terminal.yaml` |

---

### database-service

**What**: Customer database (CNPG) management. Chart at `applications/database-service`.

**Namespace**: `backend`. **Sync**: auto, prune, selfHeal, ServerSideApply.

**Image**: `ghcr.io/freecloudinitiative/database-service:sha-f247d60ac4de`. Other services use `registry.freecloudinitiative.com`. Chart falls back to `Chart.appVersion` (`0.1.0`) if `image.tag` and `image.digest` are both empty — siblings `fail` instead. `replicaCount: 2`. `config.databaseMaxConnections: 10`.

**Secrets (namespace `backend`)**:

| Secret | Key | Consumed as | Source |
|---|---|---|---|
| `database-service-config` | `DATABASE_URL` | `secretKeyRef` env; `sslrootcert=/certs/platform-postgresql/ca.crt` | OpenBao `database/postgresql-password` |
| `platform-postgresql-ca-bundle` | `ca.crt` | volume `/certs/platform-postgresql/ca.crt` | OpenBao `platform-postgresql/ca-cert` |
| `internal-token-public-key` | `internal-public.pem` | volume `/etc/fci/internal-token/internal-public.pem` | OpenBao `api-gateway/internal-public-key` |
| `valkey-password` | `password` | `VALKEY_PASSWORD` — same Secret as api-gateway | OpenBao `valkey/password` |
| `valkey-ca-cert` | `ca.crt` | volume `/etc/fci/valkey/ca.crt` — same Secret as api-gateway | OpenBao `valkey/ca-cert` |

**ExternalSecrets** (`infrastructure/external-secrets/external-secret-database.yaml`):
- `database-postgresql-credentials` (namespace `platform-database`)
- `database-service-config` (namespace `backend`)
- `database-service-postgresql-ca-cert` → target `platform-postgresql-ca-bundle`
- `database-service-internal-public-key` → target `internal-token-public-key`

**Follow-up**: `internal-token-public-key` does not follow `database-service-*` naming. Rename needs chart + ExternalSecret together.

---

### iam-service

**What**: Identity and access management. Chart at `applications/iam-service`.

**Namespace**: `backend`. **Sync**: automated **off**. Same placeholder rule as compute-service.

**Image**: `registry.freecloudinitiative.com/iam-service:sha-xxxxxxxxxxxx`. `replicaCount: 2`. `DB_MAX_CONNS: 10`.

**Secrets (namespace `backend`)**:

| Secret | Key | Consumed as | Source |
|---|---|---|---|
| `iam-service-postgresql-credentials` | `url` | `DATABASE_URL`; URL CA path `/etc/iam-service/postgres/ca.crt` | OpenBao `iam/postgresql-password` |
| `iam-service-postgresql-ca-cert` | `ca.crt` | volume `/etc/iam-service/postgres` | OpenBao `platform-postgresql/ca-cert` |
| `iam-service-internal-public-key` | `internal-public.pem` | `/etc/iam-service/internal/internal-public.pem` | OpenBao `api-gateway/internal-public-key` |
| `iam-service-valkey-password` | `password` | `VALKEY_PASSWORD` | OpenBao `valkey/password` |
| `iam-service-valkey-ca-cert` | `ca.crt` | volume `/etc/iam-service/valkey/ca.crt` | OpenBao `valkey/ca-cert` |
| `terminal-gateway-public-key` (shared) | `internal-public.pem` | `/etc/iam-service/terminal-gateway/terminal-gateway-public.pem` | OpenBao `terminal-gateway/internal-public-key`; owned by `external-secret-terminal.yaml` |

---

### storage-service

**What**: Object storage management. Chart at `applications/storage-service`. Garage S3 backend (`http://garage.garage.svc.cluster.local:3900`, region `fci-local`, bucket `platform`). Garage serves plain HTTP — `objectStore.caCertPath` empty.

**Namespace**: `backend`. **Sync**: auto, prune, selfHeal, ServerSideApply.

**Image**: `registry.freecloudinitiative.com/storage-service:sha-2f2daba0c43e`. `replicaCount: 2`. `DB_MAX_CONNS: 10`.

**Secrets (namespace `backend`)**:

| Secret | Key | Consumed as | Source |
|---|---|---|---|
| `storage-service-postgresql-credentials` | `url` | `DATABASE_URL`; URL CA path `/etc/storage-service/postgres/ca.crt` | OpenBao `storage/postgresql-password` |
| `storage-service-postgresql-ca-cert` | `ca.crt` | volume `/etc/storage-service/postgres` | OpenBao `platform-postgresql/ca-cert` |
| `storage-service-objectstore-credentials` | `access-key`, `secret-key`, `ca.crt` | files `/etc/storage-service/objectstore/` | OpenBao `garage/storage-service-access-key`, `storage-service-secret-key`, `ca-cert` |
| `storage-service-valkey-password` | `password` | `VALKEY_PASSWORD` | OpenBao `valkey/password` |
| `storage-service-valkey-ca-cert` | `ca.crt` | volume `/etc/storage-service/valkey/ca.crt` | OpenBao `valkey/ca-cert` |
| `storage-service-internal-public-key` | `internal-public.pem` | `/etc/storage-service/internal/internal-public.pem` | OpenBao `api-gateway/internal-public-key` |

---

### terminal-gateway

**What**: WebSocket-to-Kubernetes exec terminal proxy. Chart at `applications/terminal-gateway`.

**Namespace**: `backend`. **Sync**: auto, prune, selfHeal, ServerSideApply.

**Image**: `registry.freecloudinitiative.com/terminal-gateway:sha-e3c09b7baefc`. `replicaCount: 2`.

**Secrets (namespace `backend`)**:

| Secret | Key | Consumed as | Source |
|---|---|---|---|
| `terminal-gateway-signing-key` | `internal-signing.key` | volume `/etc/fci/signing/internal-signing.key` | OpenBao `terminal-gateway/internal-signing-key` |
| `terminal-gateway-valkey-password` | `password` | `VALKEY_PASSWORD` | OpenBao `valkey/password` |
| `terminal-gateway-valkey-ca-cert` | `ca.crt` | volume `/etc/fci/valkey/ca.crt` | OpenBao `valkey/ca-cert` |

No Ingress. NetworkPolicy admits `backend` only. frontend nginx proxies `/ws/` → api-gateway → `/ws/terminal/` → this Service.

---

### frontend

**What**: React SPA + nginx. Chart at `applications/frontend`.

**Namespace**: `frontend`. **Sync**: auto, prune, selfHeal, ServerSideApply.

**Image**: `registry.freecloudinitiative.com/frontend:sha-7eefcc02593a`. `replicaCount: 2`.

**Ingress**: `https://frontend.freecloudinitiative.com` — Let's Encrypt (`frontend-public-tls`), Traefik `websecure` + `traefik-security-headers`. nginx proxies `/api/` and `/ws/` to `http://api-gateway.backend.svc.cluster.local:80`.

**Secrets**: `zot-registry-pull-credentials` only (image pull). No OpenBao app secret.

---

## External Prerequisites

### OpenBao

**What**: Secret store every `ExternalSecret` in this repo reads. Not a managed application — no `Application`, namespace, or chart here. Must be running, initialised, and unsealed out of band before first ArgoCD sync. See [README.md § Prerequisites](README.md) and [ARCHITECTURE.md § Secret Flow](ARCHITECTURE.md).
