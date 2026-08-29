#!/usr/bin/env bash
# Local test harness for restrict-compute-service-rbac-writes.yaml.
#
# `kyverno test` cannot attach admission-request subjects, and the Kyverno
# CLI version paired with the pinned chart rejects `subjects` in a Values
# file. This harness therefore uses `kyverno apply --userinfo` with the
# compute-service ServiceAccount username in values.yaml.
set -euo pipefail
cd "$(dirname "$0")"

# kyverno apply exits non-zero whenever any result is fail/error, which
# several of these cases deliberately are — capture the report without
# letting that trip `set -e`.
report=$(kyverno apply ../../restrict-compute-service-rbac-writes.yaml \
  -r resources.yaml \
  --userinfo values.yaml \
  --policy-report \
  --output-format json) || true

# label|kind|name|namespace|expected-result. The allowed Role names repeat,
# so their per-case fci-cust-* namespaces identify them in the report. Plain
# array, not an associative one — macOS ships bash 3.2.
cases=(
  "role-workloads-exact|Role|compute-service-workloads|fci-cust-role-workloads-exact|pass"
  "role-terminal-exact|Role|terminal-gateway-exec|fci-cust-role-terminal-exact|pass"
  "role-workloads-extra-resource|Role|compute-service-workloads|fci-cust-role-workloads-extra-resource|fail"
  "role-workloads-extra-apigroup|Role|compute-service-workloads|fci-cust-role-workloads-extra-apigroup|fail"
  "role-workloads-extra-verb|Role|compute-service-workloads|fci-cust-role-workloads-extra-verb|fail"
  "role-terminal-with-workload-rules|Role|terminal-gateway-exec|fci-cust-role-terminal-with-workload-rules|fail"
  "role-wrong-name|Role|something-else|fci-cust-role-wrong-name|fail"
  "role-platform-namespace|Role|compute-service-workloads|backend|fail"
  "namespace-fci-cust-new|Namespace|fci-cust-new||pass"
  "namespace-platform|Namespace|kube-system||fail"
)

fail=0

for case in "${cases[@]}"; do
  IFS='|' read -r label kind name namespace want <<<"$case"
  # A Role evaluates both namespace and content rules. Collapse their
  # results with fail > error > pass so any enforcing violation wins.
  got=$(jq -r --arg kind "$kind" --arg name "$name" --arg namespace "$namespace" \
    '[.results[] | select(.resources[0].kind == $kind and
      .resources[0].name == $name and
      (.resources[0].namespace // "") == $namespace) | .result] |
      if index("fail") then "fail"
      elif index("error") then "error"
      elif index("pass") then "pass"
      else ""
      end' <<<"$report")
  if [[ -z "$got" ]]; then
    echo "FAIL $label: expected $want, got no result (rule did not evaluate it)"
    fail=1
  elif [[ "$got" != "$want" ]]; then
    echo "FAIL $label: expected $want, got $got"
    fail=1
  else
    echo "ok   $label: $got"
  fi
done

if [[ "$fail" -ne 0 ]]; then
  echo "restrict-compute-service-rbac-writes local test: FAILED"
  exit 1
fi
echo "restrict-compute-service-rbac-writes local test: all cases passed"
