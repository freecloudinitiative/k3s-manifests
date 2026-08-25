#!/usr/bin/env bash
# Local test harness for deny-pods-on-restoring-pvcs.yaml.
#
# `kyverno test` cannot exercise context.apiCall entries at all (the CLI's
# context loader only wires up a client, and therefore apiCall support, in
# the `apply` code path — see kyverno/kyverno#15427, still open). This
# policy's whole point is a context.apiCall PVC lookup, so `kyverno apply`
# with local resources + a values file (which does support apiCall,
# resolved against the same locally-supplied resources with no live
# cluster) is the only way to unit test it without a real API server.
set -euo pipefail
cd "$(dirname "$0")"

# kyverno apply exits non-zero whenever any result is fail/error, which
# several of these cases deliberately are — capture the report without
# letting that trip `set -e`.
report=$(kyverno apply ../../deny-pods-on-restoring-pvcs.yaml \
  -r resources.yaml \
  -f values.yaml \
  --policy-report \
  --output-format json) || true

# name:expected-result pairs (pass|fail|error). Plain array, not an
# associative one — macOS ships bash 3.2, which has no `declare -A`. Any
# Pod not listed here is expected to be entirely absent from the report
# (excluded by namespaceSelector before the rule ever evaluates it) —
# that's pod-guest-noncustomer-ns, the non-customer-namespace case.
cases=(
  "pod-guest-unlocked:pass"
  "pod-guest-locked-a:fail"
  "pod-restore-b:pass"
  "pod-restore-wrong-id:fail"
  "pod-mixed-mounts:fail"
  "pod-pvc-lookup-failure:error"
)

fail=0

for case in "${cases[@]}"; do
  name="${case%%:*}"
  want="${case##*:}"
  got=$(jq -r --arg name "$name" \
    '.results[] | select(.resources[0].name == $name) | .result' <<<"$report")
  if [[ -z "$got" ]]; then
    echo "FAIL $name: expected $want, got no result (rule did not evaluate it)"
    fail=1
  elif [[ "$got" != "$want" ]]; then
    echo "FAIL $name: expected $want, got $got"
    fail=1
  else
    echo "ok   $name: $got"
  fi
done

excluded_got=$(jq -r '.results[] | select(.resources[0].name == "pod-guest-noncustomer-ns") | .result' <<<"$report")
if [[ -n "$excluded_got" ]]; then
  echo "FAIL pod-guest-noncustomer-ns: expected no result (namespaceSelector excludes it), got $excluded_got"
  fail=1
else
  echo "ok   pod-guest-noncustomer-ns: excluded"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "deny-pods-on-restoring-pvcs local test: FAILED"
  exit 1
fi
echo "deny-pods-on-restoring-pvcs local test: all cases passed"
