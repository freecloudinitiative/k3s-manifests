#!/usr/bin/env bash
# Reports whether each applications/<svc>/app.yaml's pinned image.digest
# matches the digest published for the tip of the source repo's default
# branch. CI tags images sha-<commit SHA> per commit (see
# applications/*/values.yaml comments and ARCHITECTURE.md) — there is no
# floating "latest" tag, and one is actively forbidden by the
# disallow-latest-tag Kyverno policy, so the tag to check is derived per
# service rather than assumed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APPLICATIONS_DIR="$REPO_ROOT/applications"

OVERRIDE_TAG=""
QUIET=0
ONLY_SERVICE=""

usage() {
  cat <<'EOF'
Usage: check-image-digests.sh [--service <name>] [--tag <tag>] [--quiet]

For each applications/<svc>/app.yaml, compares the pinned image.digest
(read from spec.source.helm.parameters) against the digest published for
sha-<commit SHA>, where <commit SHA> is the newest commit on the default
branch of the matching github.com/<owner>/<svc> source repo (derived from
image.repository) that actually has a published image — the image-build
workflow runs asynchronously after a commit lands, so this walks back
through recent commits rather than assuming the tip is already published.
Exits non-zero if any service's pinned digest is stale.

Requires: crane (https://github.com/google/go-containerregistry),
gh (GitHub CLI, authenticated)

Auth: if GHCR_USERNAME/GHCR_TOKEN and/or REGISTRY_USERNAME/REGISTRY_PASSWORD
are set, this script runs `crane auth login` for the relevant registry
host(s) (ghcr.io / registry.freecloudinitiative.com) before checking. If
unset, it relies on crane's default docker-config auth — i.e. you already
ran `docker login`/`crane auth login` yourself. GitHub auth comes from `gh`'s
own login state.

Options:
  --service <name>   Check only applications/<name>.
  --tag <tag>         Compare against this exact tag instead of deriving
                      sha-<commit SHA> from the source repo's default branch.
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
      OVERRIDE_TAG="${2:?--tag requires a value}"
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

for bin in crane yq gh; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "check-image-digests.sh: $bin is required but not found on PATH" >&2
    exit 2
  fi
done

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

ERR_FILE="$(mktemp)"
trap 'rm -f "$ERR_FILE"' EXIT

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
  owner_repo="${repository#*/}"
  login_host_if_needed "$host"

  if [ -n "$OVERRIDE_TAG" ]; then
    tag="$OVERRIDE_TAG"
    if ! published_digest="$(crane digest "$repository:$tag" 2>"$ERR_FILE")"; then
      echo "ERROR  $svc  failed to resolve $repository:$tag: $(cat "$ERR_FILE")" >&2
      status=1
      continue
    fi
  else
    # The image-build workflow publishes asynchronously after a commit lands
    # (ARCHITECTURE.md: "Publish must succeed before tag is promoted"), so the
    # default branch tip may not have a published image yet. Walk back through
    # recent commits and compare against the newest one that does.
    if ! commit_shas="$(gh api "repos/$owner_repo/commits" -q '.[].sha' 2>"$ERR_FILE")"; then
      echo "ERROR  $svc  failed to look up commits for github.com/$owner_repo: $(cat "$ERR_FILE")" >&2
      status=1
      continue
    fi

    tag=""
    published_digest=""
    behind=0
    while IFS= read -r commit_sha; do
      candidate_tag="sha-$commit_sha"
      if published_digest="$(crane digest "$repository:$candidate_tag" 2>"$ERR_FILE")"; then
        tag="$candidate_tag"
        break
      fi
      behind=$((behind + 1))
    done <<EOF
$commit_shas
EOF

    if [ -z "$tag" ]; then
      echo "ERROR  $svc  no published image found for any of the last $behind commits on github.com/$owner_repo's default branch" >&2
      status=1
      continue
    fi
    if [ "$behind" -gt 0 ] && [ "$QUIET" -ne 1 ]; then
      echo "NOTE   $svc  default branch is $behind commit(s) ahead of the newest published image; comparing against $tag" >&2
    fi
  fi

  if [ "$pinned_digest" != "$published_digest" ]; then
    printf 'STALE  %s  pinned %.16s…  published %.16s… (%s)\n' "$svc" "$pinned_digest" "$published_digest" "$tag"
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
