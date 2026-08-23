# Infrastructure Manifests

Core Kubernetes services are managed by Argo CD using the App-of-Apps pattern.

## Access model

Everything goes through Traefik on 80/443 - no NodePorts. Locally on the LAN,
or publicly via the `cloudflared` tunnel once `terraform-cloudflare-infra` is
applied, using the master-node IP or `freecloudinitiative.com` interchangeably
today:

```text
Argo CD:    https://argocd.freecloudinitiative.com
Grafana:    https://grafana.freecloudinitiative.com
Prometheus: https://prometheus.freecloudinitiative.com
Alloy:      https://alloy.freecloudinitiative.com
Longhorn:   https://longhorn.freecloudinitiative.com
Authentik:  https://auth.freecloudinitiative.com
Registry:   https://registry.freecloudinitiative.com
Frontend:   https://frontend.freecloudinitiative.com
```

All UIs use dedicated subdomains via `Ingress` in `infrastructure/traefik`.
Authentik ForwardAuth protects ArgoCD, Grafana, Prometheus, Alloy, Longhorn, Zot with SSO.
Identity provider behind a path prefix breaks cookies and OIDC redirect URIs.

OpenBao itself is not deployed by this repo and is not routed through this
cluster's Traefik — it's an out-of-band prerequisite (see the top-level
[README.md § Prerequisites](../README.md)). OpenBao traffic inside the
cluster remains TLS-encrypted, and External Secrets authenticates with a
short-lived Kubernetes ServiceAccount token rather than an administrative
OpenBao token. Reach OpenBao's own UI/API through whatever access path the
out-of-band deployment provides.

## Components

- `argocd`: GitOps reconciliation and configuration.
- `cert-manager`: public and internal certificate issuance.
- `external-secrets`: least-privilege synchronization from OpenBao.
- `cloudnative-pg`: PostgreSQL lifecycle, failover, TLS, role, and database management.
- `platform-postgresql`: three-instance PostgreSQL cluster for platform control-plane data and Authentik.
- `authentik`: identity provider, reachable at `auth.freecloudinitiative.com`
  via a dedicated Traefik `Ingress` (TLS-only `websecure` entrypoint,
  cert-manager-issued certificate) - not a NodePort, and not a path prefix
  (Authentik doesn't tolerate running under one).
- `valkey`: private, Redis-protocol cache/Pub/Sub service for backend replicas.
- `zot-registry`: private Zot OCI registry backed by Garage object storage.
- `longhorn`: CSI block storage with explicit replicated and node-local storage classes.
- `garage`: private, three-node S3-compatible object storage for the storage service and backup targets.
- `kube-prometheus-stack`, `alloy`, `loki`, `tempo`, `opentelemetry`: private observability stack.
- `metallb`: bare-metal address allocation where an explicit public LoadBalancer is required.
- `traefik`: public HTTPS ingress controller.
- `kyverno`, `kyverno-policies`: admission controller and five cluster
  policies. Four run `Audit` (requests/limits, no `:latest`, non-root,
  registry allowlist) — report via `PolicyReport`/`ClusterPolicyReport`,
  do not block. `restrict-compute-service-rbac-writes` is `Enforce`.
- `cloudflared`: Cloudflare Tunnel connector. Forwards root domain and
  public hosts to Traefik ClusterIP. Traefik routes by hostname for all UIs.
  Ingress lives in `infrastructure/traefik`, `authentik`, `zot-registry`,
  and `applications/frontend`.
  The tunnel itself (and its DNS records) is created by the separate
  [terraform-cloudflare-infra](https://github.com/freecloudinitiative/terraform-cloudflare-infra)
  repo; this chart only runs the connector. Its `TUNNEL_TOKEN` comes from
  OpenBao via `external-secret-cloudflared.yaml` — seed it manually with
  the `tunnel_token` output from that Terraform run
  (`vault kv put secret/cloudflared tunnel-token=...` against OpenBao, or
  the equivalent OpenBao UI action).

Secrets are never stored in plaintext in this repository. OpenBao recovery
material and bootstrap credentials must remain outside both Git and Kubernetes.
`ClusterSecretStore` allow-list is `authentik`, `argocd`, `backend`, `frontend`,
`zot-registry`, `monitoring`, `platform-database`, `valkey`. Customer
namespaces must never be added. `cloudflared` is not on that list —
`cloudflared-tunnel-token` ExternalSecret cannot sync until it is.

## Identity and data bootstrap

App-of-Apps waves: namespaces (0), cert-manager / kyverno / external-secrets
(1), longhorn / loki / kyverno-policies / cloudnative-pg (2), garage +
issuers (3), metallb / platform-postgresql / valkey / zot-registry (4),
authentik (5). Full table in [ARCHITECTURE.md](../ARCHITECTURE.md).

Before secret bootstrap role can seed OpenBao, export strong unique values
for:

```sh
export AUTHENTIK_SECRET_KEY='at-least-50-random-characters'
export AUTHENTIK_POSTGRESQL_PASSWORD='at-least-24-random-characters'
export PLATFORM_POSTGRESQL_PASSWORD='at-least-24-random-characters'
export AUTHENTIK_BOOTSTRAP_PASSWORD='at-least-16-random-characters'
export AUTHENTIK_BOOTSTRAP_EMAIL='admin@freecloudinitiative.com'
export VALKEY_PASSWORD='at-least-24-random-characters'
export OPENBAO_BOOTSTRAP_TOKEN='short-lived-administrative-token'
ansible-playbook playbook.yml
```

Generate these values with a cryptographically secure password manager; the
examples are length hints, not usable credentials. Revoke the OpenBao bootstrap
token immediately afterward. On first Authentik login, change the bootstrap
administrator password and enable MFA.

The frontend OIDC blueprint is included but disabled until stable public URLs
and domain-based TLS ingress are ready. Do not enable it with an IP address that
may change; OIDC redirect URIs must be exact and stable.

PostgreSQL is authoritative. Valkey is intentionally ephemeral and must only
hold reconstructable cache, rate-limit, and live-event data. Backend clients
connect using TLS to `valkey.valkey.svc.cluster.local:6379`; they must obtain the
password and internal CA through External Secrets/cert-manager rather than
embedding either in an image.

## Required production backup configuration

Three PostgreSQL replicas protect availability but are not a backup. Before
storing real user data, configure the CloudNativePG Barman Cloud plugin with an
off-cluster S3-compatible object store, WAL archiving, a daily `ScheduledBackup`,
and a retention policy. Object-store endpoint, bucket, and credentials are
environment-specific and are intentionally not committed here. A release is
not disaster-recovery-ready until a restore into a clean namespace has been
tested.

Garage may be used as an in-cluster backup target, but it is not an off-cluster
backup. Replicate critical Garage buckets and Longhorn backups to a different
physical failure domain.
