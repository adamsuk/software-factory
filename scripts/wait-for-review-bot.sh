#!/usr/bin/env bash
# Waits for the configured review bot to review a pull request head, so the
# independent review can weigh its comments (AGENTS.md section 10.4).
#
# Usage: scripts/wait-for-review-bot.sh --repo OWNER/REPO --pr N [options]
#   --sha SHA        Head the review must belong to. Default: the PR's head.
#   --bot NAME       Override agents.review_bot from .github/factory.yml.
#   --timeout SECS   Give up after this long. Default 1500.
#   --nudge-after S  Post the section 10.2 nudge after this long. Default 1200.
#   --no-nudge       Never post the nudge.
#   --interval SECS  Poll interval. Default 30.
#
# Done when the bot has posted a review for that exact sha, or when its check
# reaches a terminal state. Exit 0 when done or when no bot is configured,
# 1 on timeout, 2 on bad usage. Never merges, never labels, never touches the
# diff. Its only possible write is the one nudge comment section 10.2 asks for,
# at most once per head.
#
# SC2016 off for this file: every single-quoted block below is a jq program, so
# its $variables must reach jq unexpanded. A file-level directive has to precede
# the first command.
# shellcheck disable=SC2016
set -euo pipefail

die() { echo "wait-for-review-bot: $2" >&2; exit "$1"; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo=""; pr=""; sha=""; bot=""
timeout=1500; nudge_after=1200; interval=30; nudge=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) [[ $# -ge 2 ]] || die 2 "missing value for --repo"; repo="$2"; shift 2 ;;
    --pr) [[ $# -ge 2 ]] || die 2 "missing value for --pr"; pr="$2"; shift 2 ;;
    --sha) [[ $# -ge 2 ]] || die 2 "missing value for --sha"; sha="$2"; shift 2 ;;
    --bot) [[ $# -ge 2 ]] || die 2 "missing value for --bot"; bot="$2"; shift 2 ;;
    --timeout) [[ $# -ge 2 ]] || die 2 "missing value for --timeout"; timeout="$2"; shift 2 ;;
    --nudge-after) [[ $# -ge 2 ]] || die 2 "missing value for --nudge-after"; nudge_after="$2"; shift 2 ;;
    --interval) [[ $# -ge 2 ]] || die 2 "missing value for --interval"; interval="$2"; shift 2 ;;
    --no-nudge) nudge=0; shift ;;
    --help) sed -n '2,19p' "$0"; exit 0 ;;
    *) die 2 "unknown argument: $1" ;;
  esac
done

[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 2 "bad or missing --repo"
[[ "$pr" =~ ^[0-9]+$ ]] || die 2 "bad or missing --pr"
for n in "$timeout" "$nudge_after"; do
  [[ "$n" =~ ^[0-9]+$ ]] || die 2 "timeouts must be whole seconds"
done
# A zero interval would spin on the API.
[[ "$interval" =~ ^[0-9]+$ && "$interval" -ge 1 ]] || die 2 "--interval must be at least 1 second"
command -v gh > /dev/null 2>&1 || die 2 "gh not found in PATH"
command -v jq > /dev/null 2>&1 || die 2 "jq not found in PATH"

# agents.review_bot decides whether there is anything to wait for. A missing
# factory.yml is an error, not a reason to skip: defaulting to "none" there
# silently disables the wait, which is how this script first appeared to work
# while doing nothing at all.
if [[ -z "$bot" ]]; then
  [[ -f "$here/.github/factory.yml" ]] \
    || die 2 "no $here/.github/factory.yml; pass --bot explicitly"
  bot=$(awk '
    /^agents:/ { in_agents = 1; next }
    /^[^[:space:]]/ { in_agents = 0 }
    in_agents && /^[[:space:]]+review_bot:/ {
      sub(/^[[:space:]]+review_bot:[[:space:]]*/, "")
      sub(/[[:space:]]*#.*$/, "")
      print; exit
    }
  ' "$here/.github/factory.yml" 2>/dev/null || true)
fi
[[ -n "$bot" ]] || die 2 "could not read agents.review_bot from factory.yml; pass --bot explicitly"

if [[ "$bot" == "none" ]]; then
  echo "wait-for-review-bot: agents.review_bot is 'none'; nothing to wait for."
  exit 0
fi

# The login that posts reviews, and the check name as `gh pr checks` reports it.
bot_login="$bot"
check_name="$bot"
if [[ "$bot" == "coderabbit" ]]; then
  bot_login="coderabbitai[bot]"
  check_name="CodeRabbit"
fi

pr_head=$(gh pr view "$pr" --repo "$repo" --json headRefOid --jq .headRefOid) \
  || die 7 "could not read the pull request head"
if [[ -z "$sha" ]]; then
  sha="$pr_head"
else
  # commit_id and headRefOid are full lowercase SHAs, and
  # foreman-orchestrate.sh accepts 7 to 40 hex characters in any case. Compared
  # raw, an abbreviated or upper-case --sha matches nothing and the script waits
  # out the whole timeout for no reason.
  sha=$(gh api "repos/${repo}/commits/${sha}" --jq .sha 2>/dev/null) \
    || die 7 "could not resolve --sha to a commit in ${repo}"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die 7 "resolved --sha is not a commit id: $sha"
fi
short=${sha:0:7}

# `gh pr checks` always reports the pull request's current head, so it is only
# evidence about --sha when they are the same commit. CodeRabbit raised this on
# #143: without the comparison, a stale terminal check on a newer head would
# look like the requested head had been reviewed.
check_is_about_sha=false
[[ "$sha" == "$pr_head" ]] && check_is_about_sha=true

# The primary signal: a review anchored to this exact sha. The check is a poor
# proxy on its own — CodeRabbit sits 'pending' for many minutes while already
# posting findings, and auto-pauses to 'skipping' after enough commits on a
# pull request, which would never become terminal (observed on #149).
# Both endpoints are consulted, because neither is sufficient alone. On #149
# CodeRabbit left review comments on a8ca777 with no review record, and a review
# record on 79632eb with no comments. Either counts as "it has looked at this
# head".
bot_reviewed_sha() {
  local path out n
  for path in reviews comments; do
    out=$(gh api "repos/${repo}/pulls/${pr}/${path}" --paginate) || return 2
    # jq -s with .[][]: --paginate prints one JSON array per page, so an
    # unslurped filter runs once per page and a two-page miss yields "0\n0",
    # which is not equal to "0" and so read as a hit. CodeRabbit found that on
    # #150, and busy pull requests -- the whole point of this wait -- are the
    # ones with more than one page.
    n=$(printf '%s' "$out" | jq -s -r --arg u "$bot_login" --arg s "$sha" \
      '[.[][] | select(.user.login == $u) | select(.commit_id == $s)] | length')
    [[ "$n" == "0" ]] || return 0
  done
  return 1
}

# gh pr checks takes no --arg, so the name goes through real jq. The exit status
# is kept: a failed gh call must not read as "absent".
bucket_now() {
  local out rc
  out=$(gh pr checks "$pr" --repo "$repo" --json name,bucket) && rc=0 || rc=$?
  # gh documents exit 8 as "Checks pending", which is the state this script
  # exists to wait through, so it is not an error. On gh 2.103.3 the --json form
  # returns 0 while pending, but the documented contract is what we rely on.
  if [[ "$rc" -ne 0 && "$rc" -ne 8 ]]; then
    return 1
  fi
  printf '%s' "$out" \
    | jq -r --arg n "$check_name" '[.[] | select(.name == $n) | .bucket][0] // ""'
}

marker="<!-- factory:review-bot-nudge sha=${sha} -->"
already_nudged() {
  local out
  out=$(gh pr view "$pr" --repo "$repo" --json comments) || return 1
  [[ "$(printf '%s' "$out" | jq -r --arg m "$marker" \
    '[.comments[] | select((.body // "") | contains($m))] | length')" != "0" ]]
}

post_nudge() {
  if already_nudged; then echo "nudge already posted for ${short}"; return 0; fi
  printf '%s\n%s\n' "$marker" "@coderabbitai full review" \
    | gh pr comment "$pr" --repo "$repo" --body-file - > /dev/null \
    && echo "nudged ${check_name} for ${short} (AGENTS.md section 10.2)"
}

waited=0
nudged=0
while :; do
  if bot_reviewed_sha; then
    echo "${bot_login} has reviewed ${short}"
    exit 0
  elif [[ "$?" -eq 2 ]]; then
    die 7 "could not read the reviews on ${repo}#${pr}"
  fi

  b=""
  if $check_is_about_sha; then
    if ! b=$(bucket_now); then
      die 7 "could not read the checks on ${repo}#${pr}"
    fi
    case "$b" in
      pass|fail|cancel|skipping)
        echo "${check_name} check finished on ${short}: ${b} (no review posted for this head)"
        exit 0 ;;
    esac
  fi

  if [[ "$waited" -ge "$timeout" ]]; then
    if $check_is_about_sha; then
      echo "wait-for-review-bot: no ${bot_login} review for ${short} and its check is '${b:-absent}' after ${timeout}s; giving up." >&2
    else
      echo "wait-for-review-bot: no ${bot_login} review for ${short} after ${timeout}s; giving up. The pull request head is ${pr_head:0:7}, so its checks say nothing about ${short}." >&2
    fi
    exit 1
  fi

  if [[ "$nudge" -eq 1 && "$nudged" -eq 0 && "$waited" -ge "$nudge_after" ]]; then
    post_nudge || true
    nudged=1
  fi

  sleep "$interval"
  waited=$((waited + interval))
done
