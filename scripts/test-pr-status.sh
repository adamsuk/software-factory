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
HOME=$(mktemp -d)
export HOME
bin=$root/bin
log=$root/gh.log
stdout_file=$root/stdout.txt
stderr_file=$root/stderr.txt
mkdir -p "$bin"

SHA=1a2b3c4d5e6f7890abcdef1234567890abcdef12

# The fake dispatches on the gh subcommand and records every call (joined by
# \x1f so a test can assert on exact arguments) to $GH_LOG.
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
    cat "$file"
    if [[ -f "$rc_file" ]]; then exit "$(cat "$rc_file")"; fi
    ;;
  "api graphql")
    repo="" owner="" name="" number=""
    for arg in "$@"; do
      case "$arg" in
        owner=*) owner=${arg#owner=} ;;
        name=*) name=${arg#name=} ;;
        number=*) number=${arg#number=} ;;
      esac
    done
    file="${GH_DIR:?}/gql-${owner}_${name}-${number}.json"
    if [[ -f "$file" ]]; then cat "$file"; else exit 1; fi
    ;;
  *)
    exit 99
    ;;
esac
FAKE
chmod +x "$bin/gh"

for tool in bash mktemp rm cat grep chmod; do
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

thread() { printf '{"isResolved":%s}' "$1"; }
review() { printf '{"state":"%s","submittedAt":"%s","author":{"login":"%s"},"commit":{"oid":"%s"}}' "$2" "$3" "$1" "$4"; }

gql_body() {
  # gql_body <reviews-json-array-no-brackets-or-empty> <threads-json-array-no-brackets-or-empty>
  printf '{"data":{"repository":{"pullRequest":{"reviews":{"pageInfo":{"hasNextPage":false},"nodes":[%s]},"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[%s]}}}}}' "$1" "$2"
}

tname="green checks and zero unresolved threads is ready"
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

tname="a failing check is failing-ci, naming the check"
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

tname="a Dependabot-authored pull request is listed with its author"
prs '[{"number":6,"author":{"login":"dependabot[bot]"},"headRefOid":"'"$SHA"'"}]' o/zeta
checks '[{"name":"tests","bucket":"pass"}]' o/zeta 6
gql "$(gql_body "" "")" o zeta 6
run_script o/zeta
assert_status 0
grep -Fqx "o/zeta#6 author=dependabot[bot] head=${SHA:0:7} checks=green reviews=- threads=0 verdict=ready" "$stdout_file" \
  || fail "expected the Dependabot line, got: $(cat "$stdout_file")"
pass

tname="an older commit's approval never counts"
OTHER=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
prs '[{"number":7,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'"}]' o/eta
checks '[{"name":"tests","bucket":"pass"}]' o/eta 7
gql "$(gql_body "$(review coderabbitai APPROVED 2026-11-01T00:00:00Z "$OTHER")" "")" o eta 7
run_script o/eta
assert_status 0
grep -Fqx "o/eta#7 author=adamsuk head=${SHA:0:7} checks=green reviews=- threads=0 verdict=ready" "$stdout_file" \
  || fail "expected the stale-approval line to show no reviews, got: $(cat "$stdout_file")"
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

tname="default repos, no arguments"
: > "$log"
status=0
"$script" > "$stdout_file" 2> "$stderr_file" || status=$?
assert_status 0
for r in adamsuk/software-factory adamsuk/line adamsuk/gh-factory adamsuk/activity-feed; do
  grep -qF "$(printf 'pr\x1flist\x1f--repo\x1f%s\x1f--state\x1fopen\x1f--limit\x1f200\x1f--json\x1fnumber,author,headRefOid' "$r")" "$log" \
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
prs '[{"number":9,"author":{"login":"adamsuk"},"headRefOid":"'"$SHA"'"}]' o/iota
checks '[{"name":"tests","bucket":"pass"}]' o/iota 9
gql "$(gql_body "" "")" o iota 9
run_script o/iota
assert_status 0
[[ -s "$log" ]] || fail "gh was never called"
# One of the logged calls carries the GraphQL query body, which can contain
# a real newline, so a per-newline scan is unsafe here. None of this
# script's allowed calls (pr list, pr checks, api graphql reviews/threads
# reads) ever carries one of these write verbs as a \x1f-delimited token,
# so their presence anywhere in the log means an unexpected call was made.
if grep -Eq $'(^|\x1f)(comment|edit|merge|close|label|delete|push|ready|mutation)($|\x1f)' "$log"; then
  fail "gh log has a write-shaped call: $(cat "$log")"
fi
pass

tname="a gh pr list failure is reported"
rm -f "$root/prs-o_kappa.json"
cat > "$bin/gh" << 'FAKE2'
#!/usr/bin/env bash
exit 1
FAKE2
chmod +x "$bin/gh"
run_script o/kappa
assert_status 7
assert_no_output
pass

echo "ok  pr-status tests"
