#!/usr/bin/env bash
# Build the two images a station host needs (#418): the station image the
# stations run in, and the allow-listing proxy that is their only way out of
# the internal network. See docs/runbooks/station-container.md.
#
# Usage: scripts/build-station-image.sh [--print] [station|proxy]...
#   --print  print the build commands instead of running them
# With no image named, both are built.
#
# Everything that decides what goes into an image is pinned here: the base
# images by digest and the Claude Code CLI by version. A bump is an edit to
# this file, reviewed like any other change.
#
# Exit codes: 0 built (or printed), 2 usage, 9 no container runtime.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { echo "build-station-image: $2" >&2; exit "$1"; }

# node:22-trixie-slim and alpine:3 as pulled on 2026-11-15.
STATION_BASE_IMAGE="docker.io/library/node@sha256:33d41cc7365593a3622f3f1ce1c6af788de32c0709016ec15685de7aaa681d97"
PROXY_BASE_IMAGE="docker.io/library/alpine@sha256:0f49f331d9212aff11b932863be4eb01cdf962969aa86dab7d1ee21ac6f5f52b"
CLAUDE_CODE_VERSION="2.1.322"

# The tags the runbook tells a host to export. The station tag carries the CLI
# version, so a bump cannot silently reuse an old image.
STATION_TAG="localhost/factory-station:claude-${CLAUDE_CODE_VERSION}"
PROXY_TAG="localhost/factory-egress-proxy:1"

print_only=false
targets=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --print) print_only=true; shift ;;
    station | proxy) targets+=("$1"); shift ;;
    *) die 2 "usage: scripts/build-station-image.sh [--print] [station|proxy]..." ;;
  esac
done
[[ ${#targets[@]} -gt 0 ]] || targets=(station proxy)

runtime=${FACTORY_CONTAINER_RUNTIME:-}
if [[ -n $runtime ]]; then
  command -v "$runtime" > /dev/null || die 9 "FACTORY_CONTAINER_RUNTIME=$runtime not found"
else
  for candidate in podman docker nerdctl; do
    if command -v "$candidate" > /dev/null; then
      runtime=$candidate
      break
    fi
  done
  [[ -n $runtime ]] || die 9 "no podman, docker or nerdctl on PATH (set FACTORY_CONTAINER_RUNTIME)"
fi

build() {
  if $print_only; then
    printf '%q ' "$runtime" "$@"
    printf '\n'
  else
    "$runtime" "$@"
  fi
}

for target in "${targets[@]}"; do
  case "$target" in
    station)
      build build --tag "$STATION_TAG" \
        --build-arg "BASE_IMAGE=$STATION_BASE_IMAGE" \
        --build-arg "CLAUDE_CODE_VERSION=$CLAUDE_CODE_VERSION" \
        --file "$here/containers/station/Containerfile" "$here/containers/station"
      ;;
    proxy)
      build build --tag "$PROXY_TAG" \
        --build-arg "BASE_IMAGE=$PROXY_BASE_IMAGE" \
        --file "$here/containers/egress-proxy/Containerfile" "$here/containers/egress-proxy"
      ;;
  esac
done

if ! $print_only; then
  echo "built: ${targets[*]}"
  echo "station image: $STATION_TAG"
  echo "proxy image:   $PROXY_TAG"
fi
