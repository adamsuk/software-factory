#!/usr/bin/env bash
# Fails when a pull request changes or removes an existing assertion in a test
# script. Adding tests is fine; weakening one is not (AGENTS.md section 5).
#
# Usage: scripts/check-test-assertions.sh [--base REF] [--head REF] [--label-present yes|no]
#
# Exit 0 when nothing protected changed, or when the override label is present.
# Exit 1 when an existing assertion was changed or removed. Exit 2 on bad usage.
# Reads git only; makes no network calls and no writes.
set -euo pipefail

die() { echo "check-test-assertions: $2" >&2; exit "$1"; }

base="${GITHUB_BASE_REF:-main}"
head="HEAD"
label_present="no"
override_label="approved-test-change"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      [[ $# -ge 2 ]] || die 2 "missing value for --base"
      base="$2"; shift 2 ;;
    --head)
      [[ $# -ge 2 ]] || die 2 "missing value for --head"
      head="$2"; shift 2 ;;
    --label-present)
      [[ $# -ge 2 ]] || die 2 "missing value for --label-present"
      label_present="$2"; shift 2 ;;
    --help) sed -n '2,11p' "$0"; exit 0 ;;
    *) die 2 "unknown argument: $1" ;;
  esac
done

[[ "$label_present" == "yes" || "$label_present" == "no" ]] \
  || die 2 "--label-present must be yes or no"

command -v git > /dev/null 2>&1 || die 2 "git not found in PATH"

merge_base=$(git merge-base "$base" "$head" 2>/dev/null) \
  || die 2 "cannot find a merge base for $base and $head"

# Only test scripts are protected here. CI config and lockfiles are covered by
# CODEOWNERS and section 5 separately.
mapfile -t changed < <(git diff --name-only "$merge_base" "$head" -- 'scripts/test-*.sh' || true)

if [[ "${#changed[@]}" -eq 0 ]]; then
  echo "No test script changed between $merge_base and $head."
  exit 0
fi

# An assertion is a line calling one of the repo's assert/fail helpers, or a
# bare grep/cmp used as a check. A removed or altered one is what we care about;
# pure additions are allowed.
assertion_re='(assert_[a-z_]+|[[:space:]]fail[[:space:]]|\|\|[[:space:]]*fail|grep -q|cmp )'

offending=()
for f in "${changed[@]}"; do
  # Lines removed from the old version of this file, assertions only.
  removed=$(git diff -U0 "$merge_base" "$head" -- "$f" \
    | grep -E '^-' | grep -vE '^---' \
    | sed 's/^-//' \
    | grep -E "$assertion_re" || true)
  if [[ -n "$removed" ]]; then
    offending+=("$f")
    echo "--- $f: existing assertion(s) changed or removed ---"
    printf '%s\n' "$removed" | sed 's/^/    /'
  fi
done

if [[ "${#offending[@]}" -eq 0 ]]; then
  echo "Test scripts changed, but only by addition: ${changed[*]}"
  exit 0
fi

if [[ "$label_present" == "yes" ]]; then
  echo
  echo "Label '$override_label' is present: a person approved this. Passing."
  exit 0
fi

cat >&2 << EOF

An existing test assertion was changed or removed in: ${offending[*]}

Under AGENTS.md section 5 that needs a person, not an agent. Adding tests, and
adding fixture or test data without touching an existing assertion, is fine.

If this change is correct and intended, have Scott add the '$override_label'
label to the pull request and re-run. Say in the PR body which assertion
changed and why.
EOF
exit 1
