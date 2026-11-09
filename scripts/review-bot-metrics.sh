#!/usr/bin/env bash
# Read-only CodeRabbit comment acceptance for recently closed or merged PRs.
#
# Usage: scripts/review-bot-metrics.sh (--repo <owner/name> | --all) [--limit N]
#
# Counts review threads that CodeRabbit started on the last N closed or merged
# PRs (default 20, max 100). A thread is accepted when it is resolved and open
# when it is not. Acceptance rate is resolved / total, to one decimal place.
# --all reads every enrolled repo (the REVIEW_BOT_REPOS env var, space
# separated, then FACTORY_REPOS, then FACTORY_HOME_REPO) and adds a total row.
#
# Why this exists: it gives "re-test when the model changes" (the Line audit
# recommendation) a baseline to compare against. Run it before and after a
# model change. It prints current state only and keeps no history.
#
# Exit 2: a flag is missing or invalid. No gh call and no stdout.
# Exit 7: a gh read failed, its output is not the expected JSON, or a PR has
# more than 100 review threads (the totals would be incomplete). No stdout.
# The only gh calls are read-only `gh api graphql` queries.
set -euo pipefail

export LC_ALL=C

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
all=0
limit=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      all=1
      shift
      ;;
    --repo|--limit)
      [[ $# -ge 2 ]] || exit 2
      case "$1" in
        --repo)
          [[ -z "$repo" ]] || exit 2
          repo=$2
          ;;
        --limit)
          [[ -z "$limit" ]] || exit 2
          limit=$2
          ;;
      esac
      shift 2
      ;;
    *)
      exit 2
      ;;
  esac
done

if [[ "$all" -eq 1 ]]; then
  [[ -z "$repo" ]] || exit 2
elif [[ -z "$repo" ]]; then
  exit 2
fi
limit=${limit:-20}
[[ "$limit" =~ ^[1-9][0-9]*$ && "$limit" -le 100 ]] || exit 2

repo_re='^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'
if [[ "$all" -eq 1 ]]; then
  read -r -a repos <<<"${REVIEW_BOT_REPOS:-${FACTORY_REPOS:-$(factory_home_repo)}}"
  [[ "${#repos[@]}" -gt 0 ]] || exit 2
else
  repos=("$repo")
fi
for r in "${repos[@]}"; do
  [[ "$r" =~ $repo_re ]] || exit 2
done

# shellcheck disable=SC2016
query='query($owner: String!, $name: String!, $limit: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequests(states: [MERGED, CLOSED], first: $limit, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes {
        number
        reviewThreads(first: 100) {
          pageInfo { hasNextPage }
          nodes {
            isResolved
            comments(first: 1) { nodes { author { login } } }
          }
        }
      }
    }
  }
}'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

i=0
for r in "${repos[@]}"; do
  if ! gh api graphql \
    -f query="$query" \
    -F owner="${r%%/*}" \
    -F name="${r##*/}" \
    -F limit="$limit" \
    >"$tmp/$i.json" 2>/dev/null; then
    exit 7
  fi
  i=$((i + 1))
done

python3 - "$tmp" "$limit" "${repos[@]}" << 'PY' || exit 7
import json
import sys

tmp, limit = sys.argv[1], sys.argv[2]
repos = sys.argv[3:]
BOT_LOGINS = {"coderabbitai", "coderabbitai[bot]"}


def count(path):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    prs = data["data"]["repository"]["pullRequests"]["nodes"]
    total = resolved = 0
    for pr in prs:
        threads = pr["reviewThreads"]
        if threads["pageInfo"]["hasNextPage"]:
            raise SystemExit(7)
        for thread in threads["nodes"]:
            comments = thread["comments"]["nodes"]
            if not comments:
                continue
            author = comments[0].get("author") or {}
            if author.get("login") not in BOT_LOGINS:
                continue
            total += 1
            if thread["isResolved"] is True:
                resolved += 1
    return len(prs), total, resolved


def rate(resolved, total):
    if total == 0:
        return "n/a"
    permille = (resolved * 1000 + total // 2) // total
    return f"{permille // 10}.{permille % 10}%"


rows = []
for index, name in enumerate(repos):
    rows.append((name,) + count(f"{tmp}/{index}.json"))

out = [
    "# CodeRabbit comment acceptance",
    f"limit: last {limit} closed or merged prs per repo",
    "",
    "| repo | prs | threads | resolved | open | acceptance |",
    "| --- | --- | --- | --- | --- | --- |",
]
for name, prs, total, resolved in rows:
    out.append(
        f"| {name} | {prs} | {total} | {resolved} | {total - resolved} | {rate(resolved, total)} |"
    )
if len(rows) > 1:
    prs = sum(r[1] for r in rows)
    total = sum(r[2] for r in rows)
    resolved = sum(r[3] for r in rows)
    out.append(
        f"| total | {prs} | {total} | {resolved} | {total - resolved} | {rate(resolved, total)} |"
    )
sys.stdout.write("\n".join(out) + "\n")
PY
