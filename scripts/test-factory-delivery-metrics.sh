#!/usr/bin/env bash
# Behaviour tests for scripts/factory-delivery-metrics.sh.
# A fake gh is the only gh on PATH. This file never calls the real gh.
# Fixtures are files under a temp directory. This file does not read
# /workspace/factory-ledger.csv.
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
metrics=$here/factory-delivery-metrics.sh
repo_root=$(cd "$here/.." && pwd)

[[ -x "$metrics" ]] || fail "factory-delivery-metrics.sh is not executable"
[[ -x "$here/test-factory-delivery-metrics.sh" ]] || fail "test-factory-delivery-metrics.sh is not executable"
read -r shebang < "$metrics"
[[ "$shebang" == "#!/usr/bin/env bash" ]] || fail "metrics shebang is [$shebang]"
read -r shebang < "$here/test-factory-delivery-metrics.sh"
[[ "$shebang" == "#!/usr/bin/env bash" ]] || fail "test shebang is [$shebang]"
if grep -F -q '/workspace/factory-ledger.csv' "$metrics"; then
  fail "metrics script hardcodes the live ledger path"
fi

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
bin=$root/bin
log=$root/gh.log
prs_json=$root/prs.json
commits_json=$root/commits.json
checks_dir=$root/checks
stdout_file=$root/stdout.txt
stderr_file=$root/stderr.txt
expected_file=$root/expected.txt
expected_log=$root/expected-log.txt
ledger=$root/ledger.csv
mkdir -p "$bin" "$checks_dir"

cat > "$bin/gh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf '%s\n' "$@"
  printf '%s\n' '---'
} >> "${GH_LOG:?}"

for arg in "$@"; do
  case "$arg" in
    edit|create|merge|ready|close|comment|review|delete|push|rebase)
      echo "forbidden gh argument: $arg" >&2
      exit 99
      ;;
    -X|--method|-f|--raw-field|-F|--field|--input)
      echo "forbidden gh flag: $arg" >&2
      exit 99
      ;;
  esac
done

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  code=${GH_PRS_STATUS:-0}
  [[ "$code" == "0" ]] || exit "$code"
  cat "${GH_PRS_JSON:?}"
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  path=""
  for arg in "$@"; do
    if [[ "$arg" == repos/* ]]; then
      path=$arg
    fi
  done
  [[ -n "$path" ]] || { echo "api call missing path" >&2; exit 99; }
  if [[ "$path" =~ ^repos/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    code=${GH_BRANCH_STATUS:-0}
    [[ "$code" == "0" ]] || exit "$code"
    printf '%s\n' "${GH_BRANCH:?}"
    exit 0
  fi
  if [[ "$path" == *"/commits?"* ]]; then
    code=${GH_COMMITS_STATUS:-0}
    [[ "$code" == "0" ]] || exit "$code"
    # gh api --paginate --slurp returns one JSON array of pages.
    if [[ " $* " == *" --slurp "* ]]; then
      printf '['
      cat "${GH_COMMITS_JSON:?}"
      printf ']\n'
    else
      cat "${GH_COMMITS_JSON:?}"
    fi
    exit 0
  fi
  if [[ "$path" =~ /commits/([0-9a-f]{40})/check-runs ]]; then
    code=${GH_CHECKS_STATUS:-0}
    [[ "$code" == "0" ]] || exit "$code"
    sha=${BASH_REMATCH[1]}
    file="${GH_CHECKS_DIR:?}/${sha}.json"
    [[ -f "$file" ]] || { echo "missing checks for $sha" >&2; exit 99; }
    cat "$file"
    exit 0
  fi
  echo "unexpected api path: $path" >&2
  exit 99
fi

echo "unexpected gh command" >&2
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
link_tool mkdir
link_tool head

# Fake gh is the only gh. Drop every other directory so a later real gh is gone.
PATH=$bin
export PATH
hash -r

# shellcheck disable=SC2034
export GH_LOG="$log" \
  GH_PRS_JSON="$prs_json" \
  GH_COMMITS_JSON="$commits_json" \
  GH_CHECKS_DIR="$checks_dir" \
  GH_BRANCH=main \
  GH_PRS_STATUS=0 \
  GH_BRANCH_STATUS=0 \
  GH_COMMITS_STATUS=0 \
  GH_CHECKS_STATUS=0

tname=path
[[ "$(command -v gh)" == "$bin/gh" ]] || fail "gh is not the fake"
gh_count=0
while IFS= read -r _; do
  gh_count=$((gh_count + 1))
done < <(type -ap gh)
[[ "$gh_count" -eq 1 ]] || fail "expected one gh on PATH, found ${gh_count}"

default_repo=adamsuk/software-factory
default_since=2026-10-20
default_until=2026-10-27
ledger_header='date_utc,kind,repo,issue_or_pr,grok_sessions,api_equiv_usd,result'

prepare() {
  : > "$log"
  printf '%s\n' '[]' > "$prs_json"
  printf '%s\n' '[]' > "$commits_json"
  rm -rf "$checks_dir"
  mkdir -p "$checks_dir"
  rm -f "$ledger"
  GH_BRANCH=main
  GH_PRS_STATUS=0
  GH_BRANCH_STATUS=0
  GH_COMMITS_STATUS=0
  GH_CHECKS_STATUS=0
  export GH_BRANCH GH_PRS_STATUS GH_BRANCH_STATUS GH_COMMITS_STATUS GH_CHECKS_STATUS
}

run_script() {
  local arg
  for arg in "$@"; do
    [[ "$arg" != "/workspace/factory-ledger.csv" ]] || fail "refusing to pass the live ledger"
  done
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

assert_no_writes() {
  if grep -E -x -q 'edit|merge|create|ready|close|comment|review|delete|push|rebase|-X|--method|-f|--raw-field|-F|--field|--input' "$log"; then
    fail "gh log has a write"
  fi
}

base_args() {
  printf '%s\n' \
    --repo "$default_repo" \
    --since "$default_since" \
    --until "$default_until" \
    --ledger "$ledger" \
    --required-check tests
}

write_report() {
  local rate=$1
  local rework=$2
  local hours=$3
  local open_flag=$4
  local cost=$5
  local since_day=${6:-$default_since}
  local until_day=${7:-$default_until}
  {
    printf '%s\n' '# Factory delivery metrics'
    printf '%s\n' "repo: ${default_repo}"
    printf '%s\n' "since: ${since_day}"
    printf '%s\n' "until: ${until_day}"
    printf '\n'
    printf '%s\n' '| metric | value |'
    printf '%s\n' '| --- | --- |'
    printf '%s\n' "| change failure rate | ${rate} |"
    printf '%s\n' "| rework rounds per pr | ${rework} |"
    printf '%s\n' "| recovery time hours | ${hours} |"
    printf '%s\n' "| recovery open | ${open_flag} |"
    printf '%s\n' "| cost per change usd | ${cost} |"
  } > "$expected_file"
}

# One read per line, then a --- marker, matching the fake gh log.
append_call() {
  local dest=$1
  shift
  local arg
  {
    for arg in "$@"; do
      printf '%s\n' "$arg"
    done
    printf '%s\n' '---'
  } >> "$dest"
}

write_reads() {
  local dest=$1
  local since_day=$2
  local search_from=$3
  local search_to=$4
  local lookback=$5
  local until_iso=$6
  shift 6
  : > "$dest"
  append_call "$dest" \
    pr list \
    --repo "$default_repo" \
    --state merged \
    --limit 200 \
    --search "merged:${search_from}..${search_to}" \
    --json number,title,body,headRefName,mergedAt
  append_call "$dest" \
    api \
    "repos/${default_repo}" \
    --jq .default_branch
  append_call "$dest" \
    api \
    --paginate \
    --slurp \
    "repos/${default_repo}/commits?sha=main&since=${lookback}&until=${until_iso}&per_page=100"
  local sha
  for sha in "$@"; do
    append_call "$dest" \
      api \
      --paginate \
      --slurp \
      "repos/${default_repo}/commits/${sha}/check-runs?per_page=100"
  done
}

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

run_default() {
  # shellcheck disable=SC2046
  run_script $(base_args)
}

# --- usage: exit 2, no gh, no stdout ---------------------------------------

expect_usage missing-all
expect_usage missing-until --repo "$default_repo" --since "$default_since" --ledger "$ledger" --required-check tests
expect_usage missing-since --repo "$default_repo" --until "$default_until" --ledger "$ledger" --required-check tests
expect_usage missing-repo --since "$default_since" --until "$default_until" --ledger "$ledger" --required-check tests
expect_usage missing-ledger --repo "$default_repo" --since "$default_since" --until "$default_until" --required-check tests
expect_usage missing-check --repo "$default_repo" --since "$default_since" --until "$default_until" --ledger "$ledger"
expect_usage missing-value --repo "$default_repo" --since "$default_since" --until "$default_until" --ledger "$ledger" --required-check
expect_usage empty-check --repo "$default_repo" --since "$default_since" --until "$default_until" --ledger "$ledger" --required-check ""
expect_usage blank-check --repo "$default_repo" --since "$default_since" --until "$default_until" --ledger "$ledger" --required-check " "
expect_usage bad-repo --repo nope --since "$default_since" --until "$default_until" --ledger "$ledger" --required-check tests
expect_usage bad-day --repo "$default_repo" --since 2026-02-31 --until "$default_until" --ledger "$ledger" --required-check tests
expect_usage non-leap --repo "$default_repo" --since 2026-02-29 --until "$default_until" --ledger "$ledger" --required-check tests
expect_usage short-day --repo "$default_repo" --since 2026-10-2 --until "$default_until" --ledger "$ledger" --required-check tests
expect_usage equal-dates --repo "$default_repo" --since "$default_since" --until "$default_since" --ledger "$ledger" --required-check tests
expect_usage reversed-dates --repo "$default_repo" --since "$default_until" --until "$default_since" --ledger "$ledger" --required-check tests
expect_usage two-slashes --repo a/b/c --since "$default_since" --until "$default_until" --ledger "$ledger" --required-check tests
expect_usage extra-arg --repo "$default_repo" --since "$default_since" --until "$default_until" --ledger "$ledger" --required-check tests extra
expect_usage duplicate-repo \
  --repo "$default_repo" --repo "$default_repo" --since "$default_since" --until "$default_until" \
  --ledger "$ledger" --required-check tests
expect_usage duplicate-ledger \
  --repo "$default_repo" --since "$default_since" --until "$default_until" \
  --ledger "$ledger" --ledger "$ledger" --required-check tests

# --- empty lists, reordered flags, real leap day ----------------------------

tname=empty-leap
prepare
run_script \
  --required-check tests \
  --ledger "$root/no-ledger.csv" \
  --until 2024-03-01 \
  --repo "$default_repo" \
  --since 2024-02-29
assert_status 0
assert_empty "$stderr_file" stderr
write_report n/a n/a n/a no n/a 2024-02-29 2024-03-01
assert_same "$stdout_file" "$expected_file" stdout
write_reads "$expected_log" 2024-02-29 2024-02-28 2024-03-08 2024-02-22T00:00:00Z 2024-03-01T00:00:00Z
assert_same "$log" "$expected_log" "gh log"
assert_no_writes

# --- gh reads fail or hit the cap: exit 7, no stdout ------------------------

tname=pr-list-fails
prepare
GH_PRS_STATUS=1
export GH_PRS_STATUS
run_default
assert_status 7
assert_empty "$stdout_file" stdout
assert_empty "$stderr_file" stderr
: > "$expected_log"
append_call "$expected_log" \
  pr list --repo "$default_repo" --state merged --limit 200 \
  --search "merged:2026-10-19..2026-11-03" \
  --json number,title,body,headRefName,mergedAt
assert_same "$log" "$expected_log" "gh log"
assert_no_writes

tname=pr-list-at-cap
prepare
python3 - "$prs_json" << 'PY'
import json
import sys
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump([{"number": i, "mergedAt": "2026-10-21T00:00:00Z", "headRefName": "factory/1-x", "title": "", "body": ""} for i in range(200)], handle)
PY
run_default
assert_status 7
assert_empty "$stdout_file" stdout
: > "$expected_log"
append_call "$expected_log" \
  pr list --repo "$default_repo" --state merged --limit 200 \
  --search "merged:2026-10-19..2026-11-03" \
  --json number,title,body,headRefName,mergedAt
assert_same "$log" "$expected_log" "gh log"
assert_no_writes

tname=pr-list-not-json
prepare
printf '%s\n' '{' > "$prs_json"
run_default
assert_status 7
assert_empty "$stdout_file" stdout
assert_no_writes

tname=branch-fails
prepare
GH_BRANCH_STATUS=1
export GH_BRANCH_STATUS
run_default
assert_status 7
assert_empty "$stdout_file" stdout
if grep -F -q '/commits?' "$log"; then
  fail "commits were fetched after the default branch failed"
fi
assert_no_writes

tname=commits-fails
prepare
GH_COMMITS_STATUS=1
export GH_COMMITS_STATUS
run_default
assert_status 7
assert_empty "$stdout_file" stdout
if grep -F -q 'check-runs' "$log"; then
  fail "check-runs were fetched after commits failed"
fi
assert_no_writes

tname=commits-not-a-list
prepare
printf '%s\n' '{}' > "$commits_json"
run_default
assert_status 7
assert_empty "$stdout_file" stdout
if grep -F -q 'check-runs' "$log"; then
  fail "check-runs were fetched for a bad commit list"
fi
assert_no_writes

# --- change failure rate fixtures -------------------------------------------

tname=change-failure-rate
prepare
python3 - "$prs_json" << 'PY'
import json
import sys

def pr(number, head, merged, title="", body=""):
    return {
        "number": number,
        "headRefName": head,
        "mergedAt": merged,
        "title": title,
        "body": body,
    }

prs = [
    pr(9, "factory/9-early", "2026-10-19T23:00:00Z", "feat: early"),
    pr(10, "factory/10-clean", "2026-10-21T00:00:00Z", "feat: clean", "total_cost_usd: 99"),
    pr(11, "factory/11-revert-me", "2026-10-21T12:00:00Z", "feat: will revert"),
    pr(201, "docs/revert-11", "2026-10-22T12:00:00Z", "Revert", "Reverts #11"),
    pr(12, "factory/12-fix-me", "2026-10-22T00:00:00Z", "feat: will fix"),
    pr(202, "factory/99-follow", "2026-10-28T00:00:00Z", "fix: follow #12"),
    pr(13, "factory/13-late-revert", "2026-10-20T00:00:00Z", "feat: late revert"),
    pr(203, "docs/late", "2026-10-27T00:00:01Z", "Revert", "Reverts #13"),
    pr(210, "docs/decoy-130", "2026-10-21T00:00:00Z", "Revert", "Reverts #130"),
    pr(14, "factory/14-late-fix", "2026-10-20T06:00:00Z", "feat: late fix"),
    pr(204, "factory/14-follow", "2026-10-27T06:00:01Z", "fix: too late #14"),
    pr(212, "factory/hotfix-140", "2026-10-21T07:00:00Z", "fix: #140"),
    pr(15, "feature/not-factory", "2026-10-21T08:00:00Z", "feat: human"),
    pr(16, "factory/16-exact", "2026-10-20T08:00:00Z", "feat: exact"),
    pr(205, "chore/exact", "2026-10-27T08:00:00Z", "Revert", "Reverts adamsuk/software-factory#16"),
    pr(17, "factory/17-lower", "2026-10-21T01:00:00Z", "feat: lower"),
    pr(206, "chore/lower", "2026-10-21T02:00:00Z", "docs", "reverts #17"),
    pr(18, "factory/18-nonfactory-fix", "2026-10-21T03:00:00Z", "feat: outside"),
    pr(207, "bugfix/18", "2026-10-21T04:00:00Z", "fix: #18"),
    pr(19, "factory/19-hot", "2026-10-21T05:00:00Z", "feat: hot"),
    pr(208, "factory/19-hotfix", "2026-10-28T05:00:00Z", "HOTFIX for #19"),
    pr(20, "factory/20-space", "2026-10-21T06:00:00Z", "feat: space"),
    pr(209, "factory/100-space", "2026-10-28T00:00:00Z", "Fix close the gap", "See adamsuk/software-factory#20"),
    pr(21, "factory/21-at-until", "2026-10-27T00:00:00Z", "feat: boundary"),
    pr(22, "factory/22-just-in", "2026-10-26T23:59:59Z", "feat: just in"),
    pr(23, "factory/23-other", "2026-10-21T09:00:00Z", "feat: other repo"),
    pr(213, "factory/23-follow", "2026-10-28T09:00:00Z", "fix: elsewhere", "see other/repo#23"),
    pr(24, "factory/24-longer", "2026-10-21T10:00:00Z", "feat: longer number"),
    pr(214, "factory/24-follow", "2026-10-28T10:00:00Z", "fix: elsewhere", "see other/repo#240"),
]
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(prs, handle)
    handle.write("\n")
PY
run_script --repo "$default_repo" --since "$default_since" --until "$default_until" \
  --ledger "$root/no-ledger.csv" --required-check tests
assert_status 0
assert_empty "$stderr_file" stderr
write_report 6/13 n/a n/a no n/a
assert_same "$stdout_file" "$expected_file" stdout
if grep -F -q '99' "$stdout_file"; then
  fail "stdout leaked a pull request body cost"
fi
write_reads "$expected_log" "$default_since" 2026-10-19 2026-11-03 2026-10-13T00:00:00Z 2026-10-27T00:00:00Z
assert_same "$log" "$expected_log" "gh log"
assert_no_writes
for metric in "change failure rate" "rework rounds per pr" "recovery time hours" "recovery open" "cost per change usd"; do
  grep -F -q "| ${metric} |" "$stdout_file" || fail "omits ${metric}"
done

# --- rework and cost --------------------------------------------------------

tname="rework-and-cost"
prepare
python3 - "$prs_json" << 'PY'
import json
import sys

def pr(number, head):
    return {
        "number": number,
        "headRefName": head,
        "mergedAt": "2026-10-21T00:00:00Z",
        "title": "feat: change",
        "body": "total_cost_usd: 99\nno api_equiv_usd line",
    }

prs = [
    pr(30, "factory/30-cost"),
    pr(31, "factory/31-cost"),
    pr(32, "factory/32-nocost"),
]
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(prs, handle)
    handle.write("\n")
PY
cat > "$ledger" << EOF
${ledger_header}
2020-01-01T00:00:00Z,build,adamsuk/software-factory,30,1,1.00,ok
2026-10-21T00:00:00Z,fix,adamsuk/software-factory,30,1,0.50,ok
2026-10-21T00:00:00Z,fix,other/repo,31,1,9.99,ok
2026-10-21T00:00:00Z,build,adamsuk/software-factory,31,1,1.00,ok
2026-10-21T00:00:00Z,build,adamsuk/software-factory,32,1,,blank
2026-10-21T00:00:00Z,build,adamsuk/software-factory,32,1,n/a,blank
2026-10-21T00:00:00Z,build,other/repo,30,1,9.99,ignored
EOF
run_default
assert_status 0
assert_empty "$stderr_file" stderr
write_report 0/3 0.7 n/a no 1.25
assert_same "$stdout_file" "$expected_file" stdout
if grep -F -q '99' "$stdout_file"; then
  fail "cost came from a pull request body"
fi
assert_no_writes

tname="rework-zero-when-ledger-has-no-fix-rows"
prepare
python3 - "$prs_json" << 'PY'
import json
import sys
prs = [{
    "number": 40,
    "headRefName": "factory/40-clean",
    "mergedAt": "2026-10-21T00:00:00Z",
    "title": "feat: clean",
    "body": "",
}]
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(prs, handle)
PY
cat > "$ledger" << EOF
${ledger_header}
2026-10-21T00:00:00Z,Fix,adamsuk/software-factory,40,1,1.00,ok
2026-10-21T00:00:00Z,fixes,adamsuk/software-factory,40,1,1.00,ok
2026-10-21T00:00:00Z,build,adamsuk/software-factory,40,1,1.00,ok
EOF
run_default
assert_status 0
write_report 0/1 0.0 n/a no 3.00
assert_same "$stdout_file" "$expected_file" stdout

tname=same-number-counts-once
prepare
python3 - "$prs_json" << 'PY'
import json
import sys
prs = [{
    "number": 7,
    "headRefName": "factory/7-same",
    "mergedAt": "2026-10-21T00:00:00Z",
    "title": "feat: same",
    "body": "",
}]
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(prs, handle)
PY
cat > "$ledger" << EOF
${ledger_header}
2026-10-21T00:00:00Z,fix,adamsuk/software-factory,7,1,2.50,ok
EOF
run_default
assert_status 0
write_report 0/1 1.0 n/a no 2.50
assert_same "$stdout_file" "$expected_file" stdout

tname="cost-half-away"
prepare
python3 - "$prs_json" << 'PY'
import json
import sys
prs = [{
    "number": 8,
    "headRefName": "factory/8-round",
    "mergedAt": "2026-10-21T00:00:00Z",
    "title": "feat: round",
    "body": "",
}]
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(prs, handle)
PY
cat > "$ledger" << EOF
${ledger_header}
2026-10-21T00:00:00Z,build,adamsuk/software-factory,8,1,1.005,ok
EOF
run_default
assert_status 0
write_report 0/1 0.0 n/a no 1.01
assert_same "$stdout_file" "$expected_file" stdout

tname=bad-ledger-header
prepare
python3 - "$prs_json" << 'PY'
import json
import sys
prs = [{
    "number": 8,
    "headRefName": "factory/8-round",
    "mergedAt": "2026-10-21T00:00:00Z",
    "title": "feat: round",
    "body": "",
}]
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(prs, handle)
PY
printf '%s\n' 'a,b,c' > "$ledger"
run_default
assert_status 7
assert_empty "$stdout_file" stdout
assert_no_writes

# --- recovery time ----------------------------------------------------------

write_commit() {
  local sha=$1
  local when=$2
  python3 - "$commits_json" "$sha" "$when" << 'PY'
import json
import sys
path, sha, when = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
except FileNotFoundError:
    data = []
data.append({
    "sha": sha,
    "commit": {"committer": {"date": when}},
})
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
    handle.write("\n")
PY
}

write_checks() {
  local sha=$1
  shift
  python3 - "$checks_dir/$sha.json" "$@" << 'PY'
import json
import sys
path = sys.argv[1]
runs = []
ident = 1
args = sys.argv[2:]
index = 0
while index < len(args):
    name, conclusion, completed = args[index:index + 3]
    runs.append({
        "id": ident,
        "name": name,
        "conclusion": conclusion,
        "completed_at": completed,
        "status": "completed",
    })
    ident += 1
    index += 3
with open(path, "w", encoding="utf-8") as handle:
    json.dump([{"total_count": len(runs), "check_runs": runs}], handle)
PY
}

SHA_RED=1111111111111111111111111111111111111111
SHA_MID=2222222222222222222222222222222222222222
SHA_GREEN=3333333333333333333333333333333333333333
SHA_RED2=4444444444444444444444444444444444444444
SHA_OLD=5555555555555555555555555555555555555555

tname=recovery-completed
prepare
printf '%s\n' '[]' > "$commits_json"
write_commit "$SHA_RED" "2026-10-21T01:00:00Z"
write_commit "$SHA_MID" "2026-10-21T03:00:00Z"
write_commit "$SHA_GREEN" "2026-10-21T04:00:00Z"
write_checks "$SHA_RED" \
  ShellCheck failure "2026-10-21T00:30:00Z" \
  ShellCheck failure "2026-10-21T02:00:00Z" \
  ShellCheck success "2026-10-21T01:30:00Z" \
  "changelog / changelog" success "2026-10-21T02:30:00Z" \
  tests failure "2026-10-21T01:00:00Z" \
  tests success "2026-10-21T00:15:00Z" \
  lint failure "2026-10-20T00:00:00Z"
write_checks "$SHA_MID" \
  ShellCheck success "2026-10-21T02:00:00Z" \
  "changelog / changelog" cancelled "2026-10-21T02:00:00Z" \
  tests success "2026-10-21T02:00:00Z"
write_checks "$SHA_GREEN" \
  ShellCheck success "2026-10-21T05:00:00Z" \
  "changelog / changelog" success "2026-10-21T04:30:00Z" \
  tests success "2026-10-21T06:00:00Z"
run_script --repo "$default_repo" --since "$default_since" --until "$default_until" \
  --ledger "$root/no-ledger.csv" \
  --required-check ShellCheck \
  --required-check "changelog / changelog" \
  --required-check tests
assert_status 0
assert_empty "$stderr_file" stderr
write_report n/a n/a 5.0 no n/a
assert_same "$stdout_file" "$expected_file" stdout
write_reads "$expected_log" "$default_since" 2026-10-19 2026-11-03 2026-10-13T00:00:00Z 2026-10-27T00:00:00Z \
  "$SHA_RED" "$SHA_MID" "$SHA_GREEN"
assert_same "$log" "$expected_log" "gh log"
assert_no_writes

tname=recovery-ends-red
prepare
printf '%s\n' '[]' > "$commits_json"
write_commit "$SHA_RED" "2026-10-22T00:00:00Z"
write_checks "$SHA_RED" tests failure "2026-10-22T01:00:00Z"
run_default
assert_status 0
write_report n/a n/a n/a yes n/a
assert_same "$stdout_file" "$expected_file" stdout
assert_no_writes

tname=recovery-completed-and-still-open
prepare
printf '%s\n' '[]' > "$commits_json"
write_commit "$SHA_RED" "2026-10-21T00:00:00Z"
write_commit "$SHA_GREEN" "2026-10-21T01:00:00Z"
write_commit "$SHA_RED2" "2026-10-22T00:00:00Z"
write_checks "$SHA_RED" tests failure "2026-10-21T00:00:00Z"
write_checks "$SHA_GREEN" tests success "2026-10-21T02:00:00Z"
write_checks "$SHA_RED2" tests failure "2026-10-22T00:00:00Z"
run_default
assert_status 0
write_report n/a n/a 2.0 yes n/a
assert_same "$stdout_file" "$expected_file" stdout

tname=recovery-two-reds-sum
prepare
printf '%s\n' '[]' > "$commits_json"
write_commit "$SHA_RED" "2026-10-21T00:00:00Z"
write_commit "$SHA_RED2" "2026-10-21T01:00:00Z"
write_commit "$SHA_GREEN" "2026-10-21T03:00:00Z"
write_checks "$SHA_RED" tests failure "2026-10-21T00:00:00Z"
write_checks "$SHA_RED2" tests failure "2026-10-21T01:00:00Z"
write_checks "$SHA_GREEN" tests success "2026-10-21T04:00:00Z"
run_default
assert_status 0
write_report n/a n/a 7.0 no n/a
assert_same "$stdout_file" "$expected_file" stdout

tname=recovery-three-minutes-rounds-half-away
prepare
printf '%s\n' '[]' > "$commits_json"
write_commit "$SHA_RED" "2026-10-21T00:00:00Z"
write_commit "$SHA_GREEN" "2026-10-21T00:01:00Z"
write_checks "$SHA_RED" tests failure "2026-10-21T00:00:00Z"
write_checks "$SHA_GREEN" tests success "2026-10-21T00:03:00Z"
run_default
assert_status 0
write_report n/a n/a 0.1 no n/a
assert_same "$stdout_file" "$expected_file" stdout

tname=recovery-start-exactly-since
prepare
printf '%s\n' '[]' > "$commits_json"
write_commit "$SHA_RED" "2026-10-20T00:00:00Z"
write_commit "$SHA_GREEN" "2026-10-20T01:00:00Z"
write_checks "$SHA_RED" tests failure "2026-10-20T00:00:00Z"
write_checks "$SHA_GREEN" tests success "2026-10-20T02:00:00Z"
run_default
assert_status 0
write_report n/a n/a 2.0 no n/a
assert_same "$stdout_file" "$expected_file" stdout

tname=recovery-start-exactly-until-is-outside
prepare
printf '%s\n' '[]' > "$commits_json"
write_commit "$SHA_RED" "2026-10-26T23:00:00Z"
write_checks "$SHA_RED" tests failure "2026-10-27T00:00:00Z"
run_default
assert_status 0
write_report n/a n/a n/a no n/a
assert_same "$stdout_file" "$expected_file" stdout

tname=recovery-end-exactly-until-stays-open
prepare
printf '%s\n' '[]' > "$commits_json"
write_commit "$SHA_RED" "2026-10-26T20:00:00Z"
write_commit "$SHA_GREEN" "2026-10-26T21:00:00Z"
write_checks "$SHA_RED" tests failure "2026-10-26T20:00:00Z"
write_checks "$SHA_GREEN" tests success "2026-10-27T00:00:00Z"
run_default
assert_status 0
write_report n/a n/a n/a yes n/a
assert_same "$stdout_file" "$expected_file" stdout

tname=recovery-check-time-in-window-commit-before
prepare
printf '%s\n' '[]' > "$commits_json"
write_commit "$SHA_OLD" "2026-10-19T12:00:00Z"
write_commit "$SHA_GREEN" "2026-10-20T02:00:00Z"
write_checks "$SHA_OLD" tests failure "2026-10-20T01:00:00Z"
write_checks "$SHA_GREEN" tests success "2026-10-20T03:00:00Z"
run_default
assert_status 0
write_report n/a n/a 2.0 no n/a
assert_same "$stdout_file" "$expected_file" stdout

tname=recovery-open-from-before-the-window
prepare
printf '%s\n' '[]' > "$commits_json"
write_commit "$SHA_OLD" "2026-10-19T12:00:00Z"
write_checks "$SHA_OLD" tests failure "2026-10-19T18:00:00Z"
run_default
assert_status 0
write_report n/a n/a n/a yes n/a
assert_same "$stdout_file" "$expected_file" stdout

tname=checks-fail
prepare
printf '%s\n' '[]' > "$commits_json"
write_commit "$SHA_RED" "2026-10-21T00:00:00Z"
write_checks "$SHA_RED" tests failure "2026-10-21T01:00:00Z"
GH_CHECKS_STATUS=1
export GH_CHECKS_STATUS
run_default
assert_status 7
assert_empty "$stdout_file" stdout
assert_empty "$stderr_file" stderr
assert_no_writes

# --- monitor procedure ------------------------------------------------------

tname="monitor-procedure"
monitor=$repo_root/agents/roles/monitor.md
[[ -f "$monitor" ]] || fail "monitor brief is missing"
if grep -F -q 'origin/factory/84-label-metrics' "$monitor"; then
  fail "monitor brief still names origin/factory/84-label-metrics"
fi
grep -F -q 'scripts/factory-label-metrics.sh' "$monitor" || fail "monitor omits label metrics"
grep -F -q 'scripts/factory-pr-metrics.sh' "$monitor" || fail "monitor omits pull request metrics"
grep -F -q 'scripts/factory-delivery-metrics.sh' "$monitor" || fail "monitor omits delivery metrics"
grep -F -q 'FACTORY_LEDGER_FILE' "$monitor" || fail "monitor omits FACTORY_LEDGER_FILE"
# shellcheck disable=SC2016 # literal env vars in the brief, not an expansion
grep -F -q '`$FACTORY_LEDGER_FILE`, defaulting to `$FACTORY_HOME/factory-ledger.csv`, where `$FACTORY_HOME` defaults to `${XDG_DATA_HOME:-$HOME/.local/share}/software-factory`' "$monitor" || fail "monitor omits the configurable ledger default"
if grep -F -q '/workspace/factory-ledger.csv' "$monitor"; then
  fail "monitor brief hardcodes the live ledger path"
fi
grep -F -q 'ShellCheck' "$monitor" || fail "monitor omits ShellCheck"
grep -F -q 'changelog / changelog' "$monitor" || fail "monitor omits changelog / changelog"
grep -F -q -- '--required-check' "$monitor" || fail "monitor omits --required-check"
grep -F -q 'metrics/<last-day>.md' "$monitor" || fail "monitor omits the metrics file"
grep -F -q 'Harness evals' "$monitor" || fail "monitor drops harness evals from out of scope"
grep -F -q 'Do not call PostHog' "$monitor" || fail "monitor may call PostHog"
grep -F -q 'Do not merge' "$monitor" || fail "monitor may merge"
grep -F -q 'Do not file an alert' "$monitor" || fail "monitor may file an alert"

printf '%s\n' "ok  factory-delivery-metrics tests"
