# APPS — What Apps Do

---

## Infrastructure

### namespaces

Creates Kubernetes namespaces. Each YAML carries sync-wave `0`. Root app includes `namespaces/*.yaml`. No dedicated `Application`.

Namespaces in this folder: `authentik`, `backend`, `cert-manager`, `cloudflared`, `cnpg-system`, `frontend`, `garage`, `kyverno`, `longhorn-system`, `metallb-system`, `monitoring`, `openbao`, `platform-database`, `traefik`, `valkey`, `zot-registry`.

`external-secrets` is not here. That Application sets `CreateNamespace=true`. `argocd` comes from bootstrap / out-of-band.

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
| Private CA | `ca-cluster-issuer` | Internal service certs (OpenBao, Valkey, Postgres) and internal-only-DNS hosts (Zot Registry, ArgoCD, Longhorn, Traefik dashboard) |
| Let's Encrypt production | `letsencrypt-production` | Public certs reachable over HTTP-01 (Authentik, frontend, Grafana, Prometheus, Alloy) |

**Sync-wave**: `cert-manager` Application `1`. Issuer/CA YAMLs wave `1`. `cert-manager-configs` Application `3`.

**Internal-only hosts and `ca-cluster-issuer`**: `registry`, `argocd`, `longhorn`, and `traefik`
(dashboard) are marked `internal_only = true` in `terraform-cloudflare-infra` and get an unproxied
RFC1918 A record — not reachable by the ACME server, so they cannot use HTTP-01 and must use the
internal CA instead. Two consequences:
- Any client that doesn't trust the internal CA sees a certificate warning for these four hosts.
  Acceptable for internal dashboards (ArgoCD, Longhorn, Traefik) — import the CA in a browser to
  clear it.
- containerd on every k3s node must trust the internal CA to pull from
  `registry.freecloudinitiative.com` without error (via `/etc/rancher/k3s/certs.d/` or
  `registries.yaml` — not yet configured; tracked as an `ansible-automation` follow-up). **The
  ghcr.io → internal-registry migration must not be considered complete until this node-level trust
  is in place.**

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
| `/traefik-dashboard` | Traefik dashboard (traefik) |

Public, tunnel-reachable hosts use Let's Encrypt TLS: `auth.`, `frontend.`, `grafana.`,
`prometheus.`, `alloy.freecloudinitiative.com`. Internal-only hosts (unproxied RFC1918 A record, not
reachable by the ACME server) use the internal CA instead: `registry.`, `argocd.`, `longhorn.`,
`traefik.freecloudinitiative.com` — see [cert-manager](#cert-manager) above. UIs are protected by
Authentik ForwardAuth.

---

### cloudnative-pg

**What**: CloudNativePG operator. Reconciles `Cluster`, `Database`, `DatabaseRole`.

**Config**:
- Upstream chart `cloudnative-pg` `0.29.0`.
- Namespace `cnpg-system`. Sync-wave `2`.
- Must be healthy before `platform-postgresql` (wave `4`) can apply CRs.

---

### openbao

**What**: Central secret management (Vault fork).

**Config**:
- Upstream chart `openbao` `0.28.6`.
- Namespace `openbao`. Sync-wave `2`.

---

### external-secrets

**What**: Syncs OpenBao (Vault) secrets into Kubernetes `Secret` objects.

**Config**:
- One `ClusterSecretStore` named `openbao-store`. Server `https://openbao-active.openbao.svc.cluster.local:8200`. Kubernetes SA auth, role `external-secrets`.
- Store `conditions.namespaces`: `authentik`, `argocd`, `backend`, `frontend`, `zot-registry`, `monitoring`, `platform-database`, `valkey`.
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
| `disallow-latest-tag` | Audit | Images must have explicit tag or digest. `latest` flagged, not blocked. |
| `require-requests-limits` | Audit | Containers must declare CPU and memory `requests` and `limits`. |
| `require-run-as-non-root` | Audit | Containers must run as non-root (`runAsNonRoot: true`). |
| `restrict-image-registries` | Enforce | Images must come from approved registries. |
| `restrict-compute-service-rbac-writes` | Enforce | compute-service may write Roles / RoleBindings / Namespaces only in `fci-cust-*`, and only approved role/subject pairings. |

Every policy sets `failureAction` per rule, inside each rule's `validate` block — the top-level
`spec.validationFailureAction` field is deprecated and has had no effect since Kyverno 1.13, well
before the chart version pinned in `infrastructure/kyverno/app.yaml`. Three policies (`disallow-latest-tag`,
`require-requests-limits`, `require-run-as-non-root`) log only; `restrict-image-registries` and
`restrict-compute-service-rbac-writes` block.

---

### platform-postgresql

**What**: Shared Postgres cluster for FCI platform services. Managed by CloudNativePG.

**Config**:
- 3 instances, one per worker (required anti-affinity).
- Tolerates `memory=limited:NoSchedule`.
- TLS enforced (`hostnossl reject`), password auth `scram-sha-256`.
- `enableSuperuserAccess: false`.
- Storage: `local-path`, 20 Gi per instance. Not Longhorn.
- `max_connections: 260`, `shared_buffers: 256MB`.
- `primaryUpdateMethod: switchover`.
- PodMonitor enabled.

Databases: `platform` (default), `authentik`. Four FCI backend services share `platform` database, separated by schema.

**DatabaseRoles** (CR `connectionLimit` total: 185 of 200; 15 reserved for CNPG superuser / replication / pg_monitor):

| Role | Schema | `connectionLimit` | Credentials Secret (platform-database) |
|---|---|---|---|
| `platform` | — | 80 | `platform-postgresql-credentials` |
| `authentik` | — | 60 | `authentik-postgresql-credentials` |
| `storage` | `storage` | 30 | `storage-postgresql-credentials` |
| `iam` | `iam` | 25 | `iam-postgresql-credentials` |
| `compute` | `compute` | 25 | `compute-postgresql-credentials` |
| `database` | `database` | 25 | `database-postgresql-credentials` |

PostSync Job grants `CREATE` on `platform` database to four service roles. Apply grant immediately on an existing cluster:

```bash
kubectl -n platform-database exec -it platform-postgresql-1 -- \
  psql -U platform -d platform -c \
  'GRANT CREATE ON DATABASE platform TO iam, compute, "database", storage;'
```

Role limits total 245 of `max_connections: 260`, leaving 15 for CNPG operations. Each service pool ceiling is `DB_MAX_CONNS: 10` × `replicaCount: 2` = 20; limits reserve rollout-surge headroom.

---

### valkey

**What**: Redis-compatible in-memory cache. Used by api-gateway, terminal-gateway, compute-service, storage-service, database-service.

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
- Public endpoint: `https://auth.freecloudinitiative.com` — Let's Encrypt via cert-manager. Provides ForwardAuth SSO for ArgoCD, Grafana, Prometheus, Alloy, Zot, Longhorn.
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
- Public endpoint: `https://ghcr.io/freecloudinitiative` — Let's Encrypt.
- Auth via Authentik SSO (ForwardAuth).
- GC enabled, 24h delay.
- Prometheus metrics at `/metrics`.

---

### argocd

**What**: ArgoCD self-configuration. ArgoCD manages own ConfigMaps through GitOps.

**Config**:
- `argocd-cm.yaml`: resource health checks, custom resource exclusions, OIDC client config.
- `argocd-cmd-params-cm.yaml`: server flags.
- `app-config.yaml`: ArgoCD `AppProject` settings. Sync-wave `10`.
- Exposed via `argocd.freecloudinitiative.com` behind Authentik SSO.

---

### kube-prometheus-stack

**What**: Prometheus + Grafana + Alertmanager.

**Config**:
- Prometheus: 14-day retention, 10 Gi PVC (`local-path`). Scrapes all ServiceMonitors.
- Grafana: admin credentials from OpenBao ExternalSecret. Four datasources: Prometheus, Loki, Tempo, Alloy.
- Exposed via Traefik at `grafana.` and `prometheus.` subdomains behind Authentik SSO.

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

**Note on Image Registries:** For non-prod/testing, applications pull from `ghcr.io`. For production, they will pull from `registry.freecloudinitiative.com` (Zot). The `values.yaml` for each application contains a commented-out Zot repository line (`# uncomment when deploying to prod`) to make this transition easy. The `zot-registry-pull-credentials` Secret contains authentication for both registries.

---

### api-gateway

**What**: HTTP reverse proxy and auth gateway for FCI backend services.

**Namespace**: `backend`. **Sync**: auto, prune, selfHeal, ServerSideApply. **Sync-wave**: 11.

**Image**: `ghcr.io/freecloudinitiative/api-gateway:sha-0ac98efb497a`. `replicaCount: 2`.

**Secrets (namespace `backend`)**:

| Secret | Key | Consumed as | Source |
|---|---|---|---|
| `api-gateway-signing-key` | `internal-signing.key` | volume `/etc/fci/keys/internal-signing.key` | OpenBao `api-gateway/internal-signing-key` |
| `valkey-password` | `password` | `VALKEY_PASSWORD` | OpenBao `valkey/password` |
| `valkey-ca-cert` | `ca.crt` | volume `/etc/fci/tls/ca.crt` | OpenBao `valkey/ca-cert` |

**OIDC**: `OIDC_ISSUER` (`https://auth.freecloudinitiative.com/application/o/freecloudinitiative/`) is
the public Authentik issuer URL, byte-compared against every token's `iss` claim — it must stay
public and must not change. `OIDC_JWKS_URL` (`http://authentik-server.authentik.svc.cluster.local/application/o/freecloudinitiative/jwks/`)
is a separate, in-cluster address used only to fetch the JWKS itself: api-gateway's NetworkPolicy has
no port-443 egress, so it cannot reach the public host to fetch keys, and instead dials Authentik's
in-cluster Service on pod port 9000 (see `networkpolicy.yaml` egress rule to namespace `authentik`).

No Ingress. NetworkPolicy admits `frontend` only.

---

### compute-service

**What**: VM lifecycle management. Chart at `applications/compute-service`.

**Namespace**: `backend`. **Sync**: auto, prune, selfHeal, ServerSideApply. **Sync-wave**: 11.

**Image**: `ghcr.io/freecloudinitiative/compute-service` pinned by `image.digest`. `replicaCount: 2`. `DB_MAX_CONNS: 10`.

**Metrics**: `metrics.enabled: true`, `PROMETHEUS_URL` set to `kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090`. This gates compute-service's own outbound Prometheus range queries that back the dashboard's per-engine Metrics tab (`GET /api/compute-engines/{id}/metrics`) — distinct from `/metrics` scraping, which `ServiceMonitor` already handles regardless of this flag. NetworkPolicy egress to `monitoring` includes TCP/9090 for these queries alongside TCP/4317 for OTLP export.

**Secrets (namespace `backend`)**:

| Secret | Key | Consumed as | Source |
|---|---|---|---|
| `compute-service-postgresql-credentials` | `url` | `DATABASE_URL`; URL CA path `/etc/compute-service/postgres/ca.crt` | OpenBao `compute/postgresql-password` |
| `compute-service-postgresql-ca-cert` | `ca.crt` | volume `/etc/compute-service/postgres` | OpenBao `platform-postgresql/ca-cert` |
| `compute-service-valkey-password` | `password` | `VALKEY_PASSWORD` | OpenBao `valkey/password` |
| `compute-service-valkey-ca-cert` | `ca.crt` | volume `/etc/compute-service/valkey/ca.crt` | OpenBao `valkey/ca-cert` |
| `compute-service-internal-public-key` | `internal-public.pem` | `/etc/compute-service/internal/internal-public.pem` | OpenBao `api-gateway/internal-public-key` |
| `terminal-gateway-public-key` (shared) | `internal-public.pem` | `/etc/compute-service/terminal-gateway/terminal-gateway-public.pem` | OpenBao `terminal-gateway/internal-public-key`; owned by `external-secret-terminal.yaml` |

**Follow-up**: nightly engine-disk backups (`BACKUP_ENABLED` in `internal/config/config.go`) are deliberately off for v1 — a decision, not an oversight. The chart's `backup:` values block (`applications/compute-service/values.yaml`) now renders all the dependent env vars — `BACKUP_JOB_IMAGE`, `BACKUP_ENDPOINT`, `BACKUP_REGION`, and file-based credentials `BACKUP_ACCESS_KEY_FILE`/`BACKUP_SECRET_KEY_FILE` (mounted from the existing `storage-service-objectstore-credentials` Secret; see `CHARTS.md`'s "Compute Backups" section) — but `backup.enabled` stays `false` until `compute-service` PR-01 (direct-call issuer fix) and PR-04 (data-job image) land. storage-service's `POST /internal/accounts/{accountID}/backup-bucket` route is already deployed and reachable. Restore stays unexposed via HTTP regardless (separate, unrelated v1 decision).

---

### database-service

**What**: Customer database (CNPG) management. Chart at `applications/database-service`.

**Namespace**: `backend`. **Sync**: auto, prune, selfHeal, ServerSideApply. **Sync-wave**: 11.

**Image**: `ghcr.io/freecloudinitiative/database-service:sha-f247d60ac4de`. Other services use `ghcr.io/freecloudinitiative`. Chart falls back to `Chart.appVersion` (`0.1.0`) if `image.tag` and `image.digest` are both empty — siblings `fail` instead. `replicaCount: 2`. `config.databaseMaxConnections: 10`. `config.computeServiceURL: http://compute-service.backend.svc.cluster.local`, `config.computeTimeout: 10s`.

**Metrics**: `metrics.enabled: true`, `PROMETHEUS_URL` set to `kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090`. This gates database-service's own outbound Prometheus range queries that back the dashboard's per-database Metrics tab (`GET /api/databases/{id}/metrics`) — distinct from `/metrics` scraping, which `ServiceMonitor` already handles regardless of this flag. NetworkPolicy egress to `monitoring` already covered TCP/9090 and TCP/4317 before this change.

**Namespace provisioning**: compute-service owns customer namespace creation, not this chart. database-service calls `POST /internal/accounts/{accountID}/namespace` on compute-service via `COMPUTE_SERVICE_URL` to ensure a customer's `fci-cust-*` namespace exists before creating a database. Without `COMPUTE_SERVICE_URL` set, database creation returns `412 namespace_missing` for any account that has never created a compute engine. Requires `INTERNAL_SIGNING_KEY_PATH` to also be set (it already is) — config validation fails closed at boot if only one of the pair is present.

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

**Customer-namespace write access**: this chart does not bind its own RBAC in `fci-cust-*`
namespaces. `role-template.yaml` emits only the ClusterRole `database-service-namespace-role`
(namespace-template pattern, see `CHARTS.md`); compute-service creates a namespace-scoped
RoleBinding referencing it by name whenever it provisions a customer namespace
(`compute-service/internal/k8s/rbac.go`). Without that RoleBinding, database-service cannot create,
patch, or delete CNPG `Cluster` objects in that namespace.

---

### iam-service

**What**: Identity and access management. Chart at `applications/iam-service`. Postgres-only — holds no Valkey credential.

**Namespace**: `backend`. **Sync**: auto, prune, selfHeal, ServerSideApply. **Sync-wave**: 11.

**Image**: `ghcr.io/freecloudinitiative/iam-service` pinned by `image.digest`. `replicaCount: 2`. `DB_MAX_CONNS: 10`.

**Secrets (namespace `backend`)**:

| Secret | Key | Consumed as | Source |
|---|---|---|---|
| `iam-service-postgresql-credentials` | `url` | `DATABASE_URL`; URL CA path `/etc/iam-service/postgres/ca.crt` | OpenBao `iam/postgresql-password` |
| `iam-service-postgresql-ca-cert` | `ca.crt` | volume `/etc/iam-service/postgres` | OpenBao `platform-postgresql/ca-cert` |
| `iam-service-internal-public-key` | `internal-public.pem` | `/etc/iam-service/internal/internal-public.pem` | OpenBao `api-gateway/internal-public-key` |
| `terminal-gateway-public-key` (shared) | `internal-public.pem` | `/etc/iam-service/terminal-gateway/terminal-gateway-public.pem` | OpenBao `terminal-gateway/internal-public-key`; owned by `external-secret-terminal.yaml` |
| `iam-service-authentik-token` | `token` | `/etc/iam-service/authentik/token` (`AUTHENTIK_TOKEN_PATH`), `defaultMode: 0400`, volume `optional: true` | OpenBao `authentik/admin-token` — seeded manually, no automated source (created in Authentik UI/API, not by `blueprint.yaml`) |

**Authentik integration** (`AUTHENTIK_*` env vars): user/group sync on account writes plus a
background drift reconciler, both optional and never fatal. `AUTHENTIK_URL` points at
`authentik-server.authentik.svc.cluster.local:80` (Service port 80 → pod port 9000; NetworkPolicy
egress matches the pod port, 9000). `AUTHENTIK_URL` and `AUTHENTIK_TOKEN_PATH` must both be set or
both empty — set only one and the pod crash-loops (`Validate()` in `internal/config/config.go`). A
disabled client (both empty, or Authentik unreachable) is nil-safe throughout — sync and
reconciliation just no-op. The token volume is `optional: true` so a pod starts fine even before
OpenBao is seeded with `authentik/admin-token` — the client only stats/reads the file lazily per
call, never at construction, so a missing file surfaces as a per-call error, not a stuck rollout.
`AUTHENTIK_GROUP_ADMIN/EDITOR/VIEWER/AUDITOR` ship empty: the `fci-admin`/`fci-editor`/`fci-viewer`/
`fci-auditor` groups are now declared in `infrastructure/authentik/blueprint.yaml`, but their
generated UUIDs (pks) can't be known until after the blueprint has synced to a live cluster — see
the read-back procedure documented above `authentikGroupAdmin` in `applications/iam-service/values.yaml`.
An empty group ID skips assignment for that role, not fatal. Prometheus metrics `authentik_drift_total`
and `authentik_reconcile_runs_total` are only populated once a real admin token is seeded.

---

### storage-service

**What**: Object storage management. Chart at `applications/storage-service`. Garage S3 backend (`http://garage.garage.svc.cluster.local:3900`, region `fci-local`, bucket `platform`). Garage serves plain HTTP — `objectStore.caCertPath` empty.

**Namespace**: `backend`. **Sync**: auto, prune, selfHeal, ServerSideApply. **Sync-wave**: 11.

**Image**: `ghcr.io/freecloudinitiative/storage-service:sha-2f2daba0c43e`. `replicaCount: 2`. `DB_MAX_CONNS: 10`.

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

**Namespace**: `backend`. **Sync**: auto, prune, selfHeal, ServerSideApply. **Sync-wave**: 11.

**Image**: `ghcr.io/freecloudinitiative/terminal-gateway:sha-e3c09b7baefc`. `replicaCount: 2`.

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

**Namespace**: `frontend`. **Sync**: auto, prune, selfHeal, ServerSideApply. **Sync-wave**: 11.

**Image**: `ghcr.io/freecloudinitiative/frontend:sha-7eefcc02593a`. `replicaCount: 2`.

**Ingress**: `https://freecloudinitiative.com` — Let's Encrypt (`frontend-public-tls`), Traefik `websecure` + `traefik-security-headers`. nginx proxies `/api/` and `/ws/` to `http://api-gateway.backend.svc.cluster.local:80`.

**Secrets**: `zot-registry-pull-credentials` only (image pull). No OpenBao app secret.

---

## Image digest drift

All seven `applications/*/app.yaml` pin `image.digest` by hand via `helm.parameters` — there is no
in-cluster image updater (no Argo CD Image Updater, no Flux automation). A service release is not
actually deployed until its digest is bumped here: **Argo CD reporting `Synced`/`Healthy` only
means the pinned digest matches what's running — it does not mean the newest service build is
running.** Nothing merges or promotes automatically; a stale pin here is silent until someone
checks.

`scripts/check-image-digests.sh` (`make check-digests`) detects that drift: for each app, it
compares the pinned `image.digest` against the digest published for `sha-<commit SHA>`, where
`<commit SHA>` is the newest commit on the default branch of the matching
`github.com/<owner>/<svc>` source repo that actually has a published image (there is no floating
`latest` tag to compare against — CI tags images `sha-<commit SHA>` per commit, and
`disallow-latest-tag` actively forbids `latest` in this cluster). The image-build workflow runs
asynchronously after a commit lands, so the script walks back through recent commits rather than
assuming the branch tip is already published. `--tag <tag>` compares against an exact tag instead.
It exits non-zero listing any service whose pin is stale,
and requires `crane`, `yq`, and an authenticated `gh` (GitHub CLI) on `PATH`. Registry auth: set
`GHCR_USERNAME`/`GHCR_TOKEN` (for `ghcr.io` repositories) and/or
`REGISTRY_USERNAME`/`REGISTRY_PASSWORD` (for `registry.freecloudinitiative.com`, once charts switch
to it) — these mirror the `ghcr-username`/`ghcr-token` and `pull-username`/`pull-password` keys
already stored at OpenBao `secret/data/zot-registry` for `zot-registry-pull-credentials`. If unset,
the script falls back to crane's default docker-config auth (i.e. a prior manual
`docker login`/`crane auth login`).

This script is not wired into a workflow (`.github/` is out of scope here) — it's a check CI can
call later. See `k3s-manifests/plans/PR-06-automate-image-digest-updates.md` for the full
rationale, including why an automatic image updater is a separate, deliberately deferred decision.

---

## Not provisioned

### Kata Containers node pool

`compute-service`'s API declares `instanceType: dedicated`, which is meant to run inside a Kata
Containers VM for hardware-level isolation. Neither this repo nor `ansible-automation` provisions
it: no `RuntimeClass`, no `fci.io/runtime=kata` node label or taint, no `kata-deploy`
installation. `compute-service/internal/instancetype.Checker` fails closed, so every `dedicated`
create is correctly rejected with `invalid_input` rather than scheduling a pod that can never
start.

This is a tracked decision, not a defect: Kata's default hypervisor (`kata-qemu`) needs nested
virtualization the cluster's Raspberry Pi (arm64) hardware doesn't provide, so a Kata pool would
realistically require adding non-Pi (`x86`) nodes to the cluster. See
`k3s-manifests/plans/PR-05-resolve-kata-node-pool.md` for the full analysis and the provisioning
path if this is ever brought into scope.

---

## External Prerequisites

### OpenBao

**What**: Secret store every `ExternalSecret` in this repo reads. Not a managed application — no `Application`, namespace, or chart here. Must be running, initialised, and unsealed out of band before first ArgoCD sync. See [README.md § Prerequisites](README.md) and [ARCHITECTURE.md § Secret Flow](ARCHITECTURE.md).
