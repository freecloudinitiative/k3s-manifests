#!/usr/bin/env bash
# Reports whether each applications/<svc>/app.yaml's pinned image.digest
# matches the digest currently published for image.repository:<tag>.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APPLICATIONS_DIR="$REPO_ROOT/applications"

TAG="latest"
QUIET=0
ONLY_SERVICE=""

usage() {
  cat <<'EOF'
Usage: check-image-digests.sh [--service <name>] [--tag <tag>] [--quiet]

For each applications/<svc>/app.yaml, compares the pinned image.digest
(read from spec.source.helm.parameters) against the digest currently
published for that chart's image.repository:<tag> (default tag: latest).
Exits non-zero if any service's pinned digest is stale.

Requires: crane (https://github.com/google/go-containerregistry)

Auth: if GHCR_USERNAME/GHCR_TOKEN and/or REGISTRY_USERNAME/REGISTRY_PASSWORD
are set, this script runs `crane auth login` for the relevant registry
host(s) (ghcr.io / registry.freecloudinitiative.com) before checking. If
unset, it relies on crane's default docker-config auth — i.e. you already
ran `docker login`/`crane auth login` yourself.

Options:
  --service <name>   Check only applications/<name>.
  --tag <tag>         Tag to compare pinned digests against (default: latest).
  --quiet             Suppress OK lines; print only STALE lines and errors.
  -h, --help          Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --service)
      ONLY_SERVICE="${2:?--service requires a value}"
      shift 2
      ;;
    --tag)
      TAG="${2:?--tag requires a value}"
      shift 2
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "check-image-digests.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v crane >/dev/null 2>&1; then
  echo "check-image-digests.sh: crane is required but not found on PATH" >&2
  echo "  https://github.com/google/go-containerregistry#installation" >&2
  exit 2
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "check-image-digests.sh: yq is required but not found on PATH" >&2
  exit 2
fi

LOGGED_IN_HOSTS=""

login_host_if_needed() {
  local host="$1"
  case " $LOGGED_IN_HOSTS " in
    *" $host "*) return 0 ;;
  esac
  LOGGED_IN_HOSTS="$LOGGED_IN_HOSTS $host"

  local user="" pass=""
  case "$host" in
    ghcr.io)
      user="${GHCR_USERNAME:-}"
      pass="${GHCR_TOKEN:-}"
      ;;
    registry.freecloudinitiative.com)
      user="${REGISTRY_USERNAME:-}"
      pass="${REGISTRY_PASSWORD:-}"
      ;;
  esac

  if [ -n "$user" ] && [ -n "$pass" ]; then
    crane auth login "$host" -u "$user" -p "$pass" >/dev/null
  fi
}

status=0
matched=0

for app_yaml in "$APPLICATIONS_DIR"/*/app.yaml; do
  svc="$(basename "$(dirname "$app_yaml")")"

  if [ -n "$ONLY_SERVICE" ] && [ "$svc" != "$ONLY_SERVICE" ]; then
    continue
  fi
  matched=1

  values_yaml="$APPLICATIONS_DIR/$svc/values.yaml"
  if [ ! -f "$values_yaml" ]; then
    echo "ERROR  $svc  missing values.yaml at $values_yaml" >&2
    status=1
    continue
  fi

  pinned_digest="$(yq -r '.spec.source.helm.parameters[] | select(.name == "image.digest") | .value' "$app_yaml")"
  repository="$(yq -r '.image.repository' "$values_yaml")"

  if [ -z "$pinned_digest" ] || [ "$pinned_digest" = "null" ]; then
    echo "ERROR  $svc  no image.digest helm parameter in $app_yaml" >&2
    status=1
    continue
  fi
  if [ -z "$repository" ] || [ "$repository" = "null" ]; then
    echo "ERROR  $svc  no image.repository in $values_yaml" >&2
    status=1
    continue
  fi

  host="${repository%%/*}"
  login_host_if_needed "$host"

  if ! published_digest="$(crane digest "$repository:$TAG" 2>/tmp/check-image-digests.$$.err)"; then
    echo "ERROR  $svc  failed to resolve $repository:$TAG: $(cat /tmp/check-image-digests.$$.err)" >&2
    rm -f "/tmp/check-image-digests.$$.err"
    status=1
    continue
  fi
  rm -f "/tmp/check-image-digests.$$.err"

  if [ "$pinned_digest" != "$published_digest" ]; then
    printf 'STALE  %s  pinned %.16s…  published %.16s…\n' "$svc" "$pinned_digest" "$published_digest"
    status=1
  elif [ "$QUIET" -ne 1 ]; then
    printf 'OK     %s  %.16s…\n' "$svc" "$pinned_digest"
  fi
done

if [ -n "$ONLY_SERVICE" ] && [ "$matched" -eq 0 ]; then
  echo "check-image-digests.sh: no service '$ONLY_SERVICE' found under $APPLICATIONS_DIR" >&2
  exit 2
fi

exit "$status"
