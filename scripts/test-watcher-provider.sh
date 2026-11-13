#!/usr/bin/env bash
# The watcher's triage call site runs the FACTORY_PROVIDER adapter, not grok
# (#398). Offline: a fake gh and a fake claude CLI, and NO grok on PATH.
# Covered for both lane scripts, plus the unchanged grok path when
# FACTORY_PROVIDER is unset or grok.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# $1 lane name, $2 provider ("" = unset), $3 case tag, $4 grok on PATH (yes|no)
run_case() {
  local name=$1 provider=$2 tag=$3 with_grok=$4
  local w=$scratch/$tag-$name
  mkdir -p "$w/bin" "$w/home" "$w/tmp" "$w/cache" "$w/watch/state" "$w/watch/work" "$w/repo/scripts/watcher"
  cp "$root/scripts/watcher/${name}.sh" "$w/repo/scripts/watcher/${name}.sh"
  cp "$root/scripts/watcher/factory-env.sh" "$w/repo/scripts/watcher/factory-env.sh"
  cp "$root/scripts/fence-untrusted.sh" "$w/repo/scripts/fence-untrusted.sh"

  cat > "$w/bin/gh" << 'ENDGH'
#!/bin/bash
set -u
if [[ ${1:-} == repo && ${2:-} == clone ]]; then
  dest=${4:-}
  mkdir -p "$dest/agents/roles" "$dest/scripts"
  printf '%s\n' '# intake fixture' > "$dest/agents/roles/intake.md"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$dest/scripts/triage-ask.sh"
  cp "$REAL_ROOT/scripts/fence-untrusted.sh" "$dest/scripts/"
  cp -R "$REAL_ROOT/adapters" "$dest/adapters"
  cp "$REAL_ROOT/AGENTS.md" "$dest/AGENTS.md"
  git init -q -b main "$dest"
  git -C "$dest" add -A
  git -C "$dest" -c user.name=t -c user.email=t@example.com commit -q -m init
  exit 0
fi
if [[ ${1:-} == issue && ${2:-} == view ]]; then printf '%s\n' '{"comments":[]}'; exit 0; fi
exit 99
ENDGH
  # Fake CLIs record that they ran. claude advertises the flags the adapter probes.
  cat > "$w/bin/claude" << 'ENDCL'
#!/bin/bash
if [[ ${1:-} == --help ]]; then echo "--print --model --append-system-prompt --permission-mode"; exit 0; fi
cat > "$CALLS_DIR/claude.stdin"
echo ran >> "$CALLS_DIR/claude.calls"
ENDCL
  cat > "$w/bin/grok" << 'ENDGROK'
#!/bin/bash
echo ran >> "$CALLS_DIR/grok.calls"
printf '%s\n' '{"stopReason":"end_turn","total_cost_usd":0}'
ENDGROK
  chmod +x "$w/bin/gh" "$w/bin/claude"
  [[ $with_grok == yes ]] && chmod +x "$w/bin/grok" || rm -f "$w/bin/grok"
  mkdir -p "$w/calls"
  printf '%s\n' '{"max_grok_build_runs_per_week":20,"max_grok_build_runs_per_day":20,"max_runs_per_loop":5}' > "$w/budget.json"
  printf '%s\n' '{"repo":"acme/software-factory","number":398,"title":"t","body":"b","createdAt":"2026-11-13T00:00:00Z","labels":[{"name":"factory:triage"}]}' > "$w/issues.jsonl"

  (
    cd "$w"
    export HOME="$w/home" TMPDIR="$w/tmp" XDG_CACHE_HOME="$w/cache" XDG_DATA_HOME="$w/xdg"
    export FACTORY_HOME="$w/factory-home" FACTORY_WATCH_ROOT="$w/watch" FACTORY_BUDGET_FILE="$w/budget.json"
    export FACTORY_LEDGER_FILE="$w/ledger.csv" FACTORY_CLONE_ROOT="$w/clones" FACTORY_WORKSPACE="$w/workspace"
    export FACTORY_HOME_REPO=acme/software-factory FACTORY_REPOS=acme/software-factory
    export GIT_TERMINAL_PROMPT=0 REAL_ROOT="$root" CALLS_DIR="$w/calls"
    # Only the fakes and the system tools: no grok anywhere unless the case adds it.
    export PATH="$w/bin:/usr/bin:/bin"
    unset FACTORY_APPROVER_LOGIN FACTORY_BLOCKED_OWNERS FACTORY_PROVIDER GH_TOKEN GITHUB_TOKEN \
      FACTORY_GH_APP_ID FACTORY_GH_APP_INSTALLATION_ID FACTORY_GH_APP_KEY_FILE FACTORY_GH_APP_ENV_FILE \
      FACTORY_GH_APP_PRIVATE_KEY FACTORY_GH_APP_SLUG GH_APP_SLUG
    [[ -n $provider ]] && export FACTORY_PROVIDER=$provider
    if [[ $with_grok == no ]] && command -v grok > /dev/null 2>&1; then fail "grok is on the test PATH"; fi
    # shellcheck disable=SC1090
    source "$w/repo/scripts/watcher/${name}.sh"
    # shellcheck disable=SC2034
    DRY=0
    # shellcheck disable=SC2034
    ISSUE_CACHE=$w/issues.jsonl
    step_triage > "$w/out.log" 2>&1 || true
  )
  printf '%s' "$w"
}

for lane in watch watch.new; do
  w=$(run_case "$lane" claudecode cc no)
  [[ -s $w/calls/claude.calls ]] || fail "$lane: FACTORY_PROVIDER=claudecode did not run the claude adapter ($(cat "$w/out.log" 2>/dev/null | tail -3))"
  [[ ! -e $w/calls/grok.calls ]] || fail "$lane: grok ran under claudecode"
  grep -Fq 'intake fixture' "$w/calls/claude.stdin" || fail "$lane: the intake brief did not reach the provider"
  grep -Fq 'You are the intake station for issue #398' "$w/calls/claude.stdin" || fail "$lane: adapter role/issue not passed"
  echo "ok: $lane triage runs the claudecode adapter with no grok on PATH"

  for p in "" grok; do
    w=$(run_case "$lane" "$p" "g${p:-unset}" yes)
    [[ -s $w/calls/grok.calls ]] || fail "$lane: FACTORY_PROVIDER='${p}' did not call grok"
    [[ ! -e $w/calls/claude.calls ]] || fail "$lane: claude ran with FACTORY_PROVIDER='${p}'"
    echo "ok: $lane triage still calls grok with FACTORY_PROVIDER='${p:-unset}'"
  done
done
echo "all watcher provider tests passed"
