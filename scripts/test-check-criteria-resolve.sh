#!/usr/bin/env bash
# Behaviour tests for scripts/check-criteria-resolve.sh (#345).
# Builds a small tree in a temp dir and a fake gh first on PATH. Never calls
# the real gh or the network. Criteria text is data and never executed.
# shellcheck disable=SC2016,SC2015  # fixtures hold literal backticks
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script=$here/check-criteria-resolve.sh
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
TREE=$ROOT/tree
OUT=$ROOT/out
CRIT=$ROOT/criteria.txt
mkdir -p "$TREE/scripts" "$TREE/.github/workflows" "$ROOT/bin"
: > "$TREE/scripts/ready-gate.sh"
cat > "$TREE/.github/workflows/lint.yml" << 'YML'
name: Lint
on: [push]
jobs:
  tests:
    name: tests
    runs-on: ubuntu-latest
    steps:
      - run: true
  shellcheck:
    name: ShellCheck
    runs-on: ubuntu-latest
    steps:
      - run: true
YML

tname=startup
fail() { echo "FAIL ($tname): $*" >&2; echo "--- stdout ---" >&2; cat "$OUT" >&2; exit 1; }
: > "$OUT"

# run <exit-code> <criteria line>...: runs the check on the tree and asserts the exit code.
run() {
  local want=$1 got=0
  shift
  printf '%s\n' "$@" > "$CRIT"
  bash "$script" "$CRIT" "$TREE" > "$OUT" 2> "$ROOT/err" || got=$?
  [[ "$got" -eq "$want" ]] || fail "expected exit $want, got $got"
}

tname="resolving path and workflow job"
run 0 '- [ ] `scripts/ready-gate.sh` exits 0 and runs inside the `tests` job.'
[[ ! -s "$OUT" ]] || fail "printed output on success"
printf '%s\n' "ok: $tname"

tname="job named by its display name, and a workflow path"
run 0 '- [ ] the `ShellCheck` job passes' '- [ ] edits .github/workflows/lint.yml'
printf '%s\n' "ok: $tname"

tname="missing path is listed once"
run 1 '- [ ] `scripts/missing.sh` exits 0' '- [ ] `scripts/missing.sh` exits 1'
[[ "$(cat "$OUT")" == "scripts/missing.sh" ]] || fail "expected only scripts/missing.sh"
printf '%s\n' "ok: $tname"

tname="missing workflow job"
run 1 '- [ ] runs inside the `ghost` job' '- [ ] job `phantom` is green'
grep -qxF 'job ghost' "$OUT" || fail "ghost not listed"
grep -qxF 'job phantom' "$OUT" || fail "phantom not listed"
printf '%s\n' "ok: $tname"

tname="(new) path and job are allowed"
run 0 '- [ ] `scripts/brand-new.sh` (new) exits 0' '- [ ] adds scripts/another.sh(new)' \
  '- [ ] the `fresh` (new) job runs it' '- [ ] a missing workflow .github/workflows/x.yml (new)'
printf '%s\n' "ok: $tname"

tname="one missing name per line, (new) ones skipped"
run 1 '- [ ] `scripts/a.sh` (new) and `scripts/b.sh` and `scripts/ready-gate.sh`'
[[ "$(cat "$OUT")" == "scripts/b.sh" ]] || fail "expected only scripts/b.sh"
printf '%s\n' "ok: $tname"

tname="criterion naming nothing passes"
run 0 '- [ ] the docs describe the rollback steps' '- [ ] CHANGELOG.md has a dated entry' ''
printf '%s\n' "ok: $tname"

tname="path cannot leave the root, directories are not files"
run 1 '- [ ] see scripts/../scripts/ready-gate.sh'
mkdir -p "$TREE/scripts/sub"
run 1 '- [ ] see scripts/sub'
printf '%s\n' "ok: $tname"

tname="symlinks and empty segments do not resolve"
mkdir -p "$ROOT/outside/dir"
: > "$ROOT/outside/real.sh"
: > "$ROOT/outside/dir/inner.sh"
: > "$TREE/scripts/ok.sh"
ln -s "$ROOT/outside/real.sh" "$TREE/scripts/link-out.sh"
ln -s "$ROOT/outside/dir" "$TREE/scripts/linkdir"
ln -s ok.sh "$TREE/scripts/link-in.sh"
run 1 '- [ ] see scripts/link-out.sh'
[[ "$(cat "$OUT")" == "scripts/link-out.sh" ]] || fail "file symlink to outside resolved"
run 1 '- [ ] see scripts/linkdir/inner.sh'
[[ "$(cat "$OUT")" == "scripts/linkdir/inner.sh" ]] || fail "directory symlink to outside resolved"
run 1 '- [ ] see scripts/link-in.sh'
[[ "$(cat "$OUT")" == "scripts/link-in.sh" ]] || fail "symlink inside root resolved"
run 0 '- [ ] see scripts/ok.sh'
run 1 '- [ ] see scripts//ok.sh'
[[ "$(cat "$OUT")" == "scripts//ok.sh" ]] || fail "empty segment resolved"
printf '%s\n' "ok: $tname"

tname="criteria text is data"
run 1 '- [ ] `scripts/x$(touch '"$ROOT"'/canary).sh` exits 0'
[[ ! -e "$ROOT/canary" ]] || fail "criteria text was executed"
printf '%s\n' "ok: $tname"

tname="bad usage"
got=0
bash "$script" > "$OUT" 2> "$ROOT/err" < /dev/null || got=$?
[[ "$got" -eq 2 ]] || fail "no arguments: expected exit 2, got $got"
got=0
bash "$script" "$ROOT/nope.txt" "$TREE" > "$OUT" 2> "$ROOT/err" || got=$?
[[ "$got" -eq 2 ]] || fail "missing file: expected exit 2, got $got"
printf '%s\n' "ok: $tname"

# --repo reads the target's default branch through gh.
cat > "$ROOT/bin/gh" << 'FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == api && "${2:-}" == */git/trees/* ]]; then
  printf '%s\n' scripts/ready-gate.sh .github/workflows/lint.yml README.md
  exit 0
fi
if [[ "${1:-}" == api && "${2:-}" == */contents/.github/workflows/lint.yml ]]; then
  cat "${GH_WORKFLOW_FILE:?}"
  exit 0
fi
echo "unexpected gh: $*" >&2
exit 99
FAKE
chmod +x "$ROOT/bin/gh"
export GH_WORKFLOW_FILE=$TREE/.github/workflows/lint.yml
PATH="$ROOT/bin:$PATH"
hash -r

tname="--repo resolves against the default branch"
printf '%s\n' '- [ ] `scripts/ready-gate.sh` runs inside the `tests` job' > "$CRIT"
bash "$script" "$CRIT" --repo adamsuk/line > "$OUT" 2> "$ROOT/err" || fail "expected exit 0"
printf '%s\n' '- [ ] `scripts/missing.sh` runs inside the `ghost` job' > "$CRIT"
got=0
bash "$script" "$CRIT" --repo adamsuk/line > "$OUT" 2> "$ROOT/err" || got=$?
[[ "$got" -eq 1 ]] || fail "expected exit 1, got $got"
grep -qxF 'scripts/missing.sh' "$OUT" && grep -qxF 'job ghost' "$OUT" || fail "missing names not listed"
printf '%s\n' "ok: $tname"

tname="--repo with an unreadable repo exits 3"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$ROOT/bin/gh"
got=0
bash "$script" "$CRIT" --repo adamsuk/line > "$OUT" 2> "$ROOT/err" || got=$?
[[ "$got" -eq 3 ]] || fail "expected exit 3, got $got"
printf '%s\n' "ok: $tname"

printf '%s\n' "ok: check-criteria-resolve"
