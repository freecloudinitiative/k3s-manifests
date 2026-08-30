#!/usr/bin/env bash
# Applies Garage cluster layout, creates one bucket, imports one key, and grants
# bucket access per run. Run once for each bucket/key pair. Parameterize pair
# with GARAGE_BUCKET, GARAGE_KEY_NAME, GARAGE_ACCESS_KEY, and GARAGE_SECRET_KEY.
# Layout bootstrap is not GitOps: node IDs are generated at runtime and must be
# assigned after pods start. Script is idempotent and safe to re-run.
#
# Supplied credentials must exactly match values ansible-automation seeded to
# OpenBao. Mismatch leaves consumer using credentials Garage does not recognize.
# Secret is never printed; Garage key-import output is suppressed because it
# contains secret.
#
# Zot registry bucket:
#   GARAGE_BUCKET=zot-registry GARAGE_KEY_NAME=zot \
#   GARAGE_ACCESS_KEY=... GARAGE_SECRET_KEY=... ./scripts/garage-bootstrap.sh
set -euo pipefail

GARAGE_ACCESS_KEY="${GARAGE_ACCESS_KEY:-${GARAGE_STORAGE_SERVICE_ACCESS_KEY:-}}"
GARAGE_SECRET_KEY="${GARAGE_SECRET_KEY:-${GARAGE_STORAGE_SERVICE_SECRET_KEY:-}}"

missing=""
for name in GARAGE_ACCESS_KEY GARAGE_SECRET_KEY; do
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

for bin in kubectl awk jq sed sort; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "garage-bootstrap.sh: $bin is required but not found on PATH" >&2
    exit 2
  fi
done

# Match bytesize 2.3.1 units accepted by Garage. JSON layout reports bytes,
# avoiding lossy comparison against human-formatted `garage layout show` output.
if ! capacity_bytes="$(printf '%s\n' "$CAPACITY" | awk '
  {
    value = toupper($0)
    gsub(/[[:space:]]/, "", value)
    if (value !~ /^[0-9]+([.][0-9]+)?(B|KB|KIB|MB|MIB|GB|GIB|TB|TIB|PB|PIB)?$/) {
      exit 1
    }
    unit = value
    sub(/^[0-9]+([.][0-9]+)?/, "", unit)
    number = value
    sub(/(B|KB|KIB|MB|MIB|GB|GIB|TB|TIB|PB|PIB)$/, "", number)
    factor = 1
    if (unit == "KB") factor = 1000
    if (unit == "KIB") factor = 1024
    if (unit == "MB") factor = 1000 ^ 2
    if (unit == "MIB") factor = 1024 ^ 2
    if (unit == "GB") factor = 1000 ^ 3
    if (unit == "GIB") factor = 1024 ^ 3
    if (unit == "TB") factor = 1000 ^ 4
    if (unit == "TIB") factor = 1024 ^ 4
    if (unit == "PB") factor = 1000 ^ 5
    if (unit == "PIB") factor = 1024 ^ 5
    bytes = int(number * factor)
    if (bytes < 1) exit 1
    printf "%.0f\n", bytes
  }
')"; then
  echo "garage-bootstrap.sh: invalid GARAGE_CAPACITY: $CAPACITY" >&2
  exit 2
fi

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

layout_json="$(garage json-api GetClusterLayout)"
current_version="$(printf '%s\n' "$layout_json" | jq -r '.version // empty')"
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
  if ! printf '%s\n' "$layout_json" | jq -e \
    --arg id "$node_id" \
    --arg zone "$ZONE" \
    --argjson capacity "$capacity_bytes" \
    '[.roles[] | select(.id | startswith($id)) |
      select(.zone == $zone and .capacity == $capacity)] | length == 1' \
    >/dev/null; then
    layout_ready=0
  fi
done <<EOF
$node_ids
EOF

if [ "$layout_ready" -eq 1 ]; then
  echo "Garage layout version $current_version already matches zone and capacity."
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
if key_output="$(garage key info "$GARAGE_ACCESS_KEY" --show-secret 2>/dev/null)"; then
  existing_secret="$(printf '%s\n' "$key_output" | sed -n 's/^Secret key:[[:space:]]*//p')"
  if [ "$existing_secret" != "$GARAGE_SECRET_KEY" ]; then
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
    "$GARAGE_ACCESS_KEY" \
    "$GARAGE_SECRET_KEY" \
    -n "$KEY_NAME" --yes >/dev/null; then
    key_output="$(garage key info "$GARAGE_ACCESS_KEY" --show-secret 2>/dev/null)" || exit 1
    existing_secret="$(printf '%s\n' "$key_output" | sed -n 's/^Secret key:[[:space:]]*//p')"
    if [ "$existing_secret" != "$GARAGE_SECRET_KEY" ]; then
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
  --key "$GARAGE_ACCESS_KEY" \
  "$BUCKET" >/dev/null

echo
echo "Garage bootstrap verification"
garage bucket info "$BUCKET"
# No --show-secret: Garage renders secret as redacted.
garage key info "$GARAGE_ACCESS_KEY"
