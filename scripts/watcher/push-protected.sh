#!/usr/bin/env bash
# push-protected.sh ISSUE_REPO NUM : after run-work-order exit 4 (protected paths) on an issue
# the maintainer approved, push the newest build clone's branch and open a PR for the maintainer to merge.
# Approval is a comment by FACTORY_APPROVER_LOGIN that contains <!-- factory:approve -->,
# or the legacy "<Name> (via chat" marker, kept for compatibility.
set -u
repo=$1; n=$2; slug=${repo/\//_}
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
# <<< factory env
factory_resolve_repos || true
[[ -n $FACTORY_APPROVER_LOGIN ]] || { echo "no approver: set FACTORY_APPROVER_LOGIN or FACTORY_HOME_REPO"; exit 2; }
# shellcheck disable=SC2164 # || exit would add a failure branch
cd "$FACTORY_WATCH_ROOT"
ok=$(gh issue view "$n" -R "$repo" --json comments --jq '[.comments[]|select(.author.login==env.FACTORY_APPROVER_LOGIN)|.body|select(test("<!-- factory:approve -->") or test("\\b[A-Z][a-z]+ \\(via chat"))]|length')
[[ ${ok:-0} -gt 0 ]] || { echo "no maintainer approval on $repo#$n"; exit 2; }
order=orders/${slug}-${n}.md
target=$(grep -m1 -E '^(target_)?repo:' "$order" | awk '{print $2}'); target=${target:-$repo}
# shellcheck disable=SC2010 # ls -dt | grep keeps newest-first; a glob loop would change the command
d=$(ls -dt "${FACTORY_CLONE_ROOT}/wo-${target/\//_}-${n}-"* 2>/dev/null | grep -v '\.[a-z]*$' | head -1)
[[ -d $d/.git ]] || { echo "no clone for $repo#$n"; exit 3; }
# shellcheck disable=SC2164 # || exit would add a failure branch
cd "$d"; br=$(git branch --show-current)
[[ $br == factory/* ]] || { echo "bad branch $br"; exit 3; }
[[ $(git rev-list --count origin/main..HEAD) -ge 1 ]] || { echo "no commits"; exit 3; }
merged=$(gh pr list -R "$target" --head "$br" --state merged --json number --jq length)
[[ ${merged:-0} -eq 0 ]] || { echo "already merged"; exit 3; }
git push -q -u origin "$br" 2>&1 | grep -v '^remote:' || true
title=$(git log -1 --format=%s)
files=$(git diff --name-only origin/main...HEAD | sed "s/^/- \`/; s/\$/\`/")
body="Closes ${repo}#${n}

Built by Grok Build. This change touches protected paths, so the maintainer reviews and merges it (they approved builders opening PRs for protected MVP station tickets on 26 Oct).

Files:
${files}"
[[ $target == "$repo" ]] && body=${body/Closes ${repo}#${n}/Closes #${n}}
url=$(gh pr list -R "$target" --head "$br" --json url --jq '.[0].url')
[[ -n $url ]] || url=$(gh pr create -R "$target" --head "$br" --title "$title" --body "$body")
gh pr comment "$url" --body "@coderabbitai review" >/dev/null
gh issue edit "$n" -R "$repo" --remove-label factory:blocked --remove-label factory:building --add-label factory:review >/dev/null
echo "$url"
