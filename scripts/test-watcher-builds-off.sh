#!/usr/bin/env bash
# Offline tests for FACTORY_WATCHER_BUILDS in scripts/watcher/watch.sh and
# watch.new.sh (#447): off means the watcher never builds. The main lane
# skips step_build, the build lane exits at start without taking its lock, and
# any value other than on or off stops the watcher at start.
# A fake gh is first on PATH. Nothing contacts GitHub. ShellCheck covers this file.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
pass() { echo "ok: $tname"; }

export FACTORY_WATCH_ROOT="$work/root"
export FACTORY_BUDGET_FILE="$work/budget.json"
export FACTORY_LEDGER_FILE="$work/ledger.csv"
export FACTORY_HOME_REPO=acme/software-factory
export FACTORY_REPOS="acme/software-factory"
unset FACTORY_BLOCKED_OWNERS FACTORY_GH_APP_ID FACTORY_GH_APP_INSTALLATION_ID FACTORY_GH_APP_KEY_FILE GH_TOKEN LANE
export GH_LOG="$work/gh.log"
mkdir -p "$work/bin" "$FACTORY_WATCH_ROOT/state"
printf '%s\n' '{"max_grok_build_runs_per_week":20,"max_grok_build_runs_per_day":20,"max_runs_per_loop":5}' > "$FACTORY_BUDGET_FILE"
cat > "$work/bin/gh" << 'ENDGH'
#!/bin/bash
printf '%s\n' "$*" >> "${GH_LOG:?}"
exit 0
ENDGH
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"

# One factory:ready issue, as collect_issues would cache it.
cache="$work/issues.jsonl"
printf '%s\n' '{"repo":"acme/software-factory","number":12,"title":"t","body":"Target repo: acme/software-factory","createdAt":"2026-11-17T00:00:00Z","labels":[{"name":"factory:ready"}]}' > "$cache"

run_step_build() { # lane script, builds setting -> the watcher log
  rm -f "$FACTORY_WATCH_ROOT/watch.log"
  : > "$GH_LOG"
  # $0 must not be the watcher's path, or sourcing it runs its main loop.
  FACTORY_WATCHER_BUILDS=$2 bash -c '
    # shellcheck disable=SC1090
    source "$1"
    # shellcheck disable=SC2034  # read by step_build
    ISSUE_CACHE=$2
    # shellcheck disable=SC2034
    DRY=1
    step_build' step-build "$1" "$cache" > /dev/null 2>&1 || true
  cat "$FACTORY_WATCH_ROOT/watch.log" 2> /dev/null
}

for lane in watch watch.new; do
  script="$root/scripts/watcher/${lane}.sh"

  tname="$lane: off skips the build step and reads nothing"
  out=$(run_step_build "$script" off)
  [[ $out == *"build skip: FACTORY_WATCHER_BUILDS=off"* ]] || fail "no skip logged: [$out]"
  [[ ! -s $GH_LOG ]] || fail "the build step still called gh: $(cat "$GH_LOG")"
  pass

  tname="$lane: on, or unset, still builds"
  for setting in on ""; do
    out=$(run_step_build "$script" "$setting")
    [[ $out != *"FACTORY_WATCHER_BUILDS=off"* ]] || fail "builds were skipped with [$setting]"
    [[ -s $GH_LOG ]] || fail "the build step did nothing with [$setting]: [$out]"
  done
  pass

  tname="$lane: the build lane does not start when builds are off"
  rm -f "$FACTORY_WATCH_ROOT/watch-build.lock"
  code=0
  err=$(LANE=build FACTORY_WATCHER_BUILDS=off timeout 30 bash "$script" --once --dry-run 2>&1 > /dev/null) || code=$?
  [[ $code -eq 0 ]] || fail "exited $code, want 0: $err"
  [[ $err == *"build lane not started: FACTORY_WATCHER_BUILDS=off"* ]] || fail "no reason given: [$err]"
  [[ ! -e "$FACTORY_WATCH_ROOT/watch-build.lock" ]] || fail "the build lane took its lock"
  pass

  tname="$lane: any other value stops the watcher at start"
  for bad in yes 0 false OFF; do
    code=0
    err=$(FACTORY_WATCHER_BUILDS=$bad timeout 30 bash "$script" --once --dry-run 2>&1 > /dev/null) || code=$?
    [[ $code -eq 2 ]] || fail "FACTORY_WATCHER_BUILDS=$bad exited $code, want 2"
    [[ $err == *"FACTORY_WATCHER_BUILDS must be on or off"* ]] || fail "no reason given for $bad: [$err]"
  done
  pass
done

echo "all watcher builds-off tests passed"
