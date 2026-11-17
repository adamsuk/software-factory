#!/usr/bin/env bash
# Offline tests for three behaviours ported from the live watcher into
# scripts/watcher/watch.sh and watch.new.sh (#443):
#   - @coderabbitai trigger comments post with the host's own gh login, not the
#     App token, because CodeRabbit ignores bots (#209);
#   - the build lane gives run-work-order.sh 60 turns;
#   - the weekly run count starts at .period_start when that is after Monday.
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
export FACTORY_REPOS="acme/software-factory acme/gh-factory"
unset FACTORY_BLOCKED_OWNERS FACTORY_GH_APP_ID FACTORY_GH_APP_INSTALLATION_ID FACTORY_GH_APP_KEY_FILE
export GH_LOG="$work/gh.log"
mkdir -p "$work/bin" "$FACTORY_WATCH_ROOT/state"

# The fake gh records its argv and whether a GitHub token was in its environment.
cat > "$work/bin/gh" << 'ENDGH'
#!/bin/bash
printf 'token=%s args=%s\n' "${GH_TOKEN:+set}" "$*" >> "${GH_LOG:?}"
exit 0
ENDGH
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"

printf '%s\n' '{"max_grok_build_runs_per_week":20,"max_grok_build_runs_per_day":20,"max_runs_per_loop":5,"max_coderabbit_requests_per_hour":8}' > "$FACTORY_BUDGET_FILE"

for lane in watch watch.new; do
  script="$root/scripts/watcher/${lane}.sh"

  tname="$lane: @coderabbitai commands post without the App token"
  : > "$GH_LOG"
  (
    # shellcheck disable=SC1090
    source "$script"
    # shellcheck disable=SC2034  # read by comment_pr in the sourced watcher
    DRY=0
    export GH_TOKEN=test-app-token
    comment_pr acme/software-factory 7 '@coderabbitai review' "" > /dev/null 2>&1
    comment_pr acme/software-factory 7 'An ordinary watcher comment' "" > /dev/null 2>&1
  ) || fail "comment_pr failed"
  grep -F -q 'token= args=pr comment 7 -R acme/software-factory --body @coderabbitai review' "$GH_LOG" \
    || fail "the CodeRabbit command was posted with the App token: $(cat "$GH_LOG")"
  grep -F -q 'token=set args=pr comment 7 -R acme/software-factory --body An ordinary watcher comment' "$GH_LOG" \
    || fail "an ordinary comment lost the App token: $(cat "$GH_LOG")"
  pass

  tname="$lane: a build gets 60 turns"
  # shellcheck disable=SC2016  # the literal line in the watcher
  grep -F -q 'GROK_MAX_TURNS=60 timeout 60m bash scripts/run-work-order.sh --push "$order"' "$script" \
    || fail "the build line does not set GROK_MAX_TURNS=60"
  if grep -E -q 'GROK_MAX_TURNS=[0-9]+' "$script" && grep -E 'GROK_MAX_TURNS=[0-9]+' "$script" | grep -v -q 'GROK_MAX_TURNS=60'; then
    fail "another GROK_MAX_TURNS value is still set"
  fi
  pass

  tname="$lane: the weekly count starts at period_start when it is after Monday"
  out=$(
    # shellcheck disable=SC1090
    source "$script"
    # A fixed Thursday, so the test means the same on any day it runs.
    # shellcheck disable=SC2034,SC2329  # replaces the sourced refresh_clock, which refresh_counts calls
    refresh_clock() { TODAY_UTC=2026-11-19; WEEK_START=2026-11-16; LONDON_NOW="2026-11-19 12:00 GMT"; }
    {
      echo 'date_utc,kind,repo,ref,runs,cost,result'
      echo '2026-11-16,build,acme/software-factory,1,1,,exit-0'
      echo '2026-11-17,build,acme/software-factory,2,1,,exit-0'
      echo '2026-11-19,build,acme/software-factory,3,1,,exit-0'
    } > "$FACTORY_LEDGER_FILE"
    for p in 2026-11-18 none 2000-01-01 not-a-date; do
      if [[ $p == none ]]; then
        jq 'del(.period_start)' "$FACTORY_BUDGET_FILE" > "$work/b.json"
      else
        jq --arg p "$p" '.period_start = $p' "$FACTORY_BUDGET_FILE" > "$work/b.json"
      fi
      cp "$work/b.json" "$FACTORY_BUDGET_FILE"
      refresh_counts
      printf '%s ' "$RUNS_WEEK"
    done
  )
  read -r mid none old bad <<< "$out"
  [[ $mid -eq 1 ]] || fail "period_start 2026-11-18 counted $mid runs, want 1 (only the 19th)"
  [[ $none -eq 3 ]] || fail "no period_start counted $none runs, want 3 (Monday on)"
  [[ $old -eq 3 ]] || fail "a period_start before Monday counted $old runs, want 3"
  [[ $bad -eq 3 ]] || fail "an invalid period_start counted $bad runs, want 3"
  # Put the budget back for the next lane.
  jq 'del(.period_start)' "$FACTORY_BUDGET_FILE" > "$work/b.json" && cp "$work/b.json" "$FACTORY_BUDGET_FILE"
  pass
done

echo "all watcher port tests passed"
