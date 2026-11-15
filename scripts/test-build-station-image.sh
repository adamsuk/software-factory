#!/usr/bin/env bash
# Offline tests for scripts/build-station-image.sh and the two Containerfiles
# (#418). Nothing is built and no registry is contacted: a fake runtime records
# its argv, and the Containerfiles are read as text. ShellCheck covers this file.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
pass() { echo "ok: $tname"; }

build="$root_dir/scripts/build-station-image.sh"
station_cf="$root_dir/containers/station/Containerfile"
proxy_dir="$root_dir/containers/egress-proxy"

BIN=$work/bin
mkdir -p "$BIN"
cat > "$BIN/podman" << 'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_RUNTIME_LOG"
FAKE
chmod +x "$BIN/podman"

tname="the station image carries every tool a station calls"
for tool in bash ca-certificates curl git gh jq python3 python3-yaml shellcheck; do
  grep -E -q "(^|[[:space:]])${tool}([[:space:]]|\$)" "$station_cf" || fail "$tool is not installed by $station_cf"
done
# shellcheck disable=SC2016  # the literal text of the Containerfile line
grep -F -q '@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}' "$station_cf" \
  || fail "the Claude Code CLI is not installed at the pinned version"
pass

tname="the station image holds no credential"
# Comments may say the word; an instruction may not set or copy one in.
if grep -v '^[[:space:]]*#' "$station_cf" | grep -E -i -q 'TOKEN|API_KEY|SECRET|hosts\.yml|\.credentials'; then
  fail "the station Containerfile sets or copies a credential"
fi
if grep -E -q '^(COPY|ADD) ' "$station_cf"; then
  fail "the station Containerfile copies host files into the image"
fi
pass

tname="both builds are pinned"
out=$(PATH="$BIN:$PATH" FACTORY_CONTAINER_RUNTIME='' bash "$build" --print)
[[ $(printf '%s\n' "$out" | grep -c ' build ') -eq 2 ]] || fail "expected two build commands, got: $out"
[[ $(printf '%s\n' "$out" | grep -c -E 'BASE_IMAGE=[a-z0-9./-]+@sha256:[0-9a-f]{64}( |$)') -eq 2 ]] \
  || fail "a base image is not pinned by digest: $out"
printf '%s\n' "$out" | grep -E -q 'CLAUDE_CODE_VERSION=[0-9]+\.[0-9]+\.[0-9]+ ' \
  || fail "the Claude Code CLI version is not an exact version: $out"
if grep -E -q '^FROM .*:latest|^FROM [a-z]' "$station_cf" "$proxy_dir/Containerfile"; then
  fail "a Containerfile names its own base instead of taking the pinned BASE_IMAGE"
fi
pass

tname="gh is a pinned, digest-verified release, not the distribution's package"
printf '%s\n' "$out" | grep -E -q 'GH_VERSION=[0-9]+\.[0-9]+\.[0-9]+ ' || fail "gh is not pinned to an exact version: $out"
printf '%s\n' "$out" | grep -E -q 'GH_SHA256=[0-9a-f]{64} ' || fail "gh has no SHA-256 digest: $out"
grep -F -q 'sha256sum -c' "$station_cf" || fail "the Containerfile does not verify the gh archive"
verify_line=$(grep -n 'sha256sum -c' "$station_cf" | head -n 1 | cut -d: -f1)
install_line=$(grep -n '/usr/local/bin/gh' "$station_cf" | head -n 1 | cut -d: -f1)
[[ -n "$install_line" && "$verify_line" -lt "$install_line" ]] || fail "gh is installed before its digest is checked"
if grep -v '^[[:space:]]*#' "$station_cf" | grep -E -q 'apt-get install.*[[:space:]]gh([[:space:]]|$)|^[[:space:]]+.*[[:space:]]git gh '; then
  fail "gh still comes from the distribution's package"
fi
# The version in the tag, so a bump cannot reuse an old image under the same name.
printf '%s\n' "$out" | grep -E -q -- '--tag [^ ]*-gh-[0-9]+\.[0-9]+\.[0-9]+ ' || fail "the station tag does not carry the gh version"
pass

tname="--print builds nothing"
: > "$work/log"
PATH="$BIN:$PATH" FAKE_RUNTIME_LOG="$work/log" bash "$build" --print > /dev/null
[[ ! -s "$work/log" ]] || fail "--print ran the runtime: $(cat "$work/log")"
pass

tname="one named image builds only that image"
: > "$work/log"
PATH="$BIN:$PATH" FAKE_RUNTIME_LOG="$work/log" bash "$build" proxy > /dev/null
[[ $(wc -l < "$work/log") -eq 1 ]] || fail "expected one build, got: $(cat "$work/log")"
grep -F -q 'factory-egress-proxy' "$work/log" || fail "the proxy build was not the one run"
pass

tname="no runtime is exit 9, an unknown argument is exit 2"
code=0
PATH="$work/empty:/usr/bin:/bin" FACTORY_CONTAINER_RUNTIME=no-such-runtime bash "$build" > /dev/null 2>&1 || code=$?
[[ $code -eq 9 ]] || fail "a missing runtime exited $code, want 9"
code=0
PATH="$BIN:$PATH" bash "$build" --push > /dev/null 2>&1 || code=$?
[[ $code -eq 2 ]] || fail "an unknown argument exited $code, want 2"
pass

tname="the proxy denies by default and allows only port 443 CONNECT"
conf="$proxy_dir/tinyproxy.conf"
grep -q -x 'FilterDefaultDeny Yes' "$conf" || fail "the proxy does not deny by default"
grep -q -x 'ConnectPort 443' "$conf" || fail "CONNECT is not limited to port 443"
[[ $(grep -c '^ConnectPort ' "$conf") -eq 1 ]] || fail "more than one CONNECT port is allowed"
grep -q -x 'FilterType ere' "$conf" || fail "the allow-list is not read as anchored regular expressions"
pass

tname="every allow-list line is one exact host"
allow="$proxy_dir/allowlist.txt"
[[ -s "$allow" ]] || fail "the allow-list is empty"
while IFS= read -r line; do
  [[ $line =~ ^\^[a-z0-9-]+(\\\.[a-z0-9-]+)+\$$ ]] || fail "not an anchored exact host: $line"
done < "$allow"
for host in 'api\.anthropic\.com' 'api\.github\.com' 'github\.com'; do
  grep -F -q -x "^${host}\$" "$allow" || fail "$host is missing from the allow-list"
done
pass

echo "all build-station-image tests passed"
