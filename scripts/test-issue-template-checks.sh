#!/usr/bin/env bash
# Behaviour tests for scripts/check-issue-template-checks.sh. ShellCheck covers
# this file. Fixtures live under a temp dir; no network and no writes outside it.
#
# The suite itself exits non-zero when the verifier is missing, and when the
# verifier exits zero on a checkbox that names no command. It exits zero when
# that checkbox names a path under scripts/ (and the other cases below hold).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd)
# CHECK_ISSUE_TEMPLATE_BIN overrides the verifier so the cases below can prove
# this suite fails closed. Unset on a normal run.
check=${CHECK_ISSUE_TEMPLATE_BIN:-$here/check-issue-template-checks.sh}
if [[ ! -f "$check" ]]; then
  echo "FAIL: verifier missing: $check" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tname="startup"
status=0
out=""
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
pass() { echo "ok: $tname"; }

# Sets the globals status and out. A non-zero verifier is a result, not a
# failure of this helper.
capture() {
  status=0
  out=$(bash "$check" "$@" 2>&1) || status=$?
}

# An indented checkbox, as it appears in a GitHub issue form's block scalar.
write_form() {
  local root=$1 line
  shift
  mkdir -p "$root/.github/ISSUE_TEMPLATE"
  {
    printf '%s\n' "body:" "  - type: textarea" "    attributes:" "      placeholder: |"
    for line in "$@"; do
      printf '        %s\n' "$line"
    done
  } > "$root/.github/ISSUE_TEMPLATE/form.yml"
}

write_lint() {
  local root=$1
  mkdir -p "$root/.github/workflows"
  cat > "$root/.github/workflows/lint.yml" << 'EOF'
name: Lint
jobs:
  # A comment sits between jobs: and the id, as in the real workflows.
  tests:
    runs-on: ubuntu-latest
EOF
}

# These two re-enter this file. They run only for the real verifier, so a
# child invoked with CHECK_ISSUE_TEMPLATE_BIN does not re-enter them.
if [[ -z ${CHECK_ISSUE_TEMPLATE_BIN:-} ]]; then
  tname="this test exits non-zero when the verifier is missing"
  status=0
  out=$(CHECK_ISSUE_TEMPLATE_BIN="$work/no-such-verifier.sh" bash "$here/test-issue-template-checks.sh" 2>&1) || status=$?
  [[ $status -ne 0 ]] || fail "expected non-zero, got 0"
  [[ "$out" == *"verifier missing"* ]] || fail "output did not report a missing verifier: $out"
  pass

  tname="this test exits non-zero when the verifier accepts a checkbox that names no command"
  cat > "$work/always-ok.sh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
  status=0
  out=$(CHECK_ISSUE_TEMPLATE_BIN="$work/always-ok.sh" bash "$here/test-issue-template-checks.sh" 2>&1) || status=$?
  [[ $status -ne 0 ]] || fail "expected non-zero, got 0: $out"
  [[ "$out" == *"names no command"* ]] || fail "output did not name the prose checkbox: $out"
  pass
fi

# This case stays first among the fixture checks. The always-ok re-entry above
# stops here, and its message must contain "names no command".
tname="a checkbox that names no command fails"
write_form "$work/prose" "- [ ] The thing works as described"
capture "$work/prose"
[[ $status -eq 1 ]] || fail "verifier accepted a checkbox that names no command (exit $status): $out"
[[ "$out" == *"neither"* ]] || fail "no explanation: $out"
[[ "$out" == *"The thing works as described"* ]] || fail "output does not quote the checkbox: $out"
pass

tname="a checkbox that names a path under scripts/ passes"
write_form "$work/script" "- [ ] scripts/does-not-exist.sh exits zero"
capture "$work/script"
[[ $status -eq 0 ]] || fail "expected exit 0 for a scripts/ path, got $status: $out"
pass

tname="a checked box naming a scripts/ path passes"
write_form "$work/checked" "- [x] scripts/example.sh exits zero"
capture "$work/checked"
[[ $status -eq 0 ]] || fail "expected exit 0, got $status: $out"
pass

tname="myscripts/foo.sh is not a path under scripts/"
write_form "$work/my" "- [ ] myscripts/foo.sh does the thing"
capture "$work/my"
[[ $status -eq 1 ]] || fail "expected exit 1, got $status: $out"
pass

tname="a workflow job passes"
write_form "$work/job" "- [ ] the tests job in .github/workflows/lint.yml exits zero"
write_lint "$work/job"
capture "$work/job"
[[ $status -eq 0 ]] || fail "expected exit 0, got $status: $out"
pass

tname="a workflow file with an unknown job fails"
write_form "$work/badjob" "- [ ] the other job in .github/workflows/lint.yml exits zero"
write_lint "$work/badjob"
capture "$work/badjob"
[[ $status -eq 1 ]] || fail "expected exit 1, got $status: $out"
pass

tname="a job id without its workflow path fails"
write_form "$work/barejob" "- [ ] the tests job exits zero"
write_lint "$work/barejob"
capture "$work/barejob"
[[ $status -eq 1 ]] || fail "expected exit 1, got $status: $out"
pass

tname="a second file under ISSUE_TEMPLATE is scanned"
write_form "$work/tree" "- [ ] scripts/example.sh exits zero"
printf '%s\n' '- [ ] prose only' > "$work/tree/.github/ISSUE_TEMPLATE/extra.md"
capture "$work/tree"
[[ $status -eq 1 ]] || fail "expected exit 1, got $status: $out"
[[ "$out" == *"extra.md"* ]] || fail "did not name extra.md: $out"
pass

tname="an empty ISSUE_TEMPLATE directory passes"
mkdir -p "$work/emptydir/.github/ISSUE_TEMPLATE"
capture "$work/emptydir"
[[ $status -eq 0 ]] || fail "expected exit 0, got $status: $out"
[[ "$out" == *"no checkboxes"* ]] || fail "output: $out"
pass

tname="a missing ISSUE_TEMPLATE directory is a usage error"
mkdir -p "$work/nodir"
capture "$work/nodir"
[[ $status -eq 2 ]] || fail "expected exit 2, got $status: $out"
pass

tname="an unknown flag is a usage error"
capture --nope
[[ $status -eq 2 ]] || fail "expected exit 2, got $status: $out"
pass

tname="help exits zero"
help_out=$(bash "$check" --help)
[[ "$help_out" == *"Exit 0"* ]] || fail "help text missing exit codes: $help_out"
pass

tname="the repo template passes and both checkboxes are seen"
capture "$repo"
[[ $status -eq 0 ]] || fail "repo template rejected (exit $status): $out"
[[ "$out" == *"2 checkboxes"* ]] || fail "verifier did not see both template checkboxes: $out"
pass

tname="task.yml has no factory-managed marker"
if grep -q 'factory-managed' "$repo/.github/ISSUE_TEMPLATE/task.yml"; then
  fail "factory-managed marker still present"
fi
pass

echo "all issue-template-checks tests passed"
