#!/usr/bin/env bash
# Local test harness for restrict-image-registries.yaml.
set -euo pipefail
cd "$(dirname "$0")"

# kyverno apply exits non-zero whenever any result is fail/error, which
# several of these cases deliberately are — capture the report without
# letting that trip `set -e`.
report=$(kyverno apply ../../restrict-image-registries.yaml \
  -r resources.yaml \
  --policy-report \
  --output-format json) || true

# name:expected-result pairs. Plain array, not an associative one — macOS
# ships bash 3.2. The out-of-scope Pod is asserted separately below.
cases=(
  "pod-ghcr:pass"
  "pod-docker-qualified:pass"
  "pod-docker-bare:fail"
  "pod-zot:pass"
  "pod-compute-os:pass"
  "pod-unlisted-registry:fail"
  "pod-bad-initcontainer:fail"
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

excluded_got=$(jq -r '.results[] | select(.resources[0].name == "pod-upstream-out-of-scope") | .result' <<<"$report")
if [[ -n "$excluded_got" ]]; then
  echo "FAIL pod-upstream-out-of-scope: expected no result (namespace excludes it), got $excluded_got"
  fail=1
else
  echo "ok   pod-upstream-out-of-scope: excluded"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "restrict-image-registries local test: FAILED"
  exit 1
fi
echo "restrict-image-registries local test: all cases passed"
