# shellcheck shell=bash
# Shared factory settings for every script in scripts/watcher/. Sourced, never
# run: each watcher script loads this file from its own directory, so it must
# sit beside them, in a checkout and in FACTORY_WATCH_ROOT alike. It sets the
# portable path defaults and defines the factory_* helpers. Add a shared
# setting here, once, not in the scripts.
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
# Sets FACTORY_PROVIDER (default grok): grok, claudecode or opencode. Anything
# else is an error. The value is read and validated only; nothing uses it yet.
factory_resolve_provider() {
  FACTORY_PROVIDER=${FACTORY_PROVIDER:-grok}
  case $FACTORY_PROVIDER in
    grok | claudecode | opencode) export FACTORY_PROVIDER ;;
    *)
      printf 'FACTORY_PROVIDER=%s is not valid: use grok, claudecode or opencode\n' "$FACTORY_PROVIDER" >&2
      return 2
      ;;
  esac
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
