#!/usr/bin/env bash
# Behaviour tests for scripts/factory-label-metrics.sh.
# A fake gh is the only gh on PATH. The real gh is never called.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script=$here/factory-label-metrics.sh

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

FAKE_BIN=$ROOT/bin
EVENTS=$ROOT/events
GH_LOG=$ROOT/gh.log
mkdir -p "$FAKE_BIN" "$EVENTS"
: > "$GH_LOG"
: > "$ROOT/out.txt"
: > "$ROOT/err.txt"
export GH_LOG GH_EVENTS_DIR="$EVENTS"

tname=setup
fail() {
  echo "FAIL ($tname): $*" >&2
  if [[ -s "$ROOT/err.txt" ]]; then
    echo "--- stderr ---" >&2
    cat "$ROOT/err.txt" >&2
  fi
  if [[ -s "$ROOT/out.txt" ]]; then
    echo "--- stdout ---" >&2
    cat "$ROOT/out.txt" >&2
  fi
  if [[ -s "$GH_LOG" ]]; then
    echo "--- gh log ---" >&2
    cat "$GH_LOG" >&2
  fi
  exit 1
}

cat > "$FAKE_BIN/gh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${GH_LOG:-}" ]]; then
  echo "GH_LOG is unset" >&2
  exit 99
fi
printf '%s\n' "$*" >> "$GH_LOG"

for arg in "$@"; do
  case "$arg" in
    edit|create|merge|ready)
      echo "forbidden gh argument: $arg" >&2
      exit 99
      ;;
  esac
done

if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  if [[ -n "${GH_LIST_EXIT:-}" && "$GH_LIST_EXIT" != "0" ]]; then
    exit "$GH_LIST_EXIT"
  fi
  if [[ -n "${GH_LIST_FILE:-}" ]]; then
    cat "$GH_LIST_FILE"
    exit 0
  fi
  printf '%s\n' "${GH_LIST_JSON:-[]}"
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  if [[ -n "${GH_API_EXIT:-}" && "$GH_API_EXIT" != "0" ]]; then
    exit "$GH_API_EXIT"
  fi
  path=
  for arg in "$@"; do
    if [[ "$arg" =~ ^repos/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/issues/[0-9]+/events$ ]]; then
      path=$arg
    fi
  done
  if [[ -z "$path" ]]; then
    echo "api call missing events path" >&2
    exit 99
  fi
  num=${path##*/issues/}
  num=${num%/events}
  file="${GH_EVENTS_DIR:?}/$num.json"
  if [[ ! -f "$file" ]]; then
    echo "missing events file for $num" >&2
    exit 99
  fi
  cat "$file"
  exit 0
fi

echo "unexpected gh command" >&2
exit 99
EOF
chmod +x "$FAKE_BIN/gh"

# GitHub-hosted Ubuntu installs the real gh with apt, at /usr/bin/gh, and /bin
# is that same directory. $FAKE_BIN:/usr/bin:/bin would still contain it.
# Link the tools this test and the metrics script call, and leave gh out.
TOOL_BIN=$ROOT/tools
mkdir -p "$TOOL_BIN"
orig_path=$PATH
for tool in bash cat cmp date diff grep head jq mkdir mktemp rm sort; do
  src=$(PATH="$orig_path" command -v "$tool") || fail "$tool is not on PATH"
  [[ -x "$src" ]] || fail "$tool is not executable: $src"
  ln -s "$src" "$TOOL_BIN/$tool"
done
unset tool src orig_path
PATH="$FAKE_BIN:$TOOL_BIN"
export PATH

command -v jq > /dev/null || fail "jq is not on PATH"
found_gh=$(command -v gh)
[[ "$found_gh" == "$FAKE_BIN/gh" ]] || fail "gh resolved to $found_gh"
gh_count=0
IFS=: read -r -a path_dirs <<< "$PATH"
for dir in "${path_dirs[@]}"; do
  if [[ -n "$dir" && -x "$dir/gh" ]]; then
    gh_count=$((gh_count + 1))
    [[ "$dir/gh" == "$FAKE_BIN/gh" ]] || fail "another gh on PATH: $dir/gh"
  fi
done
[[ "$gh_count" -eq 1 ]] || fail "expected one gh on PATH, found $gh_count"

[[ -x "$script" ]] || fail "metrics script is not executable"
shebang=$(head -n 1 "$script")
[[ "$shebang" == '#!/usr/bin/env bash' ]] || fail "bad shebang: $shebang"

STATIONS=(
  factory:triage
  factory:ready
  factory:building
  factory:gate
  factory:review
  factory:merge
  factory:release
  factory:done
  factory:blocked
)
declare -a exp_in exp_out exp_med

reset_expected() {
  local i
  for i in "${!STATIONS[@]}"; do
    exp_in[i]=0
    exp_out[i]=0
    exp_med[i]=n/a
  done
}

set_cell() {
  local name=$1 inn=$2 out=$3 med=$4
  local i
  for i in "${!STATIONS[@]}"; do
    if [[ "${STATIONS[i]}" == "$name" ]]; then
      exp_in[i]=$inn
      exp_out[i]=$out
      exp_med[i]=$med
      return 0
    fi
  done
  fail "unknown station $name"
}

write_doc() {
  local dest=$1 repo=$2 since=$3 until=$4
  local i
  {
    printf '# Factory label metrics\n'
    printf 'repo: %s\n' "$repo"
    printf 'since: %s\n' "$since"
    printf 'until: %s\n' "$until"
    printf '\n'
    printf '| station | in | out | median lead time hours |\n'
    printf '| --- | --- | --- | --- |\n'
    for i in "${!STATIONS[@]}"; do
      printf '| %s | %s | %s | %s |\n' \
        "${STATIONS[i]}" "${exp_in[i]}" "${exp_out[i]}" "${exp_med[i]}"
    done
  } > "$dest"
}

begin() {
  tname=$1
  unset GH_LIST_EXIT GH_LIST_FILE GH_LIST_JSON GH_API_EXIT
  rm -rf "$EVENTS"
  mkdir -p "$EVENTS"
  : > "$GH_LOG"
  : > "$ROOT/out.txt"
  : > "$ROOT/err.txt"
  reset_expected
}

run() {
  set +e
  "$script" "$@" > "$ROOT/out.txt" 2> "$ROOT/err.txt"
  status=$?
  set -e
}

default_run() {
  run --repo acme/software-factory --since 2026-10-20 --until 2026-10-27
}

put_events() {
  local num=$1
  cat > "$EVENTS/$num.json"
}

list_json() {
  GH_LIST_JSON=$1
  export GH_LIST_JSON
}

assert_status() {
  [[ "$status" -eq "$1" ]] || fail "exit $status, want $1"
}

assert_empty_stdout() {
  [[ ! -s "$ROOT/out.txt" ]] || fail "expected empty stdout"
}

assert_empty_stderr() {
  [[ ! -s "$ROOT/err.txt" ]] || fail "expected empty stderr"
}

assert_no_gh() {
  [[ ! -s "$GH_LOG" ]] || fail "gh was called"
}

assert_stdout() {
  if ! cmp -s "$1" "$ROOT/out.txt"; then
    diff -u "$1" "$ROOT/out.txt" >&2 || true
    fail "stdout mismatch"
  fi
}

assert_clean_log() {
  local word
  for word in edit create merge ready; do
    if grep -F -q -w -- "$word" "$GH_LOG"; then
      fail "gh log contains $word"
    fi
  done
}

assert_row() {
  grep -F -q -- "$1" "$ROOT/out.txt" || fail "missing row [$1]"
}

finish_ok() {
  write_doc "$ROOT/expected.md" acme/software-factory 2026-10-20 2026-10-27
  assert_status 0
  assert_empty_stderr
  assert_stdout "$ROOT/expected.md"
  assert_clean_log
}

# The literal document locks spacing. The helper must reproduce it.
tname=doc-shape
reset_expected
cat > "$ROOT/zero.md" << 'EOF'
# Factory label metrics
repo: acme/software-factory
since: 2026-10-20
until: 2026-10-27

| station | in | out | median lead time hours |
| --- | --- | --- | --- |
| factory:triage | 0 | 0 | n/a |
| factory:ready | 0 | 0 | n/a |
| factory:building | 0 | 0 | n/a |
| factory:gate | 0 | 0 | n/a |
| factory:review | 0 | 0 | n/a |
| factory:merge | 0 | 0 | n/a |
| factory:release | 0 | 0 | n/a |
| factory:done | 0 | 0 | n/a |
| factory:blocked | 0 | 0 | n/a |
EOF
write_doc "$ROOT/generated-zero.md" acme/software-factory 2026-10-20 2026-10-27
if ! cmp -s "$ROOT/zero.md" "$ROOT/generated-zero.md"; then
  diff -u "$ROOT/zero.md" "$ROOT/generated-zero.md" >&2 || true
  fail "expected-document helper drifted"
fi

# --- case 1: two issues, non-factory label, event exactly at --until ---------
begin case1
list_json '[{"number":8},{"number":7}]'
put_events 7 << 'EOF'
[
  {
    "event": "labeled",
    "created_at": "2026-10-21T09:00:00Z",
    "label": {"name": "enhancement", "color": "aaaaaa"}
  },
  {
    "event": "labeled",
    "created_at": "2026-10-21T10:00:00Z",
    "label": {"name": "factory:building"}
  },
  {
    "event": "unlabeled",
    "created_at": "2026-10-21T12:00:00Z",
    "label": {"name": "factory:building"}
  }
]
EOF
put_events 8 << 'EOF'
[
  {
    "event": "labeled",
    "created_at": "2026-10-22T10:00:00Z",
    "label": {"name": "factory:building"}
  },
  {
    "event": "unlabeled",
    "created_at": "2026-10-22T14:00:00Z",
    "label": {"name": "factory:building"}
  },
  {
    "event": "labeled",
    "created_at": "2026-10-27T00:00:00Z",
    "label": {"name": "factory:done"}
  }
]
EOF
set_cell factory:building 2 2 3.0
default_run
finish_ok
assert_row '| factory:building | 2 | 2 | 3.0 |'
assert_row '| factory:done | 0 | 0 | n/a |'
mapfile -t log_lines < "$GH_LOG"
[[ "${#log_lines[@]}" -eq 3 ]] || fail "expected 3 gh calls, got ${#log_lines[@]}"
[[ "${log_lines[0]}" == "issue list --repo acme/software-factory --state all --limit 200 --search updated:>=2026-10-20 --json number" ]] \
  || fail "list invocation: ${log_lines[0]}"
[[ "${log_lines[0]}" == *"--state all"* ]] || fail "log missing --state all"
[[ "${log_lines[1]}" == "api --paginate repos/acme/software-factory/issues/7/events" ]] \
  || fail "issue 7 should be fetched before issue 8: ${log_lines[1]}"
[[ "${log_lines[2]}" == "api --paginate repos/acme/software-factory/issues/8/events" ]] \
  || fail "issue 8 events path: ${log_lines[2]}"
if grep -F -q -- 'edit' "$GH_LOG"; then
  fail "log contains edit"
fi

# --- case 2: add before --since, removal inside the window -------------------
begin case2
list_json '[{"number":7}]'
put_events 7 << 'EOF'
[
  {
    "event": "labeled",
    "created_at": "2026-10-19T00:00:00Z",
    "label": {"name": "factory:ready"}
  },
  {
    "event": "unlabeled",
    "created_at": "2026-10-21T00:00:00Z",
    "label": {"name": "factory:ready"}
  }
]
EOF
set_cell factory:ready 0 1 48.0
default_run
finish_ok
assert_row '| factory:ready | 0 | 1 | 48.0 |'

# --- case 3: bad repo, no gh, empty stdout -----------------------------------
begin case3-bad-repo
run --repo nope --since 2026-10-20 --until 2026-10-27
assert_status 2
assert_empty_stdout
assert_empty_stderr
assert_no_gh

# --- case 4: issue list fails -------------------------------------------------
begin case4-list-fails
GH_LIST_EXIT=1
export GH_LIST_EXIT
default_run
assert_status 7
assert_empty_stdout
assert_empty_stderr

# --- case 5: 200 issue objects, no events API --------------------------------
begin case5-full-page
{
  printf '['
  i=1
  while (( i <= 200 )); do
    if (( i > 1 )); then
      printf ','
    fi
    printf '{"number":%s}' "$i"
    i=$((i + 1))
  done
  printf ']\n'
} > "$ROOT/list200.json"
listed=$(jq 'length' "$ROOT/list200.json")
[[ "$listed" == "200" ]] || fail "fixture length $listed"
GH_LIST_FILE=$ROOT/list200.json
export GH_LIST_FILE
default_run
assert_status 7
assert_empty_stdout
assert_empty_stderr
if grep -F -q -- 'repos/' "$GH_LOG"; then
  fail "events API was called for a full page"
fi
mapfile -t log_lines < "$GH_LOG"
[[ "${#log_lines[@]}" -eq 1 ]] || fail "expected only the list call"

# --- half-up: one pair of 1.25 hours prints 1.3, not 1.2 ---------------------
begin half-up-1.25
list_json '[{"number":4}]'
# 10:00Z to 11:15Z is 4500 seconds, which is 1.25 hours.
put_events 4 << 'EOF'
[
  {
    "event": "labeled",
    "created_at": "2026-10-21T10:00:00Z",
    "label": {"name": "factory:blocked"}
  },
  {
    "event": "unlabeled",
    "created_at": "2026-10-21T11:15:00Z",
    "label": {"name": "factory:blocked"}
  }
]
EOF
set_cell factory:blocked 1 1 1.3
default_run
finish_ok
assert_row '| factory:blocked | 1 | 1 | 1.3 |'
if grep -F -q -- '1.2' "$ROOT/out.txt"; then
  fail "1.25 hours rounded to 1.2"
fi
if grep -F -q -- '1.25' "$ROOT/out.txt"; then
  fail "1.25 hours was not rounded"
fi

# --- even count: mean of 1.0h and 1.5h is 1.25h, which rounds to 1.3 ---------
begin half-up-even-mean
list_json '[{"number":4}]'
put_events 4 << 'EOF'
[
  {
    "event": "labeled",
    "created_at": "2026-10-21T10:00:00Z",
    "label": {"name": "factory:release"}
  },
  {
    "event": "unlabeled",
    "created_at": "2026-10-21T11:00:00Z",
    "label": {"name": "factory:release"}
  },
  {
    "event": "labeled",
    "created_at": "2026-10-21T12:00:00Z",
    "label": {"name": "factory:release"}
  },
  {
    "event": "unlabeled",
    "created_at": "2026-10-21T13:30:00Z",
    "label": {"name": "factory:release"}
  }
]
EOF
set_cell factory:release 2 2 1.3
default_run
finish_ok

# --- odd count of three: median is the middle value, not the mean -----------
begin odd-median
list_json '[{"number":4}]'
put_events 4 << 'EOF'
[
  {
    "event": "labeled",
    "created_at": "2026-10-21T08:00:00Z",
    "label": {"name": "factory:gate"}
  },
  {
    "event": "unlabeled",
    "created_at": "2026-10-21T09:00:00Z",
    "label": {"name": "factory:gate"}
  },
  {
    "event": "labeled",
    "created_at": "2026-10-21T10:00:00Z",
    "label": {"name": "factory:gate"}
  },
  {
    "event": "unlabeled",
    "created_at": "2026-10-21T12:00:00Z",
    "label": {"name": "factory:gate"}
  },
  {
    "event": "labeled",
    "created_at": "2026-10-21T13:00:00Z",
    "label": {"name": "factory:gate"}
  },
  {
    "event": "unlabeled",
    "created_at": "2026-10-21T22:00:00Z",
    "label": {"name": "factory:gate"}
  }
]
EOF
set_cell factory:gate 3 3 2.0
default_run
finish_ok

# --- latest labeled at or before the removal, not an earlier add -------------
begin latest-add
list_json '[{"number":4}]'
put_events 4 << 'EOF'
[
  {
    "event": "labeled",
    "created_at": "2026-10-21T08:00:00Z",
    "label": {"name": "factory:gate"}
  },
  {
    "event": "unlabeled",
    "created_at": "2026-10-21T09:00:00Z",
    "label": {"name": "factory:gate"}
  },
  {
    "event": "labeled",
    "created_at": "2026-10-21T10:00:00Z",
    "label": {"name": "factory:gate"}
  },
  {
    "event": "unlabeled",
    "created_at": "2026-10-21T13:00:00Z",
    "label": {"name": "factory:gate"}
  }
]
EOF
set_cell factory:gate 2 2 2.0
default_run
finish_ok

# --- events are not assumed to be in chronological order ---------------------
begin reversed-events
list_json '[{"number":4}]'
put_events 4 << 'EOF'
[
  {
    "event": "unlabeled",
    "created_at": "2026-10-21T12:00:00Z",
    "label": {"name": "factory:building"}
  },
  {
    "event": "labeled",
    "created_at": "2026-10-21T10:00:00Z",
    "label": {"name": "factory:building"}
  }
]
EOF
set_cell factory:building 1 1 2.0
default_run
finish_ok

# --- numeric order, and a removal does not pair with another issue's add -----
begin numeric-order-no-cross-issue
list_json '[{"number":10},{"number":9}]'
put_events 9 << 'EOF'
[
  {
    "event": "labeled",
    "created_at": "2026-10-21T10:00:00Z",
    "label": {"name": "factory:merge"}
  }
]
EOF
put_events 10 << 'EOF'
[
  {
    "event": "unlabeled",
    "created_at": "2026-10-21T12:00:00Z",
    "label": {"name": "factory:merge"}
  }
]
EOF
set_cell factory:merge 1 1 n/a
default_run
finish_ok
mapfile -t log_lines < "$GH_LOG"
[[ "${log_lines[1]}" == *"/issues/9/events" ]] || fail "issue 9 should be fetched first"
[[ "${log_lines[2]}" == *"/issues/10/events" ]] || fail "issue 10 should be fetched second"

# --- a later add does not pair; a lone removal still counts as out -----------
begin skip-unpaired
list_json '[{"number":4}]'
put_events 4 << 'EOF'
[
  {
    "event": "unlabeled",
    "created_at": "2026-10-21T04:00:00Z",
    "label": {"name": "factory:review"}
  },
  {
    "event": "unlabeled",
    "created_at": "2026-10-21T10:00:00Z",
    "label": {"name": "factory:blocked"}
  },
  {
    "event": "labeled",
    "created_at": "2026-10-21T12:00:00Z",
    "label": {"name": "factory:blocked"}
  }
]
EOF
set_cell factory:review 0 1 n/a
set_cell factory:blocked 1 1 n/a
default_run
finish_ok

# --- --since is inclusive and --until is exclusive ---------------------------
begin window-bounds
list_json '[{"number":4}]'
put_events 4 << 'EOF'
[
  {
    "event": "labeled",
    "created_at": "2026-10-20T00:00:00Z",
    "label": {"name": "factory:triage"}
  },
  {
    "event": "unlabeled",
    "created_at": "2026-10-20T02:00:00Z",
    "label": {"name": "factory:triage"}
  },
  {
    "event": "unlabeled",
    "created_at": "2026-10-27T00:00:00Z",
    "label": {"name": "factory:triage"}
  }
]
EOF
set_cell factory:triage 1 1 2.0
default_run
finish_ok

# --- empty issue list is success and does not call the events API ------------
begin empty-list
list_json '[]'
default_run
assert_status 0
assert_empty_stderr
assert_stdout "$ROOT/zero.md"
assert_clean_log
mapfile -t log_lines < "$GH_LOG"
[[ "${#log_lines[@]}" -eq 1 ]] || fail "empty list should call gh once"
if grep -F -q -- 'repos/' "$GH_LOG"; then
  fail "events API was called for an empty list"
fi

# --- events API failure ------------------------------------------------------
begin api-fails
list_json '[{"number":4}]'
put_events 4 << 'EOF'
[{"event":"labeled","created_at":"2026-10-21T10:00:00Z","label":{"name":"factory:gate"}}]
EOF
GH_API_EXIT=1
export GH_API_EXIT
default_run
assert_status 7
assert_empty_stdout
assert_empty_stderr

# --- usage ---------------------------------------------------------------------
expect_usage() {
  begin "$1"
  shift
  run "$@"
  assert_status 2
  assert_empty_stdout
  assert_empty_stderr
  assert_no_gh
}

expect_usage usage-no-args
expect_usage usage-missing-until --repo acme/software-factory --since 2026-10-20
expect_usage usage-bad-date --repo acme/software-factory --since 2026-02-31 --until 2026-10-27
expect_usage usage-date-format --repo acme/software-factory --since 2026-10-2 --until 2026-10-27
expect_usage usage-since-equal --repo acme/software-factory --since 2026-10-20 --until 2026-10-20
expect_usage usage-since-after --repo acme/software-factory --since 2026-10-27 --until 2026-10-20
expect_usage usage-two-slashes --repo a/b/c --since 2026-10-20 --until 2026-10-27
expect_usage usage-duplicate-repo \
  --repo acme/software-factory --repo acme/software-factory \
  --since 2026-10-20 --until 2026-10-27
expect_usage usage-extra \
  --repo acme/software-factory --since 2026-10-20 --until 2026-10-27 extra
