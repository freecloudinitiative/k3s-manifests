# CHARTS — How Application Charts Live Here

## Where Charts Live

Application Helm charts live at `charts/<service>/`. Never beside an ArgoCD Application.

- **`applications/`** — what ArgoCD is told: `app.yaml` points at a source path and destination namespace.
- **`charts/`** — what ArgoCD renders: `Chart.yaml`, `values.yaml`, `templates/`, and `tests/`.

Putting a `Chart.yaml` next to an `app.yaml` under `applications/<service>/` makes it unclear which file ArgoCD reads. Keep them apart.

Inline infrastructure charts (`infrastructure/cloudflared/`, `applications/random-logger/`) stay where they are. They are not application-service charts.

## YAML Only

This repo is YAML. No `go.mod`. No `.go` file. No compiled tooling. Chart invariants are asserted with `helm unittest` suites — YAML files next to the chart they test.

If a check seems to need Go, it is the wrong check. Express it in YAML or leave it out.

## Every Chart Carries Tests

Every chart under `charts/<service>/` carries a `tests/` directory with helm-unittest suites:

```
charts/<service>/
  Chart.yaml
  values.yaml
  templates/
  tests/
    security_test.yaml
    wiring_test.yaml
    image_test.yaml
```

Suites are YAML at `charts/<service>/tests/*_test.yaml`. They run with `helm unittest charts/<service>`.

## What a Suite Must Assert

Suites assert **security boundaries**, not style. `helm lint` and ArgoCD catch none of these. ArgoCD applies whatever renders.

Translate the invariants that used to live in each service's Go chart tests. At minimum:

| Invariant | Why it cannot silently regress |
|---|---|
| No Ingress on backend services | The gateway becomes internet-reachable and bypasses the frontend nginx that is the intended single entry point |
| Cluster-scope RBAC is `namespaces: [get, list]` only | `pods/exec` at cluster scope means exec into any pod in the cluster |
| No cluster-wide NetworkPolicy write | A controller writes NetworkPolicies into every namespace instead of one customer namespace at a time |
| No private signing key mounted into a verifier | A service that only needs to verify gets a signing key |
| Writable emptyDir when `readOnlyRootFilesystem: true` | Chart renders clean, pod crash-loops on start |
| `failedTemplate` when both `image.tag` and `image.digest` are empty | A missing ArgoCD parameter would otherwise ship `:latest` or an empty tag |

Use helm-unittest asserts (`isKind`, `equal`, `contains`, `notExists`, `matchRegex`, `failedTemplate`, `documentIndex`, `set`). Do not drop an assertion because it is awkward in YAML.

Charts that `fail` when `image.tag` and `image.digest` are both empty need a tag to render. Validation passes `--set image.tag=ci`.

## How to Run Validation Locally

Install Helm, yamllint, kubeconform, and the helm-unittest plugin:

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest.git --version v1.1.2
# Helm 4: add --verify=false (git plugin installs have no GPG webhook).
```

From this repo root:

```bash
make validate
```

That runs, in order:

1. `yamllint .` and `helm lint` every `Chart.yaml` under `infrastructure/`, `applications/`, and `charts/`
2. `helm template` every chart to `/dev/null`
3. `helm template` piped through `kubeconform -strict -summary -ignore-missing-schemas`
4. `helm unittest` for every chart under `charts/`

`kubeconform` stays in strict mode. `-ignore-missing-schemas` skips CRDs that have no built-in schema (`ServiceMonitor`, `PrometheusRule`). It does not disable strict checking of core Kubernetes types.

Individual targets: `make lint`, `make template`, `make schema`, `make unittest`.
