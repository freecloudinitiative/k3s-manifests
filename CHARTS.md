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

No `tests/` directory exists yet. `make unittest` finds none and skips.
Add suites before claiming a chart is covered.

## Namespace-Template ClusterRoles

Some charts (`storage-service`, `database-service`) need write access inside `fci-cust-*`
namespaces that don't exist at Helm install time — compute-service creates them at runtime. Such a
chart cannot ship a namespaced `Role`, since it has no namespace name to put it in.

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
