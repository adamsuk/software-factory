#!/usr/bin/env bash
# Behaviour tests for scripts/pr-status.sh. ShellCheck covers this file.
# A fake gh is the only gh on PATH, and HOME is private, so this suite never
# reads real credentials. The fake serves canned JSON per call and logs every
# call, so the tests can also prove the script only reads.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$here/pr-status.sh"

fail() {
  printf 'FAIL (%s): %s\n' "$tname" "$*" >&2
  for f in "$stdout_file" "$stderr_file" "$log"; do
    if [[ -n "${f:-}" && -f "$f" ]]; then
      printf '%s\n' "--- $f ---" >&2
      cat "$f" >&2 || true
    fi
  done
  exit 1
}
pass() { echo "ok: $tname"; }

tname=startup
[[ -x "$script" ]] || fail "pr-status.sh is not executable"
read -r shebang < "$script"
[[ "$shebang" == "#!/usr/bin/env bash" ]] || fail "shebang is [$shebang]"

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

# Found with the real HOME still in place, before it's replaced below: the
# fake HOME hides any PyYAML installed under the real one (user
# site-packages), so without this, fetch_required_checks always falls back
# to its minimal parser and the YAML-dict validation path it shares with
# gate-issue.sh never runs under test. PYTHONPATH carries no credentials, so
# restoring it doesn't weaken the HOME sandbox below.
PYYAML_DIR=$(python3 -c 'import yaml, os; print(os.path.dirname(os.path.dirname(yaml.__file__)))' 2>/dev/null || true)
if [[ -n "$PYYAML_DIR" ]]; then
  PYTHONPATH="$PYYAML_DIR${PYTHONPATH:+:$PYTHONPATH}"
  export PYTHONPATH
fi

# Required, not just preferred: pr-status.sh's minimal fallback parser (used
# when PyYAML isn't importable) reads an unquoted YAML scalar like `true` as
# the literal string "true", not a rejected non-string item, so the
# non-string-item test below would silently pass for the wrong reason
# without PyYAML actually backing the YAML-dict validation path.
tname=pyyaml-required
python3 -c 'import yaml' 2>/dev/null \
  || fail "PyYAML is required to run this suite (pip install -r requirements.txt)"

HOME=$(mktemp -d)
export HOME
bin=$root/bin
log=$root/gh.log
stdout_file=$root/stdout.txt
stderr_file=$root/stderr.txt
mkdir -p "$bin"

SHA=1a2b3c4d5e6f7890abcdef1234567890abcdef12

# The fake dispatches on the gh subcommand and records every call (joined by
# \x1f so a test can assert on exact arguments) to $GH_LOG. "pr checks" and
# "api graphql" fall back to an empty/default fixture when no per-call one
# was written, the same way "pr list" already did, so a test that only
# cares about one thing (e.g. the pull request list itself) doesn't have to
# wire up every downstream call too.
cat > "$bin/gh" << 'FAKE'
#!/usr/bin/env bash
set -euo pipefail
{
  printf '%s\x1f' "$@"
  printf '\n'
} >> "${GH_LOG:?}"
case "$1 $2" in
  "pr list")
    repo="" prev=""
    for arg in "$@"; do
      case "$prev" in --repo) repo=$arg ;; esac
      prev=$arg
    done
    file="${GH_DIR:?}/prs-${repo//\//_}.json"
    if [[ -f "$file" ]]; then cat "$file"; else echo "[]"; fi
    ;;
  "pr checks")
    num=$3
    repo="" prev=""
    for arg in "$@"; do
      case "$prev" in --repo) repo=$arg ;; esac
      prev=$arg
    done
    file="${GH_DIR:?}/checks-${repo//\//_}-${num}.json"
    rc_file="${GH_DIR:?}/checks-${repo//\//_}-${num}.rc"
    if [[ -f "$file" ]]; then cat "$file"; else echo "[]"; fi
    if [[ -f "$rc_file" ]]; then exit "$(cat "$rc_file")"; fi
    ;;
  "api -H")
    path=""
    for arg in "$@"; do
      case "$arg" in repos/*) path=$arg ;; esac
    done
    rest=${path#repos/}
    repopart=${rest%%/contents/*}
    refpart=${rest##*ref=}
    file="${GH_DIR:?}/factory-${repopart//\//_}-${refpart}.json"
    fail_file="${GH_DIR:?}/factory-${repopart//\//_}-${refpart}.fail"
    if [[ -f "$file" ]]; then
      cat "$file"
    elif [[ -f "$fail_file" ]]; then
      cat "$fail_file" >&2
      exit 1
    else
      echo "gh: Not Found (HTTP 404)" >&2
      exit 1
    fi
    ;;
  "api graphql")
    owner="" name="" number="" cursor=""
    for arg in "$@"; do
      case "$arg" in
        owner=*) owner=${arg#owner=} ;;
        name=*) name=${arg#name=} ;;
        number=*) number=${arg#number=} ;;
        cursor=*) cursor=${arg#cursor=} ;;
      esac
    done
    if [[ -n "$cursor" ]]; then
      file="${GH_DIR:?}/gql-${owner}_${name}-${number}-${cursor}.json"
    else
      file="${GH_DIR:?}/gql-${owner}_${name}-${number}.json"
    fi
    if [[ -f "$file" ]]; then
      cat "$file"
    elif [[ -f "${GH_DIR:?}/gql-default.json" ]]; then
      cat "${GH_DIR:?}/gql-default.json"
    else
      exit 1
    fi
    ;;
  *)
    exit 99
    ;;
esac
FAKE
chmod +x "$bin/gh"

for tool in bash mktemp rm cat grep chmod seq base64 wc; do
  ln -s "$(command -v "$tool")" "$bin/$tool"
done
# Resolve through shims (asdf, pyenv) so the symlink still runs.
ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$bin/python3"
PATH=$bin
export PATH
hash -r
export GH_LOG="$log" GH_DIR="$root"

run_script() {
  : > "$log"
  status=0
  "$script" "$@" > "$stdout_file" 2> "$stderr_file" || status=$?
}

assert_status() { [[ "$status" -eq "$1" ]] || fail "expected exit $1, got $status"; }
assert_no_output() { [[ ! -s "$stdout_file" ]] || fail "stdout is not empty"; }

prs() { printf '%s' "$1" > "$root/prs-${2//\//_}.json"; }
checks() { printf '%s' "$1" > "$root/checks-${2//\//_}-${3}.json"; }
checks_rc() { printf '%s' "$1" > "$root/checks-${2//\//_}-${3}.rc"; }
gql() { printf '%s' "$1" > "$root/gql-${2}_${3}-${4}.json"; }
gql_page() { printf '%s' "$1" > "$root/gql-${2}_${3}-${4}-${5}.json"; }
factory_yml() { printf '%s' "$1" > "$root/factory-${2//\//_}-${3}.json"; }
# A failed factory.yml read that is not a confirmed 404: $1 is the stderr
# text the fake gh emits (anything other than containing "Not Found").
factory_yml_fail() { printf '%s' "$1" > "$root/factory-${2//\//_}-${3}.fail"; }

thread() { printf '{"isResolved":%s}' "$1"; }
review() { printf '{"state":"%s","submittedAt":"%s","author":{"login":"%s"},"commit":{"oid":"%s"}}' "$2" "$3" "$1" "$4"; }

gql_body() {
  # gql_body <reviews-nodes> <threads-nodes> [reviews-hasNext 0/1] \
  #   [reviews-cursor] [threads-hasNext 0/1] [threads-cursor]
  local rhn="${3:-0}" rcur="${4:-}" thn="${5:-0}" tcur="${6:-}"
  local rhnj="false" thnj="false" rcj="null" tcj="null"
  [[ "$rhn" == 1 ]] && rhnj=true
  [[ "$thn" == 1 ]] && thnj=true
  [[ -n "$rcur" ]] && rcj="\"$rcur\""
  [[ -n "$tcur" ]] && tcj="\"$tcur\""
  printf '{"data":{"repository":{"pullRequest":{"reviews":{"pageInfo":{"hasNextPage":%s,"endCursor":%s},"nodes":[%s]},"reviewThreads":{"pageInfo":{"hasNextPage":%s,"endCursor":%s},"nodes":[%s]}}}}}' \
    "$rhnj" "$rcj" "$1" "$thnj" "$tcj" "$2"
}

reviews_page_body() {
  # reviews_page_body <nodes> <hasNext 0/1> <cursor-or-empty>
  local hnj="false" cj="null"
  [[ "$2" == 1 ]] && hnj=true
  [[ -n "$3" ]] && cj="\"$3\""
  printf '{"data":{"repository":{"pullRequest":{"reviews":{"pageInfo":{"hasNextPage":%s,"endCursor":%s},"nodes":[%s]}}}}}' "$hnj" "$cj" "$1"
}

threads_page_body() {
  # threads_page_body <nodes> <hasNext 0/1> <cursor-or-empty>
  local hnj="false" cj="null"
  [[ "$2" == 1 ]] && hnj=true
  [[ -n "$3" ]] && cj="\"$3\""
  printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":%s,"endCursor":%s},"nodes":[%s]}}}}}' "$hnj" "$cj" "$1"
}

tname="green checks and zero unresolved threads, with an approval on the head, is ready"
prs '[{"number":1,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'"}]' o/alpha
checks '[{"name":"tests","bucket":"pass"},{"name":"lint","bucket":"pass"}]' o/alpha 1
gql "$(gql_body "$(review coderabbitai APPROVED 2026-11-01T00:00:00Z "$SHA")" "")" o alpha 1
run_script o/alpha
assert_status 0
grep -Fqx "o/alpha#1 author=adamsuk head=${SHA:0:7} checks=green reviews=coderabbitai:APPROVED threads=0 verdict=ready" "$stdout_file" \
  || fail "expected a ready line, got: $(cat "$stdout_file")"
pass

tname="green checks with an unresolved thread is open-threads, even with an approval"
prs '[{"number":2,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'"}]' o/beta
checks '[{"name":"tests","bucket":"pass"}]' o/beta 2
gql "$(gql_body "$(review coderabbitai APPROVED 2026-11-01T00:00:00Z "$SHA")" "$(thread false),$(thread true)")" o beta 2
run_script o/beta
assert_status 0
grep -Fqx "o/beta#2 author=adamsuk head=${SHA:0:7} checks=green reviews=coderabbitai:APPROVED threads=1 verdict=open-threads" "$stdout_file" \
  || fail "expected an open-threads line, got: $(cat "$stdout_file")"
pass

tname="a failing check is failing-ci, naming the check (no factory.yml: every reported check is judged)"
prs '[{"number":3,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'"}]' o/gamma
checks '[{"name":"tests","bucket":"pass"},{"name":"ShellCheck","bucket":"fail"}]' o/gamma 3
checks_rc 1 o/gamma 3
gql "$(gql_body "" "")" o gamma 3
run_script o/gamma
assert_status 0
grep -Fqx "o/gamma#3 author=adamsuk head=${SHA:0:7} checks=failing(ShellCheck) reviews=- threads=0 verdict=failing-ci" "$stdout_file" \
  || fail "expected a failing-ci line, got: $(cat "$stdout_file")"
pass

tname="a pending check wins over an already-failed one"
prs '[{"number":4,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'"}]' o/delta
checks '[{"name":"tests","bucket":"fail"},{"name":"lint","bucket":"pending"}]' o/delta 4
checks_rc 8 o/delta 4
gql "$(gql_body "" "")" o delta 4
run_script o/delta
assert_status 0
grep -Fqx "o/delta#4 author=adamsuk head=${SHA:0:7} checks=pending reviews=- threads=0 verdict=pending" "$stdout_file" \
  || fail "expected a pending line, got: $(cat "$stdout_file")"
pass

tname="no checks at all is none, and reads as pending"
prs '[{"number":5,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'"}]' o/epsilon
checks '[]' o/epsilon 5
checks_rc 1 o/epsilon 5
gql "$(gql_body "" "")" o epsilon 5
run_script o/epsilon
assert_status 0
grep -Fqx "o/epsilon#5 author=adamsuk head=${SHA:0:7} checks=none reviews=- threads=0 verdict=pending" "$stdout_file" \
  || fail "expected a none/pending line, got: $(cat "$stdout_file")"
pass

tname="green checks, zero threads, but no review at all on the head is needs-review, not ready"
prs '[{"number":6,"author":{"login":"dependabot[bot]"},"headRefOid":"'"$SHA"'"}]' o/zeta
checks '[{"name":"tests","bucket":"pass"}]' o/zeta 6
gql "$(gql_body "" "")" o zeta 6
run_script o/zeta
assert_status 0
grep -Fqx "o/zeta#6 author=dependabot[bot] head=${SHA:0:7} checks=green reviews=- threads=0 verdict=needs-review" "$stdout_file" \
  || fail "expected the needs-review line, got: $(cat "$stdout_file")"
pass

tname="an older commit's approval never counts, so this reads as needs-review too"
OTHER=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
prs '[{"number":7,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'"}]' o/eta
checks '[{"name":"tests","bucket":"pass"}]' o/eta 7
gql "$(gql_body "$(review coderabbitai APPROVED 2026-11-01T00:00:00Z "$OTHER")" "")" o eta 7
run_script o/eta
assert_status 0
grep -Fqx "o/eta#7 author=adamsuk head=${SHA:0:7} checks=green reviews=- threads=0 verdict=needs-review" "$stdout_file" \
  || fail "expected the stale-approval line to show no reviews and needs-review, got: $(cat "$stdout_file")"
pass

tname="only the latest review per author on the head commit counts"
prs '[{"number":8,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'"}]' o/theta
checks '[{"name":"tests","bucket":"pass"}]' o/theta 8
gql "$(gql_body "$(review coderabbitai CHANGES_REQUESTED 2026-11-01T00:00:00Z "$SHA"),$(review coderabbitai APPROVED 2026-11-02T00:00:00Z "$SHA")" "")" o theta 8
run_script o/theta
assert_status 0
grep -Fqx "o/theta#8 author=adamsuk head=${SHA:0:7} checks=green reviews=coderabbitai:APPROVED threads=0 verdict=ready" "$stdout_file" \
  || fail "expected the latest review to win, got: $(cat "$stdout_file")"
pass

tname="a latest CHANGES_REQUESTED review on the head blocks ready, even with zero threads"
prs '[{"number":9,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'"}]' o/iota
checks '[{"name":"tests","bucket":"pass"}]' o/iota 9
gql "$(gql_body "$(review coderabbitai CHANGES_REQUESTED 2026-11-01T00:00:00Z "$SHA")" "")" o iota 9
run_script o/iota
assert_status 0
grep -Fqx "o/iota#9 author=adamsuk head=${SHA:0:7} checks=green reviews=coderabbitai:CHANGES_REQUESTED threads=0 verdict=changes-requested" "$stdout_file" \
  || fail "expected a changes-requested line, got: $(cat "$stdout_file")"
pass

tname="a failing optional check (not in factory.yml's required_checks) is ignored"
prs '[{"number":10,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'","baseRefName":"main"}]' o/kappa2
factory_yml "$(printf 'required_checks:\n  - tests\n')" o/kappa2 main
checks '[{"name":"tests","bucket":"pass"},{"name":"optional-lint","bucket":"fail"}]' o/kappa2 10
checks_rc 1 o/kappa2 10
gql "$(gql_body "$(review adamsuk APPROVED 2026-11-01T00:00:00Z "$SHA")" "")" o kappa2 10
run_script o/kappa2
assert_status 0
grep -Fqx "o/kappa2#10 author=adamsuk head=${SHA:0:7} checks=green reviews=adamsuk:APPROVED threads=0 verdict=ready" "$stdout_file" \
  || fail "expected the optional check's failure to be ignored, got: $(cat "$stdout_file")"
pass

tname="a required check (from factory.yml) that never reported is pending, not ignored"
prs '[{"number":11,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'","baseRefName":"main"}]' o/lambda2
factory_yml "$(printf 'required_checks:\n  - tests\n  - lint\n')" o/lambda2 main
checks '[{"name":"tests","bucket":"pass"}]' o/lambda2 11
gql "$(gql_body "" "")" o lambda2 11
run_script o/lambda2
assert_status 0
grep -Fqx "o/lambda2#11 author=adamsuk head=${SHA:0:7} checks=pending reviews=- threads=0 verdict=pending" "$stdout_file" \
  || fail "expected the missing required check to read as pending, got: $(cat "$stdout_file")"
pass

tname="a required_checks list with a non-string item is rejected whole, falling back to judging every check"
prs '[{"number":12,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'","baseRefName":"main"}]' o/xi
factory_yml "$(printf 'required_checks:\n  - tests\n  - true\n')" o/xi main
checks '[{"name":"tests","bucket":"pass"},{"name":"extra-check","bucket":"fail"}]' o/xi 12
checks_rc 1 o/xi 12
gql "$(gql_body "" "")" o xi 12
run_script o/xi
assert_status 0
grep -Fqx "o/xi#12 author=adamsuk head=${SHA:0:7} checks=failing(extra-check) reviews=- threads=0 verdict=failing-ci" "$stdout_file" \
  || fail "expected the invalid required_checks list to fall back to judging every check, got: $(cat "$stdout_file")"
pass

tname="a failed factory.yml read that is not a confirmed 404 is pending, not ready, even with every reported check green and an approval"
prs '[{"number":14,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'","baseRefName":"main"}]' o/pi
factory_yml_fail "gh: Bad Gateway (HTTP 502)" o/pi main
checks '[{"name":"tests","bucket":"pass"}]' o/pi 14
gql "$(gql_body "$(review adamsuk APPROVED 2026-11-01T00:00:00Z "$SHA")" "")" o pi 14
run_script o/pi
assert_status 0
grep -Fqx "o/pi#14 author=adamsuk head=${SHA:0:7} checks=pending reviews=adamsuk:APPROVED threads=0 verdict=pending" "$stdout_file" \
  || fail "expected an unknown required-check set (not a confirmed-missing file) to read as pending, got: $(cat "$stdout_file")"
pass

tname="a confirmed-missing factory.yml (404) still falls back to judging every reported check"
prs '[{"number":15,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'","baseRefName":"main"}]' o/rho
checks '[{"name":"tests","bucket":"pass"}]' o/rho 15
gql "$(gql_body "$(review adamsuk APPROVED 2026-11-01T00:00:00Z "$SHA")" "")" o rho 15
run_script o/rho
assert_status 0
grep -Fqx "o/rho#15 author=adamsuk head=${SHA:0:7} checks=green reviews=adamsuk:APPROVED threads=0 verdict=ready" "$stdout_file" \
  || fail "expected a confirmed-missing factory.yml to fall back to judging every reported check, got: $(cat "$stdout_file")"
pass

tname="a COMMENTED-only review on the head is needs-review, not ready"
prs '[{"number":13,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'"}]' o/omicron
checks '[{"name":"tests","bucket":"pass"}]' o/omicron 13
gql "$(gql_body "$(review coderabbitai COMMENTED 2026-11-01T00:00:00Z "$SHA")" "")" o omicron 13
run_script o/omicron
assert_status 0
grep -Fqx "o/omicron#13 author=adamsuk head=${SHA:0:7} checks=green reviews=coderabbitai:COMMENTED threads=0 verdict=needs-review" "$stdout_file" \
  || fail "expected a comment-only review to leave the pull request needs-review, got: $(cat "$stdout_file")"
pass

tname="reviews and reviewThreads each paginate past their first page with their own cursor"
prs '[{"number":1,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'"}]' o/mu
checks '[{"name":"tests","bucket":"pass"}]' o/mu 1
gql "$(gql_body "$(review alice APPROVED 2026-11-01T00:00:00Z "$SHA")" "$(thread true)" 1 rcur1 1 tcur1)" o mu 1
gql_page "$(reviews_page_body "$(review bob CHANGES_REQUESTED 2026-11-02T00:00:00Z "$SHA")" 0 "")" o mu 1 rcur1
gql_page "$(threads_page_body "$(thread false)" 0 "")" o mu 1 tcur1
run_script o/mu
assert_status 0
grep -Fqx "o/mu#1 author=adamsuk head=${SHA:0:7} checks=green reviews=alice:APPROVED,bob:CHANGES_REQUESTED threads=1 verdict=open-threads" "$stdout_file" \
  || fail "expected both pages merged (bob's review and the second unresolved thread), got: $(cat "$stdout_file")"
pass

tname="a repeated pagination cursor on reviews is a hard failure, not an infinite loop"
prs '[{"number":16,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'"}]' o/sigma
checks '[{"name":"tests","bucket":"pass"}]' o/sigma 16
gql "$(gql_body "$(review alice APPROVED 2026-11-01T00:00:00Z "$SHA")" "" 1 rcur1)" o sigma 16
gql_page "$(reviews_page_body "$(review bob CHANGES_REQUESTED 2026-11-02T00:00:00Z "$SHA")" 1 rcur1)" o sigma 16 rcur1
run_script o/sigma
assert_status 7
pass

tname="a full page of open pull requests (at or past the old 200-item cap) is not treated as an error"
lambda_prs="["
for n in $(seq 1 205); do
  [[ "$n" -gt 1 ]] && lambda_prs+=","
  lambda_prs+="{\"number\":$n,\"author\":{\"login\":\"adamsuk\"},\"headRefOid\":\"$SHA\"}"
done
lambda_prs+="]"
printf '%s' "$lambda_prs" > "$root/prs-o_nu.json"
printf '%s' "$(gql_body "" "")" > "$root/gql-default.json"
run_script o/nu
assert_status 0
line_count=$(wc -l < "$stdout_file")
[[ "$line_count" -eq 205 ]] || fail "expected 205 lines, got $line_count"
grep -Fqx "o/nu#1 author=adamsuk head=${SHA:0:7} checks=none reviews=- threads=0 verdict=pending" "$stdout_file" \
  || fail "expected the first pull request's line, got: $(head -n3 "$stdout_file")"
grep -Fqx "o/nu#205 author=adamsuk head=${SHA:0:7} checks=none reviews=- threads=0 verdict=pending" "$stdout_file" \
  || fail "expected the last pull request's line, got: $(tail -n3 "$stdout_file")"
pass

tname="default repos, no arguments"
: > "$log"
status=0
"$script" > "$stdout_file" 2> "$stderr_file" || status=$?
assert_status 0
for r in adamsuk/software-factory adamsuk/line adamsuk/gh-factory adamsuk/activity-feed; do
  grep -qF "$(printf 'pr\x1flist\x1f--repo\x1f%s\x1f--state\x1fopen\x1f--limit\x1f1000\x1f--json\x1fnumber,author,headRefOid,baseRefName' "$r")" "$log" \
    || fail "did not list $r by default"
done
pass

tname="a bad repo argument is a usage error"
run_script "not-a-repo"
assert_status 2
assert_no_output
[[ ! -s "$log" ]] || fail "gh was called for a bad repo argument"
pass

tname="read-only: no gh write call is ever made"
prs '[{"number":9,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'"}]' o/xi2
checks '[{"name":"tests","bucket":"pass"}]' o/xi2 9
gql "$(gql_body "" "")" o xi2 9
run_script o/xi2
assert_status 0
[[ -s "$log" ]] || fail "gh was never called"
# One of the logged calls carries the GraphQL query body, which can contain
# a real newline, so a per-newline scan is unsafe here. None of this
# script's allowed calls (pr list, pr checks, the factory.yml contents
# read, api graphql reviews/threads reads) ever carries one of these write
# verbs as a \x1f-delimited token, so their presence anywhere in the log
# means an unexpected call was made.
if grep -Eq $'(^|\x1f)(comment|edit|merge|close|label|delete|push|ready|mutation)($|\x1f)' "$log"; then
  fail "gh log has a write-shaped call: $(cat "$log")"
fi
pass

tname="a gh pr list failure is reported"
rm -f "$root/prs-o_omicron.json"
cat > "$bin/gh" << 'FAKE2'
#!/usr/bin/env bash
exit 1
FAKE2
chmod +x "$bin/gh"
run_script o/omicron
assert_status 7
assert_no_output
pass

echo "ok  pr-status tests"
