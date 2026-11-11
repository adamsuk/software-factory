#!/usr/bin/env bash
# Behaviour tests for scripts/ready-gate.sh and its callers. ShellCheck covers
# this file. A fake gh is the only gh on PATH and HOME is private, so this
# suite makes no live GitHub calls and reads no real credentials. The fake
# serves canned JSON from $GH_DIR and logs every call, so the tests can also
# prove the gate only reads. The watcher callers are covered in
# test-watcher-dismiss.sh (t_ready_gate_refuses).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
gate="$here/ready-gate.sh"
post="$here/station-post.sh"
review="$here/review-issue.sh"

tname="startup"
fail() {
  printf 'FAIL (%s): %s\n' "$tname" "$*" >&2
  for f in "${stdout_file:-}" "${stderr_file:-}" "${log:-}"; do
    if [[ -n "$f" && -f "$f" ]]; then
      printf '%s\n' "--- $f ---" >&2
      cat "$f" >&2 || true
    fi
  done
  exit 1
}
pass() { echo "ok: $tname"; }

[[ -x "$gate" ]] || fail "ready-gate.sh is not executable"
read -r shebang < "$gate"
[[ "$shebang" == "#!/usr/bin/env bash" ]] || fail "shebang is [$shebang]"

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
HOME=$(mktemp -d)
export HOME
bin=$root/bin
log=$root/gh.log
stdout_file=$root/stdout.txt
stderr_file=$root/stderr.txt
GH_DIR=$root/gh
mkdir -p "$bin" "$GH_DIR"
export GH_LOG="$log" GH_DIR
export FACTORY_HOME_REPO=acme/software-factory
unset FACTORY_APPROVER_LOGIN GITHUB_REPOSITORY READY_GATE_CMD

REPO=acme/software-factory
PR=7
SHA=1a2b3c4d5e6f7890abcdef1234567890abcdef12
OLD=0123456789abcdef0123456789abcdef01234567

# The fake dispatches on the gh subcommand and logs every call.
#   pr view ...            view.json (a superset of every --json field asked for)
#   pr list / pr checks    prs.json / checks.json
#   api -H ... contents    factory.yml, else a 404
#   api graphql            threads-<n>.json when the query asks about
#                          isOutdated (page n, by cursor), else status-gql.json
#   api repos/../reviews   cr-reviews.json; .../comments: cr-comments.json
#   issue view             issue.json; issue edit / comment, pr comment: logged
cat > "$bin/gh" << 'FAKE'
#!/usr/bin/env bash
set -euo pipefail
{
  printf '%s\x1f' "$@"
  printf '\n'
} >> "${GH_LOG:?}"
d=${GH_DIR:?}
for a in "$@"; do
  [[ "$a" != merge ]] || { echo "forbidden: merge" >&2; exit 99; }
done
case "$1 $2" in
  "pr view")
    [[ ! -f "$d/view.fail" ]] || exit 1
    cat "$d/view.json"
    ;;
  "pr list") cat "$d/prs.json" ;;
  "pr checks") cat "$d/checks.json" ;;
  "pr comment" | "issue edit" | "issue comment") exit 0 ;;
  "issue view") cat "$d/issue.json" ;;
  "api -H")
    if [[ -f "$d/factory.yml" ]]; then
      cat "$d/factory.yml"
    else
      echo '{"message":"Not Found","status":"404"}'
      echo "gh: Not Found (HTTP 404)" >&2
      exit 1
    fi
    ;;
  "api graphql")
    if printf '%s' "$*" | grep -q isOutdated; then
      [[ ! -f "$d/threads.fail" ]] || exit 1
      cursor=""
      for a in "$@"; do
        case "$a" in cursor=*) cursor=${a#cursor=} ;; esac
      done
      if [[ -n "$cursor" ]]; then cat "$d/threads-${cursor}.json"; else cat "$d/threads-first.json"; fi
    else
      cat "$d/status-gql.json"
    fi
    ;;
  "api repos"*)
    case "$2" in
      */reviews) cat "$d/cr-reviews.json" ;;
      */comments) cat "$d/cr-comments.json" ;;
      *) exit 99 ;;
    esac
    ;;
  *) echo "unmocked gh: $*" >&2; exit 99 ;;
esac
FAKE
chmod +x "$bin/gh"
for tool in bash mktemp rm cat grep chmod seq base64 wc sed head tr dirname basename awk cut sort paste printf git; do
  p=$(command -v "$tool" || true)
  [[ -z "$p" ]] || ln -sf "$p" "$bin/$tool"
done
ln -sf "$(command -v jq)" "$bin/jq"
ln -sf "$(python3 -c 'import sys; print(sys.executable)')" "$bin/python3"
PATH=$bin
export PATH
hash -r

# --- fixture builders -------------------------------------------------------

LABELS='[]'
COMMENTS='[]'

ir_comment() {
  # ir_comment SHA VERDICT [SUMMARY]
  jq -nc --arg sha "$1" --arg v "$2" --arg s "${3:-All good.}" \
    '{author:{login:"software-factory-line"},createdAt:"2026-11-11T10:00:00Z",
      body:("<!-- factory:independent-review v2 sha=" + $sha + " -->\n**Independent review (after CodeRabbit): " + $v + "** on " + $sha[0:7] + "\n" + $s)}'
}

thread() {
  # thread RESOLVED OUTDATED AUTHOR BODY
  jq -nc --argjson r "$1" --argjson o "$2" --arg a "$3" --arg b "$4" \
    '{isResolved:$r,isOutdated:$o,path:"scripts/x.sh",comments:{nodes:[{author:{login:$a},body:$b}]}}'
}

threads_page() {
  # threads_page NODES HASNEXT CURSOR
  jq -nc --argjson n "[$1]" --argjson h "$2" --arg c "$3" \
    '{data:{repository:{pullRequest:{reviewThreads:{pageInfo:{hasNextPage:$h,endCursor:(if $c == "" then null else $c end)},nodes:$n}}}}}'
}

write_view() {
  jq -nc --arg sha "$SHA" --argjson labels "$LABELS" --argjson comments "$COMMENTS" \
    '{number:7,baseRefName:"main",headRefOid:$sha,labels:$labels,comments:$comments,reviews:[]}' \
    > "$GH_DIR/view.json"
}

reset() {
  rm -f "$GH_DIR"/*
  LABELS='[{"name":"size/M"}]'
  COMMENTS="[$(ir_comment "$SHA" PASS)]"
  jq -nc --arg sha "$SHA" '[{number:7,author:{login:"x"},headRefOid:$sha,baseRefName:"main"}]' > "$GH_DIR/prs.json"
  printf '%s' '[{"name":"lint","bucket":"pass"},{"name":"tests","bucket":"pass"}]' > "$GH_DIR/checks.json"
  printf '%s\n' '{"data":{"repository":{"pullRequest":{"reviews":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}' > "$GH_DIR/status-gql.json"
  threads_page '' false '' > "$GH_DIR/threads-first.json"
  printf '%s' '[]' > "$GH_DIR/cr-reviews.json"
  printf '%s' '[]' > "$GH_DIR/cr-comments.json"
  printf '%s\n' '{"labels":[{"name":"factory:review"}],"comments":[]}' > "$GH_DIR/issue.json"
  write_view
}

run_gate() {
  : > "$log"
  status=0
  "$gate" --repo "$REPO" --pr "$PR" "$@" > "$stdout_file" 2> "$stderr_file" || status=$?
}

assert_status() { [[ "$status" -eq "$1" ]] || fail "expected exit $1, got $status"; }
assert_out() { grep -qF -- "$1" "$stdout_file" || fail "stdout lacks [$1]"; }
assert_out_lines() { [[ "$(wc -l < "$stdout_file")" -eq "$1" ]] || fail "expected $1 stdout lines"; }
assert_ready() { assert_status 0; assert_out "ready: ${REPO}#${PR}"; }

# --- independent review PASS for the exact head -----------------------------

tname="ready-baseline"
reset
run_gate
assert_ready
pass

tname="no-independent-review"
reset
COMMENTS='[]'; write_view
run_gate
assert_status 1
assert_out "independent review: no PASS recorded for head ${SHA:0:7}"
assert_out_lines 1
pass

tname="pass-for-older-sha-does-not-count"
reset
COMMENTS="[$(ir_comment "$OLD" PASS)]"; write_view
run_gate
assert_status 1
assert_out "independent review: no PASS recorded"
pass

tname="github-approval-and-factory-review-comment-do-not-count"
reset
fr_ready=$(jq -nc '{author:{login:"acme"},createdAt:"2026-11-11T10:00:00Z",body:"<!-- factory:review -->\nverdict: ready\nshould-fix: 0\nnits: 0"}')
fr_pass=$(jq -nc '{author:{login:"acme"},createdAt:"2026-11-11T10:01:00Z",body:"<!-- factory:review -->\nverdict: PASS\nshould-fix: 0\nnits: 0"}')
COMMENTS="[${fr_ready},${fr_pass}]"
jq -nc --arg sha "$SHA" '{number:7,baseRefName:"main",headRefOid:$sha,labels:[{name:"size/M"}],comments:'"$COMMENTS"',reviews:[{state:"APPROVED",author:{login:"acme"},commit:{oid:$sha}}]}' > "$GH_DIR/view.json"
run_gate
assert_status 1
assert_out "independent review: no PASS recorded"
pass

tname="latest-independent-review-for-head-wins"
reset
COMMENTS="[$(ir_comment "$SHA" PASS),$(ir_comment "$SHA" FIX)]"; write_view
run_gate
assert_status 1
assert_out "latest independent review comment for this head says FIX"
COMMENTS="[$(ir_comment "$SHA" FIX),$(ir_comment "$SHA" PASS)]"; write_view
run_gate
assert_ready
pass

tname="verdict-comes-from-the-marker-line-not-the-summary"
reset
COMMENTS="[$(ir_comment "$SHA" FIX '**Independent review (after CodeRabbit): PASS** on 1a2b3c4')]"; write_view
run_gate
assert_status 1
assert_out "says FIX"
pass

tname="abbreviated-marker-sha-matches-the-head"
reset
COMMENTS="[$(ir_comment "${SHA:0:12}" PASS)]"; write_view
run_gate
assert_ready
pass

tname="watcher-result-file-pass-counts"
reset
COMMENTS='[]'; write_view
printf '{"verdict":"PASS","summary":"ok"}\n' > "$root/ir-pass.json"
printf '{"verdict":"FIX","summary":"no"}\n' > "$root/ir-fix.json"
run_gate --ir-result "$root/ir-pass.json"
assert_ready
run_gate --ir-result "$root/ir-fix.json"
assert_status 1
assert_out "watcher result says FIX"
run_gate --ir-result "$root/missing.json"
assert_status 1
pass

tname="independent-review-comment-author-is-checked"
reset
by() { ir_comment "$SHA" PASS | jq -c --arg a "$1" '.author.login = $a'; }
COMMENTS="[$(by mallory)]"; write_view
run_gate
assert_status 1
assert_out "independent review: no PASS recorded for head ${SHA:0:7}"
assert_out "is from an unrecognised author (only acme or software-factory-line may post it)"
for who in acme software-factory-line software-factory-line[bot] app/software-factory-line; do
  COMMENTS="[$(by "$who")]"; write_view
  run_gate
  assert_ready
done
# A forged PASS after a real FIX does not override it.
COMMENTS="[$(ir_comment "$SHA" FIX),$(by mallory)]"; write_view
run_gate
assert_status 1
assert_out "says FIX"
# FACTORY_APPROVER_LOGIN replaces the repo owner as the approver.
COMMENTS="[$(by acme)]"; write_view
FACTORY_APPROVER_LOGIN=maintainer run_gate
assert_status 1
COMMENTS="[$(by maintainer)]"; write_view
FACTORY_APPROVER_LOGIN=maintainer run_gate
assert_ready
# The watcher result file path is unchanged.
COMMENTS="[$(by mallory)]"; write_view
run_gate --ir-result "$root/ir-pass.json"
assert_ready
pass

# --- review threads ---------------------------------------------------------

tname="unresolved-non-outdated-thread-refuses"
reset
threads_page "$(thread false false coderabbitai '_Minor_ rename this variable')" false '' > "$GH_DIR/threads-first.json"
run_gate
assert_status 1
assert_out "unresolved review thread (not outdated) on scripts/x.sh by coderabbitai: _Minor_ rename this variable"
assert_out_lines 1
pass

tname="human-thread-also-refuses"
reset
threads_page "$(thread false false some-human 'please add a test')" false '' > "$GH_DIR/threads-first.json"
run_gate
assert_status 1
assert_out "by some-human: please add a test"
pass

tname="outdated-and-resolved-threads-do-not-block"
reset
threads_page "$(thread false true coderabbitai 'stale'),$(thread true false coderabbitai 'done'),$(thread true true coderabbitai 'both')" false '' > "$GH_DIR/threads-first.json"
run_gate
assert_ready
pass

tname="outdated-thread-does-not-hide-a-live-minor"
reset
threads_page "$(thread false true coderabbitai 'stale'),$(thread false false coderabbitai '_Minor_ live one')" false '' > "$GH_DIR/threads-first.json"
run_gate
assert_status 1
assert_out "_Minor_ live one"
assert_out_lines 1
pass

tname="thread-on-a-later-page-refuses"
reset
threads_page "$(thread true false a "done")" true cur1 > "$GH_DIR/threads-first.json"
threads_page "$(thread false false a 'second page')" false '' > "$GH_DIR/threads-cur1.json"
run_gate
assert_status 1
assert_out "second page"
pass

# --- required checks (the pr-status.sh rule) --------------------------------

tname="required-check-failing-refuses-and-names-it"
reset
printf '%s\n' 'required_checks:' '  - lint' '  - tests' > "$GH_DIR/factory.yml"
printf '%s' '[{"name":"lint","bucket":"pass"},{"name":"tests","bucket":"fail"}]' > "$GH_DIR/checks.json"
run_gate
assert_status 1
assert_out "required checks not green: checks=failing(tests)"
pass

tname="required-check-missing-or-pending-refuses"
reset
printf '%s\n' 'required_checks:' '  - lint' '  - tests' > "$GH_DIR/factory.yml"
printf '%s' '[{"name":"lint","bucket":"pass"}]' > "$GH_DIR/checks.json"
run_gate
assert_status 1
assert_out "required checks not green: checks=pending"
printf '%s' '[{"name":"lint","bucket":"pass"},{"name":"tests","bucket":"pending"}]' > "$GH_DIR/checks.json"
run_gate
assert_status 1
assert_out "checks=pending"
pass

tname="optional-failing-check-is-ignored"
reset
printf '%s\n' 'required_checks:' '  - lint' '  - tests' > "$GH_DIR/factory.yml"
printf '%s' '[{"name":"lint","bucket":"pass"},{"name":"tests","bucket":"pass"},{"name":"extra","bucket":"fail"}]' > "$GH_DIR/checks.json"
run_gate
assert_ready
pass

tname="no-required-list-judges-every-check"
reset
printf '%s' '[{"name":"lint","bucket":"pass"},{"name":"extra","bucket":"fail"}]' > "$GH_DIR/checks.json"
run_gate
assert_status 1
assert_out "checks=failing(extra)"
printf '%s' '[]' > "$GH_DIR/checks.json"
run_gate
assert_status 1
assert_out "checks=none"
pass

# --- CodeRabbit on size/L and size/XL ---------------------------------------

cr_review() { jq -nc --arg c "$1" --arg s "${2:-COMMENTED}" '[{user:{login:"coderabbitai[bot]"},commit_id:$c,state:$s}]'; }
cr_comment() { jq -nc --arg c "$1" --arg o "$2" '[{user:{login:"coderabbitai[bot]"},commit_id:$c,original_commit_id:$o}]'; }

for size in size/L size/XL; do
  tname="${size//\//-}-without-coderabbit-refuses"
  reset
  LABELS=$(jq -nc --arg s "$size" '[{name:$s}]'); write_view
  run_gate
  assert_status 1
  assert_out "CodeRabbit has no review of head ${SHA:0:7}"
  assert_out_lines 1
  pass

  tname="${size//\//-}-coderabbit-review-of-older-sha-does-not-count"
  reset
  LABELS=$(jq -nc --arg s "$size" '[{name:$s}]'); write_view
  cr_review "$OLD" APPROVED > "$GH_DIR/cr-reviews.json"
  cr_comment "$SHA" "$OLD" > "$GH_DIR/cr-comments.json"
  run_gate
  assert_status 1
  assert_out "CodeRabbit has no review of head"
  pass

  tname="${size//\//-}-coderabbit-review-of-this-head-counts-in-any-state"
  reset
  LABELS=$(jq -nc --arg s "$size" '[{name:$s}]'); write_view
  cr_review "$SHA" CHANGES_REQUESTED > "$GH_DIR/cr-reviews.json"
  run_gate
  assert_ready
  cr_review "$SHA" COMMENTED > "$GH_DIR/cr-reviews.json"
  run_gate
  assert_ready
  pass

  tname="${size//\//-}-coderabbit-comment-written-against-this-head-counts"
  reset
  LABELS=$(jq -nc --arg s "$size" '[{name:$s}]'); write_view
  cr_comment "$SHA" "$SHA" > "$GH_DIR/cr-comments.json"
  run_gate
  assert_ready
  pass
done

tname="smaller-size-needs-no-coderabbit-review"
reset
for size in size/XS size/S size/M; do
  LABELS=$(jq -nc --arg s "$size" '[{name:$s}]'); write_view
  run_gate
  assert_ready
  grep -q 'pulls/' "$log" && fail "read CodeRabbit reviews for $size"
done
pass

# --- head handling and read failures ----------------------------------------

tname="head-moved-since-the-caller-judged-it"
reset
run_gate --sha "$OLD"
assert_status 1
assert_out "head moved: judged ${OLD:0:7}, the pull request head is now ${SHA:0:7}"
run_gate --sha "${SHA:0:9}"
assert_ready
pass

tname="every-missing-item-is-listed-one-per-line"
reset
COMMENTS='[]'
LABELS='[{"name":"size/L"}]'; write_view
threads_page "$(thread false false coderabbitai 'a')" false '' > "$GH_DIR/threads-first.json"
printf '%s' '[{"name":"lint","bucket":"fail"}]' > "$GH_DIR/checks.json"
run_gate
assert_status 1
assert_out_lines 4
assert_out "independent review:"
assert_out "unresolved review thread"
assert_out "required checks not green"
assert_out "CodeRabbit has no review"
pass

tname="unreadable-pr-or-threads-fail-closed"
reset
: > "$GH_DIR/view.fail"
run_gate
assert_status 7
[[ ! -s "$stdout_file" ]] || fail "stdout not empty on a failed read"
rm -f "$GH_DIR/view.fail"
: > "$GH_DIR/threads.fail"
run_gate
assert_status 7
pass

tname="bad-usage"
status=0; "$gate" --repo nope --pr 1 > /dev/null 2>&1 || status=$?
assert_status 2
status=0; "$gate" --repo "$REPO" --pr x > /dev/null 2>&1 || status=$?
assert_status 2
status=0; "$gate" --repo "$REPO" --pr 1 --sha zz > /dev/null 2>&1 || status=$?
assert_status 2
pass

tname="read-only"
reset
threads_page "$(thread false false coderabbitai 'a')" false '' > "$GH_DIR/threads-first.json"
LABELS='[{"name":"size/L"}]'; write_view
run_gate
# shellcheck disable=SC2016
if tr '\037' ' ' < "$log" | grep -E '^(pr (comment|merge|edit|review|close|ready)|issue |label |-X|api .*(-X|--method))' > /dev/null; then
  fail "the gate wrote to GitHub"
fi
pass

# --- callers: station-post.sh and review-issue.sh ---------------------------
# These run the real gate (READY_GATE_CMD is unset) against the same fake gh.

edits() { tr '\037' ' ' < "$log" | grep -c '^issue edit' || true; }

post_verdict() {
  : > "$log"
  status=0
  "$post" verdict --repo "$REPO" --pr "$PR" --issue 326 --sha "$1" --verdict PASS \
    --protected no --summary "Meets the acceptance criteria." > "$stdout_file" 2> "$stderr_file" || status=$?
}

tname="station-post-refuses-with-an-open-thread"
reset
threads_page "$(thread false false coderabbitai '_Minor_ still open')" false '' > "$GH_DIR/threads-first.json"
post_verdict "$SHA"
assert_status 4
grep -qF "_Minor_ still open" "$stderr_file" || fail "stderr does not name the thread"
[[ "$(edits)" -eq 0 ]] || fail "station-post moved labels after a refusal"
tr '\037' ' ' < "$log" | grep -q 'factory:merge' && fail "factory:merge was applied"
pass

tname="station-post-refuses-a-stale-head"
reset
post_verdict "$OLD"
assert_status 4
grep -qF "head moved" "$stderr_file" || fail "stderr does not say the head moved"
[[ "$(edits)" -eq 0 ]] || fail "station-post moved labels on a stale head"
pass

tname="station-post-refuses-when-the-gate-cannot-read"
reset
: > "$GH_DIR/threads.fail"
post_verdict "$SHA"
assert_status 7
[[ "$(edits)" -eq 0 ]] || fail "station-post moved labels on an unreadable gate"
pass

tname="station-post-moves-to-merge-when-ready"
reset
post_verdict "$SHA"
assert_status 0
tr '\037' ' ' < "$log" | grep -q '^issue edit 326 --repo acme/software-factory --remove-label factory:review --add-label factory:merge' \
  || fail "factory:merge was not applied"
pass

review_order() {
  # review_order VERDICT-COMMENT-JSON ... : write a work order and the pr view
  cat > "$root/order.md" << 'EOF'
---
repo: acme/software-factory
issue: 326
issue_repo: acme/software-factory
branch: factory/326-ready-gate
attempt: 1
---
body is ignored
EOF
}

run_review() {
  : > "$log"
  status=0
  "$review" "$root/order.md" > "$stdout_file" 2> "$stderr_file" || status=$?
}

for verdict in PASS ready; do
  tname="review-issue-refuses-an-unready-head-on-a-${verdict}-verdict"
  reset
  review_order
  fr=$(jq -nc --arg v "$verdict" '{author:{login:"acme"},createdAt:"2026-11-11T10:00:00Z",body:("<!-- factory:review -->\nverdict: " + $v + "\nshould-fix: 0\nnits: 0")}')
  COMMENTS="[${fr}]"; write_view
  printf '%s\n' '{"labels":[{"name":"factory:review"}],"comments":[]}' > "$GH_DIR/issue.json"
  run_review
  assert_status 0
  [[ "$(cat "$stdout_file")" == "wait" ]] || fail "expected wait, got [$(cat "$stdout_file")]"
  grep -qF "independent review: no PASS recorded" "$stderr_file" || fail "stderr does not name the missing PASS"
  [[ "$(edits)" -eq 0 ]] || fail "review-issue moved labels after a refusal"
  pass

  tname="review-issue-merges-a-ready-head-on-a-${verdict}-verdict"
  reset
  review_order
  COMMENTS="[${fr},$(ir_comment "$SHA" PASS)]"; write_view
  run_review
  assert_status 0
  [[ "$(cat "$stdout_file")" == "merge" ]] || fail "expected merge, got [$(cat "$stdout_file")]"
  tr '\037' ' ' < "$log" | grep -q '^issue edit 326 --repo acme/software-factory --remove-label factory:review --add-label factory:merge' \
    || fail "factory:merge was not applied"
  pass
done

tname="review-issue-fails-closed-when-the-gate-cannot-read"
reset
review_order
COMMENTS="[${fr},$(ir_comment "$SHA" PASS)]"; write_view
: > "$GH_DIR/threads.fail"
run_review
assert_status 7
[[ "$(edits)" -eq 0 ]] || fail "review-issue moved labels on an unreadable gate"
pass

# --- the watcher wiring and board-sync --------------------------------------

for w in watch.sh watch.new.sh; do
  tname="${w}-calls-the-gate-before-any-ready-or-merge-decision"
  f="$here/watcher/$w"
  call=$(awk '/^merge_gate\(\)/ { in_fn = 1 } in_fn && /run_ready_gate "\$repo" "\$pr" "\$GATE_SHA"/ { print NR; exit }' "$f")
  first=$(awk '/^merge_gate\(\)/ { in_fn = 1 } in_fn && /GATE_DECISION=(merge|protected)/ { print NR; exit }' "$f")
  [[ -n "$call" && -n "$first" && "$call" -lt "$first" ]] \
    || fail "$w: run_ready_gate (line ${call:-none}) must precede the first merge or protected decision (line ${first:-none})"
  grep -q 'ready=1' "$f" || fail "$w: ready bit missing"
  pass
done

tname="board-sync-stays-a-label-mirror"
if grep -n 'ready-gate' "$here/watcher/board-sync.sh" > /dev/null 2>&1; then
  fail "board-sync.sh must not carry its own ready decision"
fi
pass

echo "all ready-gate tests passed"
