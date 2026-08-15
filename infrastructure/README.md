# Infrastructure Manifests

Core Kubernetes services are managed by Argo CD using the App-of-Apps pattern.

## Access model

During the current bootstrap phase, administrative services are available from
the master-node IP through the original path routes and selected NodePorts:

```text
Argo CD:    http://MASTER_IP/argocd/ or https://MASTER_IP:30443/
Grafana:    http://MASTER_IP/grafana/ or http://MASTER_IP:30001/
Prometheus: http://MASTER_IP/prometheus/ or http://MASTER_IP:30090/
OpenBao:    http://MASTER_IP/ui/
Authentik:  http://MASTER_IP:30900/
```

This is transitional access and should be restricted by the host firewall or a
trusted source-IP allowlist. Domain-based TLS ingress will be configured later.
OpenBao traffic inside the cluster remains TLS-encrypted, and External Secrets
authenticates with a short-lived Kubernetes ServiceAccount token rather than an
administrative OpenBao token.

## Components

- `argocd`: GitOps reconciliation and configuration.
- `cert-manager`: public and internal certificate issuance.
- `external-secrets`: least-privilege synchronization from OpenBao.
- `cloudnative-pg`: PostgreSQL lifecycle, failover, TLS, role, and database management.
- `platform-postgresql`: three-instance PostgreSQL cluster for platform control-plane data and Authentik.
- `authentik`: identity provider, currently exposed through a temporary NodePort.
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
