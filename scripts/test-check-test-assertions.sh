#!/usr/bin/env bash
# Behaviour tests for scripts/check-test-assertions.sh. ShellCheck covers this
# file. Builds throwaway git repos under a temp dir; no network, no writes
# outside it.
set -euo pipefail

# SC2016 off for this file: the single-quoted strings below are literal fixture
# content written into throwaway test scripts. They must reach disk with their
# $variables unexpanded, because the point is to assert on the text itself.
# shellcheck disable=SC2016

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
check="$here/check-test-assertions.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
pass() { echo "ok: $tname"; }

# A repo with one test script on main, then one commit on a branch.
make_repo() {
  local dir=$1 base_body=$2 head_body=$3
  rm -rf "$dir"; mkdir -p "$dir/scripts"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email t@example.com
  git -C "$dir" config user.name test
  printf '%s\n' "$base_body" > "$dir/scripts/test-thing.sh"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m base
  git -C "$dir" checkout -q -b topic
  printf '%s\n' "$head_body" > "$dir/scripts/test-thing.sh"
  git -C "$dir" add -A
  # --allow-empty: one case deliberately leaves the test script untouched.
  git -C "$dir" commit -q --allow-empty -m head
}

run_check() {
  local dir=$1; shift
  ( cd "$dir" && bash "$check" --base main --head HEAD "$@" 2>&1 )
}
code_of() {
  local dir=$1; shift
  ( cd "$dir" && bash "$check" --base main --head HEAD "$@" > /dev/null 2>&1 ) && echo 0 || echo $?
}

base='assert_eq "$got" "expected"'

tname="a changed assertion fails"
make_repo "$work/r1" "$base" 'assert_eq "$got" "something else"'
[[ "$(code_of "$work/r1")" == "1" ]] || fail "expected exit 1"
out=$(run_check "$work/r1" || true)
[[ "$out" == *"existing assertion"* ]] || fail "no explanation printed"
pass

tname="a removed assertion fails"
make_repo "$work/r2" "$base" '# assertion gone'
[[ "$(code_of "$work/r2")" == "1" ]] || fail "expected exit 1"
pass

tname="the override label passes a changed assertion"
make_repo "$work/r3" "$base" 'assert_eq "$got" "something else"'
[[ "$(code_of "$work/r3" --label-present yes)" == "0" ]] || fail "label should pass it"
out=$(run_check "$work/r3" --label-present yes || true)
[[ "$out" == *"approved this"* ]] || fail "no label note"
pass

tname="adding an assertion passes"
make_repo "$work/r4" "$base" "$base"$'\n''assert_eq "$other" "new"'
[[ "$(code_of "$work/r4")" == "0" ]] || fail "additions must pass"
pass

tname="a comment-only edit passes"
make_repo "$work/r5" "$base" "# a note"$'\n'"$base"
[[ "$(code_of "$work/r5")" == "0" ]] || fail "comment-only must pass"
pass

tname="an untouched test script passes"
make_repo "$work/r6" "$base" "$base"
[[ "$(code_of "$work/r6")" == "0" ]] || fail "no change must pass"
pass

tname="a weakened grep check fails"
make_repo "$work/r7" 'grep -q "wanted" out || fail "missing"' 'grep -q "anything" out || fail "missing"'
[[ "$(code_of "$work/r7")" == "1" ]] || fail "weakened grep must fail"
pass

tname="non-test scripts are ignored"
rm -rf "$work/r8"; mkdir -p "$work/r8/scripts"
git -C "$work/r8" init -q -b main
git -C "$work/r8" config user.email t@example.com
git -C "$work/r8" config user.name test
printf '%s\n' 'assert_eq a b' > "$work/r8/scripts/not-a-test.sh"
git -C "$work/r8" add -A && git -C "$work/r8" commit -q -m base
git -C "$work/r8" checkout -q -b topic
printf '%s\n' 'assert_eq a c' > "$work/r8/scripts/not-a-test.sh"
git -C "$work/r8" add -A && git -C "$work/r8" commit -q -m head
[[ "$(code_of "$work/r8")" == "0" ]] || fail "only scripts/test-*.sh is protected"
pass

tname="bad --label-present is a usage error"
make_repo "$work/r9" "$base" "$base"
[[ "$(code_of "$work/r9" --label-present maybe)" == "2" ]] || fail "expected exit 2"
pass

echo "all check-test-assertions tests passed"
