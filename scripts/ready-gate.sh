#!/usr/bin/env bash
# The one owner-ready decision. Read-only: it never comments, labels, merges
# or pushes.
#
# Usage: scripts/ready-gate.sh --repo OWNER/REPO --pr N [--sha SHA] [--ir-result FILE]
#   --sha SHA        The head the caller believes it is judging (7 to 40 hex
#                    characters). If the pull request head has moved, the gate
#                    refuses. The gate always reads the current head itself.
#   --ir-result FILE The watcher's per-head ireview-result-...-<sha>.json. Its
#                    verdict counts as the independent review when it is PASS.
#
# Exit 0 only when every condition holds on the pull request's current head:
#   1. An independent-review PASS is recorded for that exact head SHA: the
#      latest `<!-- factory:independent-review v2 sha=<head> -->` comment
#      says PASS, or the --ir-result file says PASS. A PASS for another SHA, a
#      GitHub approval, and a `<!-- factory:review -->` comment do not count.
#   2. There are no unresolved, non-outdated review threads, from any author.
#   3. Required checks are green (checks=green from scripts/pr-status.sh, so
#      the same required-check rule).
#   4. On a size/L or size/XL pull request, CodeRabbit has a review of that
#      same head SHA (any state; the rule scripts/wait-for-review-bot.sh uses).
# Otherwise it prints one missing condition per line on stdout and exits 1.
# Exit 2: bad usage. Exit 7: a read failed, so readiness is unknown (fail
# closed; the caller must treat it as not ready).
# The only gh calls are reads: `gh pr view`, `gh api graphql` (review
# threads), `gh api repos/.../pulls/N/{reviews,comments}` (size/L and size/XL
# only), and whatever scripts/pr-status.sh reads.
set -euo pipefail

die() { echo "ready-gate: $2" >&2; exit "$1"; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo=""; pr=""; want_sha=""; ir_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) [[ $# -ge 2 ]] || die 2 "missing value for --repo"; repo="$2"; shift 2 ;;
    --pr) [[ $# -ge 2 ]] || die 2 "missing value for --pr"; pr="$2"; shift 2 ;;
    --sha) [[ $# -ge 2 ]] || die 2 "missing value for --sha"; want_sha="$2"; shift 2 ;;
    --ir-result) [[ $# -ge 2 ]] || die 2 "missing value for --ir-result"; ir_file="$2"; shift 2 ;;
    --help | -h) sed -n '2,28p' "$0"; exit 0 ;;
    *) die 2 "unknown argument: $1" ;;
  esac
done

[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 2 "bad or missing --repo"
[[ "$pr" =~ ^[0-9]+$ ]] || die 2 "bad or missing --pr"
[[ -z "$want_sha" || "$want_sha" =~ ^[0-9a-fA-F]{7,40}$ ]] || die 2 "bad --sha"
command -v gh > /dev/null 2>&1 || die 2 "gh not found in PATH"
command -v jq > /dev/null 2>&1 || die 2 "jq not found in PATH"

missing=()

view=$(gh pr view "$pr" --repo "$repo" --json headRefOid,labels,comments) \
  || die 7 "could not read ${repo}#${pr}"
head=$(printf '%s' "$view" | jq -r '.headRefOid // ""' | tr 'A-F' 'a-f') \
  || die 7 "could not read the head of ${repo}#${pr}"
[[ "$head" =~ ^[0-9a-f]{40}$ ]] || die 7 "no head commit for ${repo}#${pr}"
short=${head:0:7}

if [[ -n "$want_sha" ]]; then
  want_lc=$(printf '%s' "$want_sha" | tr 'A-F' 'a-f')
  if [[ "$head" != "$want_lc"* ]]; then
    missing+=("head moved: judged ${want_lc:0:7}, the pull request head is now ${short}")
  fi
fi

# 1. Independent review PASS for this exact head. Comments are in creation
# order, so the last matching one is the latest. The verdict is read from the
# marker's own second line only, never from the free-text summary below it.
# Only the approver (FACTORY_APPROVER_LOGIN, else the repo owner) and the
# factory bot may post it; anyone else's comment is ignored and reported.
approver=${FACTORY_APPROVER_LOGIN:-${repo%%/*}}
# shellcheck disable=SC2016
ir_json=$(printf '%s' "$view" | jq -c --arg head "$head" --arg approver "$approver" '
  [ .comments[]?
    | (.author.login // "") as $who
    | (.body // "") as $b
    | ($b | split("\n") | map(gsub("\r$"; ""))) as $lines
    | select(($lines[0] // "") | test("^<!-- factory:independent-review v2 sha=[0-9a-fA-F]{7,40} -->$"))
    | (($lines[0] | capture("sha=(?<s>[0-9a-fA-F]{7,40})").s) | ascii_downcase) as $s
    | select($head | startswith($s))
    | {trusted: ($who == $approver or $who == "software-factory-line" or $who == "software-factory-line[bot]" or $who == "app/software-factory-line"),
       v: ((($lines[1] // "") | [scan("^\\*\\*Independent review \\(after CodeRabbit\\): (PASS|FIX|ESCALATE)\\*\\* on ")] | .[0][0]) // "unreadable")}
  ] | {untrusted: ([.[] | select(.trusted | not)] | length),
       v: (([.[] | select(.trusted)] | last | .v) // "none")}') \
  || die 7 "could not read the comments on ${repo}#${pr}"
ir_comment=$(printf '%s' "$ir_json" | jq -r '.v')
ir_untrusted=$(printf '%s' "$ir_json" | jq -r '.untrusted')
ir_file_verdict=""
if [[ -n "$ir_file" && -s "$ir_file" ]]; then
  ir_file_verdict=$(jq -r '.verdict // ""' "$ir_file" 2> /dev/null || true)
fi
if [[ "$ir_comment" != "PASS" && "$ir_file_verdict" != "PASS" ]]; then
  detail="no independent review comment for this head"
  [[ "$ir_comment" == "none" ]] || detail="latest independent review comment for this head says ${ir_comment}"
  [[ -z "$ir_file_verdict" ]] || detail="${detail}; watcher result says ${ir_file_verdict}"
  missing+=("independent review: no PASS recorded for head ${short} (${detail})")
  if [[ "$ir_untrusted" != "0" ]]; then
    missing+=("independent review comment for head ${short} is from an unrecognised author (only ${approver} or software-factory-line may post it)")
  fi
fi

# 2. Unresolved, non-outdated review threads from any author.
# shellcheck disable=SC2016
threads_query='query($owner: String!, $name: String!, $number: Int!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          isResolved
          isOutdated
          path
          comments(first: 1) { nodes { author { login } body } }
        }
      }
    }
  }
}'
cursor=""
pages=0
while :; do
  pages=$((pages + 1))
  [[ "$pages" -le 100 ]] || die 7 "too many review thread pages on ${repo}#${pr}"
  cursor_args=()
  [[ -z "$cursor" ]] || cursor_args=(-f "cursor=${cursor}")
  page=$(gh api graphql -f query="$threads_query" \
    -F owner="${repo%%/*}" -F name="${repo##*/}" -F number="$pr" \
    ${cursor_args[@]+"${cursor_args[@]}"}) || die 7 "could not read review threads on ${repo}#${pr}"
  # One line per blocking thread: path, author, first line of the first comment.
  lines=$(printf '%s' "$page" | jq -r '
    .data.repository.pullRequest.reviewThreads.nodes[]
    | select(.isResolved == false and .isOutdated == false)
    | ((.comments.nodes[0].body // "") | split("\n") | .[0] | gsub("[[:cntrl:]]"; " ") | .[0:120]) as $first
    | "unresolved review thread (not outdated) on \(.path // "?") by \(.comments.nodes[0].author.login // "unknown"): \($first)"
  ') || die 7 "could not read review threads on ${repo}#${pr}"
  while IFS= read -r line; do
    [[ -z "$line" ]] || missing+=("$line")
  done <<< "$lines"
  next=$(printf '%s' "$page" | jq -r '
    .data.repository.pullRequest.reviewThreads.pageInfo
    | if .hasNextPage == true then (.endCursor // "") else "" end
  ') || die 7 "could not read review threads on ${repo}#${pr}"
  [[ -n "$next" ]] || break
  [[ "$next" != "$cursor" ]] || die 7 "review thread cursor did not advance on ${repo}#${pr}"
  cursor=$next
done

# 3. Required checks, by the same rule as pr-status.sh.
status_out=$("$here/pr-status.sh" "$repo") || die 7 "could not read checks for ${repo}#${pr}"
status_line=$(printf '%s\n' "$status_out" | grep -F "${repo}#${pr} " | head -n 1 || true)
[[ -n "$status_line" ]] || die 7 "${repo}#${pr} is not among the open pull requests"
status_head=$(printf '%s' "$status_line" | sed -n 's/.* head=\([0-9a-f]*\) .*/\1/p')
checks_field=$(printf '%s' "$status_line" | sed -n 's/.* checks=\([^ ]*\) .*/\1/p')
[[ -n "$checks_field" ]] || die 7 "could not parse the status of ${repo}#${pr}"
if [[ -n "$status_head" && "$head" != "$status_head"* ]]; then
  missing+=("head moved while reading checks: ${short} then ${status_head}")
elif [[ "$checks_field" != "green" ]]; then
  missing+=("required checks not green: checks=${checks_field}")
fi

# 4. size/L and size/XL need a CodeRabbit review of this exact head. Same
# rule as wait-for-review-bot.sh: a review's commit_id, or a review comment's
# original_commit_id (commit_id on a comment is re-anchored, so it proves
# nothing). Any state counts. An older commit's review does not.
if printf '%s' "$view" | jq -e '[.labels[]?.name] | any(. == "size/L" or . == "size/XL")' > /dev/null; then
  cr_seen=0
  for path in reviews comments; do
    field=commit_id
    [[ "$path" == "comments" ]] && field=original_commit_id
    out=$(gh api "repos/${repo}/pulls/${pr}/${path}" --paginate) \
      || die 7 "could not read the ${path} on ${repo}#${pr}"
    n=$(printf '%s' "$out" | jq -s -r --arg s "$head" --arg f "$field" \
      '[.[][] | select(.user.login == "coderabbitai[bot]") | select(.[$f] == $s)] | length') \
      || die 7 "could not read the ${path} on ${repo}#${pr}"
    if [[ "$n" != "0" ]]; then cr_seen=1; break; fi
  done
  if [[ "$cr_seen" -eq 0 ]]; then
    missing+=("CodeRabbit has no review of head ${short} (required on size/L and size/XL)")
  fi
fi

if [[ ${#missing[@]} -gt 0 ]]; then
  printf '%s\n' "${missing[@]}"
  exit 1
fi
echo "ready: ${repo}#${pr} head ${short}"
