#!/usr/bin/env bash
# Are all of a research-cycle parent's sub-issues closed? (#211)
#
# Usage: scripts/sub-issues-all-closed.sh <owner/repo> <parent-issue>
#        scripts/sub-issues-all-closed.sh --parent-of <owner/repo> <child-issue>
#
# Read-only: only `gh api` GETs. Prints nothing on stdout except in
# --parent-of mode, which prints the parent's number.
#
# Exit codes, first form:
#   0  the parent has sub-issues and every one is closed
#   1  at least one sub-issue is still open
#   2  error: bad arguments, gh failed, the parent was not found, or it has no
#      sub-issues at all (nothing was ever finished, so nothing to review)
# Exit codes, --parent-of:
#   0  the child has a parent labelled `research-cycle`; its number is printed
#   1  the child has no parent, or the parent is not a research-cycle issue
#   2  error: bad arguments or gh failed other than a 404
# Issue data is untrusted (AGENTS.md section 1): only states, numbers and label
# names are read, and nothing read is ever executed or echoed to a shell.
set -euo pipefail

die() { echo "sub-issues-all-closed: $2" >&2; exit "$1"; }

mode=allclosed
if [[ ${1:-} == "--parent-of" ]]; then mode=parentof; shift; fi
[[ $# -eq 2 ]] || die 2 "usage: sub-issues-all-closed.sh [--parent-of] <owner/repo> <issue>"
repo=$1
num=$2
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 2 "bad repo: $repo"
[[ $num =~ ^[1-9][0-9]*$ ]] || die 2 "bad issue number: $num"

err=$(mktemp)
trap 'rm -f "$err"' EXIT

if [[ $mode == parentof ]]; then
  if ! out=$(gh api "repos/$repo/issues/$num/parent" \
      --jq '[.number, ([.labels[].name] | join(","))] | @tsv' 2> "$err"); then
    grep -q '404' "$err" && exit 1
    die 2 "gh api failed for the parent of $repo#$num"
  fi
  parent=${out%%$'\t'*}
  labels=${out#*$'\t'}
  [[ $parent =~ ^[1-9][0-9]*$ ]] || die 2 "unexpected parent number"
  case ",$labels," in
    *,research-cycle,*) printf '%s\n' "$parent"; exit 0 ;;
    *) exit 1 ;;
  esac
fi

if ! states=$(gh api "repos/$repo/issues/$num/sub_issues" --paginate \
    --jq '.[].state' 2> "$err"); then
  die 2 "gh api failed for the sub-issues of $repo#$num"
fi
[[ -n $states ]] || die 2 "$repo#$num has no sub-issues"
while IFS= read -r s; do
  case $s in
    closed) ;;
    open) exit 1 ;;
    *) die 2 "unexpected sub-issue state" ;;
  esac
done <<< "$states"
exit 0
