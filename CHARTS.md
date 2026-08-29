# CHARTS — How Application Charts Live Here

## Where Charts Live

Application Helm charts live at `applications/<service>/` next to ArgoCD
Application descriptor (`app.yaml`).

- **`applications/<service>/`** — `app.yaml`, `Chart.yaml`, `values.yaml`,
  `templates/`, and `rules/` when the chart loads Prometheus rules via
  `.Files.Get`.

No `charts/` directory. Do not add one.

Inline infrastructure chart: `infrastructure/cloudflared/` (Chart.yaml +
templates). Other infrastructure apps are upstream Helm charts plus values
and extra YAML.

## YAML Only

This repo is YAML. No `go.mod`. No `.go` file. No compiled tooling. Chart
invariants go in `helm unittest` suites — YAML next to the chart they test.

If a check seems to need Go, it is the wrong check. Express it in YAML or
leave it out.

## Image Registries

Image references must carry an explicit registry host. `restrict-image-registries`
is Enforce and matches the literal string, so `cloudflare/cloudflared` is denied
while `docker.io/cloudflare/cloudflared` is not. This applies to local charts and
to any complete image reference this repo supplies through an upstream chart's
values; a chart that composes a separate registry and repository must still
render a fully-qualified reference.

The policy governs FCI's own workloads in `backend`, `frontend`, and
`fci-cust-*`. Customer compute images remain in scope through the wildcard.
Third-party infrastructure namespaces are deliberately out of scope: their
charts are controlled by the exact versions in `infrastructure/*/app.yaml`, and
image digests committed in values remain pinned. Re-audit rendered images when
bumping an upstream chart rather than expanding the admission-policy allowlist
for each vendor registry.

## Every Chart Carries Tests

Contract: every chart under `applications/<service>/` should carry a
`tests/` directory with helm-unittest suites.

```
applications/<service>/
  Chart.yaml
  values.yaml
  templates/
  tests/
    security_test.yaml
    wiring_test.yaml
    image_test.yaml
```

Suites are YAML at `applications/<service>/tests/*_test.yaml`. Run with
`helm unittest applications/<service>`.

Every Kyverno policy with `failureAction: Enforce` must have its own case
directory under `infrastructure/kyverno-policies/kyverno-tests/`. Audit-only
policies do not require one.

`applications/database-service/tests/rbac_test.yaml` is the first suite in this repo — it locks the
namespace-template ClusterRole's rendered name (see below) against the security-critical contract
with compute-service and Kyverno. Other charts have no `tests/` directory yet; `make unittest` finds
none and skips them. Add suites before claiming a chart is covered.

## Namespace-Template ClusterRoles

Some charts (`storage-service`, `database-service`) need write access inside `fci-cust-*`
namespaces that don't exist at Helm install time — compute-service creates them at runtime. Such a
chart cannot ship a namespaced `Role`, since it has no namespace name to put it in.

This pattern applies to `storage-service` and `database-service` only. compute-service does not use
it: compute-service is the service that provisions customer namespaces, so it defines its own
namespace-scoped rule set directly in Go (`compute-service/internal/k8s/rbac.go`) rather than via a
templated ClusterRole. An earlier `compute-service-namespace-role` ClusterRole existed here but was
never bound by anything — `rbac.go` builds its own `compute-service-workloads` Role instead — and its
rule set had drifted from `rbac.go`'s; it was removed rather than fixed, since keeping it accurate
would have meant maintaining the same rule set in two places.

The pattern: `role-template.yaml` emits a single `ClusterRole` named
`{{ include "<chart>.fullname" . }}-namespace-role`, labeled `fci.io/rbac-scope: namespace-template`,
and **no ClusterRoleBinding**. It defines the verb set a customer namespace's RoleBinding should
grant, nothing more — it only takes effect where compute-service's per-namespace RBAC provisioning
(`compute-service/internal/k8s/rbac.go`) creates a namespace-scoped RoleBinding naming it. Binding it
cluster-wide from within the owning chart would grant that write access in every namespace, including
platform ones — exactly what this pattern exists to avoid.

The ClusterRole's rendered *name* is a stable contract with compute-service's
`internal/k8s/config.go` defaults (`STORAGE_NAMESPACE_CLUSTERROLE`, `DATABASE_NAMESPACE_CLUSTERROLE`).
Changing a chart's release name changes `fullname` and silently breaks the binding — Kubernetes
accepts a RoleBinding pointing at a nonexistent ClusterRole and grants nothing, with no error.
Always verify the rendered name after any release-name or `fullnameOverride` change:
```bash
helm template <release> applications/<chart> --set image.tag=t | grep -A1 "kind: ClusterRole$"
```

## What a Suite Must Assert

Suites assert **security boundaries**, not style. `helm lint` and ArgoCD
catch none of these. ArgoCD applies whatever renders.

At minimum:

| Invariant | Why it cannot silently regress |
|---|---|
| No Ingress on backend services | Gateway becomes internet-reachable and bypasses frontend nginx, the intended single entry point |
| Cluster-scope RBAC is `namespaces: [get, list]` only | `pods/exec` at cluster scope means exec into any pod |
| No cluster-wide NetworkPolicy write | Controller writes NetworkPolicies into every namespace instead of one customer namespace at a time |
| No private signing key mounted into a verifier | Service that only needs to verify gets a signing key |
| Writable emptyDir when `readOnlyRootFilesystem: true` | Chart renders clean, pod crash-loops on start |
| `failedTemplate` when both `image.tag` and `image.digest` are empty | Missing ArgoCD parameter would ship `:latest` or empty tag. database-service currently falls back to `Chart.appVersion` — suite should lock the intended `fail` once that chart matches siblings |

Use helm-unittest asserts (`isKind`, `equal`, `contains`, `notExists`,
`matchRegex`, `failedTemplate`, `documentIndex`, `set`). Do not drop an
assertion because it is awkward in YAML.

Charts that `fail` when `image.tag` and `image.digest` are both empty need
a tag to render. Validation passes `--set image.tag=ci`.

## API Gateway Values

| Value | Required | Contract |
|---|---|---|
| `config.consoleTicketBindIP` | No; defaults to `true` | Binds minted console tickets to the client IP derived from the left-most `X-Forwarded-For` entry. Must equal terminal-gateway's `consoleTicket.bindIP`. The secure `true` default depends on api-gateway PR-30 preserving the inbound forwarding chain. |

## Terminal Gateway Values

| Value | Required | Contract |
|---|---|---|
| `websocket.allowedOrigins` | Yes; must be non-empty | Comma-separated WebSocket origin allow-list. Must track `applications/frontend/values.yaml` `ingress.host`; use a bare host without a scheme or port. |
| `consoleTicket.bindIP` | No; defaults to `true` | Rejects ticket redemption when the handshake client IP differs from the minting IP. Must equal api-gateway's `config.consoleTicketBindIP`; a mismatch either silently drops binding or makes every bound redemption fail. The secure `true` default depends on api-gateway PR-30. |

## Direct-Call Public Keys

Mounts the caller's public key into the callee so a direct backend-to-backend
call (bypassing api-gateway) verifies against the caller's own signing key
instead of only api-gateway's. Both are optional: the consuming config field
(`COMPUTE_SERVICE_PUBLIC_KEY_PATH` / `DATABASE_SERVICE_PUBLIC_KEY_PATH`) is
not required, so the pod still starts if the Secret is absent — that only
disables direct-call verification for the one route it covers.

| Chart | Value | Required | Contract |
|---|---|---|---|
| `storage-service` | *(none — Secret name is hardcoded, not chart-owned)* | No | Mounts the existing `compute-service-public-key` Secret (namespace `backend`, created by `infrastructure/external-secrets/external-secret-iam.yaml`) as `optional: true`, sets `COMPUTE_SERVICE_PUBLIC_KEY_PATH=/etc/storage-service/compute-service/internal-public.pem`. Enables verifying `compute-service`'s direct call to `POST /internal/accounts/{accountID}/backup-bucket`. |
| `compute-service` | `secrets.databaseServicePublicKey` | No | Mounts the existing `database-service-public-key` Secret (namespace `backend`) as `optional: true`, sets `DATABASE_SERVICE_PUBLIC_KEY_PATH=/etc/compute-service/database-service/internal-public.pem`. Enables verifying `database-service`'s direct call to `POST /internal/accounts/{accountID}/namespace`. |

## Compute Backups

`applications/compute-service/values.yaml`'s `backup:` block wires the nightly
compute-engine disk-backup scheduler (`internal/reconcile/backup.go` in
`compute-service`). It defaults `enabled: false` — flipping it to `true`
requires, in order:

1. `compute-service` PR-01 (fixes the direct-call issuer so
   `ResolveTarget` against storage-service doesn't 401 on every pass), and
2. `compute-service` PR-04 (publishes the `compute-data-job` image this
   chart's `backup.jobImage` must reference).

Turning `backup.enabled=true` before both land produces a nightly cron of
guaranteed failures.

| Value | Required when enabled | Contract |
|---|---|---|
| `backup.enabled` | — | Gates `BACKUP_ENABLED` and every other `BACKUP_*` env var, the `backup-objectstore-credentials` volume/mount, and the `garage:3900` NetworkPolicy egress rule — all render only when `true`. |
| `backup.jobImage` | Yes | Must be digest-pinned (`…@sha256:<64 hex>`); a `{{- fail }}` guard in `templates/deployment.yaml` mirrors `compute-service/internal/config/config.go`'s `Validate()` and rejects a tag at render time. |
| `backup.schedule`, `backup.retentionDays`, `backup.concurrencyPerNode` | No (defaults match compute-service's own Go defaults) | Standard 5-field cron, retention window, and per-node concurrency cap. |
| `backup.bucketEndpoint` | Yes | Rendered as `BACKUP_ENDPOINT` (not `BACKUP_BUCKET_ENDPOINT` — the values key and the env var name diverge here). storage-service's own base URL, used to resolve each account's backup bucket via `POST /internal/accounts/{accountID}/backup-bucket`. |
| `backup.region` | No | Rendered as `BACKUP_REGION`; empty string is a valid default, matching compute-service's Go default. |
| *(none — Secret name is hardcoded, not chart-owned)* | Yes | Mounts the existing `storage-service-objectstore-credentials` Secret (namespace `backend`, created by `infrastructure/external-secrets/external-secret-storage.yaml`) at `/etc/compute-service/backup-objectstore`, sets `BACKUP_ACCESS_KEY_FILE` / `BACKUP_SECRET_KEY_FILE`. Reuses storage-service's Garage credentials rather than provisioning a second copy — compute-service's own scheduler deletes expired backup objects directly from Garage during retention sweeps, bypassing storage-service. |

RBAC needs no chart change: `compute-service/internal/k8s/rbac.go`'s
`compute-service-workloads` Role (applied per-namespace by compute-service
itself at runtime, not by this chart's static `clusterrole.yaml` — see
"Namespace-Template ClusterRoles" above) already grants `batch/jobs`
`create`/`get`/`list`/`watch`/`delete`.

## How to Run Validation Locally

Install Helm, yamllint, kubeconform, and helm-unittest plugin:

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest.git --version v1.1.2
# Helm 4: add --verify=false (git plugin installs have no GPG webhook).
```

From this repo root:

```bash
make validate
```

That runs, in order:

1. `yamllint .` and `helm lint` every `Chart.yaml` under `infrastructure/`
   and `applications/`
2. `helm template` every chart to `/dev/null`
3. `helm template` piped through `kubeconform -strict -summary -ignore-missing-schemas`
4. `helm unittest` for any `tests/` under `infrastructure/` or
   `applications/` (skips if none)

`kubeconform` stays in strict mode. `-ignore-missing-schemas` skips CRDs
that have no built-in schema (`ServiceMonitor`, `PrometheusRule`). It does
not disable strict checking of core Kubernetes types.

Individual targets: `make lint`, `make template`, `make schema`,
`make unittest`.
