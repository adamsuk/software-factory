#!/usr/bin/env bash
# Red-check record for scripts/gate-issue.sh (#24). A fake gh is first on PATH.
# This file never calls the real gh.
#
# On retry, and on blocked for repeat or cap, the script writes
# <work-order>.red-record with one line per current red required check, in
# the same order as the red: list: "<name> <new|seen-before> Scott". A name
# is seen-before only when that exact name is an item on the red: line of
# any earlier <!-- factory:gate --> comment, split on ", ". The sentinel
# "red: -" is not a check name. Stdout stays the one outcome word, and the
# posted comment stays the body gate-issue.sh already posts. review,
# pending, skip, and blocked for no-required-checks do not write a record.
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
  if [[ -n "${order:-}" && -f "${order}.red-record" ]]; then
    echo "--- red record ---" >&2
    cat "${order}.red-record" >&2
  fi
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
  cat "${GH_FACTORY_FILE:?}"
  exit 0
fi

if [[ "$cmd" == "issue" && "$sub" == "edit" ]]; then
  printf '%s\n' "https://github.com/example/issues/1"
  exit 0
fi

if [[ "$cmd" == "issue" && "$sub" == "comment" ]]; then
  printf '%s\n' "https://github.com/example/issues/1#issuecomment-1"
  exit 0
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

assert_invocations() {
  local want=$1
  shift
  local n
  n=$(gh_count "$@")
  assert_eq "$n" "$want"
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

escape_stream() {
  python3 -c 'import sys; data = sys.stdin.read(); sys.stdout.write(data.replace("\\", "\\\\").replace("\n", "\\n"))'
}

record_of() {
  printf '%s.red-record\n' "$order"
}

assert_no_temps() {
  local record dir base f
  record=$(record_of)
  dir=$(dirname "$record")
  base=$(basename "$record")
  for f in "$dir"/"$base".*; do
    if [[ -e "$f" ]]; then
      fail "temp red record left behind: $f"
    fi
  done
}

assert_record() {
  local record
  record=$(record_of)
  [[ -f "$record" ]] || fail "missing red record"
  printf '%s\n' "$@" > "$ROOT/expect-record"
  if ! cmp -s "$ROOT/expect-record" "$record"; then
    echo "--- record ---" >&2
    cat "$record" >&2
    echo "--- expected ---" >&2
    cat "$ROOT/expect-record" >&2
    fail "red record mismatch"
  fi
  assert_no_temps
}

assert_no_record() {
  [[ ! -e "$(record_of)" ]] || fail "record file should not exist"
  assert_no_temps
}

run_gate() {
  : > "$GH_LOG"
  cp "$order" "$order.before"
  code=0
  stdout=$(bash "$script" "$order" 2> "$ROOT/err" | escape_stream) || code=$?
  cmp -s "$order.before" "$order" || fail "work order changed"
}

expect_word() {
  assert_eq "$code" "0"
  assert_eq "$stdout" "$1\\n"
  [[ ! -s "$ROOT/err" ]] || fail "stderr on success"
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

# Pairs of createdAt, body. Array order is not time order.
set_comments_at() {
  GH_COMMENTS_JSON=$(python3 - "$@" << 'PY'
import json, sys
args = sys.argv[1:]
if len(args) % 2 != 0:
    sys.stderr.write("bad comments\n")
    sys.exit(1)
comments = []
for i in range(0, len(args), 2):
    comments.append({"createdAt": args[i], "body": args[i + 1]})
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
Do not run this body.
EOF
  rm -f "${order}.red-record" "${order}.red-record."*
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
  # shellcheck disable=SC2090
  export GH_LABELS GH_COMMENTS_JSON GH_CHECKS_JSON GH_CHECKS_STATUS GH_PR_JSON
  set_factory << 'EOF'
required_checks:
  - ShellCheck
EOF
}

pass() { echo "ok: $tname"; }

# --- retry: new name, non-marker ignored, previous file replaced -----------
tname="retry writes a new record and today's comment"
reset_case
write_order adamsuk/software-factory 24 adamsuk/software-factory factory/24-red-check-record 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - Analyze (javascript-typescript)
EOF
set_checks '[{"name":"Analyze (javascript-typescript)","bucket":"fail"}]'
set_comments $'not a marker\nred: Analyze (javascript-typescript)'
printf '%s\n' "STALE" "old name seen-before Ada" > "${order}.red-record"
run_gate
expect_word retry
assert_no_edit
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: Analyze (javascript-typescript)
EOF
)"
assert_record "Analyze (javascript-typescript) new Scott"
pass

# --- older marker, not the latest; attempt 2 stays retry -------------------
tname="older red name is seen-before and attempt 2 still retries"
reset_case
write_order adamsuk/software-factory 24 adamsuk/software-factory factory/24-red-check-record 2
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - NewOne
  - Gamma
  - Alpha
EOF
set_checks '[{"name":"NewOne","bucket":"fail"},{"name":"Gamma","bucket":"fail"},{"name":"Alpha","bucket":"fail"},{"name":"Beta","bucket":"fail"}]'
set_comments \
  $'<!-- factory:gate -->\nred: Alpha, OldCheck' \
  $'not a marker\nred: Gamma' \
  $'<!-- factory:gate -->\nred: Beta'
run_gate
expect_word retry
assert_no_edit
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: Alpha, Gamma, NewOne
EOF
)"
assert_record \
  "Alpha seen-before Scott" \
  "Gamma new Scott" \
  "NewOne new Scott"
pass

# --- split on ", " ; latest list differs, so retry -------------------------
tname="comma-space split marks both names seen-before"
reset_case
write_order adamsuk/software-factory 24 adamsuk/software-factory factory/24-red-check-record 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - "C D"
  - "A,B"
EOF
set_checks '[{"name":"C D","bucket":"fail"},{"name":"A,B","bucket":"fail"}]'
set_comments \
  $'<!-- factory:gate -->\nred: A,B, C D' \
  $'<!-- factory:gate -->\nred: Other'
run_gate
expect_word retry
assert_no_edit
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: A,B, C D
EOF
)"
assert_record \
  "A,B seen-before Scott" \
  "C D seen-before Scott"
pass

# --- exact name, not a prefix ------------------------------------------------
tname="Shell is seen-before and ShellCheck is new"
reset_case
write_order adamsuk/software-factory 24 adamsuk/software-factory factory/24-red-check-record 2
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - ShellCheck
  - Shell
EOF
set_checks '[{"name":"ShellCheck","bucket":"fail"},{"name":"Shell","bucket":"fail"}]'
set_comments $'<!-- factory:gate -->\nred: Shell'
run_gate
expect_word retry
assert_no_edit
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: Shell, ShellCheck
EOF
)"
assert_record \
  "Shell seen-before Scott" \
  "ShellCheck new Scott"
pass

# --- repeat: newest comment by time, not array order ------------------------
tname="repeat blocks and records seen-before"
reset_case
write_order adamsuk/software-factory 24 adamsuk/software-factory factory/24-red-check-record 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - Beta
  - Alpha
EOF
set_checks '[{"name":"Alpha","bucket":"fail"},{"name":"Beta","bucket":"fail"},{"name":"Gamma","bucket":"fail"}]'
set_comments_at \
  "2026-10-27T00:00:00Z" $'<!-- factory:gate -->\nred: Alpha, Beta' \
  "2026-10-26T00:00:00Z" $'<!-- factory:gate -->\nred: Gamma'
run_gate
expect_word blocked
assert_edit adamsuk/software-factory factory:gate factory:blocked
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
blocked: repeat
red: Alpha, Beta
Scott must act.
EOF
)"
assert_record \
  "Alpha seen-before Scott" \
  "Beta seen-before Scott"
pass

# --- cap still caps when the list is new or seen-before ---------------------
tname="cap blocks with new and seen-before"
reset_case
write_order adamsuk/software-factory 24 adamsuk/software-factory factory/24-red-check-record 3
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - Gamma
  - Alpha
  - Beta
EOF
set_checks '[{"name":"Gamma","bucket":"fail"},{"name":"Alpha","bucket":"fail"},{"name":"Beta","bucket":"fail"}]'
set_comments \
  $'<!-- factory:gate -->\nred: Beta' \
  $'<!-- factory:gate -->\nred: Alpha'
run_gate
expect_word blocked
assert_edit adamsuk/software-factory factory:gate factory:blocked
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
blocked: cap
red: Alpha, Beta, Gamma
Scott must act.
EOF
)"
assert_record \
  "Alpha seen-before Scott" \
  "Beta seen-before Scott" \
  "Gamma new Scott"
pass

# --- sentinel on the latest marker is not a name; older name still counts ---
tname="sentinel is not a name and attempt 1 still retries"
reset_case
write_order adamsuk/software-factory 24 adamsuk/software-factory factory/24-red-check-record 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - Gamma
  - Beta
EOF
set_checks '[{"name":"Gamma","bucket":"fail"},{"name":"Beta","bucket":"fail"}]'
set_comments \
  $'<!-- factory:gate -->\nred: Beta' \
  $'<!-- factory:gate -->\nblocked: no-required-checks\nred: -\nScott must act.'
run_gate
expect_word retry
assert_no_edit
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
red: Beta, Gamma
EOF
)"
assert_record \
  "Beta seen-before Scott" \
  "Gamma new Scott"
pass

# A required check named "-" repeats when the latest red: line is the
# sentinel, because repeat compares that whole line. The sentinel is not a
# seen name, so the record flags it new.
tname="check named dash repeats and is recorded new"
reset_case
write_order adamsuk/software-factory 24 adamsuk/software-factory factory/24-red-check-record 1
set_labels factory:gate
set_factory << 'EOF'
required_checks:
  - "-"
EOF
set_checks '[{"name":"-","bucket":"fail"}]'
set_comments $'<!-- factory:gate -->\nblocked: no-required-checks\nred: -\nScott must act.'
run_gate
expect_word blocked
assert_edit adamsuk/software-factory factory:gate factory:blocked
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
blocked: repeat
red: -
Scott must act.
EOF
)"
assert_record "- new Scott"
pass

# --- outcomes that must not write a record ----------------------------------
tname="review does not write a record"
reset_case
write_order adamsuk/software-factory 24 adamsuk/software-factory factory/24-red-check-record 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"pass"}]'
run_gate
expect_word review
assert_edit adamsuk/software-factory factory:gate factory:review
assert_no_comment
assert_no_record
pass

tname="review leaves an existing record untouched"
reset_case
write_order adamsuk/software-factory 24 adamsuk/software-factory factory/24-red-check-record 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"pass"}]'
printf '%s\n' "STALE" > "${order}.red-record"
cp "${order}.red-record" "$ROOT/held-record"
run_gate
expect_word review
assert_no_comment
cmp -s "$ROOT/held-record" "${order}.red-record" || fail "review wrote the red record"
pass

tname="pending does not write a record"
reset_case
write_order adamsuk/software-factory 24 adamsuk/software-factory factory/24-red-check-record 1
set_labels factory:gate
set_checks '[{"name":"ShellCheck","bucket":"pending"}]' 8
run_gate
expect_word pending
assert_no_edit
assert_no_comment
assert_no_record
pass

tname="skip does not write a record"
reset_case
write_order adamsuk/software-factory 24 adamsuk/software-factory factory/24-red-check-record 1
set_labels factory:building
set_checks '[{"name":"ShellCheck","bucket":"fail"}]'
run_gate
expect_word skip
assert_no_edit
assert_no_comment
assert_no_record
pass

tname="no-required-checks does not write a record"
reset_case
write_order adamsuk/software-factory 24 adamsuk/software-factory factory/24-red-check-record 1
set_labels factory:gate
set_factory << 'EOF'
required_checks: []
EOF
set_checks '[{"name":"ShellCheck","bucket":"fail"}]'
run_gate
expect_word blocked
assert_edit adamsuk/software-factory factory:gate factory:blocked
assert_one_comment "$(cat << 'EOF'
<!-- factory:gate -->
blocked: no-required-checks
red: -
Scott must act.
EOF
)"
assert_no_record
assert_invocations 0 pr checks
pass

tname="already blocked does not write a record"
reset_case
write_order adamsuk/software-factory 24 adamsuk/software-factory factory/24-red-check-record 1
set_labels factory:gate factory:blocked
set_checks '[{"name":"ShellCheck","bucket":"fail"}]'
run_gate
expect_word blocked
assert_no_edit
assert_no_comment
assert_no_record
pass

echo "ok: red-check record"
