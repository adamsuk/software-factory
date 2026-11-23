#!/usr/bin/env bash
# Offline tests for scripts/watcher-preflight.sh (#390).
# Builds the prepared case and the unprepared case with a fake gh on PATH and
# a temporary state directory. Does not start either lane and does not use
# the network. The unprepared case fails the suite when the preflight exits
# zero or omits the missing item's name.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
preflight=$here/watcher-preflight.sh
runbook=$root/docs/runbooks/local-watcher.md
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tname=startup
fail() { printf 'FAIL (%s): %s\n' "$tname" "$*" >&2; exit 1; }
pass() { printf 'ok: %s\n' "$tname"; }

# Sentinel placed in credential variables and in the auth file. A real token
# is never used. Output that contains it fails the suite.
secret=not-a-real-token
bash_bin=$(command -v bash)
[[ -n $bash_bin && -x $bash_bin ]] || fail "bash not found"

mkdir -p "$work/home" "$work/watch/state" "$work/bin"

reset_bin() {
  rm -rf "${work:?}/bin"
  mkdir -p "$work/bin"
  cat > "$work/bin/gh" << 'EOF'
#!/bin/sh
if [ -n "${GH_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$GH_LOG"
fi
if [ "${1:-}" = auth ] && [ "${2:-}" = status ]; then
  exit "${GH_AUTH_RC:-0}"
fi
exit 99
EOF
  chmod +x "$work/bin/gh"
}

add_cmd() {
  printf '#!/bin/sh\nexit 0\n' > "$work/bin/$1"
  chmod +x "$work/bin/$1"
}

reset_bin
add_cmd podman

# Runs the preflight with a clean environment. Sets pf_rc and pf_out.
# Extra arguments are KEY=value assignments for the child only.
run_pf() {
  : > "$work/gh.log"
  pf_rc=0
  pf_out=$(
    env -i \
      PATH="$work/bin" \
      HOME="$work/home" \
      GH_LOG="$work/gh.log" \
      "$@" \
      "$bash_bin" "$preflight" 2>&1
  ) || pf_rc=$?
  local needle
  for needle in "$secret" "factory-station:test" "=" "$work"; do
    if printf '%s\n' "$pf_out" | grep -F -q -- "$needle"; then
      if [[ $needle == "$secret" || $needle == "factory-station:test" ]]; then
        fail "preflight printed a variable value"
      fi
      fail "preflight printed a value ($needle)"
    fi
  done
}

expect_ok() {
  tname=$1
  shift
  run_pf "$@"
  [[ $pf_rc -eq 0 ]] || fail "prepared environment exited $pf_rc"
  [[ $pf_out == "watcher-preflight: ok" ]] || fail "prepared run did not say ok"
  [[ $(cat "$work/gh.log") == "auth status" ]] || fail "gh auth status was not the check"
  pass
}

# Unprepared: non-zero, and the missing item's name is in the output.
# Exit zero, or output that omits the name, fails the suite.
expect_missing() {
  tname=$1
  local name=$2
  shift 2
  run_pf "$@"
  [[ $pf_rc -ne 0 ]] || fail "unprepared environment exited zero"
  printf '%s\n' "$pf_out" | grep -F -q -- "$name" || fail "unprepared run omitted $name"
  pass
}

tname=runbook
[[ -f $runbook ]] || fail "runbook missing"
for name in \
  FACTORY_PROVIDER FACTORY_CONTAINER_IMAGE FACTORY_CONTAINER_RUNTIME \
  FACTORY_GROK_BIN FACTORY_GROK_AUTH_FILE XAI_API_KEY \
  CLAUDE_CODE_OAUTH_TOKEN \
  OPENCODE_API_KEY OPENROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY \
  FACTORY_WATCH_ROOT FACTORY_HOME XDG_DATA_HOME \
  'FACTORY_HOME_REPO=<owner>/<repo>' 'FACTORY_WATCHER_BUILDS=off' \
  'on its own' \
  gh grok claude opencode podman docker nerdctl \
  'LANE=build' watch.sh watch.new.sh 'systemctl --user'; do
  grep -F -q -- "$name" "$runbook" || fail "runbook does not name $name"
done
dollar='$'
grep -F -q -- "${dollar}HOME" "$runbook" || fail "runbook does not name \$HOME"
pass

image=localhost/factory-station:test

tname=prepared-grok
expect_ok "$tname" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  XAI_API_KEY="$secret" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"

tname=prepared-grok-subscription
printf '%s\n' "$secret" > "$work/auth-file"
printf '#!/bin/sh\nexit 0\n' > "$work/grok-bin"
chmod +x "$work/grok-bin"
expect_ok "$tname" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  FACTORY_GROK_BIN="$work/grok-bin" \
  FACTORY_GROK_AUTH_FILE="$work/auth-file" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"

# Builds stay on, so the build foreman still needs a grok credential.
tname=prepared-claudecode
expect_ok "$tname" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=claudecode \
  CLAUDE_CODE_OAUTH_TOKEN="$secret" \
  XAI_API_KEY="$secret" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"

tname=prepared-opencode
expect_ok "$tname" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=opencode \
  ANTHROPIC_API_KEY="$secret" \
  XAI_API_KEY="$secret" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"

tname=prepared-claudecode-builds-off
expect_ok "$tname" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=claudecode \
  FACTORY_WATCHER_BUILDS=off \
  CLAUDE_CODE_OAUTH_TOKEN="$secret" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"

tname=prepared-opencode-builds-off
expect_ok "$tname" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=opencode \
  FACTORY_WATCHER_BUILDS=off \
  ANTHROPIC_API_KEY="$secret" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"

tname=prepared-grok-auth-file-only
printf '%s\n' "$secret" > "$work/auth-file-only"
expect_ok "$tname" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  FACTORY_GROK_AUTH_FILE="$work/auth-file-only" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"

tname=prepared-nerdctl
reset_bin
add_cmd nerdctl
expect_ok "$tname" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  XAI_API_KEY="$secret" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"
reset_bin
add_cmd podman

tname=prepared-runtime-override
add_cmd docker
expect_ok "$tname" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  XAI_API_KEY="$secret" \
  FACTORY_CONTAINER_RUNTIME=docker \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"
rm -f "$work/bin/docker"

tname=prepared-factory-home
mkdir -p "$work/by-home/factory-watch/state"
expect_ok "$tname" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  XAI_API_KEY="$secret" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_HOME="$work/by-home"

tname=prepared-xdg
mkdir -p "$work/xdg/software-factory/factory-watch/state"
expect_ok "$tname" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  XAI_API_KEY="$secret" \
  FACTORY_CONTAINER_IMAGE="$image" \
  XDG_DATA_HOME="$work/xdg"

tname=prepared-home-default
mkdir -p "$work/home/.local/share/software-factory/factory-watch/state"
expect_ok "$tname" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  XAI_API_KEY="$secret" \
  FACTORY_CONTAINER_IMAGE="$image"

# The unprepared case: several pieces absent. Each name must appear, and a
# zero exit fails the suite.
tname=unprepared
reset_bin
run_pf \
  GH_AUTH_RC=1 \
  FACTORY_PROVIDER=grok \
  FACTORY_WATCH_ROOT="$work/empty"
[[ $pf_rc -ne 0 ]] || fail "unprepared environment exited zero"
for name in "gh auth status" "XAI_API_KEY" "FACTORY_GROK_AUTH_FILE" \
  FACTORY_CONTAINER_IMAGE podman docker nerdctl FACTORY_CONTAINER_RUNTIME \
  "FACTORY_WATCH_ROOT/state"; do
  printf '%s\n' "$pf_out" | grep -F -q -- "$name" || fail "unprepared run omitted $name"
done
printf '%s\n' "$pf_out" | grep -F -x -q "watcher-preflight: missing grok" \
  || fail "unprepared run omitted grok"
printf '%s\n' "$pf_out" | grep -F -x -q "watcher-preflight: missing XAI_API_KEY or FACTORY_GROK_AUTH_FILE" \
  || fail "unprepared run omitted the grok credential"
if printf '%s\n' "$pf_out" | grep -F -q -- "FACTORY_GROK_BIN"; then
  fail "unprepared run named FACTORY_GROK_BIN when it was unset"
fi
pass
reset_bin
add_cmd podman

tname=unprepared-no-gh
rm -f "$work/bin/gh"
run_pf \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  XAI_API_KEY="$secret" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"
[[ $pf_rc -ne 0 ]] || fail "unprepared environment exited zero"
[[ $pf_out == "watcher-preflight: missing gh" ]] || fail "unprepared run omitted gh"
[[ ! -s $work/gh.log ]] || fail "gh was invoked when it was not on PATH"
pass
reset_bin
add_cmd podman

tname=unprepared-bad-provider
run_pf \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=not-a-provider \
  XAI_API_KEY="$secret" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"
[[ $pf_rc -ne 0 ]] || fail "unprepared environment exited zero"
[[ $pf_out == "watcher-preflight: missing FACTORY_PROVIDER" ]] || fail "unprepared run omitted FACTORY_PROVIDER"
pass

tname=unprepared-runtime-override
expect_missing "$tname" FACTORY_CONTAINER_RUNTIME \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  XAI_API_KEY="$secret" \
  FACTORY_CONTAINER_RUNTIME=docker \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"
[[ $pf_out == "watcher-preflight: missing FACTORY_CONTAINER_RUNTIME" ]] || fail "runtime value leaked or extra items were named"

tname=unprepared-auth-file
expect_missing "$tname" FACTORY_GROK_AUTH_FILE \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  FACTORY_GROK_BIN="$work/grok-bin" \
  FACTORY_GROK_AUTH_FILE="$work/no-such-auth-file" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"

tname=unprepared-grok-bin
printf '#!/bin/sh\nexit 0\n' > "$work/grok-bin-plain"
chmod 644 "$work/grok-bin-plain"
expect_missing "$tname" FACTORY_GROK_BIN \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  XAI_API_KEY="$secret" \
  FACTORY_GROK_BIN="$work/grok-bin-plain" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"

tname=unprepared-claude-token
expect_missing "$tname" CLAUDE_CODE_OAUTH_TOKEN \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=claudecode \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"

tname=unprepared-opencode-keys
expect_missing "$tname" OPENCODE_API_KEY \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=opencode \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"
printf '%s\n' "$pf_out" | grep -F -q -- OPENROUTER_API_KEY || fail "unprepared run omitted OPENROUTER_API_KEY"
printf '%s\n' "$pf_out" | grep -F -q -- OPENAI_API_KEY || fail "unprepared run omitted OPENAI_API_KEY"
printf '%s\n' "$pf_out" | grep -F -q -- ANTHROPIC_API_KEY || fail "unprepared run omitted ANTHROPIC_API_KEY"

tname=unprepared-state-not-dir
mkdir -p "$work/file-root"
printf 'x\n' > "$work/file-root/state"
expect_missing "$tname" "FACTORY_WATCH_ROOT/state" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  XAI_API_KEY="$secret" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/file-root"

tname=unprepared-claudecode-needs-grok
expect_missing "$tname" "XAI_API_KEY or FACTORY_GROK_AUTH_FILE" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=claudecode \
  CLAUDE_CODE_OAUTH_TOKEN="$secret" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"

tname=unprepared-opencode-needs-grok
expect_missing "$tname" "XAI_API_KEY or FACTORY_GROK_AUTH_FILE" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=opencode \
  ANTHROPIC_API_KEY="$secret" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"

tname=unprepared-grok-builds-off
expect_missing "$tname" "XAI_API_KEY or FACTORY_GROK_AUTH_FILE" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  FACTORY_WATCHER_BUILDS=off \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"

tname=unprepared-auth-file-without-bin
expect_missing "$tname" FACTORY_GROK_AUTH_FILE \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  FACTORY_GROK_AUTH_FILE="$work/no-such-auth-file" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/watch"
if printf '%s\n' "$pf_out" | grep -F -q -- FACTORY_GROK_BIN; then
  fail "auth-file check required FACTORY_GROK_BIN"
fi

# Non-root owner: mode 0600 is writable but not searchable. Mode 0700 is usable.
tname=unprepared-state-mode-0600
[[ $(id -u) -ne 0 ]] || fail "state mode cases need a non-root owner"
mkdir -p "$work/mode-0600/state"
chmod 0600 "$work/mode-0600/state"
expect_missing "$tname" "FACTORY_WATCH_ROOT/state" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  XAI_API_KEY="$secret" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/mode-0600"
[[ $pf_out == "watcher-preflight: missing FACTORY_WATCH_ROOT/state" ]] || fail "mode 0600 was accepted or extra items were named"

tname=prepared-state-mode-0700
mkdir -p "$work/mode-0700/state"
chmod 0700 "$work/mode-0700/state"
expect_ok "$tname" \
  GH_AUTH_RC=0 \
  FACTORY_PROVIDER=grok \
  XAI_API_KEY="$secret" \
  FACTORY_CONTAINER_IMAGE="$image" \
  FACTORY_WATCH_ROOT="$work/mode-0700"

printf 'test-watcher-preflight: all passed\n'
exit 0
