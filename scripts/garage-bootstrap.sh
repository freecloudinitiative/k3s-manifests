#!/usr/bin/env bash
# Wrapper only — the real script lives in
# infrastructure/garage/bootstrap-script-configmap.yaml so manual runs and
# the ArgoCD PostSync Job run identical code. Edit the ConfigMap, not this
# file.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec /bin/bash <(
  awk '/^  garage-bootstrap\.sh: \|$/{f=1;next} f&&(/^    /||/^$/){sub(/^    /,"");print;next} f{exit}' \
    "$SCRIPT_DIR/../infrastructure/garage/bootstrap-script-configmap.yaml"
) "$@"
