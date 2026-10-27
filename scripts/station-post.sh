#!/usr/bin/env bash
# Post the factory trail any provider can leave on GitHub.
# One comment and one factory:* label per step. Never merges.
# Refuses a second triage comment, a non-factory branch, and a second open PR.
set -euo pipefail

die() { echo "station-post: $2" >&2; exit "$1"; }

usage() {
  cat >&2 <<'EOF'
Usage: scripts/station-post.sh [--dry-run] <command> [options]

Commands:
  triage   --repo OWNER/REPO --issue N --status ready|blocked --body-file PATH
  pickup   --repo OWNER/REPO --issue N --branch factory/N-slug
  pr       --repo OWNER/REPO --issue N --head factory/N-slug --title TEXT --body-file PATH
           [--issue-repo OWNER/REPO]
  verdict  --repo OWNER/REPO --pr N --issue N --sha SHA --verdict PASS|FIX|ESCALATE
           --summary TEXT [--protected yes|no] [--issue-repo OWNER/REPO]
  blocked  --repo OWNER/REPO --issue N --body-file PATH

Never merges. --dry-run still reads GitHub, and prints the comment and label
it would write.
EOF
  exit 2
}

dry=0
if [[ "${1:-}" == "--dry-run" ]]; then
  dry=1
  shift
fi

[[ $# -ge 1 ]] || usage
cmd="$1"
shift

repo=""
issue=""
issue_repo=""
pr=""
status=""
body_file=""
branch=""
head=""
title=""
sha=""
verdict=""
summary=""
protected="no"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 ;;
    --issue) issue="${2:-}"; shift 2 ;;
    --issue-repo) issue_repo="${2:-}"; shift 2 ;;
    --pr) pr="${2:-}"; shift 2 ;;
    --status) status="${2:-}"; shift 2 ;;
    --body-file) body_file="${2:-}"; shift 2 ;;
    --branch) branch="${2:-}"; shift 2 ;;
    --head) head="${2:-}"; shift 2 ;;
    --title) title="${2:-}"; shift 2 ;;
    --sha) sha="${2:-}"; shift 2 ;;
    --verdict) verdict="${2:-}"; shift 2 ;;
    --summary) summary="${2:-}"; shift 2 ;;
    --protected) protected="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) die 2 "unknown argument: $1" ;;
  esac
done

repo_pat='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
[[ "$repo" =~ $repo_pat ]] || die 2 "bad repo"
if [[ -z "$issue_repo" ]]; then
  issue_repo=$repo
fi
[[ "$issue_repo" =~ $repo_pat ]] || die 2 "bad issue-repo"
[[ "$issue" =~ ^[0-9]+$ ]] || die 2 "bad issue"
command -v gh >/dev/null 2>&1 || die 2 "gh not found"
command -v jq >/dev/null 2>&1 || die 2 "jq not found"

read_issue() {
  gh issue view "$issue" --repo "$issue_repo" --json labels,comments
}

labels_of() {
  printf '%s\n' "$1" | jq -r '.labels[]?.name'
}

has_label() {
  local want=$1
  local name
  while IFS= read -r name; do
    [[ "$name" == "$want" ]] && return 0
  done <<< "$2"
  return 1
}

# 0 when a comment's first line equals $2. JSON on stdin.
first_line_is() {
  local marker=$1
  jq -e --arg m "$marker" '
    [.comments[]? | ((.body // "") | split("\n")[0] | gsub("\r$"; ""))]
    | any(.[]; . == $m)
  ' >/dev/null
}

swap_to() {
  local add=$1
  local json=$2
  local -a args=()
  local name have=0
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if [[ "$name" == "$add" ]]; then
      have=1
      continue
    fi
    if [[ "$name" == factory:* ]]; then
      args+=(--remove-label "$name")
    fi
  done <<< "$(labels_of "$json")"
  if [[ "$have" -eq 0 ]]; then
    args+=(--add-label "$add")
  fi
  if [[ ${#args[@]} -eq 0 ]]; then
    echo "label: ${issue_repo}#${issue} already ${add}"
    return 0
  fi
  if [[ "$dry" -eq 1 ]]; then
    echo "label: ${issue_repo}#${issue} -> ${add}"
    return 0
  fi
  gh issue edit "$issue" --repo "$issue_repo" "${args[@]}" >/dev/null \
    || die 7 "could not set ${add}"
  echo "label: ${issue_repo}#${issue} -> ${add}"
}

post_issue() {
  local body=$1
  if [[ "$dry" -eq 1 ]]; then
    printf '%s\n' "--- issue ${issue_repo}#${issue} ---" "$body"
    return 0
  fi
  gh issue comment "$issue" --repo "$issue_repo" --body "$body" >/dev/null \
    || die 7 "could not comment on issue"
}

post_pr() {
  local body=$1
  if [[ "$dry" -eq 1 ]]; then
    printf '%s\n' "--- pr ${repo}#${pr} ---" "$body"
    return 0
  fi
  gh pr comment "$pr" --repo "$repo" --body "$body" >/dev/null \
    || die 7 "could not comment on pull request"
}

read_body_file() {
  [[ -n "$body_file" && -f "$body_file" ]] || die 2 "body file not found"
  cat "$body_file"
}

branch_ok() {
  local name=$1
  [[ "$name" =~ ^factory/[0-9]+-[A-Za-z0-9._-]+$ ]] || die 2 "branch must be factory/<issue>-<slug>"
  [[ "$name" == factory/"${issue}"-* ]] || die 4 "branch ${name} is not for issue ${issue}"
}

cmd_triage() {
  [[ "$status" == "ready" || "$status" == "blocked" ]] || die 2 "status must be ready or blocked"
  local text marker=$'<!-- factory:triage -->' json
  text=$(read_body_file)
  if [[ "${text%%$'\n'*}" != "$marker" ]]; then
    text="${marker}"$'\n'"${text}"
  fi
  json=$(read_issue) || die 7 "could not read issue"
  if printf '%s\n' "$json" | first_line_is "$marker"; then
    local want="factory:ready"
    if [[ "$status" == "blocked" ]]; then
      want="factory:blocked"
    fi
    if ! has_label "$want" "$(labels_of "$json")"; then
      swap_to "$want" "$json"
      echo "already posted: ${issue_repo}#${issue} triage; label set to ${want}"
      exit 0
    fi
    die 4 "triage comment already posted on ${issue_repo}#${issue}"
  fi
  post_issue "$text"
  if [[ "$status" == "ready" ]]; then
    swap_to "factory:ready" "$json"
  else
    swap_to "factory:blocked" "$json"
  fi
}

cmd_pickup() {
  branch_ok "$branch"
  local marker=$'<!-- factory:building -->' json body
  json=$(read_issue) || die 7 "could not read issue"
  if printf '%s\n' "$json" | first_line_is "$marker"; then
    echo "already posted: ${issue_repo}#${issue} building"
    # A comment that landed before a failed label write must not block the
    # retry. Only factory:ready moves; factory:gate stays at the pull request.
    if has_label "factory:ready" "$(labels_of "$json")"; then
      swap_to "factory:building" "$json"
    fi
    exit 0
  fi
  local names
  names=$(labels_of "$json")
  if ! has_label "factory:ready" "$names"; then
    die 4 "pickup requires factory:ready on ${issue_repo}#${issue}"
  fi
  body=$(printf '%s\n' "$marker" "Picked up ${issue_repo}#${issue}." "Branch: \`${branch}\`." "One pull request on that branch. Not merged.")
  post_issue "$body"
  swap_to "factory:building" "$json"
}

cmd_pr() {
  branch_ok "$head"
  [[ -n "$title" ]] || die 2 "title is required"
  local json names number existing other
  json=$(read_issue) || die 7 "could not read issue"
  names=$(labels_of "$json")
  if has_label "factory:blocked" "$names" || has_label "factory:done" "$names"; then
    die 4 "issue ${issue_repo}#${issue} is blocked or done"
  fi
  if ! has_label "factory:building" "$names" && ! has_label "factory:gate" "$names"; then
    die 4 "open the pull request only from factory:building (run pickup first)"
  fi
  existing=$(gh pr list --repo "$repo" --state open --limit 50 \
    --json number,headRefName,body) || die 7 "could not list pull requests"
  number=$(printf '%s\n' "$existing" | jq -r --arg h "$head" '
    [ .[] | select(.headRefName == $h) | .number ] | if length == 0 then "" else .[0] | tostring end
  ')
  other=$(printf '%s\n' "$existing" | jq -r --arg h "$head" --arg n "$issue" '
    def closes: ((.body // "") | test("([Cc]loses|[Ff]ixes|[Rr]esolves)[[:space:]]+#"+$n+"(?![0-9])"));
    [ .[] | select(.headRefName != $h) | select((.headRefName | startswith("factory/"+$n+"-")) or closes) | .number ]
    | if length == 0 then "" else .[0] | tostring end
  ')
  if [[ -n "$other" ]]; then
    die 4 "issue ${issue} already has open pull request #${other}; not opening another"
  fi
  if [[ -z "$number" ]]; then
    local body
    body=$(read_body_file)
    if [[ "$dry" -eq 1 ]]; then
      echo "pr: create ${repo} ${head}"
      number="0"
    else
      gh pr create --repo "$repo" --base main --head "$head" --title "$title" --body "$body" >/dev/null \
        || die 7 "could not create pull request"
      number=$(gh pr list --repo "$repo" --state open --limit 20 --json number,headRefName \
        | jq -r --arg h "$head" '[.[] | select(.headRefName == $h) | .number][0] // empty') \
        || die 7 "could not read new pull request"
      [[ -n "$number" ]] || die 7 "could not read new pull request"
    fi
    echo "pr: ${repo}#${number} opened on ${head}"
  else
    echo "pr: ${repo}#${number} already open on ${head}"
  fi
  local marker=$'<!-- factory:pr -->' note
  if ! printf '%s\n' "$json" | first_line_is "$marker"; then
    note=$(printf '%s\n' "$marker" \
      "Pull request: ${repo}#${number}" \
      "Branch: \`${head}\`" \
      "Waiting on required checks. Not merged.")
    post_issue "$note"
  else
    echo "already posted: ${issue_repo}#${issue} pull request link"
  fi
  if has_label "factory:building" "$names"; then
    swap_to "factory:gate" "$json"
  fi
}

cmd_verdict() {
  [[ "$pr" =~ ^[0-9]+$ ]] || die 2 "bad pr"
  [[ "$sha" =~ ^[0-9a-fA-F]{7,40}$ ]] || die 2 "bad sha"
  case "$verdict" in
    PASS|FIX|ESCALATE) ;;
    *) die 2 "verdict must be PASS, FIX, or ESCALATE" ;;
  esac
  [[ "$protected" == "yes" || "$protected" == "no" ]] || die 2 "protected must be yes or no"
  [[ -n "$summary" ]] || die 2 "summary is required"
  local json names
  json=$(read_issue) || die 7 "could not read issue"
  names=$(labels_of "$json")
  if has_label "factory:blocked" "$names" || has_label "factory:done" "$names"; then
    die 4 "issue ${issue_repo}#${issue} is blocked or done; not posting a verdict"
  fi
  local pr_json marker should human four short
  pr_json=$(gh pr view "$pr" --repo "$repo" --json comments) || die 7 "could not read pull request"
  short=$(printf '%s' "$sha" | cut -c1-7)
  summary=${summary//$'\n'/ }
  marker="<!-- factory:independent-review v2 sha=${sha} -->"
  if ! printf '%s\n' "$pr_json" | first_line_is "$marker"; then
    human=$(printf '%s\n' "$marker" \
      "**Independent review (after CodeRabbit): ${verdict}** on ${short}" \
      "$summary")
    post_pr "$human"
  else
    echo "already posted: ${repo}#${pr} independent review ${short}"
  fi
  case "$verdict" in
    FIX) should=1 ;;
    *) should=0 ;;
  esac
  four=$(printf '%s\n' "<!-- factory:review -->" "verdict: ${verdict}" "should-fix: ${should}" "nits: 0")
  if ! printf '%s\n' "$pr_json" | jq -e --arg v "verdict: ${verdict}" '
      [.comments[]? | ((.body // "") | split("\n") | map(gsub("\r$"; "")))]
      | map(select(.[0] == "<!-- factory:review -->"))
      | if length == 0 then false else (.[-1][1] == $v) end
    ' >/dev/null; then
    post_pr "$four"
  else
    echo "already posted: ${repo}#${pr} verdict ${verdict}"
  fi
  if [[ "$verdict" == "FIX" ]]; then
    swap_to "factory:building" "$json"
    return 0
  fi
  if [[ "$verdict" == "ESCALATE" || ( "$verdict" == "PASS" && "$protected" == "yes" ) ]]; then
    local why=$'<!-- factory:review -->'$'\nblocked: needs-scott\nScott must act.'
    if ! printf '%s\n' "$json" | jq -e '
        [.comments[]? | ((.body // "") | split("\n") | map(gsub("\r$"; "")))]
        | any(.[]; .[0] == "<!-- factory:review -->" and .[1] == "blocked: needs-scott")
      ' >/dev/null; then
      post_issue "$why"
    fi
    swap_to "factory:blocked" "$json"
    return 0
  fi
  swap_to "factory:merge" "$json"
  echo "not merged: ${repo}#${pr} is factory:merge; merging stays in AGENTS.md section 6"
}

cmd_blocked() {
  local text marker=$'<!-- factory:blocked -->' json
  text=$(read_body_file)
  if [[ "${text%%$'\n'*}" != "$marker" ]]; then
    text="${marker}"$'\n'"${text}"
  fi
  json=$(read_issue) || die 7 "could not read issue"
  if printf '%s\n' "$json" | first_line_is "$marker"; then
    echo "already posted: ${issue_repo}#${issue} blocked"
    if ! has_label "factory:blocked" "$(labels_of "$json")"; then
      swap_to "factory:blocked" "$json"
    fi
    exit 0
  fi
  post_issue "$text"
  swap_to "factory:blocked" "$json"
}

case "$cmd" in
  triage) cmd_triage ;;
  pickup) cmd_pickup ;;
  pr) cmd_pr ;;
  verdict) cmd_verdict ;;
  blocked) cmd_blocked ;;
  help|-h|--help) usage ;;
  *) die 2 "unknown command: $cmd" ;;
esac
