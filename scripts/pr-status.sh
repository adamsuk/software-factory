#!/usr/bin/env bash
# Read-only PR status from the gate's view: checks state on the head commit,
# the latest review per reviewer on that same head commit, and the
# unresolved review-thread count, with a derived verdict. Never comments,
# labels, merges or pushes.
#
# Usage: scripts/pr-status.sh [owner/repo ...]
#
# With no arguments, reads the four factory repos: adamsuk/software-factory,
# adamsuk/line, adamsuk/gh-factory, adamsuk/activity-feed. Any repo works,
# factory-authored or not (e.g. a Dependabot pull request), since nothing
# here reads labels or review decisions.
#
# One line per open pull request, in number order within each repo, in the
# order repos were given (or the default order above):
#
#   <repo>#<number> author=<login> head=<short sha> \
#     checks=<green|pending|none|failing(name,name,...)> \
#     reviews=<login:STATE,...|-> threads=<n> \
#     verdict=<failing-ci|open-threads|pending|ready>
#
# checks comes from `gh pr checks`: an empty check list is `none`; any
# pending check makes it `pending` even when another check has already
# failed (pending always wins, the same rule scripts/gate-issue.sh uses);
# otherwise any non-pass check makes it `failing`, naming every such check,
# sorted. reviews and threads come from one `gh api graphql` call per pull
# request: reviews is the latest review (by submittedAt) per author login,
# kept only when that review's commit is the pull request's current head
# (an older commit's review never counts, including an approval); threads is
# the count of unresolved review threads on the whole pull request
# (GraphQL reviewThreads.isResolved), not filtered by commit, since a thread
# stays open until someone resolves it regardless of which commit raised it.
#
# Verdict precedence, highest first: failing-ci (a check failed), open-threads
# (one or more unresolved review threads, regardless of any approval),
# pending (checks still running or none have reported), ready (checks green
# and zero unresolved threads). A pull request is ready only with both; one
# reviewer's approval never overrides another reviewer's open thread, because
# threads are counted independently of review state.
#
# Exit 2: a repo argument is not owner/name shaped. No gh call, no stdout.
# Exit 7: a gh read failed, returned something other than the expected JSON,
# or a GraphQL reviews or reviewThreads list hit its 100-item page cap (the
# count would be incomplete). Lines for pull requests already processed may
# already be on stdout.
# The only gh calls are read-only: `gh pr list`, `gh pr checks`, and
# `gh api graphql` (reviews and reviewThreads queries only).
set -euo pipefail

export LC_ALL=C

die() { echo "pr-status: $2" >&2; exit "$1"; }

default_repos="adamsuk/software-factory adamsuk/line adamsuk/gh-factory adamsuk/activity-feed"

if [[ $# -eq 0 ]]; then
  read -r -a repos <<< "$default_repos"
else
  repos=("$@")
fi

repo_re='^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'
for r in "${repos[@]}"; do
  [[ "$r" =~ $repo_re ]] || die 2 "bad repo: $r"
done

# shellcheck disable=SC2016
review_query='query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviews(first: 100) {
        pageInfo { hasNextPage }
        nodes { state submittedAt author { login } commit { oid } }
      }
      reviewThreads(first: 100) {
        pageInfo { hasNextPage }
        nodes { isResolved }
      }
    }
  }
}'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

manifest="$tmp/manifest.txt"
: > "$manifest"

idx=0
for repo in "${repos[@]}"; do
  prs_file="$tmp/${idx}.prs.json"
  if ! gh pr list --repo "$repo" --state open --limit 200 \
    --json number,author,headRefOid > "$prs_file" 2>/dev/null; then
    die 7 "could not list pull requests for $repo"
  fi
  if ! python3 -c 'import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if isinstance(data, list) and len(data) < 200 else 1)' "$prs_file" \
    2> /dev/null; then
    die 7 "could not read the pull request list for $repo"
  fi

  rows=$(python3 -c 'import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
for pr in sorted(data, key=lambda p: p["number"]):
    author = (pr.get("author") or {}).get("login") or "(unknown)"
    head = pr.get("headRefOid") or ""
    print("\t".join([str(pr["number"]), head, author]))' "$prs_file") \
    || die 7 "could not read the pull request list for $repo"

  while IFS=$'\t' read -r number head author; do
    [[ -n "$number" ]] || continue
    [[ -n "$head" ]] || die 7 "no head commit for $repo#$number"

    checks_file="$tmp/${idx}.${number}.checks.json"
    checks_status=0
    gh pr checks "$number" --repo "$repo" --json name,bucket \
      > "$checks_file" 2>/dev/null || checks_status=$?
    if [[ "$checks_status" -ne 0 && "$checks_status" -ne 1 && "$checks_status" -ne 8 ]]; then
      die 7 "could not read checks for $repo#$number"
    fi
    if ! python3 -c 'import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if isinstance(data, list) else 1)' "$checks_file" 2> /dev/null; then
      die 7 "could not read checks for $repo#$number"
    fi

    gql_file="$tmp/${idx}.${number}.gql.json"
    if ! gh api graphql -f query="$review_query" \
      -F owner="${repo%%/*}" -F name="${repo##*/}" -F number="$number" \
      > "$gql_file" 2>/dev/null; then
      die 7 "could not read reviews for $repo#$number"
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' "$repo" "$number" "$head" "$author" "$idx" >> "$manifest"
  done <<< "$rows"

  idx=$((idx + 1))
done

python3 - "$tmp" "$manifest" << 'PY' || exit 7
import json
import sys

tmp, manifest_path = sys.argv[1:3]


def classify_checks(entries):
    if not entries:
        return "none", []
    if any(e.get("bucket") == "pending" for e in entries):
        return "pending", []
    bad = sorted(
        e.get("name", "")
        for e in entries
        if e.get("bucket") != "pass"
    )
    if bad:
        return "failing", bad
    return "green", []


def reviews_and_threads(gql, head_sha):
    pr = gql["data"]["repository"]["pullRequest"]
    reviews = pr["reviews"]
    threads = pr["reviewThreads"]
    if reviews["pageInfo"]["hasNextPage"] or threads["pageInfo"]["hasNextPage"]:
        raise SystemExit(7)
    latest = {}
    for node in reviews["nodes"]:
        author = node.get("author") or {}
        login = author.get("login")
        if not login:
            continue
        commit = node.get("commit") or {}
        if commit.get("oid") != head_sha:
            continue
        submitted = node.get("submittedAt") or ""
        prev = latest.get(login)
        if prev is None or submitted >= prev[0]:
            latest[login] = (submitted, node.get("state"))
    unresolved = sum(1 for n in threads["nodes"] if n.get("isResolved") is False)
    review_str = ",".join(
        f"{login}:{state}" for login, (_, state) in sorted(latest.items())
    )
    return (review_str or "-"), unresolved


def verdict(checks_state, unresolved):
    if checks_state == "failing":
        return "failing-ci"
    if unresolved > 0:
        return "open-threads"
    if checks_state != "green":
        return "pending"
    return "ready"


with open(manifest_path, encoding="utf-8") as handle:
    rows = [line.rstrip("\n").split("\t") for line in handle if line.strip()]

for repo, number, head, author, idx in rows:
    with open(f"{tmp}/{idx}.{number}.checks.json", encoding="utf-8") as handle:
        entries = json.load(handle)
    checks_state, bad_names = classify_checks(entries)

    with open(f"{tmp}/{idx}.{number}.gql.json", encoding="utf-8") as handle:
        gql = json.load(handle)
    review_str, unresolved = reviews_and_threads(gql, head)

    if checks_state == "failing":
        checks_field = "failing(" + ",".join(bad_names) + ")"
    else:
        checks_field = checks_state

    line = (
        f"{repo}#{number} author={author} head={head[:7]} "
        f"checks={checks_field} reviews={review_str} threads={unresolved} "
        f"verdict={verdict(checks_state, unresolved)}"
    )
    print(line)
PY
