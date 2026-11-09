#!/usr/bin/env bash
# Behaviour tests for scripts/gate-issue.sh. A fake gh is first on PATH.
# This file never calls the real gh. Cases 1-15 are the acceptance cases.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script=$here/gate-issue.sh
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
ORIG_PATH=$PATH
FAKE_BIN=$ROOT/bin
GH_LOG=$ROOT/gh.log
GH_FACTORY_FILE=$ROOT/factory.yml
mkdir -p "$FAKE_BIN"
: > "$GH_LOG"
export GH_LOG GH_FACTORY_FILE

tname="startup"
stdout=""
code=0
issue_num=""
order=""

fail() {
  echo "FAIL ($tname): $*" >&2
  echo "--- stdout ---" >&2
  printf '%s\n' "${stdout:-}" >&2
  echo "--- stderr ---" >&2
  cat "$ROOT/err" >&2 2>/dev/null || true
  echo "--- gh log ---" >&2
  cat "$GH_LOG" >&2 2>/dev/null || true
  exit 1
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "expected [$2] got [$1]"
}

cat > "$FAKE_BIN/gh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@" >> "${GH_LOG:?}"

for arg in "$@"; do
  case "$arg" in
    merge | create | ready | --watch | --required)
      echo "forbidden gh arg: $arg" >&2
      exit 99
      ;;
  esac
done

cmd=${1:-}
sub=${2:-}
json_field=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--json" ]]; then
    json_field=$arg
  fi
  prev=$arg
done

if [[ "$cmd" == "issue" && "$sub" == "view" ]]; then
  if [[ "$json_field" == "labels" ]]; then
    python3 -c 'import json,os
labels=[x for x in os.environ.get("GH_LABELS","").split("\n") if x]
print(json.dumps({"labels":[{"name":n} for n in labels]}))'
    exit 0
  fi
  if [[ "$json_field" == "comments" ]]; then
    printf '%s\n' "$GH_COMMENTS_JSON"
    exit 0
  fi
  echo "unexpected issue view json: $json_field" >&2
  exit 99
fi

if [[ "$cmd" == "pr" && "$sub" == "view" ]]; then
  printf '%s\n' "$GH_PR_JSON"
  exit 0
fi

if [[ "$cmd" == "pr" && "$sub" == "checks" ]]; then
  printf '%s\n' "$GH_CHECKS_JSON"
  exit "$GH_CHECKS_STATUS"
fi

if [[ "$cmd" == "api" ]]; then
  if [[ "${GH_FACTORY_MODE:-raw}" == "json" ]]; then
    python3 -c 'import base64, json, os
data = open(os.environ["GH_FACTORY_FILE"], "rb").read()
b64 = base64.b64encode(data).decode("ascii")
wrapped = "\n".join(b64[i:i+60] for i in range(0, len(b64), 60))
print(json.dumps({"name": "factory.yml", "encoding": "base64", "content": wrapped}))'
  else
    cat "${GH_FACTORY_FILE:?}"
  fi
  exit 0
fi

# A real gh prints a URL on success. The script must not pass that through.
if [[ "$cmd" == "issue" && "$sub" == "edit" ]]; then
  status=${GH_EDIT_STATUS:-0}
  if [[ "$status" -eq 0 ]]; then
    printf '%s\n' "https://github.com/example/issues/1"
  fi
  exit "$status"
fi

if [[ "$cmd" == "issue" && "$sub" == "comment" ]]; then
  status=${GH_COMMENT_STATUS:-0}
  if [[ "$status" -eq 0 ]]; then
    printf '%s\n' "https://github.com/example/issues/1#issuecomment-1"
  fi
  exit "$status"
fi

echo "unexpected gh: $*" >&2
exit 99
EOF
chmod +x "$FAKE_BIN/gh"
PATH="$FAKE_BIN:$ORIG_PATH"
export PATH
hash -r
[[ "$(command -v gh)" == "$FAKE_BIN/gh" ]] || fail "fake gh is not first on PATH"
[[ -x "$script" ]] || fail "gate-issue.sh is not executable"
[[ -x "$here/test-gate-issue.sh" ]] || fail "test-gate-issue.sh is not executable"

gh_count() {
  python3 - "$GH_LOG" "$@" << 'PY'
import json, sys
path = sys.argv[1]
want = sys.argv[2:]
n = 0
with open(path) as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        args = json.loads(line)
        if args[:len(want)] == want:
            n += 1
print(n)
PY
}

gh_has_arg() {
  python3 - "$GH_LOG" "$1" << 'PY'
import json, sys
path, word = sys.argv[1:]
found = False
with open(path) as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        if word in json.loads(line):
            found = True
            break
sys.exit(0 if found else 1)
PY
}

assert_no_forbidden() {
  local word
  for word in merge create ready --watch --required; do
    if gh_has_arg "$word"; then
      fail "gh received a forbidden argument: $word"
    fi
  done
}

assert_invocations() {
  local want=$1
  shift
  local n
  n=$(gh_count "$@")
  assert_eq "$n" "$want"
}

assert_no_arg() {
  if gh_has_arg "$1"; then
    fail "gh received argument [$1]"
  fi
}

assert_edit() {
  local repo=$1 remove=$2 add=$3
  python3 - "$GH_LOG" "$issue_num" "$repo" "$remove" "$add" << 'PY' || fail "issue edit did not match"
import json, sys
path, issue, repo, remove, add = sys.argv[1:]
edits = []
with open(path) as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        args = json.loads(line)
        if args[:2] == ["issue", "edit"]:
            edits.append(args)
if len(edits) != 1:
    sys.stderr.write("edit count %s\n" % len(edits))
    sys.exit(1)
args = edits[0]

def values(flag):
    return [args[i + 1] for i in range(len(args) - 1) if args[i] == flag]

label_flags = [a for a in args if a in ("--remove-label", "--add-label", "--label")]
if values("--repo") != [repo] or values("--remove-label") != [remove] or values("--add-label") != [add]:
    sys.exit(1)
if label_flags != ["--remove-label", "--add-label"]:
    sys.exit(1)
if issue not in args:
    sys.exit(1)
PY
}

assert_one_comment() {
  local expect=$1 raw
  raw=$(python3 - "$GH_LOG" << 'PY'
import json, sys
path = sys.argv[1]
bodies = []
with open(path) as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        args = json.loads(line)
        if args[:2] == ["issue", "comment"] and "--body" in args:
            bodies.append(args[args.index("--body") + 1])
if len(bodies) != 1:
    sys.stderr.write("comment count %s\n" % len(bodies))
    sys.exit(1)
sys.stdout.write(bodies[0])
sys.stdout.write("@@END@@")
PY
) || fail "expected one issue comment"
  raw=${raw%@@END@@}
  if [[ "$raw" == *$'\n' ]]; then
    raw=${raw%$'\n'}
  fi
  expect=${expect%$'\n'}
  assert_eq "$raw" "$expect"
}

assert_no_comment() {
  assert_invocations 0 issue comment
}

assert_no_edit() {
  assert_invocations 0 issue edit
}

assert_pr_view() {
  local repo=$1 branch=$2
  python3 - "$GH_LOG" "$repo" "$branch" << 'PY' || fail "pr view did not match"
import json, sys
path, repo, branch = sys.argv[1:]
found = False
with open(path) as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        args = json.loads(line)
        if args[:2] != ["pr", "view"]:
            continue
        if "--repo" not in args or "--json" not in args:
            continue
        if args[args.index("--repo") + 1] != repo:
            continue
        if args[args.index("--json") + 1] != "number,baseRefName":
            continue
        if branch in args:
            found = True
if not found:
    sys.exit(1)
PY
}

assert_pr_checks() {
  local repo=$1 number=$2
  python3 - "$GH_LOG" "$repo" "$number" << 'PY' || fail "pr checks did not match"
import json, sys
path, repo, number = sys.argv[1:]
found = False
with open(path) as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        args = json.loads(line)
        if args[:2] != ["pr", "checks"]:
            continue
        if "--repo" not in args or "--json" not in args:
            continue
        if args[args.index("--repo") + 1] != repo:
            continue
        if args[args.index("--json") + 1] != "name,bucket":
            continue
        if number in args:
            found = True
if not found:
    sys.exit(1)
PY
}

escape_stream() {
  python3 -c 'import sys; data = sys.stdin.read(); sys.stdout.write(data.replace("\\", "\\\\").replace("\n", "\\n"))'
}

run_gate() {
  : > "$GH_LOG"
  cp "$order" "$order.before"
  code=0
  stdout=$(bash "$script" "$order" 2> "$ROOT/err" | escape_stream) || code=$?
  cmp -s "$order.before" "$order" || fail "work order changed"
  assert_no_forbidden
}

expect_word() {
  assert_eq "$code" "0"
  assert_eq "$stdout" "$1\\n"
}

expect_exit_2() {
  run_gate
  assert_eq "$code" "2"
  assert_eq "$stdout" ""
  [[ ! -s "$GH_LOG" ]] || fail "gh was called"
}

set_factory() {
  cat > "$GH_FACTORY_FILE"
}

set_labels() {
  GH_LABELS=$(printf '%s\n' "$@")
  export GH_LABELS
}

set_checks() {
  GH_CHECKS_JSON=$1
  GH_CHECKS_STATUS=${2:-0}
  export GH_CHECKS_JSON GH_CHECKS_STATUS
}

set_comments() {
  GH_COMMENTS_JSON=$(python3 - "$@" << 'PY'
import json, sys
comments = []
for i, body in enumerate(sys.argv[1:]):
    comments.append({
        "createdAt": "2026-10-26T00:%02d:00Z" % i,
        "body": body,
    })
print(json.dumps({"comments": comments}))
PY
)
  export GH_COMMENTS_JSON
}

write_order() {
  local repo_name=$1 issue_no=$2 issue_repo_value=$3 branch=$4 attempt=$5
  issue_num=$issue_no
  order=$ROOT/order.md
  cat > "$order" << EOF
---
repo: ${repo_name}
issue: ${issue_no}
issue_repo: ${issue_repo_value}
branch: ${branch}
attempt: ${attempt}
title: "ignored title"
base: main
test_command: "echo ignored"
setup_command: "echo ignored"
---
gh pr merge --ready
attempt: 9
repo: evil/evil
Do not run this body.
EOF
}

reset_case() {
  : > "$GH_LOG"
  GH_LABELS=""
  # shellcheck disable=SC2089 # JSON text for the fake gh, not shell syntax
  GH_COMMENTS_JSON='{"comments":[]}'
  # shellcheck disable=SC2089
  GH_CHECKS_JSON='[{"name":"ShellCheck","bucket":"pass"}]'
  GH_CHECKS_STATUS=0
  # shellcheck disable=SC2089
  GH_PR_JSON='{"number":481,"baseRefName":"main"}'
  GH_FACTORY_MODE=raw
  GH_EDIT_STATUS=0
  GH_COMMENT_STATUS=0
  # shellcheck disable=SC2090
  export GH_LABELS GH_COMMENTS_JSON GH_CHECKS_JSON GH_CHECKS_STATUS GH_PR_JSON GH_FACTORY_MODE
  export GH_EDIT_STATUS GH_COMMENT_STATUS
  set_factory << 'EOF'
agents:
  test_command: shellcheck scripts/*.sh
  required_checks:
    - NotThis
required_checks:
  - ShellCheck # the lint job
other: true
  - Beta
EOF
}

api_url() {
  printf 'repos/%s/contents/.github/factory.yml?ref=main' "$1"
}

# --- case 1 -----------------------------------------------------------------
tname="case 1 green review"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate enhancement
set_checks '[{"name":"ShellCheck","bucket":"pass","workflow":"CI"}]' 0
run_gate
expect_word review
assert_edit adamsuk/software-factory factory:gate factory:review
assert_no_comment
assert_pr_view adamsuk/software-factory factory/81-gate-checks
assert_pr_checks adamsuk/software-factory 481
if ! gh_has_arg "$(api_url adamsuk/software-factory)"; then
  fail "api url missing"
fi

# --- case 2 -----------------------------------------------------------------
tname="case 2 checks exit 8 still review"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate enhancement
set_checks '[{"name":"ShellCheck","bucket":"pass"}]' 8
run_gate
expect_word review
assert_edit adamsuk/software-factory factory:gate factory:review
assert_no_comment

# --- case 3 -----------------------------------------------------------------
tname="case 3 fail attempt 1 retry"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"fail"}]' 0
set_comments $'hello\nred: ShellCheck'
run_gate
expect_word retry
assert_no_edit
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: ShellCheck
EOF
)"

# --- case 4 -----------------------------------------------------------------
tname="case 4 repeated red list blocked"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 2
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"fail"}]' 0
set_comments \
  $'<!-- factory:gate -->\nred: Other' \
  $'not a marker\nred: ShellCheck' \
  $'<!-- factory:gate -->\nblocked: cap\nred: ShellCheck\nScott must act.'
run_gate
expect_word blocked
assert_edit adamsuk/software-factory factory:gate factory:blocked
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
blocked: repeat
red: ShellCheck
The maintainer must act.
EOF
)"

# --- case 5 -----------------------------------------------------------------
tname="case 5 attempt 3 cap"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 3
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"fail"}]' 0
set_comments \
  $'<!-- factory:gate -->\nred: ShellCheck' \
  $'<!-- factory:gate -->\nred: Other' \
  $'newest comment is not a marker'
run_gate
expect_word blocked
assert_edit adamsuk/software-factory factory:gate factory:blocked
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
blocked: cap
red: ShellCheck
The maintainer must act.
EOF
)"

# --- case 6 -----------------------------------------------------------------
tname="case 6 pending"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"pending"}]' 8
run_gate
expect_word pending
assert_no_edit
assert_no_comment
assert_invocations 1 pr checks

# --- case 7 -----------------------------------------------------------------
tname="case 7 already blocked"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate factory:blocked
set_checks '[{"name":"ShellCheck","bucket":"pass"}]' 0
run_gate
expect_word blocked
assert_no_edit
assert_no_comment
assert_no_arg pr

# --- case 8 -----------------------------------------------------------------
tname="case 8 not gate"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:building
set_checks '[{"name":"ShellCheck","bucket":"pass"}]' 0
run_gate
expect_word skip
assert_no_edit
assert_no_comment
assert_no_arg pr

# --- case 9 -----------------------------------------------------------------
tname="case 9 no required checks"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
agents:
  required_checks:
    - ShellCheck
required_checks:
not_checks:
  - ShellCheck
EOF
set_checks '[{"name":"ShellCheck","bucket":"pass"}]' 0
run_gate
expect_word blocked
assert_edit adamsuk/software-factory factory:gate factory:blocked
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
blocked: no-required-checks
red: -
The maintainer must act.
EOF
)"
assert_no_arg checks
assert_invocations 0 pr checks

# --- case 10 ----------------------------------------------------------------
tname="case 10 sorted red names"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - Beta
  - Alpha
stop:
  - Zeta
EOF
set_checks '[{"name":"Zeta","bucket":"fail"},{"name":"Beta","bucket":"fail"},{"name":"Alpha","bucket":"fail"}]' 0
run_gate
expect_word retry
assert_no_edit
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: Alpha, Beta
EOF
)"

# --- case 11 ----------------------------------------------------------------
tname="case 11 pass and pending"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - Alpha
  - Beta
EOF
set_checks '[{"name":"Alpha","bucket":"pass"},{"name":"Beta","bucket":"pending"}]' 0
run_gate
expect_word pending
assert_no_edit
assert_no_comment

# --- case 12 ----------------------------------------------------------------
tname="case 12 skipping is red"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - Alpha
  - Beta
stop:
  - Zeta
EOF
set_checks '[{"name":"Alpha","bucket":"pass"},{"name":"Beta","bucket":"skipping"},{"name":"Zeta","bucket":"fail"}]' 0
run_gate
expect_word retry
assert_no_edit
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: Beta
EOF
)"

# --- case 13 ----------------------------------------------------------------
tname="case 13 absent required check is pending"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_checks '[{"name":"CodeRabbit","bucket":"pass","workflow":"ShellCheck"}]' 0
run_gate
expect_word pending
assert_no_edit
assert_no_comment

# --- case 14 ----------------------------------------------------------------
tname="case 14 empty issue_repo"
reset_case
write_order adamsuk/gh-factory 81 "" factory/81-gate-checks 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"pass"}]' 0
run_gate
expect_word review
assert_edit adamsuk/gh-factory factory:gate factory:review
assert_pr_view adamsuk/gh-factory factory/81-gate-checks
assert_pr_checks adamsuk/gh-factory 481
if ! gh_has_arg "$(api_url adamsuk/gh-factory)"; then
  fail "api url did not use adamsuk/gh-factory"
fi

# --- case 15 ----------------------------------------------------------------
tname="case 15 attempt 4"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 4
set_labels factory:gate
expect_exit_2

# Spec clauses the fifteen cases do not already pin down.
tname="pending wins over red"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - Alpha
  - Beta
EOF
set_checks '[{"name":"Alpha","bucket":"fail"},{"name":"Beta","bucket":"pending"}]' 8
run_gate
expect_word pending
assert_no_edit
assert_no_comment

tname="attempt 1 repeat"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"fail"}]' 0
set_comments $'<!-- factory:gate -->\nred: ShellCheck'
run_gate
expect_word blocked
assert_edit adamsuk/software-factory factory:gate factory:blocked
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
blocked: repeat
red: ShellCheck
The maintainer must act.
EOF
)"

tname="cancel is red"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"cancel"}]' 0
run_gate
expect_word retry
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: ShellCheck
EOF
)"

tname="other bucket is red"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"success"}]' 0
run_gate
expect_word retry
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: ShellCheck
EOF
)"

tname="names with spaces and parentheses"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - Analyze (javascript-typescript) # codeql
EOF
set_checks '[{"name":"Analyze (javascript-typescript)","bucket":"fail"}]' 0
run_gate
expect_word retry
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: Analyze (javascript-typescript)
EOF
)"

tname="base64 factory.yml"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate enhancement
GH_FACTORY_MODE=json
export GH_FACTORY_MODE
set_checks '[{"name":"ShellCheck","bucket":"pass"}]' 0
run_gate
expect_word review
assert_edit adamsuk/software-factory factory:gate factory:review

tname="checks exit 1"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"pass"}]' 1
run_gate
assert_eq "$code" "7"
assert_eq "$stdout" ""
assert_no_edit
assert_no_comment

tname="issue_repo differs from repo"
reset_case
write_order adamsuk/gh-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"pass"}]' 0
run_gate
expect_word review
assert_edit adamsuk/software-factory factory:gate factory:review
assert_pr_view adamsuk/gh-factory factory/81-gate-checks
assert_pr_checks adamsuk/gh-factory 481
if ! gh_has_arg "$(api_url adamsuk/gh-factory)"; then
  fail "pull request read did not use repo"
fi
if gh_has_arg "$(api_url adamsuk/software-factory)"; then
  fail "pull request read used issue_repo"
fi

tname="invalid yaml exits 7 with no stdout"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
required_checks: [] # none inline
  - ShellCheck # not a second value
not_an_item: true
  - Hidden
EOF
set_checks '[{"name":"ShellCheck","bucket":"pass"},{"name":"Hidden","bucket":"fail"}]' 0
run_gate
assert_eq "$code" "7"
assert_eq "$stdout" ""
assert_no_edit
assert_no_comment
assert_invocations 0 pr checks
grep -q 'could not read factory.yml' "$ROOT/err" || fail "stderr missing parser failure"

tname="blank line keeps later required checks"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - Alpha

  - Beta
EOF
set_checks '[{"name":"Alpha","bucket":"pass"},{"name":"Beta","bucket":"fail"}]' 0
run_gate
expect_word retry
assert_no_edit
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: Beta
EOF
)"

tname="comment line keeps later required checks"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - Alpha
  # still required
  - Beta
EOF
set_checks '[{"name":"Alpha","bucket":"pass"},{"name":"Beta","bucket":"fail"}]' 0
run_gate
expect_word retry
assert_no_edit
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: Beta
EOF
)"

tname="quoted required check name"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - "Analyze (javascript-typescript)" # codeql
EOF
set_checks '[{"name":"Analyze (javascript-typescript)","bucket":"fail"}]' 0
run_gate
expect_word retry
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: Analyze (javascript-typescript)
EOF
)"

tname="double quoted escape in a required check name"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - "A \"quoted\" name"
EOF
set_checks '[{"name":"A \"quoted\" name","bucket":"fail"}]' 0
run_gate
expect_word retry
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: A "quoted" name
EOF
)"

tname="required checks indented four spaces"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
    - ShellCheck
EOF
set_checks '[{"name":"ShellCheck","bucket":"pass"}]' 0
run_gate
expect_word review
assert_edit adamsuk/software-factory factory:gate factory:review
assert_no_comment

tname="flow required checks"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
required_checks: [Beta, "Alpha"]
EOF
set_checks '[{"name":"Alpha","bucket":"fail"},{"name":"Beta","bucket":"fail"}]' 0
run_gate
expect_word retry
assert_no_edit
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: Alpha, Beta
EOF
)"

tname="required_checks must be a list of strings"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
required_checks: ShellCheck
EOF
set_checks '[{"name":"ShellCheck","bucket":"pass"}]' 0
run_gate
assert_eq "$code" "7"
assert_eq "$stdout" ""
assert_no_edit
assert_no_comment
assert_invocations 0 pr checks

tname="non-string required check exits 7"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - ShellCheck
  - 1
EOF
run_gate
assert_eq "$code" "7"
assert_eq "$stdout" ""
assert_no_edit
assert_no_comment
assert_invocations 0 pr checks

tname="duplicate check name uses every row"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"pass","workflow":"a"},{"name":"ShellCheck","bucket":"fail","workflow":"b"}]' 0
run_gate
expect_word retry
assert_no_edit
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: ShellCheck
EOF
)"

tname="duplicate check name pending wins"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"pass"},{"name":"ShellCheck","bucket":"pending"}]' 0
run_gate
expect_word pending
assert_no_edit
assert_no_comment

tname="duplicate check name all pass"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"pass"},{"name":"ShellCheck","bucket":"pass"}]' 0
run_gate
expect_word review
assert_edit adamsuk/software-factory factory:gate factory:review
assert_no_comment

tname="duplicate check name non-string bucket is red"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"pass"},{"name":"ShellCheck","bucket":null}]' 0
run_gate
expect_word retry
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: ShellCheck
EOF
)"

tname="blocked edit failure prints no stdout"
reset_case
write_order adamsuk/software-factory 81 adamsuk/software-factory factory/81-gate-checks 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
EOF
GH_EDIT_STATUS=1
export GH_EDIT_STATUS
run_gate
assert_eq "$code" "7"
assert_eq "$stdout" ""
assert_invocations 1 issue comment
assert_invocations 1 issue edit

tname="dotted repo name"
reset_case
write_order my.repo_1/name-2 81 "" factory/81-gate-checks 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"pass"}]' 0
run_gate
expect_word review
assert_edit my.repo_1/name-2 factory:gate factory:review

tname="bad work orders"
bad_order() {
  tname="bad: $1"
  shift
  reset_case
  order=$ROOT/order.md
  printf '%s\n' "$@" > "$order"
  expect_exit_2
}
bad_order "repo without slash" \
  "---" "repo: adamsuk" "issue: 81" "branch: factory/81-gate-checks" "attempt: 1" "---"
bad_order "repo two slashes" \
  "---" "repo: adamsuk/software/factory" "issue: 81" "branch: factory/81-gate-checks" "attempt: 1" "---"
bad_order "repo space" \
  "---" "repo: adamsuk/soft ware" "issue: 81" "branch: factory/81-gate-checks" "attempt: 1" "---"
bad_order "bad issue_repo" \
  "---" "repo: adamsuk/software-factory" "issue: 81" "issue_repo: not a repo" \
  "branch: factory/81-gate-checks" "attempt: 1" "---"
bad_order "issue not digits" \
  "---" "repo: adamsuk/software-factory" "issue: 81a" "branch: factory/81-gate-checks" "attempt: 1" "---"
bad_order "empty branch" \
  "---" "repo: adamsuk/software-factory" "issue: 81" "branch:" "attempt: 1" "---"
bad_order "branch space" \
  "---" "repo: adamsuk/software-factory" "issue: 81" "branch: factory/81 gate" "attempt: 1" "---"
bad_order "attempt 0" \
  "---" "repo: adamsuk/software-factory" "issue: 81" "branch: factory/81-gate-checks" "attempt: 0" "---"
bad_order "attempt 03" \
  "---" "repo: adamsuk/software-factory" "issue: 81" "branch: factory/81-gate-checks" "attempt: 03" "---"
tname="bad: missing file"
reset_case
code=0
stdout=$(bash "$script" "$ROOT/missing.md" 2> "$ROOT/err" | escape_stream) || code=$?
assert_eq "$code" "2"
assert_eq "$stdout" ""
[[ ! -s "$GH_LOG" ]] || fail "gh was called"
