#!/usr/bin/env bash
# Move a factory:review issue from the PR Reviewer's verdict comment.
#
# Usage: scripts/review-issue.sh <work-order.md>
#
# Reads only repo, issue, issue_repo, branch, and attempt from the front
# matter. An empty issue_repo means repo. The body after the closing ---
# is ignored. Exit 2 on a bad work order (no gh call, no stdout). Exit 7
# when gh fails or factory.yml cannot be parsed, except a Not Found
# factory.yml, which means review_bot none. No stdout on exit 2 or 7.
# Success prints one word: merge, build, blocked, wait, or skip.
# Never merges, creates, pushes, or edits the work order. Does not change
# attempt. nits is part of the verdict shape and does not change the outcome.
set -euo pipefail

die() { echo "review-issue: $2" >&2; exit "$1"; }

finish() { printf '%s\n' "$1"; exit 0; }

api_err_file=""
cleanup() {
  if [[ -n "$api_err_file" ]]; then
    rm -f "$api_err_file"
  fi
}
trap cleanup EXIT

# Front matter value: the text after `key:` up to a # comment, with one
# matching pair of surrounding quotes stripped. Same rules as gate-issue.sh.
field() {
  awk -v k="$1" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && index($0, k ":") == 1 {
      v = substr($0, length(k) + 2); sub(/[ \t]+#.*$/, "", v)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      q = substr(v, 1, 1)
      if (length(v) >= 2 && (q == "\"" || q == "'\''") && substr(v, length(v), 1) == q) {
        v = substr(v, 2, length(v) - 2)
      }
      print v; exit
    }' "$order"
}

# Latest adamsuk factory:review comment on stdin (the pr view JSON).
# Prints "wait", or "ok <verdict> <should-fix> <nits>".
# Exit non-zero when the JSON itself is unusable.
parse_marker() {
  python3 -c 'import json, re, sys

marker = "<!-- factory:review -->"
verdict_re = re.compile(r"^verdict: (ready|changes-needed|needs-scott)\Z")
should_re = re.compile(r"^should-fix: (0|[1-9][0-9]*)\Z")
nits_re = re.compile(r"^nits: (0|[1-9][0-9]*)\Z")

def fail():
    sys.exit(1)

def emit_wait():
    sys.stdout.write("wait\n")
    sys.exit(0)

try:
    data = json.load(sys.stdin)
except Exception:
    fail()
if not isinstance(data, dict):
    fail()
comments = data.get("comments", [])
if comments is None:
    comments = []
if not isinstance(comments, list):
    fail()

kept = []
for comment in comments:
    if not isinstance(comment, dict):
        continue
    author = comment.get("author")
    if not isinstance(author, dict) or author.get("login") != "adamsuk":
        continue
    body = comment.get("body")
    if not isinstance(body, str):
        continue
    first = body.split("\n", 1)[0].rstrip("\r")
    if first != marker:
        continue
    created = comment.get("createdAt")
    if not isinstance(created, str):
        created = ""
    kept.append((created, body))

if not kept:
    emit_wait()

kept.sort(key=lambda item: item[0])
body = kept[-1][1]
parts = body.split("\n")
if parts and parts[-1] == "":
    parts.pop()
lines = [part.rstrip("\r") for part in parts]
if len(lines) != 4 or lines[0] != marker:
    emit_wait()
verdict_m = verdict_re.match(lines[1])
should_m = should_re.match(lines[2])
nits_m = nits_re.match(lines[3])
if verdict_m is None or should_m is None or nits_m is None:
    emit_wait()
sys.stdout.write("ok %s %s %s\n" % (verdict_m.group(1), should_m.group(1), nits_m.group(1)))
'
}

# agents.review_bot from a factory.yml document on stdin.
# Prints none, coderabbit, or other. Exit non-zero if YAML cannot be parsed.
# Missing agents, or a missing or null review_bot, is none.
# Requires PyYAML from requirements.txt; see README.md for review workflow setup.
review_bot_from_yaml() {
  python3 -c 'import sys
try:
    import yaml
except Exception:
    sys.exit(1)

def emit(value):
    sys.stdout.write(value + "\n")
    sys.exit(0)

try:
    text = sys.stdin.buffer.read().decode("utf-8")
    data = yaml.safe_load(text)
except Exception:
    sys.exit(1)
if not isinstance(data, dict):
    emit("none")
agents = data.get("agents")
if not isinstance(agents, dict):
    emit("none")
if "review_bot" not in agents or agents.get("review_bot") is None:
    emit("none")
bot = agents.get("review_bot")
if bot == "coderabbit" or bot == "none":
    emit(bot)
emit("other")
'
}

# True when a failed gh api is the factory.yml Not Found case.
is_not_found() {
  local err_file=$1 body=$2
  if [[ -f "$err_file" ]] && grep -q 'Not Found' "$err_file"; then
    return 0
  fi
  if printf '%s' "$body" | jq -e 'type == "object" and .message == "Not Found"' > /dev/null 2>&1; then
    return 0
  fi
  return 1
}

load_labels() {
  local labels_json label_text name
  has_blocked=0
  has_review=0
  labels_json=$(gh issue view "$issue" --repo "$issue_repo" --json labels) \
    || die 7 "could not read labels"
  label_text=$(printf '%s\n' "$labels_json" | jq -r '.labels[]?.name') \
    || die 7 "could not read labels"
  while IFS= read -r name || [[ -n "$name" ]]; do
    if [[ "$name" == "factory:blocked" ]]; then
      has_blocked=1
    elif [[ "$name" == "factory:review" ]]; then
      has_review=1
    fi
  done <<< "$label_text"
}

load_pr() {
  pr_json=$(gh pr view "$branch" --repo "$repo" \
    --json number,comments,reviews,baseRefName) \
    || die 7 "could not read pull request"
  if ! printf '%s\n' "$pr_json" | jq -e 'type == "object"' > /dev/null 2>&1; then
    die 7 "could not read pull request"
  fi
}

# Sets review_bot to none, coderabbit, or other. A Not Found file is none.
load_factory() {
  local raw ref_q api_status
  base_ref=$(printf '%s\n' "$pr_json" | jq -r \
    'if (.baseRefName | type) == "string" then .baseRefName else "" end') \
    || die 7 "could not read factory.yml"
  [[ -n "$base_ref" ]] || die 7 "could not read factory.yml"
  ref_q=$(printf '%s' "$base_ref" | jq -sRr @uri) || die 7 "could not read factory.yml"
  api_err_file=$(mktemp) || die 7 "could not read factory.yml"
  api_status=0
  raw=$(gh api -H "Accept: application/vnd.github.raw" \
    "repos/${repo}/contents/.github/factory.yml?ref=${ref_q}" 2>"$api_err_file") || api_status=$?
  if [[ "$api_status" -ne 0 ]]; then
    if is_not_found "$api_err_file" "$raw"; then
      rm -f "$api_err_file"
      api_err_file=""
      review_bot=none
      return 0
    fi
    rm -f "$api_err_file"
    api_err_file=""
    die 7 "could not read factory.yml"
  fi
  rm -f "$api_err_file"
  api_err_file=""
  # gh api returns JSON with base64 content unless the raw media type is honoured.
  if printf '%s\n' "$raw" | jq -e \
    'type == "object" and .encoding == "base64" and (.content | type) == "string"' \
    > /dev/null 2>&1; then
    raw=$(printf '%s\n' "$raw" | jq -r '.content | gsub("\n"; "")' | base64 -d) \
      || die 7 "could not read factory.yml"
  fi
  review_bot=$(printf '%s\n' "$raw" | review_bot_from_yaml) \
    || die 7 "could not read factory.yml"
}

# State of the latest coderabbitai review, or empty when there is none.
# Reads submittedAt and state only.
latest_coderabbit_state() {
  printf '%s\n' "$pr_json" | jq -r '
    if (.reviews | type) == "null" then
      ""
    elif (.reviews | type) != "array" then
      error("reviews")
    else
      [ .reviews[]
        | select(type == "object" and (.author | type) == "object" and .author.login == "coderabbitai")
        | {
            t: (if (.submittedAt | type) == "string" then .submittedAt else "" end),
            state: (if (.state | type) == "string" then .state else "" end)
          }
      ]
      | sort_by(.t)
      | if length == 0 then "" else .[-1].state end
    end
  '
}

apply_label() {
  local add=$1
  gh issue edit "$issue" --repo "$issue_repo" \
    --remove-label "factory:review" \
    --add-label "$add" > /dev/null || die 7 "could not edit labels"
}

apply_merge() {
  apply_label "factory:merge"
  finish merge
}

apply_build() {
  apply_label "factory:building"
  finish build
}

# Comment before the label edit: a factory:blocked issue is left untouched,
# so a comment that never landed cannot be posted on a later run.
apply_needs_scott() {
  local body
  body=$(printf '%s\n' \
    "<!-- factory:review -->" \
    "blocked: needs-scott" \
    "Scott must act.")
  gh issue comment "$issue" --repo "$issue_repo" --body "$body" > /dev/null \
    || die 7 "could not comment"
  apply_label "factory:blocked"
  finish blocked
}

apply_coderabbit() {
  local state
  state=$(latest_coderabbit_state) || die 7 "could not read pull request"
  if [[ "$state" == "APPROVED" ]]; then
    apply_merge
  fi
  finish wait
}

apply_ready() {
  load_factory
  case "$review_bot" in
    none) apply_merge ;;
    coderabbit) apply_coderabbit ;;
    other) finish wait ;;
    *) die 7 "could not read factory.yml" ;;
  esac
}

apply_verdict() {
  local parsed tag verdict should_fix nits
  parsed=$(printf '%s\n' "$pr_json" | parse_marker) \
    || die 7 "could not read pull request"
  if [[ "$parsed" == "wait" ]]; then
    finish wait
  fi
  read -r tag verdict should_fix nits <<< "$parsed"
  [[ "$tag" == "ok" ]] || die 7 "could not read pull request"
  # Recorded from the verdict. It does not change the outcome.
  : "$nits"
  case "$verdict" in
    needs-scott) apply_needs_scott ;;
    changes-needed)
      if [[ "$should_fix" == "0" ]]; then
        finish wait
      fi
      apply_build
      ;;
    ready)
      if [[ "$should_fix" != "0" ]]; then
        finish wait
      fi
      apply_ready
      ;;
    *) die 7 "could not read pull request" ;;
  esac
}

main() {
  local repo_pat='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
  [[ $# -eq 1 && -f "$1" ]] || die 2 "usage: $0 <work-order.md>"
  order="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"

  repo=$(field repo)
  issue=$(field issue)
  issue_repo=$(field issue_repo)
  branch=$(field branch)
  attempt=$(field attempt)

  if [[ ! "$repo" =~ $repo_pat ]]; then
    die 2 "bad repo"
  fi
  if [[ -n "$issue_repo" && ! "$issue_repo" =~ $repo_pat ]]; then
    die 2 "bad issue_repo"
  fi
  if [[ ! "$issue" =~ ^[0-9]+$ ]]; then
    die 2 "bad issue"
  fi
  if [[ -z "$branch" || "$branch" =~ [[:space:]] ]]; then
    die 2 "bad branch"
  fi
  if [[ "$attempt" != "1" && "$attempt" != "2" && "$attempt" != "3" ]]; then
    die 2 "bad attempt"
  fi
  if [[ -z "$issue_repo" ]]; then
    issue_repo=$repo
  fi

  load_labels
  if [[ "$has_blocked" -eq 1 ]]; then
    finish blocked
  fi
  if [[ "$has_review" -eq 0 ]]; then
    finish skip
  fi

  load_pr
  apply_verdict
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
