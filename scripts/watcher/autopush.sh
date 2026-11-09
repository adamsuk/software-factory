#!/usr/bin/env bash
# Every 60s: for builds that exited 4 (protected paths) on issues the maintainer approved, push and open the PR.
# >>> factory env: identical in every watcher script (no script sources another file).
# Portable defaults. Each path derives from FACTORY_HOME unless set itself.
FACTORY_HOME="${FACTORY_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/software-factory}"
FACTORY_WATCH_ROOT="${FACTORY_WATCH_ROOT:-$FACTORY_HOME/factory-watch}"
FACTORY_BUDGET_FILE="${FACTORY_BUDGET_FILE:-$FACTORY_HOME/factory-budget.json}"
FACTORY_LEDGER_FILE="${FACTORY_LEDGER_FILE:-$FACTORY_HOME/factory-ledger.csv}"
FACTORY_CLONE_ROOT="${FACTORY_CLONE_ROOT:-$FACTORY_HOME}"
FACTORY_WORKSPACE="${FACTORY_WORKSPACE:-$FACTORY_HOME}"
export FACTORY_HOME FACTORY_WATCH_ROOT FACTORY_BUDGET_FILE FACTORY_LEDGER_FILE FACTORY_CLONE_ROOT FACTORY_WORKSPACE
# Sets FACTORY_HOME_REPO (env, then GITHUB_REPOSITORY, then the origin remote of
# this checkout, then gh repo view), FACTORY_REPOS (default FACTORY_HOME_REPO),
# FACTORY_APPROVER_LOGIN (default the FACTORY_HOME_REPO owner) and
# FACTORY_BLOCKED_OWNERS (default empty). Non-zero when no home repo resolves.
factory_resolve_repos() {
  local top url
  FACTORY_HOME_REPO=${FACTORY_HOME_REPO:-${GITHUB_REPOSITORY:-}}
  if [[ -z $FACTORY_HOME_REPO ]] && top=$(git rev-parse --show-toplevel 2>/dev/null) \
    && url=$(git -C "$top" remote get-url origin 2>/dev/null); then
    FACTORY_HOME_REPO=$(printf '%s\n' "$url" | sed -nE 's#\.git/?$##; s#^.*[:/]([^/:]+/[^/:]+)/?$#\1#p')
  fi
  if [[ -z $FACTORY_HOME_REPO ]]; then
    FACTORY_HOME_REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || FACTORY_HOME_REPO=""
  fi
  FACTORY_REPOS=${FACTORY_REPOS:-$FACTORY_HOME_REPO}
  FACTORY_APPROVER_LOGIN=${FACTORY_APPROVER_LOGIN:-${FACTORY_HOME_REPO%%/*}}
  FACTORY_BLOCKED_OWNERS=${FACTORY_BLOCKED_OWNERS:-}
  export FACTORY_HOME_REPO FACTORY_REPOS FACTORY_APPROVER_LOGIN FACTORY_BLOCKED_OWNERS
  [[ -n $FACTORY_HOME_REPO ]]
}
# 0 when the owner of owner/repo $1 is in FACTORY_BLOCKED_OWNERS (any case).
factory_owner_blocked() {
  local owner=${1%%/*} b
  local -a blocked=()
  read -r -a blocked <<<"${FACTORY_BLOCKED_OWNERS:-}"
  owner=$(printf '%s' "$owner" | tr '[:upper:]' '[:lower:]')
  for b in ${blocked[@]+"${blocked[@]}"}; do
    b=$(printf '%s' "$b" | tr '[:upper:]' '[:lower:]')
    [[ -n $owner && $b == "$owner" ]] && return 0
  done
  return 1
}
# <<< factory env
# shellcheck disable=SC2164 # || exit would add a failure branch
cd "$FACTORY_WATCH_ROOT"; touch state/autopush-done.txt
while true; do [[ $((10#$(TZ=Europe/London date +%H))) -ge 7 ]] || { sleep 300; continue; };
  grep -ho 'run-work-order failed rc=4 for [^;]*' watch.log watch-build.log 2>/dev/null | awk '{print $NF}' | sort -u | while read -r ref; do
    grep -qxF "$ref" state/autopush-done.txt && continue
    url=$(./push-protected.sh "${ref%#*}" "${ref#*#}" 2>&1 | tail -1)
    if [[ $url == https://* ]]; then
      echo "$ref" >> state/autopush-done.txt
      ( flock 9; echo "$(date -u +%FT%TZ) needs-scott protected PR opened for $ref: $url (the maintainer merges)" >> state/events-pending.txt ) 9>state/events.lock
      echo "$(date -u +%FT%TZ) $ref -> $url" >> autopush.log
    else echo "$(date -u +%FT%TZ) $ref skipped: $url" >> autopush.log; echo "$ref" >> state/autopush-done.txt; fi
  done
  sleep 60
done
