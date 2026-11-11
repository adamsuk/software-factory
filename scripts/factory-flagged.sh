#!/usr/bin/env bash
# Lists the issues the maintainer has flagged for pickup on the Software Factory board,
# in the order they should be worked.
#
# Usage: scripts/factory-flagged.sh [--repo OWNER/REPO] [--label LABEL]
# The default repo is the first entry of FACTORY_REPOS, which defaults to
# FACTORY_HOME_REPO (the env value, then GITHUB_REPOSITORY, then this
# checkout's origin remote, then gh repo view).
#
# The flag is the `priority: next` label, set from the board's item pane. It is
# additive, so it never displaces an issue's single factory:* status
# (AGENTS.md section 9). More than one issue may carry it.
#
# Order: priority P0, P1, P2, P3, then unprioritised, then issue number.
# Read-only: gh issue list only. Never writes, never picks anything up.
set -euo pipefail

die() { echo "factory-flagged: $2" >&2; exit "$1"; }

# FACTORY_HOME_REPO: the env value, then GITHUB_REPOSITORY, then the origin
# remote of this checkout, then gh repo view. Prints nothing when none resolves.
factory_home_repo() {
  local r="${FACTORY_HOME_REPO:-${GITHUB_REPOSITORY:-}}" top url
  if [[ -z "$r" ]] && top=$(git rev-parse --show-toplevel 2>/dev/null) \
    && url=$(git -C "$top" remote get-url origin 2>/dev/null); then
    r=$(printf '%s\n' "$url" | sed -nE 's#\.git/?$##; s#^.*[:/]([^/:]+/[^/:]+)/?$#\1#p')
  fi
  if [[ -z "$r" ]]; then
    r=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || r=""
  fi
  printf '%s\n' "$r"
}

repo=""
label="priority: next"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || die 2 "missing value for --repo"
      repo="$2"; shift 2 ;;
    --label)
      [[ $# -ge 2 ]] || die 2 "missing value for --label"
      label="$2"; shift 2 ;;
    --help) sed -n '2,16p' "$0"; exit 0 ;;
    *) die 2 "unknown argument: $1" ;;
  esac
done

if [[ -z "$repo" ]]; then
  read -r repo _ <<< "${FACTORY_REPOS:-}" || true
  [[ -n "$repo" ]] || repo=$(factory_home_repo)
  [[ -n "$repo" ]] || die 2 "no repo: pass --repo, or set FACTORY_REPOS or FACTORY_HOME_REPO"
fi
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 2 "bad --repo: $repo"
command -v gh > /dev/null 2>&1 || die 2 "gh not found in PATH"
command -v jq > /dev/null 2>&1 || die 2 "jq not found in PATH"

json=$(gh issue list --repo "$repo" --state open --label "$label" \
  --limit 200 --json number,title,labels) || die 7 "could not list issues"

count=$(printf '%s' "$json" | jq 'length')
if [[ "$count" -eq 0 ]]; then
  echo "Nothing flagged. Add the '$label' label on the board to queue an issue."
  exit 0
fi

echo "Flagged for pickup in $repo ($count):"
echo

# rank: P0=0 .. P3=3, unprioritised last. Then by issue number.
printf '%s' "$json" | jq -r '
  def rank:
    [ .labels[].name ] as $n
    | if   ($n | index("priority: P0")) then 0
      elif ($n | index("priority: P1")) then 1
      elif ($n | index("priority: P2")) then 2
      elif ($n | index("priority: P3")) then 3
      else 4 end;
  def prio:
    [ .labels[].name ]
    | map(select(startswith("priority: ") and . != "priority: next"))
    | if length == 0 then "--" else (.[0] | ltrimstr("priority: ")) end;
  def status:
    [ .labels[].name ]
    | map(select(startswith("factory:")))
    | if length == 0 then "(no status)" else .[0] end;
  [ .[] | { r: rank, number, title, p: prio, s: status } ]
  | sort_by(.r, .number)
  | .[]
  | "  \(.p)  #\(.number)  [\(.s)]  \(.title)"
'
echo
echo "Work them top down. Each goes through the stations; nothing is picked up"
echo "automatically (AGENTS.md section 9: only factory:ready may be built, and"
echo "merging stays with the maintainer)."
