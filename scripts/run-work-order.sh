#!/usr/bin/env bash
# Run one factory work order with Grok Build, headless. See agents/grok-build.md.
#
# Usage: scripts/run-work-order.sh [--push] agents/work-orders/<owner>_<repo>-<issue>.md
#
# Exit codes: 0 ready (pushed with --push), 2 usage or bad work order,
# 3 Grok Build failed or made no change, 4 protected path touched, 5 tests failed.
# It never opens PRs or merges.
set -euo pipefail

die() { echo "run-work-order: $2" >&2; exit "$1"; }

push=false
if [[ "${1:-}" == "--push" ]]; then push=true; shift; fi
[[ $# -eq 1 && -f "$1" ]] || die 2 "usage: $0 [--push] <work-order.md>"
order="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rules="$here/AGENTS.md"
[[ -f "$rules" ]] || die 2 "missing $rules"
for tool in git gh grok jq; do command -v "$tool" > /dev/null || die 2 "$tool not found"; done
git var GIT_COMMITTER_IDENT > /dev/null 2>&1 || die 2 "set git user.name and user.email (the identity agent commits use)"

# Front matter value: the text after `key:` up to a `#` comment, quotes stripped.
field() {
  awk -v k="$1" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && index($0, k ":") == 1 {
      v = substr($0, length(k) + 2); sub(/[ \t]+#.*$/, "", v)
      gsub(/^[ \t"]+|[ \t"]+$/, "", v); print v; exit
    }' "$order"
}

repo=$(field repo); issue=$(field issue); branch=$(field branch)
base=$(field base); tests=$(field test_command); title=$(field title)
base=${base:-main}
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 2 "bad repo: '$repo'"
[[ "$issue" =~ ^[0-9]+$ ]] || die 2 "bad issue: '$issue'"
[[ "$branch" =~ ^factory/[0-9]+-[A-Za-z0-9._-]+$ ]] || die 2 "branch must be factory/<issue>-<slug>"
[[ "$base" =~ ^[A-Za-z0-9._/-]+$ ]] || die 2 "bad base: '$base'"
[[ -n "$tests" ]] || die 2 "test_command is required"
[[ -n "$title" ]] || die 2 "title is required"

dir=$(mktemp -d "/workspace/wo-${repo/\//_}-$issue-XXXXXX")
echo "run-work-order: $repo#$issue in $dir"
gh repo clone "$repo" "$dir" -- --quiet
cd "$dir"
if git ls-remote --exit-code --heads origin "$branch" > /dev/null; then
  git fetch --quiet origin "$branch"
  git switch --quiet "$branch"
else
  git switch --quiet -c "$branch" "origin/$base"
fi
start=$(git rev-parse HEAD)

status=0
env -u GH_TOKEN -u GITHUB_TOKEN grok --no-auto-update \
  --cwd "$dir" --trust \
  --prompt-file "$order" --rules "$(cat "$rules")" \
  --output-format json --max-turns "${GROK_MAX_TURNS:-60}" \
  --always-approve --sandbox workspace \
  --deny 'Bash(git push*)' --deny 'Bash(gh *)' \
  --disable-web-search > "$dir.grok.json" || status=$?
stop=$(jq -r '.stopReason // "none"' "$dir.grok.json" 2> /dev/null || echo none)
[[ $status -eq 0 && "$stop" == "end_turn" ]] || die 3 "grok exit $status, stopReason $stop; see $dir.grok.json"

if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit --quiet -m "$title (#$issue)"
fi
[[ "$(git rev-parse HEAD)" != "$start" ]] || die 3 "grok made no change"

# AGENTS.md section 5: CI config, lockfiles, agent instructions, and edits to existing tests.
protected='^(\.github/(workflows|actions)/|\.github/factory\.yml$|\.github/CODEOWNERS$|CODEOWNERS$|AGENTS\.md$|agents/)|(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|go\.sum|[^/]*\.lock)$'
tests_re='(^|/)(tests?|__tests__|spec)/|[._-](test|spec)\.[a-z]+$|(^|/)test_[^/]*$'
hits=$({
  git diff --name-only "$start" HEAD | grep -E "$protected"
  git diff --name-only --diff-filter=MDR "$start" HEAD | grep -Ei "$tests_re"
} || true)
[[ -z "$hits" ]] || die 4 "needs a person, protected paths changed: $(echo "$hits" | tr '\n' ' ')"

bash -c "$tests" || die 5 "tests failed: $tests"

if $push; then
  git push --quiet -u origin "$branch"
  echo "run-work-order: pushed $branch; open the PR with gh pr create"
else
  echo "run-work-order: ready in $dir on $branch; rerun with --push or push it yourself"
fi
