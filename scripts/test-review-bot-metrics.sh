#!/usr/bin/env bash
# Behaviour tests for scripts/review-bot-metrics.sh.
# A fake gh is the only gh on PATH. This file never calls the real gh.
set -euo pipefail

fail() {
  printf 'FAIL (%s): %s\n' "$tname" "$*" >&2
  for f in "$stdout_file" "$stderr_file" "$log"; do
    if [[ -n "$f" && -f "$f" ]]; then
      printf '%s\n' "--- $f ---" >&2
      cat "$f" >&2 || true
    fi
  done
  exit 1
}

tname=startup
stdout_file=""
stderr_file=""
log=""

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
metrics=$here/review-bot-metrics.sh
[[ -x "$metrics" ]] || fail "review-bot-metrics.sh is not executable"
read -r shebang < "$metrics"
[[ "$shebang" == "#!/usr/bin/env bash" ]] || fail "shebang is [$shebang]"

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
bin=$root/bin
log=$root/gh.log
stdout_file=$root/stdout.txt
stderr_file=$root/stderr.txt
expected_file=$root/expected.txt
mkdir -p "$bin"

# The fake serves $GH_DIR/<name>.json for the repo's -F name=<name> argument.
cat > "$bin/gh" << 'EOF2'
#!/usr/bin/env bash
set -euo pipefail
{
  printf '%s\n' "$@"
  printf '%s\n' '---'
} >> "${GH_LOG:?}"
[[ "${1:-}" == api && "${2:-}" == graphql ]] || exit 99
name=""
for arg in "$@"; do
  case "$arg" in
    name=*) name=${arg#name=} ;;
  esac
done
[[ "$name" != failing ]] || exit 1
cat "${GH_DIR:?}/${name}.json"
EOF2
chmod +x "$bin/gh"

for tool in bash mktemp rm cat grep cmp; do
  ln -s "$(command -v "$tool")" "$bin/$tool"
done
# Resolve through shims (asdf, pyenv) so the symlink still runs.
ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$bin/python3"
PATH=$bin
export PATH
hash -r
export GH_LOG="$log" GH_DIR="$root"

# thread <login> <resolved>
thread() {
  printf '{"isResolved":%s,"comments":{"nodes":[{"author":{"login":"%s"}}]}}' "$2" "$1"
}

cat > "$root/alpha.json" << EOF2
{"data":{"repository":{"pullRequests":{"nodes":[
{"number":1,"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[$(thread coderabbitai true),$(thread coderabbitai false),$(thread scott true)]}},
{"number":2,"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[$(thread coderabbitai true),{"isResolved":true,"comments":{"nodes":[{"author":null}]}}]}}
]}}}}
EOF2
cat > "$root/beta.json" << EOF2
{"data":{"repository":{"pullRequests":{"nodes":[
{"number":3,"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[$(thread coderabbitai false)]}}
]}}}}
EOF2
cat > "$root/empty.json" << 'EOF2'
{"data":{"repository":{"pullRequests":{"nodes":[]}}}}
EOF2
cat > "$root/big.json" << 'EOF2'
{"data":{"repository":{"pullRequests":{"nodes":[
{"number":4,"reviewThreads":{"pageInfo":{"hasNextPage":true},"nodes":[]}}]}}}}
EOF2
printf '%s\n' 'not json' > "$root/bad.json"

run_script() {
  : > "$log"
  status=0
  "$metrics" "$@" >"$stdout_file" 2>"$stderr_file" || status=$?
}

assert_status() {
  [[ "$status" -eq "$1" ]] || fail "expected exit $1, got ${status}"
}

assert_no_output() {
  [[ ! -s "$stdout_file" ]] || fail "stdout is not empty"
}

tname=single-repo
run_script --repo o/alpha --limit 5
assert_status 0
cat > "$expected_file" << 'EOF2'
# CodeRabbit comment acceptance
limit: last 5 closed or merged prs per repo

| repo | prs | threads | resolved | open | acceptance |
| --- | --- | --- | --- | --- | --- |
| o/alpha | 2 | 3 | 2 | 1 | 66.7% |
EOF2
cmp -s "$stdout_file" "$expected_file" || fail "single repo report mismatch"
grep -q -x 'limit=5' "$log" || fail "limit not passed"

tname=default-limit
run_script --repo o/alpha
assert_status 0
grep -q -x 'limit=20' "$log" || fail "default limit is not 20"

tname=all
export REVIEW_BOT_REPOS="o/alpha o/beta o/empty"
run_script --all
assert_status 0
cat > "$expected_file" << 'EOF2'
# CodeRabbit comment acceptance
limit: last 20 closed or merged prs per repo

| repo | prs | threads | resolved | open | acceptance |
| --- | --- | --- | --- | --- | --- |
| o/alpha | 2 | 3 | 2 | 1 | 66.7% |
| o/beta | 1 | 1 | 0 | 1 | 0.0% |
| o/empty | 0 | 0 | 0 | 0 | n/a |
| total | 3 | 4 | 2 | 2 | 50.0% |
EOF2
cmp -s "$stdout_file" "$expected_file" || fail "all report mismatch"
unset REVIEW_BOT_REPOS

tname=read-only
if grep -E -x -q 'mutation.*|edit|merge|create|comment' "$log"; then
  fail "gh log has a mutation"
fi

tname=usage
for args in "" "--limit 5" "--repo bad" "--repo o/alpha --limit 0" "--repo o/alpha --limit 101" \
  "--repo o/alpha --limit x" "--all --repo o/alpha" "--repo o/alpha --repo o/beta" "--bogus" "--repo"; do
  # shellcheck disable=SC2086
  run_script $args
  assert_status 2
  assert_no_output
  [[ ! -s "$log" ]] || fail "gh was called for args [$args]"
done

tname=gh-failure
run_script --repo o/failing
assert_status 7
assert_no_output

tname=bad-json
run_script --repo o/bad
assert_status 7
assert_no_output

tname=thread-cap
run_script --repo o/big
assert_status 7
assert_no_output

printf '%s\n' "ok  review-bot-metrics tests"
