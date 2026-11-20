#!/usr/bin/env bash
# Tests for scripts/watcher-preflight.sh (#390).
# Covers a prepared environment (exit 0) and an unprepared one (non-zero, missing item named).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
preflight=$here/watcher-preflight.sh
chmod +x "$preflight"

fail() { echo "test-watcher-preflight: $*" >&2; exit 1; }

# Unprepared: no gh, no runtime, no credential → must fail and name something.
out=$(env -i PATH="$PATH" HOME="$HOME" bash "$preflight" 2>&1) && fail "unprepared environment exited zero"
echo "$out" | grep -q "missing" || fail "unprepared run did not name a missing item: $out"
echo "unprepared: ok ($out)"

# Prepared (container path): stub gh, stub runtime, set the required names.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/gh"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/podman"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/grok"
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH"
export XAI_API_KEY=dummy
export FACTORY_CONTAINER_IMAGE=test-image
export FACTORY_CONTAINER_NETWORK=none
export FACTORY_HOME="$tmp/state"
mkdir -p "$FACTORY_HOME"

out=$(bash "$preflight" 2>&1) || fail "prepared environment failed: $out"
echo "$out" | grep -q "watcher-preflight: ok" || fail "prepared run did not say ok: $out"
echo "prepared (container): ok"

# Prepared (host sandbox bypass): no runtime needed.
unset FACTORY_CONTAINER_IMAGE FACTORY_CONTAINER_NETWORK
export FACTORY_GROK_ON_HOST=host-is-a-disposable-sandbox
out=$(bash "$preflight" 2>&1) || fail "sandbox bypass failed: $out"
echo "$out" | grep -q "watcher-preflight: ok" || fail "sandbox run did not say ok: $out"
echo "prepared (sandbox bypass): ok"

echo "test-watcher-preflight: all passed"
exit 0
