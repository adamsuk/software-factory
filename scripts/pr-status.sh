#!/usr/bin/env bash
# Read-only PR status from the gate's view: required-checks state on the
# head commit, the latest review per reviewer on that same head commit, and
# the unresolved review-thread count, with a derived verdict. Never
# comments, labels, merges or pushes.
#
# Usage: scripts/pr-status.sh [owner/repo ...]
#
# With no arguments, reads the four factory repos: adamsuk/software-factory,
# adamsuk/line, adamsuk/gh-factory, adamsuk/activity-feed. Any repo works,
# factory-authored or not (e.g. a Dependabot pull request): a repo with no
# readable `.github/factory.yml`, or none with a `required_checks` list,
# falls back to judging every reported check (the only option without a
# declared required list), the same as before this script knew about
# required checks.
#
# One line per open pull request, in number order within each repo, in the
# order repos were given (or the default order above):
#
#   <repo>#<number> author=<login> head=<short sha> \
#     checks=<green|pending|none|failing(name,name,...)> \
#     reviews=<login:STATE,...|-> threads=<n> \
#     verdict=<failing-ci|open-threads|changes-requested|pending|needs-review|ready>
#
# checks is classified from `gh pr checks` against the pull request base
# branch's `required_checks` list in `.github/factory.yml` (read the same
# way scripts/gate-issue.sh reads it: the contents API with the raw media
# type, falling back to decoding base64 when it isn't honoured, then a
# top-level `required_checks` list). Optional checks (not in that list) are
# ignored entirely, even when failing. A required name with no matching
# check run is pending, same as one still running; pending always wins over
# a failing required check, the same rule scripts/gate-issue.sh uses for its
# own required checks. An empty check list, or no required_checks list at
# all (missing file, unreadable file, or the key absent), is `none` and
# judges every reported check instead, so a plain repo still gets a status
# line. reviews and threads come from one or more `gh api graphql` calls per
# pull request, paginated to completion with their own cursors: reviews is
# the latest review (by submittedAt) per author login, kept only when that
# review's commit is the pull request's current head (an older commit's
# review never counts, including an approval); threads is the count of
# unresolved review threads on the whole pull request
# (GraphQL reviewThreads.isResolved), not filtered by commit, since a thread
# stays open until someone resolves it regardless of which commit raised it.
#
# Verdict precedence, highest first: failing-ci (a required check failed),
# open-threads (one or more unresolved review threads, regardless of any
# approval), changes-requested (the latest review on the head commit, from
# any reviewer, is CHANGES_REQUESTED), pending (required checks still
# running, missing, or none have reported), needs-review (required checks
# green, zero unresolved threads, but no review at all on the head commit),
# ready (required checks green, zero unresolved threads, and at least one
# review on the head commit, none of them CHANGES_REQUESTED as their
# latest). A pull request is ready only with all of that; one reviewer's
# approval never overrides another reviewer's open thread or a different
# reviewer's change request, because threads and per-reviewer state are
# both counted independently.
#
# Exit 2: a repo argument is not owner/name shaped. No gh call, no stdout.
# Exit 7: a gh read failed, or returned something other than the expected
# JSON. Lines for pull requests already processed may already be on stdout.
# The only gh calls are read-only: `gh pr list`, `gh pr checks`,
# `gh api -H ... contents/.github/factory.yml` (best-effort: a failure here
# falls back to judging every check, it never exits 7), and
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

# A large enough --limit that `gh pr list` (which already pages internally
# through as many GraphQL requests as it takes to reach this many results)
# returns every open pull request a factory repo actually has in one call,
# instead of silently stopping at some arbitrary small page size.
pr_list_limit=1000

# shellcheck disable=SC2016
review_query='query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviews(first: 100) {
        pageInfo { hasNextPage endCursor }
        nodes { state submittedAt author { login } commit { oid } }
      }
      reviewThreads(first: 100) {
        pageInfo { hasNextPage endCursor }
        nodes { isResolved }
      }
    }
  }
}'

# shellcheck disable=SC2016
reviews_page_query='query($owner: String!, $name: String!, $number: Int!, $cursor: String!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviews(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes { state submittedAt author { login } commit { oid } }
      }
    }
  }
}'

# shellcheck disable=SC2016
threads_page_query='query($owner: String!, $name: String!, $number: Int!, $cursor: String!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes { isResolved }
      }
    }
  }
}'

# hasNextPage (1/0) and endCursor, tab-separated, for one connection
# ("reviews" or "reviewThreads") inside a one-page GraphQL response file.
conn_page_info() {
  python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
info = data["data"]["repository"]["pullRequest"][sys.argv[2]]["pageInfo"]
print(("1" if info.get("hasNextPage") else "0") + "\t" + (info.get("endCursor") or ""))
' "$1" "$2"
}

# Required check names for one repo+ref, read the same way
# scripts/gate-issue.sh reads them (contents API, raw media type, base64
# fallback, top-level required_checks list), with PyYAML when it's
# importable. Unlike gate-issue.sh, which gates a merge and so must fail
# loudly, this is a best-effort status read: any failure (no such file, bad
# YAML, not a list of strings) prints nothing, which the caller treats as
# "judge every reported check". When PyYAML itself isn't importable (a
# documented gap on some hosts, see .github/factory.yml's required_checks
# comment), fall back to a minimal parser for the one shape this key
# actually takes: a top-level `required_checks:` block or flow list of
# plain strings.
fetch_required_checks() {
  local repo=$1 ref=$2 ref_q raw
  ref_q=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$ref") \
    || return 0
  raw=$(gh api -H "Accept: application/vnd.github.raw" \
    "repos/${repo}/contents/.github/factory.yml?ref=${ref_q}" 2> /dev/null) || return 0
  if printf '%s' "$raw" | python3 -c 'import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if isinstance(d, dict) and d.get("encoding") == "base64"
          and isinstance(d.get("content"), str) else 1)' \
    > /dev/null 2>&1; then
    raw=$(printf '%s' "$raw" | python3 -c 'import json, sys
d = json.load(sys.stdin)
sys.stdout.write(d["content"])' 2> /dev/null | base64 -d 2> /dev/null) || return 0
  fi
  printf '%s' "$raw" | python3 -c '
import sys


def parse_simple(text):
    def strip_comment(s):
        out = []
        in_s = in_d = False
        for ch in s:
            if ch == "\x27" and not in_d:
                in_s = not in_s
            elif ch == "\"" and not in_s:
                in_d = not in_d
            elif ch == "#" and not in_s and not in_d:
                break
            out.append(ch)
        return "".join(out)

    def unquote(s):
        s = s.strip()
        if len(s) >= 2 and s[0] == s[-1] and s[0] in "\x27\"":
            return s[1:-1]
        return s

    lines = text.splitlines()
    for i, raw_line in enumerate(lines):
        stripped = strip_comment(raw_line).strip()
        if stripped == "required_checks:":
            items = []
            for later in lines[i + 1:]:
                content = strip_comment(later).strip()
                if not content:
                    continue
                if not content.startswith("- "):
                    break
                items.append(unquote(content[2:]))
            return items
        if stripped.startswith("required_checks:"):
            rest = stripped[len("required_checks:"):].strip()
            if rest.startswith("[") and rest.endswith("]"):
                inner = rest[1:-1].strip()
                return [] if not inner else [unquote(p) for p in inner.split(",")]
            return None
    return None


text = sys.stdin.read()
try:
    import yaml
except Exception:
    yaml = None

checks = None
if yaml is not None:
    try:
        data = yaml.safe_load(text)
    except Exception:
        data = None
    if isinstance(data, dict):
        candidate = data.get("required_checks")
        if isinstance(candidate, list):
            checks = candidate
else:
    checks = parse_simple(text)

if not isinstance(checks, list):
    sys.exit(0)
for item in checks:
    if isinstance(item, str) and "\n" not in item and "\r" not in item:
        print(item)
' 2> /dev/null || true
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

manifest="$tmp/manifest.txt"
: > "$manifest"

declare -A required_cache=()

idx=0
for repo in "${repos[@]}"; do
  prs_file="$tmp/${idx}.prs.json"
  if ! gh pr list --repo "$repo" --state open --limit "$pr_list_limit" \
    --json number,author,headRefOid,baseRefName > "$prs_file" 2>/dev/null; then
    die 7 "could not list pull requests for $repo"
  fi

  rows=$(python3 -c 'import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
if not isinstance(data, list):
    sys.exit(1)
for pr in sorted(data, key=lambda p: p["number"]):
    author = (pr.get("author") or {}).get("login") or "(unknown)"
    head = pr.get("headRefOid") or ""
    base = pr.get("baseRefName") or ""
    print("\t".join([str(pr["number"]), head, author, base]))' "$prs_file") \
    || die 7 "could not read the pull request list for $repo"

  while IFS=$'\t' read -r number head author base; do
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

    cache_key="${repo}"$'\x1f'"${base}"
    if [[ -z "${required_cache[$cache_key]+x}" ]]; then
      required_cache[$cache_key]=$(fetch_required_checks "$repo" "$base")
    fi
    printf '%s' "${required_cache[$cache_key]}" > "$tmp/${idx}.${number}.required.txt"

    gql_file="$tmp/${idx}.${number}.gql.json"
    if ! gh api graphql -f query="$review_query" \
      -F owner="${repo%%/*}" -F name="${repo##*/}" -F number="$number" \
      > "$gql_file" 2>/dev/null; then
      die 7 "could not read reviews for $repo#$number"
    fi

    reviews_extra=""
    rpage=0
    IFS=$'\t' read -r has cursor < <(conn_page_info "$gql_file" reviews)
    while [[ "$has" == "1" ]]; do
      rpage=$((rpage + 1))
      page_file="$tmp/${idx}.${number}.gql.reviews.${rpage}.json"
      if ! gh api graphql -f query="$reviews_page_query" \
        -F owner="${repo%%/*}" -F name="${repo##*/}" -F number="$number" \
        -f cursor="$cursor" > "$page_file" 2>/dev/null; then
        die 7 "could not read reviews for $repo#$number"
      fi
      reviews_extra+="${reviews_extra:+,}${page_file}"
      IFS=$'\t' read -r has cursor < <(conn_page_info "$page_file" reviews)
    done

    threads_extra=""
    tpage=0
    IFS=$'\t' read -r has cursor < <(conn_page_info "$gql_file" reviewThreads)
    while [[ "$has" == "1" ]]; do
      tpage=$((tpage + 1))
      page_file="$tmp/${idx}.${number}.gql.threads.${tpage}.json"
      if ! gh api graphql -f query="$threads_page_query" \
        -F owner="${repo%%/*}" -F name="${repo##*/}" -F number="$number" \
        -f cursor="$cursor" > "$page_file" 2>/dev/null; then
        die 7 "could not read review threads for $repo#$number"
      fi
      threads_extra+="${threads_extra:+,}${page_file}"
      IFS=$'\t' read -r has cursor < <(conn_page_info "$page_file" reviewThreads)
    done

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repo" "$number" "$head" "$author" "$idx" \
      "${reviews_extra:--}" "${threads_extra:--}" >> "$manifest"
  done <<< "$rows"

  idx=$((idx + 1))
done

python3 - "$tmp" "$manifest" << 'PY' || exit 7
import json
import sys

tmp, manifest_path = sys.argv[1:3]


def classify_all_checks(entries):
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


def classify_required_checks(entries, required):
    if not required:
        return classify_all_checks(entries)
    pending = False
    bad = []
    for name in required:
        matching = [e for e in entries if e.get("name") == name]
        if not matching or any(e.get("bucket") == "pending" for e in matching):
            pending = True
            continue
        if not all(e.get("bucket") == "pass" for e in matching):
            bad.append(name)
    if pending:
        return "pending", []
    if bad:
        return "failing", sorted(bad)
    return "green", []


def load_extra_nodes(paths, key):
    nodes = []
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        nodes.extend(data["data"]["repository"]["pullRequest"][key]["nodes"])
    return nodes


def reviews_and_threads(gql, head_sha, reviews_extra, threads_extra):
    pr = gql["data"]["repository"]["pullRequest"]
    review_nodes = list(pr["reviews"]["nodes"]) + load_extra_nodes(reviews_extra, "reviews")
    thread_nodes = list(pr["reviewThreads"]["nodes"]) + load_extra_nodes(threads_extra, "reviewThreads")

    latest = {}
    for node in review_nodes:
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
    unresolved = sum(1 for n in thread_nodes if n.get("isResolved") is False)
    review_str = ",".join(
        f"{login}:{state}" for login, (_, state) in sorted(latest.items())
    )
    latest_states = [state for _, state in latest.values()]
    return (review_str or "-"), unresolved, latest_states


def verdict(checks_state, unresolved, latest_states):
    if checks_state == "failing":
        return "failing-ci"
    if unresolved > 0:
        return "open-threads"
    if "CHANGES_REQUESTED" in latest_states:
        return "changes-requested"
    if checks_state != "green":
        return "pending"
    if not latest_states:
        return "needs-review"
    return "ready"


with open(manifest_path, encoding="utf-8") as handle:
    rows = [line.rstrip("\n").split("\t") for line in handle if line.strip()]

for repo, number, head, author, idx, reviews_extra, threads_extra in rows:
    with open(f"{tmp}/{idx}.{number}.checks.json", encoding="utf-8") as handle:
        entries = json.load(handle)
    with open(f"{tmp}/{idx}.{number}.required.txt", encoding="utf-8") as handle:
        required = [line.strip() for line in handle if line.strip()]
    checks_state, bad_names = classify_required_checks(entries, required)

    with open(f"{tmp}/{idx}.{number}.gql.json", encoding="utf-8") as handle:
        gql = json.load(handle)
    reviews_extra_paths = [] if reviews_extra == "-" else reviews_extra.split(",")
    threads_extra_paths = [] if threads_extra == "-" else threads_extra.split(",")
    review_str, unresolved, latest_states = reviews_and_threads(
        gql, head, reviews_extra_paths, threads_extra_paths
    )

    if checks_state == "failing":
        checks_field = "failing(" + ",".join(bad_names) + ")"
    else:
        checks_field = checks_state

    line = (
        f"{repo}#{number} author={author} head={head[:7]} "
        f"checks={checks_field} reviews={review_str} threads={unresolved} "
        f"verdict={verdict(checks_state, unresolved, latest_states)}"
    )
    print(line)
PY
