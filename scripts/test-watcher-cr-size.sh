#!/usr/bin/env bash
# Offline tests for the CodeRabbit size rule in scripts/watcher/watch.sh and
# watch.new.sh (#445, AGENTS.md section 10.4): only size/L and size/XL pull
# requests (or, with no size label, over 200 changed lines) get CodeRabbit;
# smaller ones get the independent review alone and the Grok fix and conflict
# paths without waiting for a CodeRabbit request.
# A fake gh is first on PATH. Nothing contacts GitHub. ShellCheck covers this file.
# The grep and awk patterns below are literal watcher source text.
# shellcheck disable=SC2016
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
unset FACTORY_BLOCKED_OWNERS FACTORY_GH_APP_ID FACTORY_GH_APP_INSTALLATION_ID FACTORY_GH_APP_KEY_FILE GH_TOKEN
export GH_LOG="$work/gh.log"
mkdir -p "$work/bin" "$FACTORY_WATCH_ROOT/state"
printf '%s\n' '{"max_grok_build_runs_per_week":20,"max_grok_build_runs_per_day":20,"max_runs_per_loop":5,"max_coderabbit_requests_per_hour":8}' > "$FACTORY_BUDGET_FILE"

# The fake gh answers `pr view --json labels` from FAKE_LABELS (one per line)
# and `pr view --json additions,deletions` from FAKE_STATS ("adds<TAB>dels").
# FAKE_GH_FAIL=1 makes every call fail.
cat > "$work/bin/gh" << 'ENDGH'
#!/bin/bash
printf '%s\n' "$*" >> "${GH_LOG:?}"
[[ ${FAKE_GH_FAIL:-0} == 1 ]] && exit 1
case "$*" in
  *"--json labels"*) [[ -n ${FAKE_LABELS:-} ]] && printf '%s\n' "$FAKE_LABELS"; exit 0 ;;
  *"--json additions,deletions"*) printf '%s\n' "${FAKE_STATS:-0	0}"; exit 0 ;;
esac
exit 0
ENDGH
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"

needs() { # labels, stats, fail -> prints yes or no
  # $0 must not be the watcher's path, or sourcing it runs its main loop.
  FAKE_LABELS=$1 FAKE_STATS=$2 FAKE_GH_FAIL=${3:-0} bash -c '
    # shellcheck disable=SC1090
    source "$1"
    if pr_needs_coderabbit acme/software-factory 7; then echo yes; else echo no; fi' needs-check "$script"
}

for lane in watch watch.new; do
  script="$root/scripts/watcher/${lane}.sh"

  tname="$lane: which pull requests get CodeRabbit"
  [[ $(needs 'size/L' '0	0') == yes ]] || fail "size/L does not get CodeRabbit"
  [[ $(needs $'bug\nsize/XL' '0	0') == yes ]] || fail "size/XL does not get CodeRabbit"
  [[ $(needs 'size/M' '900	900') == no ]] || fail "size/M got CodeRabbit (a size label wins over line count)"
  [[ $(needs 'size/S' '0	0') == no ]] || fail "size/S got CodeRabbit"
  [[ $(needs '' '150	60') == yes ]] || fail "an unlabelled 210-line pull request did not get CodeRabbit"
  [[ $(needs '' '150	50') == no ]] || fail "an unlabelled 200-line pull request got CodeRabbit"
  [[ $(needs '' 'x	y') == no ]] || fail "unreadable line counts got CodeRabbit"
  [[ $(needs 'size/L' '0	0' 1) == no ]] || fail "a failed read counted as large"
  pass

  tname="$lane: every CodeRabbit trigger checks the size first"
  for fn in step_cr_review_resume step_cr_fix_comment step_cr_autopilot step_cr_conflict_comment; do
    body=$(sed -n "/^${fn}() {/,/^}/p" "$script")
    [[ -n $body ]] || fail "$fn not found"
    gate=$(grep -n 'pr_needs_coderabbit' <<< "$body" | head -n 1 | cut -d: -f1)
    [[ -n $gate ]] || fail "$fn does not check pr_needs_coderabbit"
    # Every trigger after the size check, except autopilot's stop on a
    # sensitive pull request, which must still be sent.
    while IFS=: read -r n line; do
      [[ $line == *"autopilot stop"* ]] && continue
      (( n > gate )) || fail "$fn posts a CodeRabbit trigger (line $n) before the size check (line $gate)"
    done < <(grep -n -E "comment_pr .*'@coderabbitai|post_cr_resume_pair \"|cr_full_review_followup \"" <<< "$body")
  done
  build_trigger=$(grep -n -B3 "comment_pr \"\$wo_repo\" \"\$pr_num\" '@coderabbitai review'" "$script")
  [[ $build_trigger == *'pr_needs_coderabbit "$wo_repo" "$pr_num"'* ]] \
    || fail "the review request after a build is not size-checked"
  pass

  tname="$lane: the independent review waits for CodeRabbit only on large pull requests"
  body=$(sed -n '/^step_independent_review() {/,/^}/p' "$script")
  awk '/if pr_needs_coderabbit "\$repo" "\$pr"; then/ {g = 1} g && /GATE_CR_COUNT == 0/ {ok = 1} END {exit !ok}' <<< "$body" \
    || fail "the wait for a CodeRabbit review is not inside the size check"
  grep -F -q 'CodeRabbit does not review pull requests this size; you are the only review before merge' <<< "$body" \
    || fail "small pull requests do not get the thorough-review prompt"
  grep -F -q '(1) secrets or credentials in the diff' <<< "$body" || fail "the small-PR checklist is missing"
  pass

  tname="$lane: a small pull request's fix and conflict paths do not wait for CodeRabbit"
  body=$(sed -n '/^step_fix_fallback() {/,/^}/p' "$script")
  grep -F -q 'if [[ $GATE_IR == FIX ]] && (( sens || ! cr_large )); then' <<< "$body" \
    || fail "a small pull request with a FIX verdict does not go straight to the Grok fix"
  grep -F -q 'elif (( sens || ! cr_large )); then' <<< "$body" \
    || fail "the Grok fix on a small pull request is not limited to once per head"
  body=$(sed -n '/^step_conflict_fallback() {/,/^}/p' "$script")
  awk '/if \[\[ ! -f \$marker \]\]; then/ {m = 1} m && /pr_needs_coderabbit/ {ok = 1; exit} END {exit !ok}' <<< "$body" \
    || fail "a small pull request's conflict still waits for a CodeRabbit request"
  pass
done

tname="AGENTS.md and the reviewer brief state the rule"
grep -F -q 'A `size/L` or `size/XL` PR (or, with no size label, one over 200 changed lines) gets a CodeRabbit review' "$root/AGENTS.md" \
  || fail "AGENTS.md section 10.4 does not state the size rule"
grep -F -q 'A smaller PR does not get CodeRabbit (AGENTS.md section 10.4)' "$root/agents/roles/reviewer.md" \
  || fail "the reviewer brief does not state the size rule"
grep -F -q 'size/L or size/XL' "$root/scripts/ready-gate.sh" || fail "ready-gate.sh no longer has the same size line"
pass

echo "all watcher CodeRabbit size tests passed"
