#!/usr/bin/env bash
# Move a factory:gate issue from the pull request head's required checks.
#
# Usage: scripts/gate-issue.sh <work-order.md>
#
# Reads only repo, issue, issue_repo, branch, and attempt from the front
# matter. An empty issue_repo means repo. The body after the closing ---
# is ignored. Exit 2 on a bad work order (no gh call, no stdout). Exit 7
# when gh fails or required_checks cannot be parsed, except gh pr checks
# exit 8, whose JSON is kept. No stdout on exit 2 or 7. Success prints one
# word: review, retry, blocked, pending,
# or skip. Never merges, creates, pushes, or edits the work order.
set -euo pipefail

die() { echo "gate-issue: $2" >&2; exit "$1"; }

finish() { printf '%s\n' "$1"; exit 0; }

# Front matter value: the text after `key:` up to a # comment, with one
# matching pair of surrounding quotes stripped. Same rules as run-work-order.sh.
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

# Top-level required_checks from a factory.yml document on stdin.
# Missing, null, and [] print nothing. Any other value must be a list of
# single-line strings (quotes and escapes already decoded). Blank lines,
# comments, flow sequences, and any legal indent are part of the document.
# Exit non-zero if python or the YAML parser cannot start, or the document
# is not that shape, so the caller can exit 7 without using a partial list.
required_check_names() {
  python3 -c 'import sys
try:
    import yaml
except Exception:
    # 3, not 1: a missing PyYAML is an environment problem, not a bad
    # factory.yml. load_required turns this into its own message.
    sys.exit(3)

def fail():
    sys.exit(1)

try:
    text = sys.stdin.buffer.read().decode("utf-8")
    data = yaml.safe_load(text)
except Exception:
    fail()
if data is None:
    sys.exit(0)
if not isinstance(data, dict):
    fail()
if "required_checks" not in data:
    sys.exit(0)
checks = data["required_checks"]
if checks is None:
    sys.exit(0)
if not isinstance(checks, list):
    fail()
names = []
for item in checks:
    if not isinstance(item, str) or "\n" in item or "\r" in item:
        fail()
    names.append(item)
for item in names:
    sys.stdout.write(item + "\n")
'
}

# Red names in LC_ALL=C byte order, joined with ", " (comma, space).
join_sorted() {
  local joined="" name
  while IFS= read -r name || [[ -n "$name" ]]; do
    [[ -n "$name" ]] || continue
    if [[ -z "$joined" ]]; then
      joined=$name
    else
      joined+=", ${name}"
    fi
  done < <(printf '%s\n' "$@" | LC_ALL=C sort)
  printf '%s' "$joined"
}

load_labels() {
  local labels_json label_text name
  has_blocked=0
  has_gate=0
  labels_json=$(gh issue view "$issue" --repo "$issue_repo" --json labels) \
    || die 7 "could not read labels"
  label_text=$(printf '%s\n' "$labels_json" | jq -r '.labels[]?.name') \
    || die 7 "could not read labels"
  while IFS= read -r name || [[ -n "$name" ]]; do
    if [[ "$name" == "factory:blocked" ]]; then
      has_blocked=1
    elif [[ "$name" == "factory:gate" ]]; then
      has_gate=1
    fi
  done <<< "$label_text"
}

load_pr() {
  local pr_json
  pr_json=$(gh pr view "$branch" --repo "$repo" --json number,baseRefName) \
    || die 7 "could not read pull request"
  pr_number=$(printf '%s\n' "$pr_json" | jq -r '.number') \
    || die 7 "could not read pull request"
  base_ref=$(printf '%s\n' "$pr_json" | jq -r '.baseRefName') \
    || die 7 "could not read pull request"
  [[ "$pr_number" =~ ^[0-9]+$ ]] || die 7 "could not read pull request"
  [[ -n "$base_ref" && "$base_ref" != "null" ]] || die 7 "could not read pull request"
}

load_factory() {
  local raw ref_q
  ref_q=$(printf '%s' "$base_ref" | jq -sRr @uri) || die 7 "could not read factory.yml"
  raw=$(gh api -H "Accept: application/vnd.github.raw" \
    "repos/${repo}/contents/.github/factory.yml?ref=${ref_q}") \
    || die 7 "could not read factory.yml"
  # gh api returns JSON with base64 content unless the raw media type is honoured.
  if printf '%s\n' "$raw" | jq -e \
    'type == "object" and .encoding == "base64" and (.content | type) == "string"' \
    > /dev/null 2>&1; then
    raw=$(printf '%s\n' "$raw" | jq -r '.content | gsub("\n"; "")' | base64 -d) \
      || die 7 "could not read factory.yml"
  fi
  factory_yml=$raw
}

load_required() {
  local parsed name rc
  # Command substitution, not a process substitution: a parser or startup
  # failure has to fail this assignment. A partial list is discarded.
  parsed=$(printf '%s\n' "$factory_yml" | required_check_names) && rc=0 || rc=$?
  if [[ "$rc" -eq 3 ]]; then
    die 7 "python3 cannot import yaml: install PyYAML (pip install -r requirements.txt). factory.yml itself was read fine."
  fi
  # Message unchanged on purpose: scripts/test-gate-issue.sh asserts it, and
  # under AGENTS.md section 5 an existing assertion is not an agent's to edit.
  [[ "$rc" -eq 0 ]] || die 7 "could not read factory.yml"
  required=()
  while IFS= read -r name || [[ -n "$name" ]]; do
    [[ -n "$name" ]] || continue
    required+=("$name")
  done <<< "$parsed"
}

# Sets outcome to pending, red, or green, and red_names for the red ones.
# Pending wins over red. An absent required name is pending. Every row with
# the required name counts: any pending is pending, every row pass is green,
# and anything else is red. Only bucket pass is green. fail, cancel,
# skipping, and every other bucket are red.
classify_checks() {
  local name bucket
  outcome=green
  red_names=()
  for name in "${required[@]}"; do
    # shellcheck disable=SC2016 # $n is a jq variable, bound by --arg
    bucket=$(printf '%s\n' "$checks_json" | jq -r --arg n "$name" '
      [.[] | select(.name == $n) | .bucket
        | if type == "string" then . else "other" end]
      | if length == 0 then "absent"
        elif any(. == "pending") then "pending"
        elif all(. == "pass") then "pass"
        else "other" end
    ') || die 7 "could not read checks"
    case "$bucket" in
      pass) ;;
      pending | absent)
        outcome=pending
        ;;
      *)
        if [[ "$outcome" != "pending" ]]; then
          outcome=red
        fi
        red_names+=("$name")
        ;;
    esac
  done
}

load_checks() {
  local checks_status
  checks_status=0
  checks_json=$(gh pr checks "$pr_number" --repo "$repo" --json name,bucket) \
    || checks_status=$?
  if [[ "$checks_status" -ne 0 && "$checks_status" -ne 8 ]]; then
    die 7 "could not read checks"
  fi
  if ! printf '%s\n' "$checks_json" | jq -e 'type == "array"' > /dev/null 2>&1; then
    die 7 "could not read checks"
  fi
}

# 0 when the latest marker comment's red: line equals this red list.
red_repeated() {
  local body line
  body=$(gh issue view "$issue" --repo "$issue_repo" --json comments | jq -r '
    [ .comments[]?
      | select(((.body // "") | split("\n")[0]) == "<!-- factory:gate -->")
      | {t: (.createdAt // ""), body: (.body // "")}
    ]
    | sort_by(.t)
    | if length == 0 then "" else .[-1].body end
  ') || die 7 "could not read comments"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "red: ${red_list}" ]]; then
      return 0
    fi
  done <<< "$body"
  return 1
}

apply_review() {
  gh issue edit "$issue" --repo "$issue_repo" \
    --remove-label "factory:gate" \
    --add-label "factory:review" > /dev/null || die 7 "could not edit labels"
  finish review
}

apply_retry() {
  local body
  body=$(printf '%s\n' "<!-- factory:gate -->" "red: ${red_list}")
  gh issue comment "$issue" --repo "$issue_repo" --body "$body" > /dev/null \
    || die 7 "could not comment"
  finish retry
}

# Comment before the label edit: a factory:blocked issue is left untouched,
# so a comment that never landed cannot be posted on a later run.
apply_blocked() {
  local reason=$1 red_field body
  if [[ "$reason" == "no-required-checks" ]]; then
    red_field="-"
  else
    red_field=$red_list
  fi
  body=$(printf '%s\n' \
    "<!-- factory:gate -->" \
    "blocked: ${reason}" \
    "red: ${red_field}" \
    "Scott must act.")
  gh issue comment "$issue" --repo "$issue_repo" --body "$body" > /dev/null \
    || die 7 "could not comment"
  gh issue edit "$issue" --repo "$issue_repo" \
    --remove-label "factory:gate" \
    --add-label "factory:blocked" > /dev/null || die 7 "could not edit labels"
  finish blocked
}

decide_red() {
  red_list=$(join_sorted "${red_names[@]}")
  if red_repeated; then
    apply_blocked repeat
  elif [[ "$attempt" == "3" ]]; then
    apply_blocked cap
  else
    apply_retry
  fi
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
  if [[ "$has_gate" -eq 0 ]]; then
    finish skip
  fi

  load_pr
  load_factory
  load_required
  if [[ "${#required[@]}" -eq 0 ]]; then
    apply_blocked no-required-checks
  fi

  load_checks
  classify_checks
  case "$outcome" in
    pending) finish pending ;;
    green) apply_review ;;
    red) decide_red ;;
    *) die 7 "could not read checks" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
