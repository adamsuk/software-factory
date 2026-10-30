#!/usr/bin/env bash
# Behaviour tests for scripts/run-work-order.sh. The CI lint job shellchecks
# this file; run it with bash to exercise setup and the squashed commit.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/run-work-order.sh
source "$here/run-work-order.sh"

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
ORIG_PATH=$PATH
MOCK_BIN=$ROOT/mockbin
mkdir -p "$MOCK_BIN"
PYTHON_LOG=$ROOT/python.log
NODE_LOG=$ROOT/node.log
PIP_LOG=$ROOT/pip.log
export PYTHON_LOG NODE_LOG PIP_LOG
: > "$PYTHON_LOG"
: > "$NODE_LOG"
: > "$PIP_LOG"

tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2] got [$1]"; }

new_repo() {
  mkdir -p "$1"
  git -C "$1" init -q -b main
  git -C "$1" config user.name Test
  git -C "$1" config user.email test@example.com
  git -C "$1" config commit.gpgsign false
}

reset_logs() {
  : > "$PYTHON_LOG"
  : > "$NODE_LOG"
  : > "$PIP_LOG"
  unset PIP_FAIL_SUBSTR PIP_PROVIDE PIP_TOUCH NODE_TOUCH || true
}

# --- pure helpers -----------------------------------------------------------

tname="yaml"
expect_yaml() {
  local got
  got=$(printf '%s\n' "$2" | agents_setup_from_yaml)
  assert_eq "$got" "$1"
}

expect_yaml "echo hello" "agents:
  setup_command: echo hello"

expect_yaml "echo # hi" "agents:
  setup_command: \"echo # hi\""

expect_yaml "echo hello" "agents:
  setup_command: echo hello # note"

expect_yaml "pip install -e .[dev]" "agents:
  setup_command: 'pip install -e .[dev]'"

expect_yaml "echo yes" "agents:
  setup_command: \"echo yes\"  # comment"

expect_yaml "" "setup_command: echo no
other:
  setup_command: echo also no"

expect_yaml "" "agents:
  extra:
    setup_command: echo nested"

expect_yaml "echo direct" "agents:
  extra:
    setup_command: echo nested
  setup_command: echo direct"

expect_yaml "echo yes" "# file
agents: # roles
  merge: true

  # comment
  setup_command: echo yes
skip:
  setup_command: echo no"

expect_yaml "echo deep" "agents:
    setup_command: echo deep"

expect_yaml "" "agents:
  merge: true"

expect_yaml "" "agents:
  setup_command:"

expect_yaml "echo yes" "setup_command: echo no
agents:
  setup_command: echo yes"

tname="tool-words"
assert_tool() {
  if tool_named "$1" "$2"; then
    [[ "$3" == yes ]] || fail "unexpected match: $2 in [$1]"
  else
    [[ "$3" == no ]] || fail "missed $2 in [$1]"
  fi
}
assert_tool "pytest -q" pytest yes
assert_tool "pytest -q" ruff no
assert_tool "notpytest" pytest no
assert_tool "pytest_cov" pytest no
assert_tool "ruff check . && pytest -q" ruff yes
assert_tool "ruff check . && pytest -q" pytest yes
assert_tool "python -m pytest" pytest yes
assert_tool "mypy." mypy yes
assert_tool "blacken" black no
assert_tool "flake8 src" flake8 yes
assert_tool "" pytest no

tname="python-project-detect"
proj=$ROOT/detect
mkdir -p "$proj/nested"
cd "$proj"
if python_project; then fail "empty dir looked like python"; fi
printf 'x\n' > nested/requirements.txt
if python_project; then fail "nested requirements.txt counted"; fi
printf 'x\n' > requirements-dev.txt
python_project || fail "requirements-dev.txt not detected"
rm requirements-dev.txt
printf 'x\n' > setup.py
python_project || fail "setup.py not detected"
rm setup.py
printf 'x\n' > pyproject.toml
python_project || fail "pyproject.toml not detected"
cd "$ROOT"

tname="work-order-field"
order=$ROOT/order.md
cat > "$order" << 'EOF'
---
repo: acme/widgets
setup_command: "pip install -e '.[dev]'" # comment
---
setup_command: echo hacked
EOF
assert_eq "$(field setup_command)" "pip install -e '.[dev]'"

cat > "$order" << 'EOF'
---
repo: acme/widgets
setup_command: 'python -m venv "/tmp/test venv"' # comment
---
EOF
assert_eq "$(field setup_command)" 'python -m venv "/tmp/test venv"'

cat > "$order" << 'EOF'
---
repo: acme/widgets
setup_command:
---
EOF
assert_eq "$(field setup_command)" ""

# --- commit squashing -------------------------------------------------------

tname="commit-preserves-start"
repo=$ROOT/commits
new_repo "$repo"
cd "$repo"
printf 'base\n' > README
git add README
git commit -q -m base
printf 'old\n' > old.txt
git add old.txt
git commit -q -m "previous attempt"
start=$(git rev-parse HEAD)
start_subject=$(git log -1 --format=%s)
title="feat: prepare things"
issue=34
printf 'mid\n' > README
git add README
git commit -q -m "grok one"
printf 'new\n' > new.txt
git add new.txt
git commit -q -m "grok two"
printf 'final\n' > README
printf 'extra\n' > extra.txt
finish_commit
assert_eq "$(git rev-parse HEAD^)" "$start"
assert_eq "$(git rev-parse "$start")" "$start"
assert_eq "$(git log -1 --format=%s "$start")" "$start_subject"
assert_eq "$(git rev-list --count "$start"..HEAD)" "1"
assert_eq "$(git log -1 --format=%s)" "feat: prepare things (#34)"
assert_eq "$(git rev-list --count HEAD)" "3"
assert_eq "$(git show HEAD:README)" "final"
assert_eq "$(git show HEAD:old.txt)" "old"
assert_eq "$(git show HEAD:new.txt)" "new"
assert_eq "$(git show HEAD:extra.txt)" "extra"
if git log --format=%s | grep -q "grok one"; then
  fail "grok commit message survived the squash"
fi

tname="commit-dirty-only"
repo=$ROOT/dirty-only
new_repo "$repo"
cd "$repo"
printf 'v1\n' > f.txt
git add f.txt
git commit -q -m base
start=$(git rev-parse HEAD)
title="fix: tidy"
issue=34
printf 'v2\n' > f.txt
finish_commit
assert_eq "$(git rev-parse HEAD^)" "$start"
assert_eq "$(git log -1 --format=%s)" "fix: tidy (#34)"
assert_eq "$(git show HEAD:f.txt)" "v2"
assert_eq "$(git rev-list --count "$start"..HEAD)" "1"

tname="commit-no-change"
repo=$ROOT/no-change
new_repo "$repo"
cd "$repo"
git commit -q --allow-empty -m base
start=$(git rev-parse HEAD)
before=$start
title="feat: nothing"
issue=7
code=0
( finish_commit ) > /dev/null 2>&1 || code=$?
assert_eq "$code" "3"
assert_eq "$(git rev-parse HEAD)" "$before"

tname="commit-net-zero"
repo=$ROOT/net-zero
new_repo "$repo"
cd "$repo"
git commit -q --allow-empty -m base
start=$(git rev-parse HEAD)
printf 'x\n' > f.txt
git add f.txt
git commit -q -m "grok add"
git rm -q f.txt
git commit -q -m "grok revert"
title="feat: nothing"
issue=7
code=0
( finish_commit ) > /dev/null 2>&1 || code=$?
assert_eq "$code" "3"
assert_eq "$(git rev-parse HEAD)" "$start"
if git cat-file -e "HEAD:f.txt" 2> /dev/null; then
  fail "reverted file still in the tree"
fi

# --- environment setup ------------------------------------------------------

# Non-venv python3 (reading pyproject.toml) is the real interpreter.
REAL_PYTHON=$(command -v python3)
export REAL_PYTHON
cat > "$MOCK_BIN/python3" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "python3 $*" >> "${PYTHON_LOG:?}"
if [[ "${1:-}" == "-c" ]]; then
  exec "${REAL_PYTHON:?}" "$@"
fi
if [[ "${1:-}" != "-m" || "${2:-}" != "venv" ]]; then
  echo "unexpected python3: $*" >&2
  exit 1
fi
dest="${3:?}"
mkdir -p "$dest/bin"
cat > "$dest/bin/pip" << 'PIP'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${PIP_LOG:?}"
if [[ -n "${PIP_TOUCH:-}" ]]; then
  printf 'touched\n' >> "$PIP_TOUCH"
fi
if [[ -n "${PIP_FAIL_SUBSTR:-}" && "$*" == *"$PIP_FAIL_SUBSTR"* ]]; then
  exit 1
fi
if [[ -n "${PIP_PROVIDE:-}" ]]; then
  printf '%s\n' '#!/bin/sh' > "$(dirname "$0")/${PIP_PROVIDE}"
  chmod +x "$(dirname "$0")/${PIP_PROVIDE}"
fi
for arg in "$@"; do
  case "$arg" in
    pytest|ruff|mypy|black|flake8)
      printf '%s\n' '#!/bin/sh' > "$(dirname "$0")/$arg"
      chmod +x "$(dirname "$0")/$arg"
      ;;
  esac
done
PIP
chmod +x "$dest/bin/pip"
EOF
chmod +x "$MOCK_BIN/python3"

install_node_mock() {
  local name=$1
  cat > "$MOCK_BIN/$name" << EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$name \$*" >> "\${NODE_LOG:?}"
if [[ -n "\${NODE_TOUCH:-}" ]]; then
  printf 'touched\n' >> "\${NODE_TOUCH}"
fi
if [[ "\${NODE_FAIL:-}" == "$name" ]]; then
  exit 1
fi
mkdir -p node_modules/.bin
EOF
  chmod +x "$MOCK_BIN/$name"
}
install_node_mock pnpm
install_node_mock yarn
install_node_mock npm

blank_order() {
  order=$1/order.md
  printf '%s\n' '---' 'repo: acme/widgets' '---' > "$order"
}

enter_project() {
  local d=$1
  new_repo "$d"
  cd "$d"
  blank_order "$d"
  base=main
  dir=$d
  tests="pytest -q"
  reset_logs
  PATH="$MOCK_BIN:$ORIG_PATH"
}

run_fail() {
  local want=$1
  shift
  local code=0 out
  out=$("$@" 2>&1) || code=$?
  assert_eq "$code" "$want"
  captured=$out
}

tname="setup-none"
enter_project "$ROOT/none"
prepare_env > "$ROOT/none.out"
assert_eq "$(cat "$ROOT/none.out")" "run-work-order: setup: none"
assert_eq "$PATH" "$MOCK_BIN:$ORIG_PATH"
[[ ! -e "$dir.venv" ]] || fail "venv created for an empty repo"
assert_eq "$(cat "$PYTHON_LOG")" ""
assert_eq "$(cat "$NODE_LOG")" ""
check_setup_tree

tname="setup-command-wins"
enter_project "$ROOT/wins"
marker=$ROOT/wins-marker
printf '%s\n' '---' "setup_command: touch $marker" '---' > "$order"
printf 'x\n' > pyproject.toml
printf '{}\n' > package.json
printf 'agents:\n  setup_command: touch %s\n' "$ROOT/wins-from-yml" > .github-nope
prepare_env > "$ROOT/wins.out"
assert_eq "$(cat "$ROOT/wins.out")" "run-work-order: setup: setup_command"
[[ -f "$marker" ]] || fail "work order setup_command did not run"
[[ ! -e "$dir.venv" ]] || fail "python setup ran as well"
assert_eq "$(cat "$NODE_LOG")" ""

tname="setup-command-fails"
enter_project "$ROOT/setup-fail"
printf '%s\n' '---' 'setup_command: exit 4' '---' > "$order"
run_fail 6 prepare_env
[[ "$captured" == *"setup: setup_command"* ]] || fail "missing setup line: $captured"
[[ "$captured" == *"setup failed"* ]] || fail "missing setup failed: $captured"

tname="setup-command-exit-trap-keeps-env"
enter_project "$ROOT/setup-trap"
# A setup EXIT trap must not drop exports that test_command needs.
printf '%s\n' '---' 'setup_command: trap "true" EXIT; export SOMEVAR=from-setup' '---' > "$order"
# shellcheck disable=SC2016 # expanded by test_command, not this script
tests='printf %s "$SOMEVAR"'
prepare_env > "$ROOT/setup-trap.out"
assert_eq "$(cat "$ROOT/setup-trap.out")" "run-work-order: setup: setup_command"
[[ ${#setup_env[@]} -gt 0 ]] || fail "setup snapshot missing"
got=$(env -i "${setup_env[@]}" bash -c "$tests") || fail "test_command failed"
assert_eq "$got" "from-setup"

tname="agents-setup-from-base"
enter_project "$ROOT/from-base"
mkdir -p .github
marker=$ROOT/from-base-marker
printf 'agents:\n  merge: true\n  setup_command: touch %s\n' "$marker" > .github/factory.yml
git add .github/factory.yml
git commit -q -m base
git update-ref refs/remotes/origin/main HEAD
printf 'agents:\n  setup_command: touch %s\n' "$ROOT/from-worktree" > .github/factory.yml
prepare_env > "$ROOT/from-base.out"
assert_eq "$(cat "$ROOT/from-base.out")" "run-work-order: setup: agents.setup_command"
[[ -f "$marker" ]] || fail "agents.setup_command did not run"
[[ ! -e "$ROOT/from-worktree" ]] || fail "working tree factory.yml was used"

tname="python-venv"
enter_project "$ROOT/py"
cat > pyproject.toml << 'EOF'
[project]
name = "demo"

[project.optional-dependencies]
dev = ["pytest"]
EOF
printf 'pytest\n' > requirements.txt
printf 'ruff\n' > requirements-dev.txt
tests="ruff check . && pytest -q"
PIP_PROVIDE=pytest
export PIP_PROVIDE
prepare_env > "$ROOT/py.out"
assert_eq "$(cat "$ROOT/py.out")" "run-work-order: setup: python venv"
[[ "$PATH" == "$dir.venv/bin:"* ]] || fail "venv bin is not first on PATH"
[[ -x "$dir.venv/bin/pip" ]] || fail "venv pip missing"
[[ ! -d "$dir/.venv" ]] || fail "venv was created inside the clone"
[[ "$dir.venv" != "$dir/"* ]] || fail "venv path is inside the clone"
assert_eq "$(sed -n '1p' "$PIP_LOG")" "install -e .[dev]"
if grep -Fxq 'install -e .[test]' "$PIP_LOG"; then
  fail "kept trying extras after .[dev] succeeded"
fi
grep -Fxq 'install -r requirements.txt' "$PIP_LOG" || fail "requirements.txt not installed"
grep -Fxq 'install -r requirements-dev.txt' "$PIP_LOG" || fail "requirements-dev.txt not installed"
if grep -Fxq 'install pytest' "$PIP_LOG"; then
  fail "pytest reinstalled though the venv already had it"
fi
grep -Fxq 'install ruff' "$PIP_LOG" || fail "ruff from test_command was not installed"
if grep -Fxq 'install mypy' "$PIP_LOG" || grep -Fxq 'install black' "$PIP_LOG" || grep -Fxq 'install flake8' "$PIP_LOG"; then
  fail "installed a tool that test_command did not name"
fi
assert_eq "$(cat "$NODE_LOG")" ""
check_setup_tree

tname="python-extra-test"
enter_project "$ROOT/py-test-only"
# Only test is a pip extra. A poetry dev group must not add dev.
cat > pyproject.toml << 'EOF'
[project]
name = "demo"

[project.optional-dependencies]
test = ["pytest"]

[tool.poetry.group.dev.dependencies]
ruff = "*"
EOF
prepare_env > "$ROOT/py-test-only.out"
assert_eq "$(cat "$ROOT/py-test-only.out")" "run-work-order: setup: python venv"
assert_eq "$(sed -n '1p' "$PIP_LOG")" "install -e .[test]"

tname="python-extra-both"
enter_project "$ROOT/py-both-extras"
# test is listed first; the install spec stays dev then test.
cat > pyproject.toml << 'EOF'
[project]
name = "demo"

[project.optional-dependencies]
test = ["pytest"]
dev = ["ruff"]
EOF
prepare_env > "$ROOT/py-both-extras.out"
assert_eq "$(cat "$ROOT/py-both-extras.out")" "run-work-order: setup: python venv"
assert_eq "$(sed -n '1p' "$PIP_LOG")" "install -e .[dev,test]"

tname="python-extra-none"
enter_project "$ROOT/py-no-extras"
# No dev or test extra. Other extras are not installed.
cat > pyproject.toml << 'EOF'
[project]
name = "demo"

[project.optional-dependencies]
docs = ["sphinx"]
EOF
prepare_env > "$ROOT/py-no-extras.out"
assert_eq "$(cat "$ROOT/py-no-extras.out")" "run-work-order: setup: python venv"
assert_eq "$(sed -n '1p' "$PIP_LOG")" "install -e ."

tname="python-setup-py"
enter_project "$ROOT/py-setup-py"
printf 'x\n' > setup.py
prepare_env > "$ROOT/py-setup-py.out"
assert_eq "$(cat "$ROOT/py-setup-py.out")" "run-work-order: setup: python venv"
assert_eq "$(sed -n '1p' "$PIP_LOG")" "install -e ."

tname="python-bad-pyproject"
enter_project "$ROOT/py-bad-toml"
printf 'not = [[' > pyproject.toml
prepare_env > "$ROOT/py-bad-toml.out"
assert_eq "$(cat "$ROOT/py-bad-toml.out")" "run-work-order: setup: python venv"
assert_eq "$(sed -n '1p' "$PIP_LOG")" "install -e ."

tname="python-editable-all-fail"
enter_project "$ROOT/py-fail"
printf '[project]\nname = "demo"\n' > pyproject.toml
printf 'pytest\n' > requirements.txt
PIP_FAIL_SUBSTR='install -e'
export PIP_FAIL_SUBSTR
run_fail 6 prepare_env
[[ "$captured" == *"setup: python venv"* ]] || fail "missing python line: $captured"
[[ "$captured" == *"setup failed"* ]] || fail "missing setup failed: $captured"
if grep -q 'install -r' "$PIP_LOG"; then
  fail "continued to requirements after the project install failed"
fi

tname="python-requirements-only"
enter_project "$ROOT/reqs"
printf 'pytest\n' > requirements.txt
tests="pytest -q"
prepare_env > "$ROOT/reqs.out"
assert_eq "$(cat "$ROOT/reqs.out")" "run-work-order: setup: python venv"
if grep -q 'install -e' "$PIP_LOG"; then
  fail "editable install without pyproject.toml or setup.py"
fi
grep -Fxq 'install -r requirements.txt' "$PIP_LOG" || fail "requirements.txt not installed"
grep -Fxq 'install pytest' "$PIP_LOG" || fail "pytest not installed"

tname="python-and-node-prefers-python"
enter_project "$ROOT/both"
printf '[project]\nname = "demo"\n' > pyproject.toml
printf '{}\n' > package.json
printf 'lock\n' > package-lock.json
tests="pytest -q"
prepare_env > "$ROOT/both.out"
assert_eq "$(cat "$ROOT/both.out")" "run-work-order: setup: python venv"
assert_eq "$(cat "$NODE_LOG")" ""

tname="python-dirties-tracked"
enter_project "$ROOT/py-dirty"
printf '[project]\nname = "demo"\n' > pyproject.toml
git add pyproject.toml
git commit -q -m init
PIP_TOUCH=$ROOT/py-dirty/pyproject.toml
export PIP_TOUCH
prepare_env > "$ROOT/py-dirty.out"
run_fail 4 check_setup_tree
[[ "$captured" == *"pyproject.toml"* ]] || fail "did not name the dirty file: $captured"

tname="node-managers"
node_case() {
  local label=$1 seed=$2 expect_line=$3 expect_tool=$4
  tname=$label
  local d=$ROOT/$label
  enter_project "$d"
  printf '{}\n' > package.json
  if [[ -n "$seed" ]]; then
    printf 'lock\n' > "$seed"
  fi
  git add -A
  git commit -q -m init
  prepare_env > "$d.out"
  assert_eq "$(cat "$d.out")" "run-work-order: setup: node $expect_tool"
  assert_eq "$(cat "$NODE_LOG")" "$expect_line"
  [[ "$PATH" == "$d/node_modules/.bin:"* ]] || fail "node_modules/.bin is not first on PATH"
  check_setup_tree
  [[ ! -e "$d.venv" ]] || fail "python venv created for a node repo"
}
node_case node-npm "" "npm install --no-package-lock" npm
node_case node-ci package-lock.json "npm ci" npm
node_case node-shrink npm-shrinkwrap.json "npm ci" npm
node_case node-yarn yarn.lock "yarn install --frozen-lockfile" yarn
node_case node-pnpm pnpm-lock.yaml "pnpm install --frozen-lockfile" pnpm

tname="node-pnpm-wins"
enter_project "$ROOT/node-both-locks"
printf '{}\n' > package.json
printf 'lock\n' > package-lock.json
printf 'lock\n' > pnpm-lock.yaml
prepare_env > "$ROOT/node-both-locks.out"
assert_eq "$(cat "$ROOT/node-both-locks.out")" "run-work-order: setup: node pnpm"
assert_eq "$(cat "$NODE_LOG")" "pnpm install --frozen-lockfile"

tname="node-fails"
enter_project "$ROOT/node-fail"
printf '{}\n' > package.json
NODE_FAIL=npm
export NODE_FAIL
run_fail 6 prepare_env
[[ "$captured" == *"setup: node npm"* ]] || fail "missing node line: $captured"
[[ "$captured" == *"setup failed"* ]] || fail "missing setup failed: $captured"
unset NODE_FAIL

tname="node-dirties-tracked"
enter_project "$ROOT/node-dirty"
printf '{}\n' > package.json
git add package.json
git commit -q -m init
NODE_TOUCH=$ROOT/node-dirty/package.json
export NODE_TOUCH
prepare_env > "$ROOT/node-dirty.out"
run_fail 4 check_setup_tree
[[ "$captured" == *"package.json"* ]] || fail "did not name package.json: $captured"
unset NODE_TOUCH

tname="setup-untracked-ok"
enter_project "$ROOT/untracked"
printf '%s\n' '---' "setup_command: touch $ROOT/untracked/brand-new" '---' > "$order"
git commit -q --allow-empty -m init
prepare_env > "$ROOT/untracked.out"
check_setup_tree
[[ -f "$ROOT/untracked/brand-new" ]] || fail "setup did not create the untracked file"

tname="header"
header=$(sed -n '1,16p' "$here/run-work-order.sh")
[[ "$header" == *"6 setup failed"* ]] || fail "header missing exit code 6"
[[ "$header" == *"setup_command"* ]] || fail "header missing setup step"

# --- bench handoff ----------------------------------------------------------

assert_bench() {
  local file=$1
  shift
  local expected n
  expected=$(printf '%s\n' "$@")
  assert_eq "$(cat "$file")" "$expected"
  n=$(wc -l < "$file")
  n=${n//[[:space:]]/}
  assert_eq "$n" "5"
}

# Writes $dir.bench.txt from a front-matter attempt line ($2, empty to omit it)
# and a Grok JSON document ($3). Remaining args are the five expected lines.
run_bench_case() {
  local name=$1 extra=$2 json=$3
  shift 3
  local broot found
  tname=$name
  broot=$ROOT/$name
  mkdir -p "$broot/clone"
  dir=$broot/clone
  order=$broot/order.md
  {
    printf '%s\n' '---' 'repo: acme/widgets'
    if [[ -n "$extra" ]]; then
      printf '%s\n' "$extra"
    fi
    printf '%s\n' 'test_command: shellcheck scripts/*.sh' '---'
  } > "$order"
  printf '%s\n' "$json" > "$dir.grok.json"
  write_bench_handoff
  bench_file=$dir.bench.txt
  [[ -f "$bench_file" ]] || fail "bench handoff was not written"
  found=$(find "$broot" -name '*.bench.txt' -print)
  assert_eq "$found" "$bench_file"
  assert_bench "$bench_file" "$@"
}

tname="bench-handoff"
new_repo "$ROOT/bench-handoff/clone"
run_bench_case bench-handoff 'attempt: 1' '{
  "thought": "BENCH_DO_NOT_COPY",
  "text": "BENCH_DO_NOT_COPY",
  "requestId": "BENCH_DO_NOT_COPY",
  "cwd": "BENCH_DO_NOT_COPY",
  "modelUsage": "BENCH_DO_NOT_COPY",
  "sessionId": "BENCH_DO_NOT_COPY",
  "total_cost_usd": 1.05,
  "num_turns": 12
}' \
  'attempt: 1' \
  'test_command: shellcheck scripts/*.sh' \
  'tests: pass' \
  'api_equiv_usd: 1.05' \
  'num_turns: 12'
if grep -q 'BENCH_DO_NOT_COPY' "$bench_file"; then
  fail "bench handoff copied a JSON field"
fi
assert_eq "$(git -C "$dir" status --porcelain)" ""
# The call inside main, not the function definition. declare -f main is only the body.
main_src=$(declare -f main)
die_line=$(printf '%s\n' "$main_src" | awk '/die 5 "tests failed/ { n = NR } END { if (n) print n }')
call_line=$(printf '%s\n' "$main_src" | awk '
  /write_bench_handoff[[:space:]]*\(/ { next }
  /function[[:space:]]+write_bench_handoff/ { next }
  /write_bench_handoff/ { print NR; exit }
')
push_line=$(printf '%s\n' "$main_src" | awk '/^[[:space:]]*git push([[:space:]]|$)/ { print NR; exit }')
[[ -n "$die_line" ]] || fail "main missing die 5 tests failed"
[[ -n "$call_line" ]] || fail "main does not call write_bench_handoff"
[[ "$call_line" -gt "$die_line" ]] || fail "write_bench_handoff call appears before die 5 tests failed"
[[ -n "$push_line" && "$call_line" -lt "$push_line" ]] || fail "write_bench_handoff is not before push"

run_bench_case bench-handoff-empty-attempt '' '{
  "total_cost_usd": 1.05,
  "num_turns": 12
}' \
  'attempt: ' \
  'test_command: shellcheck scripts/*.sh' \
  'tests: pass' \
  'api_equiv_usd: 1.05' \
  'num_turns: 12'

run_bench_case bench-handoff-missing-cost 'attempt: 2' '{
  "num_turns": 12
}' \
  'attempt: 2' \
  'test_command: shellcheck scripts/*.sh' \
  'tests: pass' \
  'api_equiv_usd: ' \
  'num_turns: 12'

run_bench_case bench-handoff-cost-not-number 'attempt: 2' '{
  "total_cost_usd": "BENCH_DO_NOT_COPY",
  "num_turns": 12
}' \
  'attempt: 2' \
  'test_command: shellcheck scripts/*.sh' \
  'tests: pass' \
  'api_equiv_usd: ' \
  'num_turns: 12'
if grep -q 'BENCH_DO_NOT_COPY' "$bench_file"; then
  fail "non-numeric total_cost_usd was copied"
fi

run_bench_case bench-handoff-missing-turns 'attempt: 2' '{
  "total_cost_usd": 1.05
}' \
  'attempt: 2' \
  'test_command: shellcheck scripts/*.sh' \
  'tests: pass' \
  'api_equiv_usd: 1.05' \
  'num_turns: '

run_bench_case bench-handoff-turns-not-integer 'attempt: 2' '{
  "total_cost_usd": 1.05,
  "num_turns": 12.5
}' \
  'attempt: 2' \
  'test_command: shellcheck scripts/*.sh' \
  'tests: pass' \
  'api_equiv_usd: 1.05' \
  'num_turns: '

run_bench_case bench-handoff-turns-string 'attempt: 2' '{
  "total_cost_usd": 1.05,
  "num_turns": "12"
}' \
  'attempt: 2' \
  'test_command: shellcheck scripts/*.sh' \
  'tests: pass' \
  'api_equiv_usd: 1.05' \
  'num_turns: '

# --- gate label -------------------------------------------------------------
# A fake gh is first on PATH. These cases call set_gate_label only.
# They do not call main, and they do not call the real gh.

tname="gate-label-setup"
GH_BIN=$ROOT/gate-gh
GH_LOG=$ROOT/gh.log
mkdir -p "$GH_BIN"
cat > "$GH_BIN/gh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf '%s\n' "$@"
  printf '%s\n' '---'
} >> "${GH_LOG:?}"

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  if [[ "${GH_VIEW_STATUS:-0}" != 0 ]]; then
    exit "${GH_VIEW_STATUS}"
  fi
  jq_out=0
  for arg in "$@"; do
    if [[ "$arg" == "--jq" || "$arg" == --jq=* ]]; then
      jq_out=1
    fi
  done
  if [[ "$jq_out" -eq 1 ]]; then
    printf '%s\n' "${GH_LABELS-}"
  else
    printf '%s' '{"labels":['
    sep=""
    while IFS= read -r lab || [[ -n "${lab:-}" ]]; do
      [[ -z "$lab" ]] && continue
      printf '%s{"name":"%s"}' "$sep" "$lab"
      sep=","
    done <<< "${GH_LABELS-}"
    printf '%s\n' ']}'
  fi
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "edit" ]]; then
  if [[ "${GH_EDIT_STATUS:-0}" != 0 ]]; then
    exit "${GH_EDIT_STATUS}"
  fi
  exit 0
fi

printf 'unexpected gh args\n' >&2
exit 99
EOF
chmod +x "$GH_BIN/gh"
PATH="$GH_BIN:$ORIG_PATH"
hash -r
export GH_LOG
assert_eq "$(command -v gh)" "$GH_BIN/gh"

reset_gh() {
  : > "$GH_LOG"
  GH_LABELS=""
  GH_VIEW_STATUS=0
  GH_EDIT_STATUS=0
  export GH_LABELS GH_VIEW_STATUS GH_EDIT_STATUS
}

write_gate_order() {
  local repo_name="$1" issue_repo_value="$2" issue_num="$3"
  order=$ROOT/gate-order.md
  {
    printf '%s\n' "---"
    printf '%s\n' "repo: ${repo_name}"
    printf '%s\n' "issue: ${issue_num}"
    if [[ -n "$issue_repo_value" ]]; then
      printf '%s\n' "issue_repo: ${issue_repo_value}"
    else
      printf '%s\n' "issue_repo:"
    fi
    printf '%s\n' "---"
  } > "$order"
}

assert_no_pr() {
  if grep -Fxq -- "pr" "$GH_LOG"; then
    fail "gh received a pr argument"
  fi
}

assert_gate_view() {
  local repo_name="$1" issue_num="$2"
  awk -v repo="$repo_name" -v issue="$issue_num" '
    function flush(   i, has_repo, has_issue) {
      if (!(n >= 2 && a[1] == "issue" && a[2] == "view")) { n = 0; return }
      views++
      has_repo = 0
      has_issue = 0
      for (i = 1; i <= n; i++) {
        if (a[i] == issue) has_issue = 1
        if (a[i] == "--repo" && (i + 1) <= n && a[i + 1] == repo) has_repo = 1
      }
      if (!has_repo || !has_issue) bad = 1
      n = 0
    }
    BEGIN { views = 0; bad = 0; n = 0 }
    $0 == "---" { flush(); next }
    { a[++n] = $0 }
    END { flush(); if (views != 1 || bad) exit 1 }
  ' "$GH_LOG" || fail "issue view for ${repo_name} #${issue_num} did not match: $(cat "$GH_LOG")"
}

assert_gate_edit() {
  local repo_name="$1" issue_num="$2"
  awk -v repo="$repo_name" -v issue="$issue_num" '
    function flush(   i, has_repo, has_issue, removes, adds, remove_ok, add_ok) {
      if (!(n >= 2 && a[1] == "issue" && a[2] == "edit")) { n = 0; return }
      edits++
      has_repo = 0
      has_issue = 0
      removes = 0
      adds = 0
      remove_ok = 0
      add_ok = 0
      for (i = 1; i <= n; i++) {
        if (a[i] == issue) has_issue = 1
        if (a[i] == "--repo" && (i + 1) <= n && a[i + 1] == repo) has_repo = 1
        if (a[i] == "--remove-label") {
          removes++
          if ((i + 1) <= n && a[i + 1] == "factory:building") remove_ok = 1
        }
        if (a[i] == "--add-label") {
          adds++
          if ((i + 1) <= n && a[i + 1] == "factory:gate") add_ok = 1
        }
      }
      if (!has_repo || !has_issue || removes != 1 || adds != 1 || !remove_ok || !add_ok) bad = 1
      n = 0
    }
    BEGIN { edits = 0; bad = 0; n = 0 }
    $0 == "---" { flush(); next }
    { a[++n] = $0 }
    END { flush(); if (edits != 1 || bad) exit 1 }
  ' "$GH_LOG" || fail "issue edit for ${repo_name} #${issue_num} did not match: $(cat "$GH_LOG")"
}

assert_no_issue_edit() {
  awk '
    function flush() {
      if (n >= 2 && a[1] == "issue" && a[2] == "edit") edits++
      if (n >= 2 && a[1] == "issue" && a[2] == "view") views++
      n = 0
    }
    BEGIN { edits = 0; views = 0; n = 0 }
    $0 == "---" { flush(); next }
    { a[++n] = $0 }
    END { flush(); if (edits != 0 || views != 1) exit 1 }
  ' "$GH_LOG" || fail "expected one issue view and no issue edit: $(cat "$GH_LOG")"
}

tname="gate-label-building"
reset_gh
write_gate_order "adamsuk/gh-factory" "adamsuk/software-factory" "78"
GH_LABELS=$(printf '%s\n' "factory:building" "enhancement")
export GH_LABELS
run_fail 0 set_gate_label
assert_gate_view "adamsuk/software-factory" "78"
assert_gate_edit "adamsuk/software-factory" "78"
assert_no_pr

tname="gate-label-ready"
reset_gh
write_gate_order "adamsuk/gh-factory" "adamsuk/software-factory" "78"
GH_LABELS=$(printf '%s\n' "factory:ready")
export GH_LABELS
run_fail 0 set_gate_label
assert_gate_view "adamsuk/software-factory" "78"
assert_no_issue_edit
assert_no_pr

tname="gate-label-blocked"
reset_gh
write_gate_order "adamsuk/gh-factory" "adamsuk/software-factory" "78"
GH_LABELS=$(printf '%s\n' "factory:blocked" "factory:building")
export GH_LABELS
run_fail 0 set_gate_label
assert_gate_view "adamsuk/software-factory" "78"
assert_no_issue_edit
assert_no_pr

tname="gate-label-empty-issue-repo"
reset_gh
write_gate_order "adamsuk/gh-factory" "" "78"
GH_LABELS=$(printf '%s\n' "factory:building" "enhancement")
export GH_LABELS
run_fail 0 set_gate_label
assert_gate_view "adamsuk/gh-factory" "78"
assert_gate_edit "adamsuk/gh-factory" "78"
assert_no_pr

tname="gate-label-gh-fails"
reset_gh
write_gate_order "adamsuk/gh-factory" "adamsuk/software-factory" "78"
GH_LABELS=$(printf '%s\n' "factory:building")
GH_VIEW_STATUS=1
export GH_LABELS GH_VIEW_STATUS
run_fail 7 set_gate_label
assert_no_issue_edit
assert_no_pr
reset_gh
write_gate_order "adamsuk/gh-factory" "adamsuk/software-factory" "78"
GH_LABELS=$(printf '%s\n' "factory:building" "enhancement")
GH_VIEW_STATUS=0
GH_EDIT_STATUS=1
export GH_LABELS GH_VIEW_STATUS GH_EDIT_STATUS
run_fail 7 set_gate_label
assert_gate_view "adamsuk/software-factory" "78"
assert_gate_edit "adamsuk/software-factory" "78"
assert_no_pr

tname="gate-label-main-placement"
# Confirm placement from declare -f main. Do not call main.
main_src=$(declare -f main)
push_if=$(printf '%s\n' "$main_src" | awk '/^[[:space:]]*if \$push; then[[:space:]]*$/ { print NR; exit }')
push_cmd=$(printf '%s\n' "$main_src" | awk '/^[[:space:]]*git push([[:space:]]|$)/ { print NR; exit }')
gate_call=$(printf '%s\n' "$main_src" | awk '/^[[:space:]]*set_gate_label[[:space:]]*;?[[:space:]]*$/ { print NR; exit }')
else_line=$(printf '%s\n' "$main_src" | awk -v start="$push_if" 'NR > start && /^[[:space:]]*else[[:space:]]*$/ { print NR; exit }')
fi_line=$(printf '%s\n' "$main_src" | awk -v start="$else_line" 'NR > start && /^[[:space:]]*fi;?[[:space:]]*$/ { print NR; exit }')
[[ -n "$push_if" && -n "$push_cmd" && -n "$gate_call" && -n "$else_line" && -n "$fi_line" ]] \
  || fail "could not see the --push branch in main (if=$push_if push=$push_cmd gate=$gate_call else=$else_line fi=$fi_line)"
[[ "$gate_call" -gt "$push_cmd" ]] || fail "set_gate_label is not after git push"
[[ "$gate_call" -gt "$push_if" && "$gate_call" -lt "$else_line" ]] || fail "set_gate_label is not inside the --push branch"
else_body=$(printf '%s\n' "$main_src" | awk -v a="$else_line" -v b="$fi_line" 'NR > a && NR < b { print }')
if [[ "$else_body" == *set_gate_label* || "$else_body" == *"--add-label"* || "$else_body" == *"issue edit"* ]]; then
  fail "a run without --push edits labels"
fi
gate_hits=$(printf '%s\n' "$main_src" | grep -c "set_gate_label" || true)
assert_eq "$gate_hits" "1"
if printf '%s\n' "$main_src" | grep -Eq '^[[:space:]]*gh[[:space:]]+pr([[:space:]]|$)'; then
  fail "main calls gh pr"
fi
clone_line=$(printf '%s\n' "$main_src" | awk '/gh repo clone/ { print NR; exit }')
issue_die_line=$(printf '%s\n' "$main_src" | awk '/die 2/ && /issue_repo/ { print NR; exit }')
pat='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
pat_line=$(printf '%s\n' "$main_src" | awk -v pat="$pat" 'index($0, "issue_repo") && index($0, pat) { print NR; exit }')
guard_line=$(printf '%s\n' "$main_src" | awk '/-n "\$issue_repo"|-z "\$issue_repo"/ { print NR; exit }')
[[ -n "$clone_line" && -n "$issue_die_line" && "$issue_die_line" -lt "$clone_line" ]] \
  || fail "issue_repo pattern check does not exit 2 before gh repo clone"
[[ -n "$pat_line" && "$pat_line" -lt "$clone_line" ]] \
  || fail "issue_repo owner/name pattern is not before gh repo clone"
[[ -n "$guard_line" && "$guard_line" -lt "$clone_line" ]] \
  || fail "empty issue_repo is not allowed through before gh repo clone"
repo_line=$(printf '%s\n' "$main_src" | grep -F "\"\$repo\" =~" || true)
[[ "$repo_line" == *"$pat"* ]] || fail "repo owner/name pattern changed"

# --- publish pull request ---------------------------------------------------
# A fake gh is first on PATH. These cases call publish_pr only.
# They do not call main, and they do not call the real gh.

tname="publish-pr-setup"
GH_BODY=$ROOT/pr-body.txt
export GH_BODY
cat > "$GH_BIN/gh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf '%s\n' "$*"
  printf '%s\n' '---'
} >> "${GH_LOG:?}"

prev=""
for arg in "$@"; do
  if [[ "$prev" == "--body" ]]; then
    printf '%s\n' "$arg" > "${GH_BODY:?}"
  fi
  prev=$arg
done

if [[ "${GH_STATUS:-0}" != "0" ]]; then
  exit "${GH_STATUS}"
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  printf '%s\n' "${GH_LABELS-}"
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  if [[ -n "${GH_PR_NUMBER:-}" ]]; then
    printf '%s\n' "[{\"number\":${GH_PR_NUMBER}}]"
  else
    printf '%s\n' "[]"
  fi
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "create" ]]; then
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "edit" ]]; then
  exit 0
fi

printf 'unexpected gh args\n' >&2
exit 99
EOF
chmod +x "$GH_BIN/gh"
hash -r
assert_eq "$(command -v gh)" "$GH_BIN/gh"

reset_publish_gh() {
  : > "$GH_LOG"
  : > "$GH_BODY"
  GH_LABELS=""
  GH_STATUS=0
  GH_PR_NUMBER=""
  export GH_LABELS GH_STATUS GH_PR_NUMBER
}

write_publish_order() {
  local repo_name=$1 issue_repo_value=$2 issue_num=$3 changelog_value=$4
  order=$ROOT/publish-order.md
  {
    printf '%s\n' "---"
    printf '%s\n' "repo: ${repo_name}"
    printf '%s\n' "issue: ${issue_num}"
    printf '%s\n' "issue_repo: ${issue_repo_value}"
    printf '%s\n' "branch: factory/${issue_num}-pr-run-cost"
    printf '%s\n' "base: main"
    printf '%s\n' "title: feat: record Grok Build cost and attempt on the pull request"
    if [[ -n "$changelog_value" ]]; then
      printf '%s\n' "changelog: ${changelog_value}"
    fi
    printf '%s\n' "---"
  } > "$order"
}

write_bench() {
  dir=$ROOT/publish-dir
  printf '%s\n' "$@" > "$dir.bench.txt"
}

write_standard_bench() {
  local attempt=$1
  local cost=$2
  local turns=${3:-12}
  write_bench \
    "attempt: ${attempt}" \
    "test_command: shellcheck scripts/*.sh" \
    "tests: pass" \
    "api_equiv_usd: ${cost}" \
    "num_turns: ${turns}"
}

assert_body() {
  local expected
  expected=$(printf '%s\n' "$@")
  assert_eq "$(cat "$GH_BODY")" "$expected"
  if grep -q '^[[:space:]]' "$GH_BODY"; then
    fail "body line has a leading space: $(cat "$GH_BODY")"
  fi
}

assert_consecutive() {
  local expect
  expect=$ROOT/expect-block.txt
  printf '%s\n' "$@" > "$expect"
  awk '
    NR == FNR { want[++n] = $0; next }
    {
      if ($0 == want[i + 1]) {
        i++
        if (i == n) { found = 1; exit }
      } else if ($0 == want[1]) {
        i = 1
      } else {
        i = 0
      }
    }
    END { exit found ? 0 : 1 }
  ' "$expect" "$GH_LOG" || fail "expected consecutive lines missing from log: $(cat "$GH_LOG")"
}

assert_log_has() {
  local needle=$1
  grep -Fq -- "$needle" "$GH_LOG" || fail "log missing [$needle]: $(cat "$GH_LOG")"
}

assert_log_lacks() {
  local needle=$1
  if grep -Fq -- "$needle" "$GH_LOG"; then
    fail "log unexpectedly has [$needle]: $(cat "$GH_LOG")"
  fi
}

tname="publish-pr-create"
reset_publish_gh
write_publish_order "adamsuk/software-factory" "adamsuk/software-factory" "102" "true"
GH_LABELS=$(printf '%s\n' "factory:gate" "enhancement")
export GH_LABELS
write_standard_bench "1" "1.05" "12"
bench_before=$(cat "$dir.bench.txt")
run_fail 0 publish_pr
assert_eq "$(cat "$dir.bench.txt")" "$bench_before"
assert_log_has "pr create"
assert_log_lacks "pr edit"
assert_log_has "issue view 102 --repo adamsuk/software-factory"
assert_log_has "--repo adamsuk/software-factory"
assert_log_has "--base main"
assert_log_has "--head factory/102-pr-run-cost"
assert_log_has "--title feat: record Grok Build cost and attempt on the pull request"
assert_log_lacks "skip-changelog"
assert_body \
  "Closes #102" \
  "attempt: 1" \
  "test_command: shellcheck scripts/*.sh" \
  "tests: pass" \
  "api_equiv_usd: 1.05" \
  "num_turns: 12"
assert_consecutive \
  "attempt: 1" \
  "test_command: shellcheck scripts/*.sh" \
  "tests: pass" \
  "api_equiv_usd: 1.05" \
  "num_turns: 12"
assert_log_has "Closes #102"

tname="publish-pr-edit"
reset_publish_gh
write_publish_order "adamsuk/software-factory" "adamsuk/software-factory" "102" "true"
GH_LABELS=$(printf '%s\n' "factory:gate")
GH_PR_NUMBER=55
export GH_LABELS GH_PR_NUMBER
write_standard_bench "2" "1.234" "12"
bench_before=$(cat "$dir.bench.txt")
run_fail 0 publish_pr
assert_eq "$(cat "$dir.bench.txt")" "$bench_before"
assert_log_has "pr edit"
assert_log_lacks "pr create"
assert_log_lacks "skip-changelog"
assert_log_lacks "--title"
assert_body \
  "Closes #102" \
  "attempt: 2" \
  "test_command: shellcheck scripts/*.sh" \
  "tests: pass" \
  "api_equiv_usd: 1.23" \
  "num_turns: 12"
assert_consecutive \
  "attempt: 2" \
  "test_command: shellcheck scripts/*.sh" \
  "tests: pass" \
  "api_equiv_usd: 1.23" \
  "num_turns: 12"
assert_log_has "attempt: 2"
assert_log_has "api_equiv_usd: 1.23"
if grep -Fq 'api_equiv_usd: 1.234' "$GH_LOG"; then
  fail "unrounded api_equiv_usd reached the log"
fi

tname="publish-pr-blocked"
reset_publish_gh
write_publish_order "adamsuk/software-factory" "adamsuk/software-factory" "102" "true"
GH_LABELS=$(printf '%s\n' "factory:blocked" "factory:building")
export GH_LABELS
write_standard_bench "1" "1.05" "12"
run_fail 0 publish_pr
assert_log_has "issue view"
assert_log_lacks "pr list"
assert_log_lacks "pr create"
assert_log_lacks "pr edit"

tname="publish-pr-refs"
reset_publish_gh
write_publish_order "adamsuk/software-factory" "adamsuk/gh-factory" "102" "true"
GH_LABELS=$(printf '%s\n' "factory:gate")
export GH_LABELS
write_standard_bench "1" "1.05" "12"
run_fail 0 publish_pr
assert_log_has "issue view 102 --repo adamsuk/gh-factory"
assert_log_has "pr create --repo adamsuk/software-factory"
assert_log_has "Refs adamsuk/gh-factory#102"
assert_log_lacks "Closes #102"
assert_body \
  "Refs adamsuk/gh-factory#102" \
  "attempt: 1" \
  "test_command: shellcheck scripts/*.sh" \
  "tests: pass" \
  "api_equiv_usd: 1.05" \
  "num_turns: 12"

tname="publish-pr-skip-changelog"
reset_publish_gh
write_publish_order "adamsuk/software-factory" "adamsuk/software-factory" "102" "false"
GH_LABELS=$(printf '%s\n' "factory:gate")
export GH_LABELS
write_standard_bench "1" "1.05" "12"
run_fail 0 publish_pr
assert_log_has "pr create"
assert_log_has "--label skip-changelog"
assert_log_lacks "--add-label"
assert_log_lacks "pr edit"

tname="publish-pr-edit-skip-changelog"
reset_publish_gh
write_publish_order "adamsuk/software-factory" "adamsuk/software-factory" "102" "false"
GH_LABELS=$(printf '%s\n' "factory:gate")
GH_PR_NUMBER=55
export GH_LABELS GH_PR_NUMBER
write_standard_bench "2" "1.20" "9"
run_fail 0 publish_pr
assert_log_has "pr edit"
assert_log_has "--add-label skip-changelog"
assert_log_lacks "pr create"
assert_log_has "api_equiv_usd: 1.2"
assert_body \
  "Closes #102" \
  "attempt: 2" \
  "test_command: shellcheck scripts/*.sh" \
  "tests: pass" \
  "api_equiv_usd: 1.2" \
  "num_turns: 9"

tname="publish-pr-empty-issue-repo"
reset_publish_gh
write_publish_order "adamsuk/software-factory" "" "102" "true"
GH_LABELS=$(printf '%s\n' "factory:building")
export GH_LABELS
write_standard_bench "3" "8" "4"
run_fail 0 publish_pr
assert_log_has "issue view 102 --repo adamsuk/software-factory"
assert_log_has "pr create"
assert_log_has "Closes #102"
assert_log_lacks "Refs "
assert_body \
  "Closes #102" \
  "attempt: 3" \
  "test_command: shellcheck scripts/*.sh" \
  "tests: pass" \
  "api_equiv_usd: 8" \
  "num_turns: 4"

tname="publish-pr-cost-shape"
expect_cost() {
  local raw=$1 want=$2
  tname="publish-pr-cost-${raw}"
  reset_publish_gh
  write_publish_order "adamsuk/software-factory" "adamsuk/software-factory" "102" "true"
  GH_LABELS=$(printf '%s\n' "factory:gate")
  export GH_LABELS
  write_standard_bench "1" "$raw" "12"
  bench_before=$(cat "$dir.bench.txt")
  run_fail 0 publish_pr
  assert_eq "$(cat "$dir.bench.txt")" "$bench_before"
  assert_body \
    "Closes #102" \
    "attempt: 1" \
    "test_command: shellcheck scripts/*.sh" \
    "tests: pass" \
    "api_equiv_usd: ${want}" \
    "num_turns: 12"
  [[ "$want" =~ ^[0-9]+(\.[0-9]{1,2})?$ ]] || fail "fixture ${want} is not the two-decimal shape"
}
expect_cost "1.05" "1.05"
expect_cost "1.234" "1.23"
expect_cost "1.235" "1.24"
expect_cost "1.20" "1.2"
expect_cost "8" "8"

tname="publish-pr-gh-fails"
reset_publish_gh
write_publish_order "adamsuk/software-factory" "adamsuk/software-factory" "102" "true"
GH_LABELS=$(printf '%s\n' "factory:gate")
GH_STATUS=1
export GH_LABELS GH_STATUS
write_standard_bench "1" "1.05" "12"
run_fail 7 publish_pr
assert_log_lacks "pr create"
assert_log_lacks "pr edit"

tname="publish-pr-main-placement"
main_src=$(declare -f main)
push_if=$(printf '%s\n' "$main_src" | awk '/^[[:space:]]*if \$push; then[[:space:]]*$/ { print NR; exit }')
gate_call=$(printf '%s\n' "$main_src" | awk '/^[[:space:]]*set_gate_label[[:space:]]*;?[[:space:]]*$/ { print NR; exit }')
publish_call=$(printf '%s\n' "$main_src" | awk '/^[[:space:]]*publish_pr[[:space:]]*;?[[:space:]]*$/ { print NR; exit }')
else_line=$(printf '%s\n' "$main_src" | awk -v start="$push_if" 'NR > start && /^[[:space:]]*else[[:space:]]*$/ { print NR; exit }')
fi_line=$(printf '%s\n' "$main_src" | awk -v start="$else_line" 'NR > start && /^[[:space:]]*fi;?[[:space:]]*$/ { print NR; exit }')
[[ -n "$push_if" && -n "$gate_call" && -n "$publish_call" && -n "$else_line" && -n "$fi_line" ]] \
  || fail "could not see publish_pr in main (if=$push_if gate=$gate_call publish=$publish_call else=$else_line fi=$fi_line)"
[[ "$publish_call" -gt "$gate_call" && "$publish_call" -lt "$else_line" ]] \
  || fail "publish_pr is not after set_gate_label inside the --push branch"
[[ "$publish_call" -gt "$push_if" ]] || fail "publish_pr is not inside the --push branch"
publish_hits=$(printf '%s\n' "$main_src" | grep -c "publish_pr" || true)
assert_eq "$publish_hits" "1"
else_body=$(printf '%s\n' "$main_src" | awk -v a="$else_line" -v b="$fi_line" 'NR > a && NR < b { print }')
if [[ "$else_body" == *publish_pr* ]]; then
  fail "a run without --push calls publish_pr"
fi
if printf '%s\n' "$main_src" | grep -Eq '^[[:space:]]*gh[[:space:]]+pr([[:space:]]|$)'; then
  fail "main calls gh pr"
fi

# --- bench clone root --------------------------------------------------------

tname="bench-clone-root-default"
unset FACTORY_WORKSPACE
if [[ -d /workspace && -w /workspace && -x /workspace ]]; then
  root_default=$(choose_clone_root)
  assert_eq "$root_default" "/workspace"
else
  err_file=$ROOT/default-workspace.err
  root_default=$(choose_clone_root 2>"$err_file")
  [[ "$root_default" != "/workspace" ]] || fail "should fall back when /workspace unusable"
  grep -Fq "clone root unusable: /workspace" "$err_file" || fail "missing fallback message: $(cat "$err_file")"
  grep -Fq "falling back to $root_default" "$err_file" || fail "missing fallback target: $(cat "$err_file")"
fi

tname="bench-clone-root-explicit"
export FACTORY_WORKSPACE="$ROOT/override-workspace"
mkdir -p "$FACTORY_WORKSPACE"
root_explicit=$(choose_clone_root)
assert_eq "$root_explicit" "$FACTORY_WORKSPACE"
unset FACTORY_WORKSPACE

tname="bench-clone-root-create-missing"
export FACTORY_WORKSPACE="$ROOT/new-workspace-dir"
[[ ! -e "$FACTORY_WORKSPACE" ]] || fail "test dir should not exist"
root_created=$(choose_clone_root)
assert_eq "$root_created" "$FACTORY_WORKSPACE"
[[ -d "$FACTORY_WORKSPACE" ]] || fail "missing root was not created"
[[ -w "$FACTORY_WORKSPACE" ]] || fail "created root not writable"
unset FACTORY_WORKSPACE

tname="bench-clone-root-fallback-nonwritable"
export FACTORY_WORKSPACE="$ROOT/bad-workspace"
mkdir -p "$FACTORY_WORKSPACE"
chmod 555 "$FACTORY_WORKSPACE" || fail "chmod failed"
err_file=$ROOT/bad-workspace.err
root_fb=$(FACTORY_WORKSPACE="$FACTORY_WORKSPACE" choose_clone_root 2>"$err_file")
[[ "$root_fb" != "$FACTORY_WORKSPACE" ]] || fail "did not fall back from non-writable root"
[[ -d "$root_fb" && -w "$root_fb" ]] || fail "fallback root not usable"
grep -Fq "clone root unusable: $FACTORY_WORKSPACE" "$err_file" || fail "missing fallback message: $(cat "$err_file")"
grep -Fq "falling back to $root_fb" "$err_file" || fail "missing fallback target: $(cat "$err_file")"
chmod 755 "$FACTORY_WORKSPACE" || true
unset FACTORY_WORKSPACE

tname="bench-clone-root-main-no-literal-workspace"
main_src=$(declare -f main)
if printf '%s\n' "$main_src" | grep -Fq '/workspace'; then
  fail "main still contains the literal /workspace"
fi

tname="bench-clone-root-main-calls-helper"
printf '%s\n' "$main_src" | grep -Fq 'choose_clone_dir' || fail "main does not call choose_clone_dir"

tname="bench-clone-dir-uses-helper"
export FACTORY_WORKSPACE="$ROOT/dir-workspace"
mkdir -p "$FACTORY_WORKSPACE"
dir_test=$(choose_clone_dir "acme/widgets" 123)
[[ "$dir_test" == "$FACTORY_WORKSPACE"/* ]] || fail "clone dir not under FACTORY_WORKSPACE: $dir_test"
unset FACTORY_WORKSPACE
[[ "$dir_test" == */wo-acme_widgets-123-* ]] || fail "clone dir naming wrong: $dir_test"
[[ "$dir_test" != "$here/"* ]] || fail "clone dir inside repo"
rm -rf "$dir_test" || true

tname="bench-clone-dir-relative-root-absolute"
rel_base="$ROOT/rel-base"
mkdir -p "$rel_base"
dir_rel=$(cd "$rel_base" && FACTORY_WORKSPACE="rel-workspace" choose_clone_dir "acme/widgets" 123)
[[ "$dir_rel" == /* ]] || fail "clone dir not absolute for relative root: $dir_rel"
[[ "$dir_rel" == "$rel_base/rel-workspace/"* ]] || fail "relative root not resolved against cwd: $dir_rel"
rm -rf "$dir_rel" || true

tname="protected-paths-main-placement"
# Confirm via declare -f main, without calling main (grok/gh/clone are not
# mocked for a full run). Two regressions from PR #185's review:
# 1. the protected-paths checker must be resolved through the absolute
#    $here, not a BASH_SOURCE-relative path that breaks after the earlier
#    `cd "$dir"`;
# 2. a work-order filename that happens to match the existing-test pattern
#    (e.g. agents/work-orders/test_example-162.md) must not trip "needs a
#    person" the way an edited existing test would.
main_src=$(declare -f main)
# shellcheck disable=SC2016  # literal text search, not expansion
[[ "$main_src" == *'"$protected_paths_sh"'* ]] \
  || fail "protected-paths checker is not called through \$protected_paths_sh"
# shellcheck disable=SC2016  # literal text search, not expansion
[[ "$main_src" != *'$(dirname "${BASH_SOURCE[0]}")/protected-paths.sh'* ]] \
  || fail "protected-paths checker is still resolved relative to BASH_SOURCE"
[[ "$main_src" == *"-z --name-only"* || "$main_src" == *"--name-only -z"* ]] \
  || fail "protected-paths diff is not NUL-delimited (-z)"
tests_line=$(printf '%s\n' "$main_src" | grep -F 'diff-filter=MDR')
[[ "$tests_line" == *"grep -v '^agents/work-orders/'"* ]] \
  || fail "existing-test check does not exclude agents/work-orders/: $tests_line"

PATH=$ORIG_PATH
# Read by finish_commit / prepare_env in the sourced runner.
: "$title" "$issue" "$base" "$tests"
echo "ok  run-work-order tests"
