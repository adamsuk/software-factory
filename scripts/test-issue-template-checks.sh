#!/usr/bin/env bash
# Behaviour tests for scripts/check-issue-template-checks.sh. ShellCheck covers
# this file. Fixtures live under a temp dir; no network and no writes outside it.
#
# The suite itself exits non-zero when the verifier is missing, and when the
# verifier exits zero on a checkbox that names no command. It exits zero when
# that checkbox names an existing regular file under scripts/ in the tree
# being checked (and the other cases below hold). A scripts/ path that is not
# a regular file in that tree fails.
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

# A workflow whose job id is the filename stem, so that id also occurs inside
# .github/workflows/<stem>.yml. stem is a single path segment, not a path.
write_stem_workflow() {
  local root=$1 stem=$2
  mkdir -p "$root/.github/workflows"
  cat > "$root/.github/workflows/${stem}.yml" << EOF
name: ${stem}
jobs:
  ${stem}:
    runs-on: ubuntu-latest
EOF
}

# A regular file at rel inside a fixture root. The verifier must not run it.
# Running it would create $root/executed-by-check.
write_script() {
  local root=$1 rel=$2 marker
  mkdir -p "$root/$(dirname -- "$rel")"
  marker=$(printf '%q' "$root/executed-by-check")
  printf '%s\n' '#!/usr/bin/env bash' "touch ${marker}" 'exit 0' > "$root/$rel"
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
write_script "$work/script" "scripts/example.sh"
write_form "$work/script" "- [ ] scripts/example.sh exits zero"
capture "$work/script"
[[ -f "$work/script/scripts/example.sh" ]] || fail "fixture script was not created"
[[ $status -eq 0 ]] || fail "expected exit 0 for a scripts/ path, got $status: $out"
[[ ! -e "$work/script/executed-by-check" ]] || fail "verifier executed the named script"
pass

tname="a checkbox that names a missing scripts/ path fails"
write_form "$work/missing" "- [ ] scripts/does-not-exist.sh exits zero"
capture "$work/missing"
[[ $status -eq 1 ]] || fail "expected exit 1 for a missing scripts/ path, got $status: $out"
[[ "$out" == *"scripts/does-not-exist.sh"* ]] || fail "output did not name the missing path: $out"
[[ "$out" == *"- [ ] scripts/does-not-exist.sh exits zero"* ]] || fail "output does not quote the checkbox: $out"
pass

tname="a checked box naming a scripts/ path passes"
write_script "$work/checked" "scripts/example.sh"
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

tname="a job id that occurs only inside its workflow path fails"
bare=$work/barepath
for stem in changelog size-label ruleset-drift; do
  write_stem_workflow "$bare" "$stem"
done
write_form "$bare" \
  "- [ ] .github/workflows/changelog.yml" \
  "- [ ] .github/workflows/size-label.yml" \
  "- [ ] .github/workflows/ruleset-drift.yml"
capture "$bare"
[[ $status -eq 1 ]] || fail "expected exit 1, got $status: $out"
[[ "$out" == *"neither"* ]] || fail "no explanation: $out"
[[ "$out" == *"- [ ] .github/workflows/changelog.yml"* ]] || fail "did not quote the changelog checkbox: $out"
[[ "$out" == *"- [ ] .github/workflows/size-label.yml"* ]] || fail "did not quote the size-label checkbox: $out"
[[ "$out" == *"- [ ] .github/workflows/ruleset-drift.yml"* ]] || fail "did not quote the ruleset-drift checkbox: $out"
pass

tname="a job id named beside its workflow path passes"
named=$work/namedjob
for stem in changelog size-label ruleset-drift; do
  write_stem_workflow "$named" "$stem"
done
write_form "$named" \
  "- [ ] the changelog job in .github/workflows/changelog.yml exits zero" \
  "- [ ] the size-label job in .github/workflows/size-label.yml exits zero" \
  "- [ ] the ruleset-drift job in .github/workflows/ruleset-drift.yml exits zero"
capture "$named"
[[ $status -eq 0 ]] || fail "expected exit 0, got $status: $out"
pass

tname="a second file under ISSUE_TEMPLATE is scanned"
write_script "$work/tree" "scripts/example.sh"
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
