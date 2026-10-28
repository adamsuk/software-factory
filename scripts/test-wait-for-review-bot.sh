#!/usr/bin/env bash
# Behaviour tests for scripts/wait-for-review-bot.sh. ShellCheck covers this
# file. A fake gh serves canned JSON per endpoint and logs every call, so the
# tests can prove the script only reads except for the one nudge.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$here/wait-for-review-bot.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

BIN=$work/bin
mkdir -p "$BIN" "$work/repo/.github" "$work/repo/scripts"
export MOCK="$work"

tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
pass() { echo "ok: $tname"; }

SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
OTHER=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

cat > "$BIN/gh" << 'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK/calls"
case "$*" in
  *"pulls/"*"/reviews"*) cat "$MOCK/reviews.json" ;;
  *"pulls/"*"/comments"*) cat "$MOCK/comments.json" ;;
  *"pr view"*"headRefOid"*) cat "$MOCK/head.txt" ;;
  *"pr view"*comments*) cat "$MOCK/prcomments.json" ;;
  *"pr checks"*)
    cat "$MOCK/checks.json"
    if [[ -f "$MOCK/checks_rc" ]]; then exit "$(cat "$MOCK/checks_rc")"; fi ;;
  *"commits/"*) cat "$MOCK/resolved.txt" ;;
  *"pr comment"*) echo "posted" ;;
  *) echo "[]" ;;
esac
FAKE
chmod +x "$BIN/gh"

# A repo root the script can find factory.yml in.
printf 'agents:\n  review_bot: coderabbit\n' > "$work/repo/.github/factory.yml"
cp "$script" "$work/repo/scripts/wait-for-review-bot.sh"
RUN="$work/repo/scripts/wait-for-review-bot.sh"

reset() {
  : > "$MOCK/calls"
  echo "[]" > "$MOCK/reviews.json"
  echo "[]" > "$MOCK/comments.json"
  echo '{"comments":[]}' > "$MOCK/prcomments.json"
  echo "[]" > "$MOCK/checks.json"
  printf '%s\n' "$SHA" > "$MOCK/head.txt"
  printf '%s\n' "$SHA" > "$MOCK/resolved.txt"
  rm -f "$MOCK/checks_rc"
}

run() {
  PATH="$BIN:$PATH" bash "$RUN" --repo o/r --pr 1 --interval 1 "$@" 2>&1
}
code() {
  PATH="$BIN:$PATH" bash "$RUN" --repo o/r --pr 1 --interval 1 "$@" > /dev/null 2>&1 \
    && echo 0 || echo $?
}

tname="review_bot none exits 0 without polling"
reset
printf 'agents:\n  review_bot: none\n' > "$work/repo/.github/factory.yml"
out=$(run --sha "$SHA" --timeout 5)
[[ "$out" == *"nothing to wait for"* ]] || fail "expected the none message, got [$out]"
[[ ! -s "$MOCK/calls" ]] || fail "it polled despite review_bot none"
pass
printf 'agents:\n  review_bot: coderabbit\n' > "$work/repo/.github/factory.yml"

tname="a review record for the sha is enough"
reset
printf '[{"user":{"login":"coderabbitai[bot]"},"commit_id":"%s"}]\n' "$SHA" > "$MOCK/reviews.json"
out=$(run --sha "$SHA" --timeout 5 --no-nudge)
[[ "$out" == *"has reviewed"* ]] || fail "expected success, got [$out]"
pass

tname="a review comment for the sha is enough"
reset
printf '[{"user":{"login":"coderabbitai[bot]"},"commit_id":"%s"}]\n' "$SHA" > "$MOCK/comments.json"
[[ "$(code --sha "$SHA" --timeout 5 --no-nudge)" == "0" ]] || fail "comments alone should suffice"
pass

tname="another bot's review does not count"
reset
printf '[{"user":{"login":"someone-else"},"commit_id":"%s"}]\n' "$SHA" > "$MOCK/reviews.json"
[[ "$(code --sha "$SHA" --timeout 2 --no-nudge)" == "1" ]] || fail "should still be waiting"
pass

tname="a review of another sha does not count"
reset
printf '[{"user":{"login":"coderabbitai[bot]"},"commit_id":"%s"}]\n' "$OTHER" > "$MOCK/reviews.json"
[[ "$(code --sha "$SHA" --timeout 2 --no-nudge)" == "1" ]] || fail "wrong sha should not satisfy it"
pass

tname="a terminal check counts only for the PR's own head"
reset
printf '[{"name":"CodeRabbit","bucket":"pass"}]\n' > "$MOCK/checks.json"
[[ "$(code --sha "$SHA" --timeout 5 --no-nudge)" == "0" ]] || fail "head + terminal check should pass"
pass

tname="a terminal check is ignored for a different sha"
reset
printf '[{"name":"CodeRabbit","bucket":"pass"}]\n' > "$MOCK/checks.json"
printf '%s\n' "$OTHER" > "$MOCK/head.txt"
out=$(run --sha "$SHA" --timeout 2 --no-nudge || true)
[[ "$out" == *"say nothing about"* ]] || fail "expected the stale-check explanation, got [$out]"
pass

tname="a pending check keeps it waiting"
reset
printf '[{"name":"CodeRabbit","bucket":"pending"}]\n' > "$MOCK/checks.json"
[[ "$(code --sha "$SHA" --timeout 2 --no-nudge)" == "1" ]] || fail "pending should not end the wait"
pass

tname="the nudge is posted once, after the threshold"
reset
printf '[{"name":"CodeRabbit","bucket":"pending"}]\n' > "$MOCK/checks.json"
run --sha "$SHA" --timeout 4 --nudge-after 1 > /dev/null || true
n=$(grep -c "^pr comment" "$MOCK/calls" || true)
[[ "$n" == "1" ]] || fail "expected exactly one nudge, got $n"
pass

tname="an existing nudge for the head is not repeated"
reset
printf '[{"name":"CodeRabbit","bucket":"pending"}]\n' > "$MOCK/checks.json"
printf '{"comments":[{"body":"<!-- factory:review-bot-nudge sha=%s -->"}]}\n' "$SHA" > "$MOCK/prcomments.json"
run --sha "$SHA" --timeout 4 --nudge-after 1 > /dev/null || true
n=$(grep -c "^pr comment" "$MOCK/calls" || true)
[[ "$n" == "0" ]] || fail "expected no new nudge, got $n"
pass

tname="--no-nudge never comments"
reset
printf '[{"name":"CodeRabbit","bucket":"pending"}]\n' > "$MOCK/checks.json"
run --sha "$SHA" --timeout 3 --nudge-after 1 --no-nudge > /dev/null || true
grep -q "^pr comment" "$MOCK/calls" && fail "it commented despite --no-nudge"
pass

tname="it never merges or labels"
reset
printf '[{"name":"CodeRabbit","bucket":"pending"}]\n' > "$MOCK/checks.json"
run --sha "$SHA" --timeout 3 --nudge-after 1 > /dev/null || true
grep -qE "^pr merge|^issue edit|^pr edit" "$MOCK/calls" && fail "it tried to merge or label"
pass

tname="a zero interval is refused"
reset
[[ "$(code --sha "$SHA" --interval 0 --timeout 5)" == "2" ]] || fail "expected exit 2"
pass

tname="a missing factory.yml with no --bot is refused"
reset
mv "$work/repo/.github/factory.yml" "$work/factory.yml.bak"
out=$(run --sha "$SHA" --timeout 5 || true)
[[ "$out" == *"pass --bot explicitly"* ]] || fail "expected a usage error, got [$out]"
mv "$work/factory.yml.bak" "$work/repo/.github/factory.yml"
pass

tname="--bot overrides factory.yml"
reset
printf '[{"user":{"login":"someone-else"},"commit_id":"%s"}]\n' "$SHA" > "$MOCK/reviews.json"
[[ "$(code --sha "$SHA" --bot someone-else --timeout 5 --no-nudge)" == "0" ]] || fail "--bot should match that login"
pass

# --- CodeRabbit's findings on #150 -----------------------------------------

# gh api --paginate prints one array per page, so an unslurped jq filter yields
# one count per page. Two pages with no match gave "0\n0", which is not "0" and
# was read as a hit: the wait ended at once on exactly the busy pull requests it
# exists for.
tname="two pages with no match does not read as reviewed"
reset
{
  printf '[{"user":{"login":"someone"},"commit_id":"%s"}]\n' "$OTHER"
  printf '[{"user":{"login":"another"},"commit_id":"%s"}]\n' "$OTHER"
} > "$MOCK/reviews.json"
cp "$MOCK/reviews.json" "$MOCK/comments.json"
printf '[{"name":"CodeRabbit","bucket":"pending"}]\n' > "$MOCK/checks.json"
out=$(run --sha "$SHA" --timeout 2 --no-nudge || true)
[[ "$out" != *"has reviewed"* ]] || fail "a two-page miss was read as a review: [$out]"
pass

tname="two pages with a match on the second page is found"
reset
{
  printf '[{"user":{"login":"someone"},"commit_id":"%s"}]\n' "$OTHER"
  printf '[{"user":{"login":"coderabbitai[bot]"},"commit_id":"%s"}]\n' "$SHA"
} > "$MOCK/reviews.json"
out=$(run --sha "$SHA" --timeout 5 --no-nudge)
[[ "$out" == *"has reviewed"* ]] || fail "a match on page two was missed: [$out]"
pass

# gh documents exit 8 as "Checks pending", the state this script waits through.
tname="exit 8 from gh pr checks is not an error"
reset
printf '[{"name":"CodeRabbit","bucket":"pending"}]\n' > "$MOCK/checks.json"
printf '%s\n' "8" > "$MOCK/checks_rc"
[[ "$(code --sha "$SHA" --timeout 2 --no-nudge)" == "1" ]] \
  || fail "exit 8 should keep it waiting, not kill it"
rm -f "$MOCK/checks_rc"
pass

tname="a real gh failure still stops it"
reset
printf '%s\n' "7" > "$MOCK/checks_rc"
[[ "$(code --sha "$SHA" --timeout 5 --no-nudge)" == "7" ]] \
  || fail "a non-8 failure should die 7"
rm -f "$MOCK/checks_rc"
pass

tname="an abbreviated --sha is resolved before comparing"
reset
printf '[{"user":{"login":"coderabbitai[bot]"},"commit_id":"%s"}]\n' "$SHA" > "$MOCK/reviews.json"
printf '%s\n' "$SHA" > "$MOCK/resolved.txt"
out=$(run --sha "${SHA:0:7}" --timeout 5 --no-nudge)
[[ "$out" == *"has reviewed"* ]] || fail "an abbreviated sha was not resolved: [$out]"
pass

echo "all wait-for-review-bot tests passed"
