#!/usr/bin/env bash
# Offline tests for scripts/sub-issues-all-closed.sh. A fake gh returns canned
# JSON per API path and logs every call; no network, no token.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$here/sub-issues-all-closed.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export MOCK_GH="$work"
mkdir -p "$work/bin"
tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
pass() { echo "ok: $tname"; }

cat > "$work/bin/gh" << 'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_GH/calls"
[[ $1 == api ]] || exit 9
shift
path="" jqf=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jq) jqf=$2; shift 2 ;;
    -*) shift ;;
    *) path=$1; shift ;;
  esac
done
f="$MOCK_GH/$(printf '%s' "$path" | tr '/' '_').json"
if [[ ! -f $f ]]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
if [[ $(cat "$f") == FAIL ]]; then echo "gh: HTTP 500" >&2; exit 1; fi
jq -r "$jqf" "$f"
FAKE
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"

reset() { rm -f "$work"/repos_*.json "$work/calls"; }
run() { status=0; out=$("$script" "$@" 2> "$work/stderr") || status=$?; }

tname="all closed -> 0"; reset
echo '[{"state":"closed"},{"state":"closed"}]' > "$work/repos_o_r_issues_5_sub_issues.json"
run o/r 5
[[ $status -eq 0 && -z $out ]] || fail "status $status out '$out'"
pass

tname="one open -> 1"; reset
echo '[{"state":"closed"},{"state":"open"}]' > "$work/repos_o_r_issues_5_sub_issues.json"
run o/r 5
[[ $status -eq 1 ]] || fail "status $status"
pass

tname="no sub-issues -> 2"; reset
echo '[]' > "$work/repos_o_r_issues_5_sub_issues.json"
run o/r 5
[[ $status -eq 2 ]] || fail "status $status"
pass

tname="not found -> 2"; reset
run o/r 5
[[ $status -eq 2 ]] || fail "status $status"
pass

tname="gh failure -> 2"; reset
echo FAIL > "$work/repos_o_r_issues_5_sub_issues.json"
run o/r 5
[[ $status -eq 2 ]] || fail "status $status"
pass

tname="unexpected state -> 2"; reset
echo '[{"state":"weird"}]' > "$work/repos_o_r_issues_5_sub_issues.json"
run o/r 5
[[ $status -eq 2 ]] || fail "status $status"
pass

tname="bad args -> 2, no gh call"; reset
run 'o/r;x' 5; [[ $status -eq 2 ]] || fail "bad repo: $status"
run o/r '5;x'; [[ $status -eq 2 ]] || fail "bad number: $status"
run o/r; [[ $status -eq 2 ]] || fail "missing arg: $status"
[[ ! -f $work/calls ]] || fail "gh was called"
pass

tname="parent-of: research-cycle parent -> 0 and number"; reset
echo '{"number":9,"labels":[{"name":"factory"},{"name":"research-cycle"}]}' > "$work/repos_o_r_issues_7_parent.json"
run --parent-of o/r 7
[[ $status -eq 0 && $out == 9 ]] || fail "status $status out '$out'"
pass

tname="parent-of: other parent -> 1"; reset
echo '{"number":9,"labels":[{"name":"factory"}]}' > "$work/repos_o_r_issues_7_parent.json"
run --parent-of o/r 7
[[ $status -eq 1 && -z $out ]] || fail "status $status out '$out'"
pass

tname="parent-of: lookalike label -> 1"; reset
echo '{"number":9,"labels":[{"name":"research-cycles"}]}' > "$work/repos_o_r_issues_7_parent.json"
run --parent-of o/r 7
[[ $status -eq 1 ]] || fail "status $status"
pass

tname="parent-of: no parent (404) -> 1"; reset
run --parent-of o/r 7
[[ $status -eq 1 ]] || fail "status $status"
pass

tname="parent-of: gh failure -> 2"; reset
echo FAIL > "$work/repos_o_r_issues_7_parent.json"
run --parent-of o/r 7
[[ $status -eq 2 ]] || fail "status $status"
pass

tname="only read-only api GETs"
grep -qv '^api ' "$work/calls" 2>/dev/null && fail "non-api call: $(cat "$work/calls")"
grep -qE -- '-X|--method|-f |-F ' "$work/calls" 2>/dev/null && fail "write flag used"
pass
echo "all sub-issues-all-closed tests passed"
