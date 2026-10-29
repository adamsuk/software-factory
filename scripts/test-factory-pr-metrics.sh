#!/usr/bin/env bash
# Behaviour tests for scripts/factory-pr-metrics.sh.
# A fake gh is the only gh on PATH. This file never calls the real gh.
set -euo pipefail

tname=startup

fail() {
  printf 'FAIL (%s): %s\n' "$tname" "$*" >&2
  if [[ -n "${stdout_file:-}" && -f "$stdout_file" ]]; then
    printf '%s\n' '--- stdout ---' >&2
    cat "$stdout_file" >&2 || true
  fi
  if [[ -n "${stderr_file:-}" && -f "$stderr_file" ]]; then
    printf '%s\n' '--- stderr ---' >&2
    cat "$stderr_file" >&2 || true
  fi
  if [[ -n "${log:-}" && -f "$log" ]]; then
    printf '%s\n' '--- gh log ---' >&2
    cat "$log" >&2 || true
  fi
  exit 1
}

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
metrics=$here/factory-pr-metrics.sh

[[ -x "$metrics" ]] || fail "factory-pr-metrics.sh is not executable"
[[ -x "$here/test-factory-pr-metrics.sh" ]] || fail "test-factory-pr-metrics.sh is not executable"
read -r shebang < "$metrics"
[[ "$shebang" == "#!/usr/bin/env bash" ]] || fail "metrics shebang is [$shebang]"
read -r shebang < "$here/test-factory-pr-metrics.sh"
[[ "$shebang" == "#!/usr/bin/env bash" ]] || fail "test shebang is [$shebang]"

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
bin=$root/bin
log=$root/gh.log
all_json=$root/all.json
open_json=$root/open.json
stdout_file=$root/stdout.txt
stderr_file=$root/stderr.txt
expected_file=$root/expected.txt
expected_log=$root/expected-log.txt
mkdir -p "$bin"

cat > "$bin/gh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf '%s\n' "$@"
  printf '%s\n' '---'
} >> "${GH_LOG:?}"

if [[ "${1:-}" != pr || "${2:-}" != list ]]; then
  exit 99
fi

state=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--state" ]]; then
    state=$arg
  fi
  prev=$arg
done

if [[ "$state" == all ]]; then
  code=${GH_ALL_STATUS:-0}
  if [[ "$code" != 0 ]]; then
    exit "$code"
  fi
  cat "${GH_ALL_JSON:?}"
  exit 0
fi

if [[ "$state" == open ]]; then
  code=${GH_OPEN_STATUS:-0}
  if [[ "$code" != 0 ]]; then
    exit "$code"
  fi
  cat "${GH_OPEN_JSON:?}"
  exit 0
fi

exit 99
EOF
chmod +x "$bin/gh"

link_tool() {
  local name=$1
  local src
  src=$(command -v "$name") || fail "required tool not found: ${name}"
  ln -s "$src" "$bin/$name"
}

link_tool bash
link_tool python3
link_tool date
link_tool mktemp
link_tool rm
link_tool cat
link_tool grep
link_tool cmp

# Fake gh is the only gh. Drop every other directory so a later real gh is gone.
PATH=$bin
export PATH
hash -r

# The fake gh reads these. They are not expanded in this file.
# shellcheck disable=SC2034
export GH_LOG="$log" \
  GH_ALL_JSON="$all_json" \
  GH_OPEN_JSON="$open_json" \
  GH_ALL_STATUS=0 \
  GH_OPEN_STATUS=0

tname=path
[[ "$(command -v gh)" == "$bin/gh" ]] || fail "gh is not the fake"
gh_count=0
while IFS= read -r _; do
  gh_count=$((gh_count + 1))
done < <(type -ap gh)
[[ "$gh_count" -eq 1 ]] || fail "expected one gh on PATH, found ${gh_count}"

prepare() {
  : > "$log"
  printf '%s\n' '[]' > "$all_json"
  printf '%s\n' '[]' > "$open_json"
  GH_ALL_STATUS=0
  GH_OPEN_STATUS=0
  export GH_ALL_STATUS GH_OPEN_STATUS
}

run_script() {
  : > "$log"
  status=0
  "$metrics" "$@" >"$stdout_file" 2>"$stderr_file" || status=$?
}

assert_status() {
  [[ "$status" -eq "$1" ]] || fail "expected exit $1, got ${status}"
}

assert_empty() {
  [[ ! -s "$1" ]] || fail "$2 is not empty"
}

assert_same() {
  if ! cmp -s "$1" "$2"; then
    printf '%s\n' '--- expected ---' >&2
    cat "$2" >&2 || true
    printf '%s\n' '--- got ---' >&2
    cat "$1" >&2 || true
    fail "$3 mismatch"
  fi
}

assert_no_mutations() {
  if grep -E -x -q 'edit|merge|create|ready' "$log"; then
    fail "gh log has a mutating subcommand"
  fi
}

write_report() {
  local dest=$1
  local repo_name=$2
  local since_day=$3
  local until_day=$4
  local cost=$5
  local ftg=$6
  local fix=$7
  local rounds=$8
  local open_n=$9
  {
    printf '%s\n' "# Factory pull request metrics"
    printf '%s\n' "repo: ${repo_name}"
    printf '%s\n' "since: ${since_day}"
    printf '%s\n' "until: ${until_day}"
    printf '\n'
    printf '%s\n' "| metric | value |"
    printf '%s\n' "| --- | --- |"
    printf '%s\n' "| grok cost usd | ${cost} |"
    printf '%s\n' "| first-time-green | ${ftg} |"
    printf '%s\n' "| fix attempts | ${fix} |"
    printf '%s\n' "| review rounds | ${rounds} |"
    printf '%s\n' "| open agent prs | ${open_n} |"
  } > "$dest"
}

write_all_call() {
  local dest=$1
  local repo_name=$2
  local since_day=$3
  {
    printf '%s\n' pr
    printf '%s\n' list
    printf '%s\n' --repo
    printf '%s\n' "$repo_name"
    printf '%s\n' --state
    printf '%s\n' all
    printf '%s\n' --limit
    printf '%s\n' 200
    printf '%s\n' --search
    printf '%s\n' "updated:>=${since_day}"
    printf '%s\n' --json
    printf '%s\n' number,body,state,headRefName,updatedAt,reviews
    printf '%s\n' ---
  } > "$dest"
}

append_open_call() {
  local dest=$1
  local repo_name=$2
  {
    printf '%s\n' pr
    printf '%s\n' list
    printf '%s\n' --repo
    printf '%s\n' "$repo_name"
    printf '%s\n' --state
    printf '%s\n' open
    printf '%s\n' --limit
    printf '%s\n' 200
    printf '%s\n' --json
    printf '%s\n' number,headRefName
    printf '%s\n' ---
  } >> "$dest"
}

write_n_items() {
  python3 - "$1" "$2" << 'PY'
import json
import sys

path, count = sys.argv[1], int(sys.argv[2])
with open(path, "w", encoding="utf-8") as handle:
    json.dump([{}] * count, handle)
    handle.write("\n")
PY
}

default_repo=adamsuk/software-factory
default_since=2026-10-20
default_until=2026-10-27

expect_usage() {
  tname=$1
  shift
  prepare
  run_script "$@"
  assert_status 2
  assert_empty "$stdout_file" stdout
  assert_empty "$stderr_file" stderr
  assert_empty "$log" "gh log"
}

# --- usage: exit 2, no gh, no stdout ---------------------------------------

expect_usage missing-all
expect_usage missing-until --repo "$default_repo" --since "$default_since"
expect_usage missing-since --repo "$default_repo" --until "$default_until"
expect_usage missing-repo --since "$default_since" --until "$default_until"
expect_usage missing-value --repo "$default_repo" --since "$default_since" --until
expect_usage case-4-bad-repo --repo nope --since "$default_since" --until "$default_until"
expect_usage bad-day --repo "$default_repo" --since 2026-02-31 --until "$default_until"
expect_usage non-leap --repo "$default_repo" --since 2026-02-29 --until "$default_until"
expect_usage short-day --repo "$default_repo" --since 2026-10-2 --until "$default_until"
expect_usage slashes --repo "$default_repo" --since 2026/10/20 --until "$default_until"
expect_usage equal-dates --repo "$default_repo" --since "$default_since" --until "$default_since"
expect_usage reversed-dates --repo "$default_repo" --since "$default_until" --until "$default_since"
expect_usage two-slashes --repo a/b/c --since "$default_since" --until "$default_until"
expect_usage extra-arg --repo "$default_repo" --since "$default_since" --until "$default_until" extra
expect_usage duplicate-repo \
  --repo "$default_repo" --since "$default_since" --until "$default_until" --repo "$default_repo"

# --- empty lists, reordered flags, real leap day ----------------------------

tname=empty-leap
prepare
run_script --until 2024-03-01 --repo "$default_repo" --since 2024-02-29
assert_status 0
assert_empty "$stderr_file" stderr
write_report "$expected_file" "$default_repo" 2024-02-29 2024-03-01 0.00 n/a 0 0 0
assert_same "$stdout_file" "$expected_file" stdout
write_all_call "$expected_log" "$default_repo" 2024-02-29
append_open_call "$expected_log" "$default_repo"
assert_same "$log" "$expected_log" "gh log"
assert_no_mutations

# --- case 1 -----------------------------------------------------------------

tname=case-1
prepare
python3 - "$all_json" "$open_json" << 'PY'
import json
import sys

all_path, open_path = sys.argv[1], sys.argv[2]
body_10 = "\n".join([
    "attempt: 1",
    "test_command: shellcheck scripts/*.sh",
    "tests: pass",
    "api_equiv_usd: 1.05",
    "num_turns: 12",
])
body_11 = "\n".join([
    "attempt: 3",
    "tests: pass",
    "api_equiv_usd: 0.10",
    "thought: BENCH_DO_NOT_COPY",
    "total_cost_usd: 99",
])
all_prs = [
    {
        "number": 10,
        "body": body_10,
        "state": "MERGED",
        "headRefName": "feature/x",
        "updatedAt": "2026-10-26T12:00:00Z",
        "reviews": [
            {"state": "APPROVED", "submittedAt": "2026-10-26T13:00:00Z"},
        ],
    },
    {
        "number": 11,
        "body": body_11,
        "state": "OPEN",
        "headRefName": "factory/11-x",
        "updatedAt": "2026-10-26T15:00:00Z",
        "reviews": [
            {"state": "CHANGES_REQUESTED", "submittedAt": "2026-10-26T16:00:00Z"},
            {"state": "PENDING", "submittedAt": "2026-10-26T16:01:00Z"},
            {"state": "APPROVED", "submittedAt": "2026-10-19T00:00:00Z"},
        ],
    },
]
open_prs = [
    {"number": 11, "headRefName": "factory/11-x"},
    {"number": 12, "headRefName": "factory/12-old"},
]
with open(all_path, "w", encoding="utf-8") as handle:
    json.dump(all_prs, handle)
    handle.write("\n")
with open(open_path, "w", encoding="utf-8") as handle:
    json.dump(open_prs, handle)
    handle.write("\n")
PY
run_script --repo "$default_repo" --since "$default_since" --until "$default_until"
assert_status 0
assert_empty "$stderr_file" stderr
write_report "$expected_file" "$default_repo" "$default_since" "$default_until" 1.15 1/2 2 2 2
assert_same "$stdout_file" "$expected_file" stdout
if grep -F -q 'BENCH_DO_NOT_COPY' "$stdout_file" || grep -F -q '99' "$stdout_file"; then
  fail "stdout leaked a pull request field"
fi
write_all_call "$expected_log" "$default_repo" "$default_since"
append_open_call "$expected_log" "$default_repo"
assert_same "$log" "$expected_log" "gh log"
assert_no_mutations

# --- case 2: cost only, empty reviews, nothing scored ----------------------

tname=case-2
prepare
python3 - "$all_json" "$open_json" << 'PY'
import json
import sys

all_path, open_path = sys.argv[1], sys.argv[2]
all_prs = [
    {
        "number": 2,
        "body": "api_equiv_usd: 2.00",
        "state": "OPEN",
        "headRefName": "feature/cost-only",
        "updatedAt": "2026-10-22T08:30:00Z",
        "reviews": [],
    },
]
with open(all_path, "w", encoding="utf-8") as handle:
    json.dump(all_prs, handle)
    handle.write("\n")
with open(open_path, "w", encoding="utf-8") as handle:
    json.dump([], handle)
    handle.write("\n")
PY
run_script --repo "$default_repo" --since "$default_since" --until "$default_until"
assert_status 0
assert_empty "$stderr_file" stderr
write_report "$expected_file" "$default_repo" "$default_since" "$default_until" 2.00 n/a 0 0 0
assert_same "$stdout_file" "$expected_file" stdout
write_all_call "$expected_log" "$default_repo" "$default_since"
append_open_call "$expected_log" "$default_repo"
assert_same "$log" "$expected_log" "gh log"
assert_no_mutations

# --- case 3: updated before the window. Open count is not taken from it. ---

tname=case-3
prepare
python3 - "$all_json" "$open_json" << 'PY'
import json
import sys

all_path, open_path = sys.argv[1], sys.argv[2]
# The in-window review is on a dropped pull request, so it does not count.
# headRefName starts with factory/ but the open list is empty.
all_prs = [
    {
        "number": 3,
        "body": "api_equiv_usd: 5.00",
        "state": "OPEN",
        "headRefName": "factory/outside",
        "updatedAt": "2026-10-19T23:00:00Z",
        "reviews": [
            {"state": "APPROVED", "submittedAt": "2026-10-26T12:00:00Z"},
        ],
    },
]
with open(all_path, "w", encoding="utf-8") as handle:
    json.dump(all_prs, handle)
    handle.write("\n")
with open(open_path, "w", encoding="utf-8") as handle:
    json.dump([], handle)
    handle.write("\n")
PY
run_script --repo "$default_repo" --since "$default_since" --until "$default_until"
assert_status 0
assert_empty "$stderr_file" stderr
write_report "$expected_file" "$default_repo" "$default_since" "$default_until" 0.00 n/a 0 0 0
assert_same "$stdout_file" "$expected_file" stdout
write_all_call "$expected_log" "$default_repo" "$default_since"
append_open_call "$expected_log" "$default_repo"
assert_same "$log" "$expected_log" "gh log"
assert_no_mutations

# --- case 5: first gh read fails. Do not ask for open pull requests. -------

tname=case-5
prepare
GH_ALL_STATUS=1
export GH_ALL_STATUS
printf '%s\n' '[{"headRefName":"factory/should-not-be-read"}]' > "$open_json"
run_script --repo "$default_repo" --since "$default_since" --until "$default_until"
assert_status 7
assert_empty "$stdout_file" stdout
assert_empty "$stderr_file" stderr
write_all_call "$expected_log" "$default_repo" "$default_since"
assert_same "$log" "$expected_log" "gh log"
assert_no_mutations

# --- case 6: first list is at the cap. Do not ask for open pull requests. --

tname=case-6
prepare
write_n_items "$all_json" 200
printf '%s\n' '[{"headRefName":"factory/should-not-be-read"}]' > "$open_json"
run_script --repo "$default_repo" --since "$default_since" --until "$default_until"
assert_status 7
assert_empty "$stdout_file" stdout
assert_empty "$stderr_file" stderr
write_all_call "$expected_log" "$default_repo" "$default_since"
assert_same "$log" "$expected_log" "gh log"
assert_no_mutations

# --- second read fails or is capped: exit 7 and print nothing --------------

tname=open-fails
prepare
python3 - "$all_json" << 'PY'
import json
import sys

all_prs = [
    {
        "number": 4,
        "body": "api_equiv_usd: 1.00",
        "updatedAt": "2026-10-21T00:00:00Z",
        "reviews": [],
    },
]
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(all_prs, handle)
    handle.write("\n")
PY
GH_OPEN_STATUS=1
export GH_OPEN_STATUS
run_script --repo "$default_repo" --since "$default_since" --until "$default_until"
assert_status 7
assert_empty "$stdout_file" stdout
assert_empty "$stderr_file" stderr
write_all_call "$expected_log" "$default_repo" "$default_since"
append_open_call "$expected_log" "$default_repo"
assert_same "$log" "$expected_log" "gh log"

tname=open-cap
prepare
python3 - "$all_json" << 'PY'
import json
import sys

all_prs = [
    {
        "number": 4,
        "body": "api_equiv_usd: 1.00",
        "updatedAt": "2026-10-21T00:00:00Z",
        "reviews": [],
    },
]
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(all_prs, handle)
    handle.write("\n")
PY
write_n_items "$open_json" 200
run_script --repo "$default_repo" --since "$default_since" --until "$default_until"
assert_status 7
assert_empty "$stdout_file" stdout
assert_empty "$stderr_file" stderr
write_all_call "$expected_log" "$default_repo" "$default_since"
append_open_call "$expected_log" "$default_repo"
assert_same "$log" "$expected_log" "gh log"

# --- unusable JSON ----------------------------------------------------------

tname=bad-json-all
prepare
printf '%s\n' 'not-json' > "$all_json"
printf '%s\n' '[{"headRefName":"factory/nope"}]' > "$open_json"
run_script --repo "$default_repo" --since "$default_since" --until "$default_until"
assert_status 7
assert_empty "$stdout_file" stdout
assert_empty "$stderr_file" stderr
write_all_call "$expected_log" "$default_repo" "$default_since"
assert_same "$log" "$expected_log" "gh log"

tname=bad-json-open
prepare
printf '%s\n' '[]' > "$all_json"
printf '%s\n' 'not-json' > "$open_json"
run_script --repo "$default_repo" --since "$default_since" --until "$default_until"
assert_status 7
assert_empty "$stdout_file" stdout
assert_empty "$stderr_file" stderr
write_all_call "$expected_log" "$default_repo" "$default_since"
append_open_call "$expected_log" "$default_repo"
assert_same "$log" "$expected_log" "gh log"

tname=json-object
prepare
printf '%s\n' '{"number":1}' > "$all_json"
run_script --repo "$default_repo" --since "$default_since" --until "$default_until"
assert_status 7
assert_empty "$stdout_file" stdout
write_all_call "$expected_log" "$default_repo" "$default_since"
assert_same "$log" "$expected_log" "gh log"

# --- boundaries, cents, first match, review states, open prefix ------------

tname=edges
prepare
python3 - "$all_json" "$open_json" << 'PY'
import json
import sys

all_path, open_path = sys.argv[1], sys.argv[2]
body_a = "\r\n".join([
    "total_cost_usd: 99",
    "api_equiv_usd: 1.234",
    "api_equiv_usd: 0.5",
    "api_equiv_usd: 8",
    "attempt: 2",
    "attempt: 1",
    "tests: pass",
]) + "\r\n"
all_prs = [
    {
        "number": 20,
        "body": body_a,
        "state": "MERGED",
        "headRefName": "feature/a",
        "updatedAt": "2026-10-20T00:00:00Z",
        "reviews": [
            {"state": "COMMENTED", "submittedAt": "2026-10-20T00:00:00Z"},
            {"state": "DISMISSED", "submittedAt": "2026-10-21T00:00:00Z"},
            {"state": "APPROVED", "submittedAt": "2026-10-27T00:00:00Z"},
            {"state": "APPROVED", "submittedAt": None},
            {"state": "APPROVED"},
            {"state": "APPROVED", "submittedAt": "nope"},
            {"state": "PENDING", "submittedAt": "2026-10-21T00:00:00Z"},
            {"state": "CHANGES_REQUESTED", "submittedAt": "2026-10-26T23:59:59.999Z"},
            {"state": "approved", "submittedAt": "2026-10-21T00:00:00Z"},
            {"state": "COMMENTED", "submittedAt": "2026-10-19T23:00:00Z"},
        ],
    },
    {
        "number": 21,
        "body": "api_equiv_usd: 9.00\nattempt: 1\ntests: pass\n",
        "updatedAt": "2026-10-27T00:00:00Z",
        "reviews": [
            {"state": "APPROVED", "submittedAt": "2026-10-26T12:00:00Z"},
        ],
    },
    {
        "number": 22,
        "body": "api_equiv_usd: 4.00",
        "updatedAt": "2026-10-19T23:59:59Z",
        "reviews": [],
    },
    {
        "number": 23,
        "body": "api_equiv_usd: 3.00",
        "updatedAt": None,
        "reviews": [],
    },
    {
        "number": 24,
        "body": "api_equiv_usd: 6",
        "updatedAt": "not-a-date",
        "reviews": [],
    },
    {
        "number": 25,
        "body": None,
        "updatedAt": "2026-10-26T12:00:00+00:00",
        "reviews": None,
    },
    {
        "number": 26,
        "body": "attempt: 1\ntests: pass\napi_equiv_usd: 1\n",
        "updatedAt": "2026-10-21T15:00:00.500Z",
        "reviews": [
            {"state": "APPROVED", "submittedAt": "2026-10-19T23:00:00-01:00"},
        ],
    },
    {
        "number": 27,
        "body": "api_equiv_usd: 7.00",
        "reviews": [],
    },
    {
        "number": 28,
        "body": "tests: pass\napi_equiv_usd: 0.01\n",
        "updatedAt": "2026-10-25T00:00:00Z",
        "reviews": [],
    },
    {
        "number": 29,
        "body": "",
        "updatedAt": "2026-10-25T01:00:00Z",
        "reviews": "nope",
    },
    {
        "number": 30,
        "body": "attempt: 1\ntests: pass \n",
        "updatedAt": "2026-10-25T02:00:00Z",
        "reviews": [],
    },
    {
        "number": 31,
        "body": "attempt: 10\nattempt: 4\nattempt: 1 \ntests: pass\napi_equiv_usd: 0.00\n",
        "updatedAt": "2026-10-25T03:00:00Z",
        "reviews": [],
    },
    None,
    42,
]
open_prs = [
    {"number": 1, "headRefName": "factory/a"},
    {"number": 2, "headRefName": "factory/"},
    {"number": 3, "headRefName": "factory"},
    {"number": 4, "headRefName": "Factory/x"},
    {"number": 5, "headRefName": "prefatory/factory/x"},
    {"number": 6, "headRefName": "notfactory/x"},
    {"number": 7, "headRefName": "factory-branch"},
    {"number": 8, "headRefName": ""},
    {"number": 9, "headRefName": None},
    {"number": 10},
    {"number": 11, "headRefName": 12},
    {"number": 12, "headRefName": "factory/nested/branch"},
    None,
]
with open(all_path, "w", encoding="utf-8") as handle:
    json.dump(all_prs, handle)
    handle.write("\n")
with open(open_path, "w", encoding="utf-8") as handle:
    json.dump(open_prs, handle)
    handle.write("\n")
PY
run_script --repo "$default_repo" --since "$default_since" --until "$default_until"
assert_status 0
assert_empty "$stderr_file" stderr
# 0.50 + 1.00 + 0.01 = 1.51. Scored: attempt 2, attempt 1 with pass, attempt 1
# whose tests line has a trailing space. One of those three is first-time-green.
# Fix attempts: (2-1) + (1-1) + (1-1) = 1. Review rounds: two on the first kept
# pull request plus the offset timestamp that lands on since midnight.
write_report "$expected_file" "$default_repo" "$default_since" "$default_until" 1.51 1/3 1 3 3
assert_same "$stdout_file" "$expected_file" stdout
if grep -F -q '99' "$stdout_file"; then
  fail "stdout leaked total_cost_usd"
fi
write_all_call "$expected_log" "$default_repo" "$default_since"
append_open_call "$expected_log" "$default_repo"
assert_same "$log" "$expected_log" "gh log"
assert_no_mutations

# 199 items is under the cap and still produces a report.
tname=under-cap
prepare
write_n_items "$all_json" 199
printf '%s\n' '[]' > "$open_json"
run_script --repo "$default_repo" --since "$default_since" --until "$default_until"
assert_status 0
write_report "$expected_file" "$default_repo" "$default_since" "$default_until" 0.00 n/a 0 0 0
assert_same "$stdout_file" "$expected_file" stdout
write_all_call "$expected_log" "$default_repo" "$default_since"
append_open_call "$expected_log" "$default_repo"
assert_same "$log" "$expected_log" "gh log"

# The reporter prints non-empty captured output and does not die on its own
# printf. Drive fail() directly in a subshell with known captured content.
tname=reporter-survives-output
reporter_out=$root/reporter.out
reporter_err=$root/reporter.err
printf '%s\n' 'captured-stdout-line' > "$root/rep-stdout.txt"
printf '%s\n' 'captured-stderr-line' > "$root/rep-stderr.txt"
printf '%s\n' 'captured-log-line' > "$root/rep-log.txt"
set +e
(
  stdout_file=$root/rep-stdout.txt
  stderr_file=$root/rep-stderr.txt
  log=$root/rep-log.txt
  fail "deliberate reporter check"
) > "$reporter_out" 2> "$reporter_err"
reporter_status=$?
set -e
[[ "$reporter_status" -eq 1 ]] || fail "reporter exited $reporter_status, expected 1"
for line in captured-stdout-line captured-stderr-line captured-log-line '--- stdout ---' '--- stderr ---' '--- gh log ---'; do
  grep -F -q -- "$line" "$reporter_err" || fail "reporter output is missing [$line]"
done
if grep -E -q 'invalid option|usage: printf' "$reporter_err"; then
  fail "reporter printed a printf usage error"
fi

printf '%s\n' "ok  factory-pr-metrics tests"
