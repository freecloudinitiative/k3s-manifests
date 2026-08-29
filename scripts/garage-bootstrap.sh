#!/usr/bin/env bash
# Applies Garage cluster layout, creates platform bucket, imports storage-service
# key, and grants bucket access. Layout bootstrap is not GitOps: node IDs are
# generated at runtime and must be assigned after pods start. Script is
# idempotent and safe to re-run.
#
# GARAGE_STORAGE_SERVICE_ACCESS_KEY and GARAGE_STORAGE_SERVICE_SECRET_KEY must
# exactly match values ansible-automation seeded to OpenBao. Mismatch leaves
# storage-service using credentials Garage does not recognize. Secret is never
# printed; Garage key-import output is suppressed because it contains secret.
set -euo pipefail

missing=""
for name in GARAGE_STORAGE_SERVICE_ACCESS_KEY GARAGE_STORAGE_SERVICE_SECRET_KEY; do
  if [ -z "${!name:-}" ]; then
    missing="$missing $name"
  fi
done
if [ -n "$missing" ]; then
  echo "garage-bootstrap.sh: required environment variables are empty or unset:$missing" >&2
  exit 2
fi

NS="${GARAGE_NAMESPACE:-garage}"
STATEFULSET="${GARAGE_STATEFULSET:-garage}"
BUCKET="${GARAGE_BUCKET:-platform}"
ZONE="${GARAGE_ZONE:-fci-local}"
CAPACITY="${GARAGE_CAPACITY:-100GB}"
KEY_NAME="${GARAGE_KEY_NAME:-storage-service}"
EXPECTED_REPLICAS="${GARAGE_EXPECTED_REPLICAS:-3}"
WAIT_TIMEOUT="${GARAGE_WAIT_TIMEOUT:-10m}"
POD="${STATEFULSET}-0"

for bin in kubectl awk sed sort; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "garage-bootstrap.sh: $bin is required but not found on PATH" >&2
    exit 2
  fi
done

garage() {
  kubectl -n "$NS" exec "$POD" -- /garage "$@"
}

echo "Waiting for Garage StatefulSet $NS/$STATEFULSET..."
desired_replicas="$(kubectl -n "$NS" get statefulset "$STATEFULSET" -o jsonpath='{.spec.replicas}')"
if [ "$desired_replicas" != "$EXPECTED_REPLICAS" ]; then
  echo "garage-bootstrap.sh: expected $EXPECTED_REPLICAS replicas, found $desired_replicas" >&2
  exit 1
fi
kubectl -n "$NS" rollout status "statefulset/$STATEFULSET" --timeout="$WAIT_TIMEOUT"

status_output="$(garage status)"
node_ids="$(printf '%s\n' "$status_output" | awk '
  /^==== HEALTHY NODES ====$/ { healthy = 1; next }
  /^==== / { healthy = 0 }
  healthy && $1 ~ /^[[:xdigit:]]{16}$/ { print $1 }
' | sort -u)"
node_count="$(printf '%s\n' "$node_ids" | awk 'NF { count++ } END { print count + 0 }')"
if [ "$node_count" != "$EXPECTED_REPLICAS" ]; then
  echo "garage-bootstrap.sh: expected $EXPECTED_REPLICAS healthy Garage nodes, found $node_count" >&2
  exit 1
fi

layout_output="$(garage layout show)"
current_version="$(printf '%s\n' "$layout_output" | awk -F ': ' '
  /^Current cluster layout version:/ { print $2; exit }
')"
if ! printf '%s\n' "$current_version" | awk '/^[[:digit:]]+$/ { found = 1 } END { exit !found }'; then
  echo "garage-bootstrap.sh: could not read current layout version" >&2
  exit 1
fi

layout_ready=1
if [ "$current_version" -eq 0 ]; then
  layout_ready=0
fi
while IFS= read -r node_id; do
  [ -n "$node_id" ] || continue
  if ! printf '%s\n' "$layout_output" | awk -v id="$node_id" '
    /^==== CURRENT CLUSTER LAYOUT ====$/ { current = 1; next }
    /^Current cluster layout version:/ { current = 0 }
    current && $1 == id && $0 !~ /gateway/ { found = 1 }
    END { exit !found }
  '; then
    layout_ready=0
  fi
done <<EOF
$node_ids
EOF

if [ "$layout_ready" -eq 1 ]; then
  echo "Garage layout version $current_version already assigns capacity to all nodes."
else
  echo "Assigning Garage layout..."
  while IFS= read -r node_id; do
    [ -n "$node_id" ] || continue
    garage layout assign --zone "$ZONE" --capacity "$CAPACITY" "$node_id"
  done <<EOF
$node_ids
EOF

  layout_output="$(garage layout show)"
  pending_version="$(printf '%s\n' "$layout_output" | awk '
    /garage layout apply --version [[:digit:]]+/ { print $NF; exit }
  ')"
  if ! printf '%s\n' "$pending_version" | awk '/^[[:digit:]]+$/ { found = 1 } END { exit !found }'; then
    echo "garage-bootstrap.sh: could not read pending layout version" >&2
    exit 1
  fi
  garage layout apply --version "$pending_version"
fi

if garage bucket info "$BUCKET" >/dev/null 2>&1; then
  echo "Garage bucket $BUCKET already exists."
else
  echo "Creating Garage bucket $BUCKET..."
  if ! garage bucket create "$BUCKET" >/dev/null; then
    garage bucket info "$BUCKET" >/dev/null
  fi
fi

key_output=""
if key_output="$(garage key info "$GARAGE_STORAGE_SERVICE_ACCESS_KEY" --show-secret 2>/dev/null)"; then
  existing_secret="$(printf '%s\n' "$key_output" | sed -n 's/^Secret key:[[:space:]]*//p')"
  if [ "$existing_secret" != "$GARAGE_STORAGE_SERVICE_SECRET_KEY" ]; then
    unset key_output existing_secret
    echo "garage-bootstrap.sh: Garage key ID exists but secret does not match OpenBao value" >&2
    exit 1
  fi
  unset key_output existing_secret
  echo "Garage storage-service key already exists and matches supplied credentials."
else
  echo "Importing Garage storage-service key..."
  # Garage prints imported secret on success. Discard command output.
  if ! garage key import \
    "$GARAGE_STORAGE_SERVICE_ACCESS_KEY" \
    "$GARAGE_STORAGE_SERVICE_SECRET_KEY" \
    -n "$KEY_NAME" --yes >/dev/null; then
    key_output="$(garage key info "$GARAGE_STORAGE_SERVICE_ACCESS_KEY" --show-secret 2>/dev/null)" || exit 1
    existing_secret="$(printf '%s\n' "$key_output" | sed -n 's/^Secret key:[[:space:]]*//p')"
    if [ "$existing_secret" != "$GARAGE_STORAGE_SERVICE_SECRET_KEY" ]; then
      unset key_output existing_secret
      echo "garage-bootstrap.sh: Garage key import failed and existing secret does not match" >&2
      exit 1
    fi
    unset key_output existing_secret
  fi
fi

echo "Granting read, write, and owner access on $BUCKET..."
garage bucket allow \
  --read --write --owner \
  --key "$GARAGE_STORAGE_SERVICE_ACCESS_KEY" \
  "$BUCKET" >/dev/null

echo
echo "Garage bootstrap verification"
garage bucket info "$BUCKET"
# No --show-secret: Garage renders secret as redacted.
garage key info "$GARAGE_STORAGE_SERVICE_ACCESS_KEY"
