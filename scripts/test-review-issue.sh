#!/usr/bin/env bash
# Behaviour tests for scripts/review-issue.sh. A fake gh is first on PATH.
# This file never calls the real gh. Cases 1-17 are the acceptance cases.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script=$here/review-issue.sh
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
comments_json='[]'
reviews_json='[]'

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
    merge | create | ready)
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
  echo "unexpected issue view json: $json_field" >&2
  exit 99
fi

if [[ "$cmd" == "pr" && "$sub" == "view" ]]; then
  status=${GH_PR_STATUS:-0}
  printf '%s\n' "${GH_PR_JSON:?}"
  exit "$status"
fi

if [[ "$cmd" == "api" ]]; then
  mode=${GH_API_MODE:-raw}
  if [[ "$mode" == "not_found" ]]; then
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    echo "gh: Not Found (HTTP 404)" >&2
    exit 1
  fi
  if [[ "$mode" == "error" ]]; then
    printf '%s\n' '{"message":"Server Error","status":"500"}'
    echo "gh: HTTP 500" >&2
    exit 1
  fi
  if [[ "$mode" == "json" ]]; then
    python3 -c 'import base64, json, os
data = open(os.environ["GH_FACTORY_FILE"], "rb").read()
b64 = base64.b64encode(data).decode("ascii")
wrapped = "\n".join(b64[i:i+60] for i in range(0, len(b64), 60))
print(json.dumps({"name": "factory.yml", "encoding": "base64", "content": wrapped}))'
    exit 0
  fi
  cat "${GH_FACTORY_FILE:?}"
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
[[ -x "$script" ]] || fail "review-issue.sh is not executable"
[[ -x "$here/test-review-issue.sh" ]] || fail "test-review-issue.sh is not executable"
[[ "$(head -n 1 "$script")" == "#!/usr/bin/env bash" ]] || fail "review-issue.sh shebang"
[[ "$(head -n 1 "$here/test-review-issue.sh")" == "#!/usr/bin/env bash" ]] || fail "test shebang"

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
  for word in merge create ready; do
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

assert_no_api() {
  assert_invocations 0 api
  if gh_has_arg ".github/factory.yml"; then
    fail "gh received a factory.yml argument"
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
  local expect=$1 repo=$2 raw
  raw=$(python3 - "$GH_LOG" "$issue_num" "$repo" << 'PY'
import json, sys
path, issue, repo = sys.argv[1:]
bodies = []
with open(path) as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        args = json.loads(line)
        if args[:2] != ["issue", "comment"] or "--body" not in args:
            continue
        if "--repo" not in args or args[args.index("--repo") + 1] != repo:
            sys.stderr.write("comment repo mismatch\n")
            sys.exit(1)
        if issue not in args:
            sys.stderr.write("comment issue mismatch\n")
            sys.exit(1)
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
        if args[args.index("--json") + 1] != "number,comments,reviews,baseRefName":
            continue
        if branch in args:
            found = True
if not found:
    sys.exit(1)
PY
}

assert_api_url() {
  local url=$1
  if ! gh_has_arg "$url"; then
    fail "api url missing: $url"
  fi
}

escape_stream() {
  python3 -c 'import sys; data = sys.stdin.read(); sys.stdout.write(data.replace("\\", "\\\\").replace("\n", "\\n"))'
}

run_review() {
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
  if [[ -s "$ROOT/err" ]]; then
    fail "unexpected stderr"
  fi
}

expect_exit_2() {
  run_review
  assert_eq "$code" "2"
  assert_eq "$stdout" ""
  [[ ! -s "$GH_LOG" ]] || fail "gh was called"
}

expect_exit_7() {
  assert_eq "$code" "7"
  assert_eq "$stdout" ""
}

set_factory() {
  cat > "$GH_FACTORY_FILE"
}

set_labels() {
  GH_LABELS=$(printf '%s\n' "$@")
  export GH_LABELS
}

add_comment() {
  local login=$1 created=$2 verdict=$3 should=$4 nits=$5
  comments_json=$(python3 -c 'import json,sys
comments=json.loads(sys.argv[1])
body="<!-- factory:review -->\nverdict: %s\nshould-fix: %s\nnits: %s\n" % (sys.argv[4], sys.argv[5], sys.argv[6])
comments.append({"author":{"login":sys.argv[2]},"createdAt":sys.argv[3],"body":body})
print(json.dumps(comments))
' "$comments_json" "$login" "$created" "$verdict" "$should" "$nits")
}

add_raw_comment() {
  local login=$1 created=$2 body=$3
  comments_json=$(python3 -c 'import json,sys
comments=json.loads(sys.argv[1])
comments.append({"author":{"login":sys.argv[2]},"createdAt":sys.argv[3],"body":sys.argv[4]})
print(json.dumps(comments))
' "$comments_json" "$login" "$created" "$body")
}

add_review() {
  local login=$1 state=$2 submitted=$3
  reviews_json=$(python3 -c 'import json,sys
reviews=json.loads(sys.argv[1])
reviews.append({
  "author": {"login": sys.argv[2]},
  "state": sys.argv[3],
  "submittedAt": sys.argv[4],
  "body": "review body that must be ignored",
})
print(json.dumps(reviews))
' "$reviews_json" "$login" "$state" "$submitted")
}

build_pr() {
  local base=$1 number=$2
  GH_PR_JSON=$(python3 -c 'import json,sys
print(json.dumps({
  "number": int(sys.argv[1]),
  "baseRefName": sys.argv[2],
  "comments": json.loads(sys.argv[3]),
  "reviews": json.loads(sys.argv[4]),
}))
' "$number" "$base" "$comments_json" "$reviews_json")
  export GH_PR_JSON
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

use_coderabbit_yml() {
  GH_API_MODE=json
  export GH_API_MODE
  set_factory << 'EOF'
agents:
  merge: false
  review_bot: coderabbit
  test_command: shellcheck scripts/*.sh
EOF
}

reset_case() {
  : > "$GH_LOG"
  comments_json='[]'
  reviews_json='[]'
  GH_LABELS=""
  GH_API_MODE=raw
  GH_PR_STATUS=0
  GH_EDIT_STATUS=0
  GH_COMMENT_STATUS=0
  export GH_LABELS GH_API_MODE GH_PR_STATUS GH_EDIT_STATUS GH_COMMENT_STATUS
  set_factory << 'EOF'
agents:
  review_bot: both
EOF
  build_pr main 96
}

api_url() {
  printf 'repos/%s/contents/.github/factory.yml?ref=%s' "$1" "$2"
}

# --- case 1 -----------------------------------------------------------------
tname="case 1 not found merges"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 4
build_pr main 96
GH_API_MODE=not_found
export GH_API_MODE
run_review
expect_word merge
assert_edit adamsuk/software-factory factory:review factory:merge
assert_no_comment
assert_pr_view adamsuk/software-factory factory/96-review-verdict
assert_api_url "$(api_url adamsuk/software-factory main)"
assert_invocations 1 api
if grep -q 'could not read factory.yml' "$ROOT/err"; then
  fail "Not Found treated as a hard failure"
fi
assert_no_forbidden

# --- case 2 -----------------------------------------------------------------
tname="case 2 coderabbit approved merges"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 1
add_review coderabbitai CHANGES_REQUESTED 2026-10-26T22:00:00Z
add_review coderabbitai APPROVED 2026-10-26T22:30:00Z
use_coderabbit_yml
build_pr main 96
run_review
expect_word merge
assert_edit adamsuk/software-factory factory:review factory:merge
assert_no_comment

# --- case 3 -----------------------------------------------------------------
tname="case 3 later coderabbit changes requested waits"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 1
add_review coderabbitai APPROVED 2026-10-26T22:00:00Z
add_review coderabbitai CHANGES_REQUESTED 2026-10-26T22:30:00Z
use_coderabbit_yml
build_pr main 96
run_review
expect_word wait
assert_no_edit
assert_no_comment

# --- case 4 -----------------------------------------------------------------
tname="case 4 no coderabbit review waits"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
use_coderabbit_yml
build_pr main 96
run_review
expect_word wait
assert_no_edit
assert_no_comment

# --- case 5 -----------------------------------------------------------------
tname="case 5 ready with should-fix waits"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 2 0
build_pr main 96
run_review
expect_word wait
assert_no_edit
assert_no_comment
assert_no_api

# --- case 6 -----------------------------------------------------------------
tname="case 6 changes-needed builds"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 3
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z changes-needed 1 0
build_pr main 96
run_review
expect_word build
assert_edit adamsuk/software-factory factory:review factory:building
assert_no_comment
assert_no_api
grep -q '^attempt: 3$' "$order" || fail "attempt changed"

# --- case 7 -----------------------------------------------------------------
tname="case 7 changes-needed with zero should-fix waits"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z changes-needed 0 2
build_pr main 96
run_review
expect_word wait
assert_no_edit
assert_no_comment
assert_no_api

# --- case 8 -----------------------------------------------------------------
tname="case 8 needs-scott blocks"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z needs-scott 0 3
add_review coderabbitai CHANGES_REQUESTED 2026-10-26T22:30:00Z
build_pr main 96
run_review
expect_word blocked
assert_edit adamsuk/software-factory factory:review factory:blocked
assert_one_comment "$(cat << 'EOF'
<!-- factory:review -->
blocked: needs-scott
Scott must act.
EOF
)" adamsuk/software-factory
assert_no_api

# --- case 9 -----------------------------------------------------------------
tname="case 9 blocked wins over review"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review factory:blocked
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
GH_API_MODE=not_found
export GH_API_MODE
build_pr main 96
run_review
expect_word blocked
assert_no_edit
assert_no_comment
assert_no_arg pr
assert_invocations 0 api

# --- case 10 ----------------------------------------------------------------
tname="case 10 not review skips"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:building
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
build_pr main 96
run_review
expect_word skip
assert_no_edit
assert_no_comment
assert_no_arg pr

# --- case 11 ----------------------------------------------------------------
tname="case 11 other author waits"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment coderabbitai 2026-10-26T21:00:00Z ready 0 0
GH_API_MODE=not_found
export GH_API_MODE
build_pr main 96
run_review
expect_word wait
assert_no_edit
assert_no_comment
assert_no_api

# --- case 12 ----------------------------------------------------------------
tname="case 12 later comment wins"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
add_comment adamsuk 2026-10-26T22:00:00Z changes-needed 2 1
GH_API_MODE=not_found
export GH_API_MODE
build_pr main 96
run_review
expect_word build
assert_edit adamsuk/software-factory factory:review factory:building
assert_no_comment
assert_no_api

# --- case 13 ----------------------------------------------------------------
tname="case 13 empty issue_repo"
reset_case
write_order adamsuk/gh-factory 96 "" factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
set_factory << 'EOF'
agents:
  review_bot: none
EOF
build_pr main 96
run_review
expect_word merge
assert_edit adamsuk/gh-factory factory:review factory:merge
assert_no_comment
assert_pr_view adamsuk/gh-factory factory/96-review-verdict
assert_api_url "$(api_url adamsuk/gh-factory main)"

# --- case 14 ----------------------------------------------------------------
tname="case 14 attempt 4"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 4
set_labels factory:review
expect_exit_2

# --- case 15 ----------------------------------------------------------------
tname="case 15 marker not on the first line"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_raw_comment adamsuk 2026-10-26T21:00:00Z $'\n<!-- factory:review -->\nverdict: ready\nshould-fix: 0\nnits: 0\n'
GH_API_MODE=not_found
export GH_API_MODE
build_pr main 96
run_review
expect_word wait
assert_no_edit
assert_no_comment
assert_no_api

# --- case 16 ----------------------------------------------------------------
tname="case 16 pr view failure"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
GH_API_MODE=not_found
export GH_API_MODE
GH_PR_STATUS=1
export GH_PR_STATUS
build_pr main 96
run_review
expect_exit_7
assert_no_edit
assert_no_comment
assert_invocations 0 api

# --- case 17 ----------------------------------------------------------------
tname="case 17 unknown review_bot waits"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
set_factory << 'EOF'
agents:
  review_bot: both
EOF
build_pr main 96
run_review
expect_word wait
assert_no_edit
assert_no_comment
assert_api_url "$(api_url adamsuk/software-factory main)"

# Spec clauses the seventeen cases do not already pin down.
tname="missing review_bot is none"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 9
set_factory << 'EOF'
agents:
  merge: false
  test_command: shellcheck scripts/*.sh
EOF
build_pr main 96
run_review
expect_word merge
assert_edit adamsuk/software-factory factory:review factory:merge
assert_no_comment

tname="null review_bot is none"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
set_factory << 'EOF'
agents:
  review_bot: null
EOF
build_pr main 96
run_review
expect_word merge
assert_edit adamsuk/software-factory factory:review factory:merge

tname="missing agents is none"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
set_factory << 'EOF'
required_checks:
  - ShellCheck
EOF
build_pr main 96
run_review
expect_word merge
assert_edit adamsuk/software-factory factory:review factory:merge

tname="invalid yaml exits 7"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
set_factory << 'EOF'
agents:
  review_bot: [coderabbit
EOF
build_pr main 96
run_review
expect_exit_7
assert_no_edit
assert_no_comment
grep -q 'could not read factory.yml' "$ROOT/err" || fail "stderr missing parser failure"

tname="api error exits 7"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
GH_API_MODE=error
export GH_API_MODE
build_pr main 96
run_review
expect_exit_7
assert_no_edit
assert_no_comment

tname="issue_repo differs from repo"
reset_case
write_order adamsuk/gh-factory 96 adamsuk/software-factory factory/96-review-verdict 2
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
set_factory << 'EOF'
agents:
  review_bot: none
EOF
build_pr main 96
run_review
expect_word merge
assert_edit adamsuk/software-factory factory:review factory:merge
assert_pr_view adamsuk/gh-factory factory/96-review-verdict
assert_api_url "$(api_url adamsuk/gh-factory main)"
if gh_has_arg "$(api_url adamsuk/software-factory main)"; then
  fail "pull request read used issue_repo"
fi

tname="base ref is encoded"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
set_factory << 'EOF'
agents:
  review_bot: none
EOF
build_pr "release/1.0" 96
run_review
expect_word merge
assert_api_url "$(api_url adamsuk/software-factory 'release%2F1.0')"

tname="later createdAt wins when it is first in the array"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T22:00:00Z changes-needed 2 0
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
GH_API_MODE=not_found
export GH_API_MODE
build_pr main 96
run_review
expect_word build
assert_edit adamsuk/software-factory factory:review factory:building
assert_no_api

tname="later submittedAt wins when it is first in the array"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
add_review coderabbitai CHANGES_REQUESTED 2026-10-26T22:30:00Z
add_review coderabbitai APPROVED 2026-10-26T22:00:00Z
use_coderabbit_yml
build_pr main 96
run_review
expect_word wait
assert_no_edit

tname="other author review does not satisfy coderabbit"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
add_review adamsuk APPROVED 2026-10-26T23:00:00Z
add_review coderabbitai CHANGES_REQUESTED 2026-10-26T22:00:00Z
use_coderabbit_yml
build_pr main 96
run_review
expect_word wait
assert_no_edit

tname="newer malformed marker does not hide an older verdict"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
add_raw_comment adamsuk 2026-10-26T22:00:00Z $'\n<!-- factory:review -->\nverdict: changes-needed\nshould-fix: 2\nnits: 0\n'
GH_API_MODE=not_found
export GH_API_MODE
build_pr main 96
run_review
expect_word merge
assert_edit adamsuk/software-factory factory:review factory:merge

tname="crlf verdict still merges"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_raw_comment adamsuk 2026-10-26T21:00:00Z $'<!-- factory:review -->\r\nverdict: ready\r\nshould-fix: 0\r\nnits: 4\r\n'
GH_API_MODE=not_found
export GH_API_MODE
build_pr main 96
run_review
expect_word merge
assert_edit adamsuk/software-factory factory:review factory:merge

tname="quoted front matter"
reset_case
order=$ROOT/order.md
issue_num=96
cat > "$order" << 'EOF'
---
repo: "adamsuk/software-factory"
issue: "96"
issue_repo: "adamsuk/software-factory"
branch: "factory/96-review-verdict"
attempt: "1"
title: "ignored"
---
attempt: 9
EOF
set_labels factory:review
add_comment adamsuk 2026-10-26T21:00:00Z ready 0 0
GH_API_MODE=not_found
export GH_API_MODE
build_pr main 96
run_review
expect_word merge
assert_edit adamsuk/software-factory factory:review factory:merge

bad_should=0
for bad_should in 01 00 -1 +1 1.0; do
  tname="bad should-fix ${bad_should}"
  reset_case
  write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
  set_labels factory:review
  add_raw_comment adamsuk 2026-10-26T21:00:00Z "$(printf '<!-- factory:review -->\nverdict: ready\nshould-fix: %s\nnits: 0' "$bad_should")"
  GH_API_MODE=not_found
  export GH_API_MODE
  build_pr main 96
  run_review
  expect_word wait
  assert_no_edit
  assert_no_api
done

tname="extra verdict line waits"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
add_raw_comment adamsuk 2026-10-26T21:00:00Z $'<!-- factory:review -->\nverdict: ready\nshould-fix: 0\nnits: 0\nextra\n'
GH_API_MODE=not_found
export GH_API_MODE
build_pr main 96
run_review
expect_word wait
assert_no_edit
assert_no_api

tname="usage"
: > "$GH_LOG"
code=0
stdout=$(bash "$script" 2> "$ROOT/err" | escape_stream) || code=$?
assert_eq "$code" "2"
assert_eq "$stdout" ""
[[ ! -s "$GH_LOG" ]] || fail "gh was called"

tname="missing work order"
: > "$GH_LOG"
code=0
stdout=$(bash "$script" "$ROOT/missing.md" 2> "$ROOT/err" | escape_stream) || code=$?
assert_eq "$code" "2"
assert_eq "$stdout" ""
[[ ! -s "$GH_LOG" ]] || fail "gh was called"

tname="bad repo"
reset_case
write_order adamsuk/software/factory 96 adamsuk/software-factory factory/96-review-verdict 1
set_labels factory:review
expect_exit_2

tname="branch with space"
reset_case
write_order adamsuk/software-factory 96 adamsuk/software-factory "factory/96 review" 1
set_labels factory:review
expect_exit_2

echo "ok"
