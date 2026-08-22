# Infrastructure Manifests

Core Kubernetes services are managed by Argo CD using the App-of-Apps pattern.

## Access model

Everything goes through Traefik on 80/443 - no NodePorts. Locally on the LAN,
or publicly via the `cloudflared` tunnel once `terraform-cloudflare-infra` is
applied, using the master-node IP or `freecloudinitiative.com` interchangeably
today:

```text
Argo CD:    http://MASTER_IP/argocd/      -> also freecloudinitiative.com/argocd
Grafana:    http://MASTER_IP/grafana/     -> also freecloudinitiative.com/grafana
Prometheus: http://MASTER_IP/prometheus/  -> also freecloudinitiative.com/prometheus
Authentik:  https://auth.freecloudinitiative.com/
```

Most services are reached by **path** on the root domain (`/argocd`,
`/grafana`, ...) via plain `Ingress` resources in `infrastructure/traefik`.
Authentik is the one exception: it gets its own **subdomain**
(`auth.freecloudinitiative.com`) with a cert-manager/Let's Encrypt
certificate on Traefik's `websecure` entrypoint, because running an identity
provider behind a path prefix breaks its cookies and OIDC redirect URIs.
Follow that same pattern (dedicated subdomain, not a path) for anything else
that can't tolerate being under a shared root domain - the `target` override
in `terraform-cloudflare-infra`'s `services` variable exists for exactly this
case.

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
- `kyverno`, `kyverno-policies`: policy-as-code admission controller and its
  cluster policies (resource requests/limits, no `:latest` tags, non-root,
  image registry allowlist). All policies currently run in `Audit` mode —
  they report violations via `PolicyReport`/`ClusterPolicyReport` but do not
  block anything. Promote individual policies to `Enforce` once existing
  workloads are compliant.
- `cloudflared`: Cloudflare Tunnel connector. Forwards the root domain (and
  Authentik's subdomain) to Traefik's ClusterIP Service; Traefik does the
  actual routing - by path for most services, by hostname for Authentik -
  via the `Ingress` resources in `infrastructure/traefik` and `authentik`.
  The tunnel itself (and its DNS records) is created by the separate
  [terraform-cloudflare-infra](https://github.com/freecloudinitiative/terraform-cloudflare-infra)
  repo; this chart only runs the connector. Its `TUNNEL_TOKEN` comes from
  OpenBao via `external-secret-cloudflared.yaml` — seed it manually with
  the `tunnel_token` output from that Terraform run
  (`vault kv put secret/cloudflared tunnel-token=...` against OpenBao, or
  the equivalent OpenBao UI action).

Secrets are never stored in plaintext in this repository. OpenBao recovery
material and bootstrap credentials must remain outside both Git and Kubernetes.
The OpenBao `ClusterSecretStore` is explicitly restricted to trusted platform
namespaces; customer namespaces must never be allowed to reference it.

## Identity and data bootstrap

The App-of-Apps sync waves install dependencies in this order: namespaces and
cert-manager/External Secrets, CloudNativePG, PostgreSQL and Valkey, then
Authentik. Before the secret bootstrap role can seed OpenBao, export strong,
unique values for:

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
