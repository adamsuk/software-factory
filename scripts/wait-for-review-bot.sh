#!/usr/bin/env bash
# Waits for the configured review bot to finish reviewing a pull request head,
# so the independent review can read its comments (AGENTS.md section 10.4).
#
# Usage: scripts/wait-for-review-bot.sh --repo OWNER/REPO --pr N [options]
#   --sha SHA        Head the review must belong to. Default: the PR's head.
#   --bot NAME       Override agents.review_bot from .github/factory.yml.
#   --timeout SECS   Give up after this long. Default 1500 (25 min).
#   --nudge-after S  Post the section 10.2 nudge after this long. Default 1200.
#   --no-nudge       Never post the nudge.
#   --interval SECS  Poll interval. Default 30.
#
# Exit 0 when the bot's check reaches a terminal state, or when no bot is
# configured. Exit 1 on timeout. Exit 2 on bad usage. Never merges, never
# labels, never touches the diff. The only write it can make is the one nudge
# comment section 10.2 asks for, at most once per head.
set -euo pipefail

die() { echo "wait-for-review-bot: $2" >&2; exit "$1"; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo=""
pr=""
sha=""
bot=""
timeout=1500
nudge_after=1200
interval=30
nudge=1

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
    --help) sed -n '2,17p' "$0"; exit 0 ;;
    *) die 2 "unknown argument: $1" ;;
  esac
done

[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 2 "bad or missing --repo"
[[ "$pr" =~ ^[0-9]+$ ]] || die 2 "bad or missing --pr"
for n in "$timeout" "$nudge_after" "$interval"; do
  [[ "$n" =~ ^[0-9]+$ ]] || die 2 "timeouts and interval must be whole seconds"
done
command -v gh > /dev/null 2>&1 || die 2 "gh not found in PATH"

# agents.review_bot decides whether there is anything to wait for at all.
if [[ -z "$bot" ]]; then
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
bot=${bot:-none}

if [[ "$bot" == "none" || -z "$bot" ]]; then
  echo "wait-for-review-bot: agents.review_bot is 'none'; nothing to wait for."
  exit 0
fi

# The check name as it appears in `gh pr checks`. CodeRabbit reports as
# "CodeRabbit"; anything else is taken at face value.
check_name="$bot"
[[ "$bot" == "coderabbit" ]] && check_name="CodeRabbit"

if [[ -z "$sha" ]]; then
  sha=$(gh pr view "$pr" --repo "$repo" --json headRefOid --jq .headRefOid) \
    || die 7 "could not read the pull request head"
fi
short=${sha:0:7}

bucket_now() {
  gh pr checks "$pr" --repo "$repo" --json name,bucket \
    --jq --arg n "$check_name" '[.[] | select(.name == $n) | .bucket][0] // ""' 2>/dev/null \
    || true
}

# Idempotent by head: the marker goes in the comment, so a rerun can see it.
marker="<!-- factory:review-bot-nudge sha=${sha} -->"
already_nudged() {
  gh pr view "$pr" --repo "$repo" --json comments \
    --jq --arg m "$marker" '[.comments[] | select((.body // "") | contains($m))] | length' 2>/dev/null \
    | grep -qv '^0$'
}

post_nudge() {
  already_nudged && { echo "nudge already posted for ${short}"; return 0; }
  printf '%s\n%s\n' "$marker" "@coderabbitai full review" \
    | gh pr comment "$pr" --repo "$repo" --body-file - > /dev/null \
    && echo "nudged ${check_name} for ${short} (AGENTS.md section 10.2)"
}

waited=0
nudged=0
while :; do
  b=$(bucket_now)
  case "$b" in
    pass|fail|cancel|skipping)
      echo "${check_name} finished on ${short}: ${b}"
      exit 0 ;;
  esac

  if [[ "$waited" -ge "$timeout" ]]; then
    echo "wait-for-review-bot: ${check_name} still '${b:-absent}' on ${short} after ${timeout}s; giving up." >&2
    exit 1
  fi

  if [[ "$nudge" -eq 1 && "$nudged" -eq 0 && "$waited" -ge "$nudge_after" ]]; then
    post_nudge || true
    nudged=1
  fi

  sleep "$interval"
  waited=$((waited + interval))
done
