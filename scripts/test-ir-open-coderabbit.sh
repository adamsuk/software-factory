#!/usr/bin/env bash
# Independent review must not stay PASS while any reviewer still has a blocking
# action on the current head (#451). Offline. A fake gh records the posted
# comment and thread replies. Both watcher lanes must agree. No network.
# Case functions run inside the sourced subshell. LANE_NAME and GH_BODY are
# exported there, and STATE comes from the watcher. ShellCheck sees those
# assignments as local to the subshell.
# shellcheck disable=SC2030,SC2031,SC2153
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok: %s\n' "$*"; }

HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
OLD=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

extract_between() {
  awk -v start="$2" -v end="$3" '
    index($0, start) == 1 { on = 1 }
    on { print }
    on && index($0, end) == 1 && index($0, start) != 1 { exit }
  ' "$1"
}

extract_fn() {
  awk -v name="$2" '
    $0 ~ ("^" name "\\(\\)") { on = 1 }
    on { print }
    on && /^}/ { exit }
  ' "$1"
}

extract_between "$root/scripts/watcher/watch.sh" "# \$1 graphql reviewThreads" "# \$1 grok JSON" > "$work/block.watch"
extract_between "$root/scripts/watcher/watch.new.sh" "# \$1 graphql reviewThreads" "# \$1 grok JSON" > "$work/block.watch.new"
cmp -s "$work/block.watch" "$work/block.watch.new" || fail "open-coderabbit blocks differ between watcher lanes"
pass "open-coderabbit blocks match"

extract_fn "$root/scripts/watcher/watch.sh" ir_post_comment > "$work/post.watch"
extract_fn "$root/scripts/watcher/watch.new.sh" ir_post_comment > "$work/post.watch.new"
cmp -s "$work/post.watch" "$work/post.watch.new" || fail "ir_post_comment copies differ"
pass "ir_post_comment copies match"

extract_fn "$root/scripts/watcher/watch.sh" ir_reply_body > "$work/reply-body.watch"
extract_fn "$root/scripts/watcher/watch.new.sh" ir_reply_body > "$work/reply-body.watch.new"
[[ -s $work/reply-body.watch ]] || fail "ir_reply_body missing"
cmp -s "$work/reply-body.watch" "$work/reply-body.watch.new" || fail "ir_reply_body copies differ"
pass "ir_reply_body copies match"

extract_fn "$root/scripts/watcher/watch.sh" ir_reply_threads > "$work/reply.watch"
extract_fn "$root/scripts/watcher/watch.new.sh" ir_reply_threads > "$work/reply.watch.new"
[[ -s $work/reply.watch ]] || fail "ir_reply_threads missing"
cmp -s "$work/reply.watch" "$work/reply.watch.new" || fail "ir_reply_threads copies differ"
pass "ir_reply_threads copies match"

extract_fn "$root/scripts/watcher/watch.sh" ir_save_result > "$work/save.watch"
extract_fn "$root/scripts/watcher/watch.new.sh" ir_save_result > "$work/save.watch.new"
cmp -s "$work/save.watch" "$work/save.watch.new" || fail "ir_save_result copies differ"
pass "ir_save_result copies match"

for lane in watch watch.new; do
  body=$(sed -n '/^step_independent_review() {/,/^}/p' "$root/scripts/watcher/${lane}.sh")
  [[ -n $body ]] || fail "$lane: step_independent_review not found"
  printf '%s\n' "$body" | awk '
    /ir_save_result / { saved = NR }
    saved && !guarded && /ir_guard_open_coderabbit / { guarded = NR }
    guarded && !posted && /ir_post_comment / { posted = NR }
    END { exit !(saved && guarded && posted && saved < guarded && guarded < posted) }
  ' || fail "$lane: ir_guard_open_coderabbit is not between ir_save_result and ir_post_comment"
  printf '%s\n' "$body" | awk '
    /ir_save_result / { exit }
    /ir_guard_open_coderabbit / { guarded = 1 }
    /ir_post_comment / { if (guarded) ok = 1 }
    END { exit !ok }
  ' || fail "$lane: an unposted saved result is posted without the open-coderabbit guard"
  grep -F -q 'Do not return PASS while a review thread on this head is unresolved and not outdated' <<< "$body" \
    || fail "$lane: independent-review prompt does not refuse PASS for an open review finding"
  grep -F -q 'from any reviewer' <<< "$body" \
    || fail "$lane: independent-review prompt does not count every reviewer"
  grep -F -q 'CodeRabbit does not review pull requests this size; you are the only review before merge' <<< "$body" \
    || fail "$lane: small-pull-request prompt was dropped"
done
pass "both lanes call the guard before posting"

grep -F -q 'no outstanding blocking review action remains on that head' "$root/agents/roles/reviewer.md" \
  || fail "reviewer brief does not refuse PASS while a review action is open"
grep -F -q 'dismissed with a reason, or escalated' "$root/agents/roles/reviewer.md" \
  || fail "reviewer brief does not require a disposition for each outstanding finding"
grep -F -q 'replies on each unresolved thread' "$root/agents/roles/reviewer.md" \
  || fail "reviewer brief does not require a reply on each unresolved thread"
grep -F -q 'ir_guard_open_coderabbit' "$root/agents/roles/reviewer.md" \
  || fail "reviewer brief does not name the guard"
if grep -F -q 'changes-requested alone does **not** force FIX/ESCALATE' "$root/agents/roles/reviewer.md"; then
  fail "reviewer brief still says a current-head changes-requested review does not force FIX or ESCALATE"
fi
pass "reviewer brief states the rule"

for lane in watch watch.new; do
  f="$root/scripts/watcher/${lane}.sh"
  grep -F -q 'CI_FIX_ROUNDS=3' "$f" || fail "$lane does not set CI_FIX_ROUNDS=3"
  grep -F -q 'REVIEW_COMMENT_FIX_ROUNDS=5' "$f" || fail "$lane does not set REVIEW_COMMENT_FIX_ROUNDS=5"
  # Literal watcher source: the dollars are part of the file text.
  grep -F -q "\"\${STATE}/ci-rounds-" "$f" || fail "$lane does not count failing-CI rounds apart"
  grep -F -q "\"\${STATE}/review-rounds-" "$f" || fail "$lane does not count review-comment rounds apart"
  if grep -F -q "\"\${STATE}/rounds-" "$f"; then
    fail "$lane still uses one shared rounds- counter"
  fi
  grep -F -q 'rounds >= CI_FIX_ROUNDS' "$f" || fail "$lane does not cap failing CI at CI_FIX_ROUNDS"
  grep -F -q 'rounds >= REVIEW_COMMENT_FIX_ROUNDS' "$f" || fail "$lane does not cap review comments at REVIEW_COMMENT_FIX_ROUNDS"
  grep -F -q "round_cap=\$CI_FIX_ROUNDS" "$f" || fail "$lane mode=ci does not use CI_FIX_ROUNDS"
  grep -F -q "round_cap=\$REVIEW_COMMENT_FIX_ROUNDS" "$f" || fail "$lane mode=review does not use REVIEW_COMMENT_FIX_ROUNDS"
  grep -F -q 'rounds >= round_cap' "$f" || fail "$lane step_fix_fallback does not use the mode cap"
  [[ $(grep -c 'if ! ir_guard_open_coderabbit' "$f") -eq 2 ]] \
    || fail "$lane does not keep a failed open-finding read from posting"
  awk '
    /^merge_gate\(\)/ { in_fn = 1 }
    in_fn && /ir_pass_still_blocked / { found = 1 }
    in_fn && /^}/ { exit found ? 0 : 1 }
  ' "$f" || fail "$lane merge_gate does not re-check open review findings"
done
grep -F -q '5-round cap' "$root/agents/roles/reviewer.md" \
  || fail "reviewer brief does not state the 5-round review-comment cap"
grep -F -q 'CI fix-loop stays at 3' "$root/agents/roles/reviewer.md" \
  || fail "reviewer brief does not keep the CI fix-loop at 3"
grep -F -q 'at most 3' "$root/AGENTS.md" \
  || fail "AGENTS.md lost the builder CI fix-loop cap of 3"
grep -F -q '5-round cap' "$root/AGENTS.md" \
  || fail "AGENTS.md does not state the 5-round review-comment cap"
grep -F -q 'CI fix-loop stays at 3' "$root/AGENTS.md" \
  || fail "AGENTS.md does not keep the CI fix-loop at 3"
pass "review-comment cap is 5 and the CI fix-loop stays at 3"

for fn in ir_clear_guard_fix ir_pass_still_blocked ir_comment_limit ir_outstanding_lines ir_comment_prefix ir_post_split; do
  extract_fn "$root/scripts/watcher/watch.sh" "$fn" > "$work/fn.${fn}.watch"
  extract_fn "$root/scripts/watcher/watch.new.sh" "$fn" > "$work/fn.${fn}.watch.new"
  [[ -s $work/fn.${fn}.watch ]] || fail "$fn missing"
  cmp -s "$work/fn.${fn}.watch" "$work/fn.${fn}.watch.new" || fail "$fn copies differ"
done
pass "new independent-review helpers match"

export FACTORY_HOME="$work/home"
export FACTORY_WATCH_ROOT="$work/root"
export FACTORY_BUDGET_FILE="$work/budget.json"
export FACTORY_LEDGER_FILE="$work/ledger.csv"
export FACTORY_HOME_REPO=acme/software-factory
export FACTORY_REPOS=acme/software-factory
unset FACTORY_BLOCKED_OWNERS
mkdir -p "$FACTORY_WATCH_ROOT/state" "$FACTORY_HOME" "$work/bin"
printf '%s\n' '{"max_grok_build_runs_per_week":20,"max_grok_build_runs_per_day":20,"max_runs_per_loop":5,"max_coderabbit_requests_per_hour":8}' > "$FACTORY_BUDGET_FILE"

cat > "$work/bin/gh" << 'EOF'
#!/bin/bash
if [[ ${1:-} == pr && ${2:-} == comment ]]; then
  while [[ $# -gt 0 ]]; do
    if [[ $1 == --body && $# -ge 2 ]]; then
      printf '%s\n' "$2" > "${GH_BODY:?}"
      if [[ -n ${GH_ALL:-} ]]; then
        jq -nc --arg body "$2" '{body:$body}' >> "$GH_ALL"
      fi
      exit 0
    fi
    shift
  done
fi
if [[ ${1:-} == api ]]; then
  method=""
  url=""
  body=""
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --method)
        method=${2:-}
        shift 2
        ;;
      -f)
        if [[ ${2:-} == body=* ]]; then
          body=${2#body=}
        fi
        shift 2
        ;;
      -*)
        shift
        ;;
      *)
        if [[ -z $url ]]; then
          url=$1
        fi
        shift
        ;;
    esac
  done
  if [[ $method == POST && $url == *"/comments/"*"/replies" ]]; then
    jq -nc --arg url "$url" --arg body "$body" '{url:$url, body:$body}' >> "${GH_REPLIES:?}"
    exit 0
  fi
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 99
EOF
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"

empty_threads() {
  jq -n '{data:{repository:{pullRequest:{reviewThreads:{pageInfo:{hasNextPage:false},nodes:[]}}}}}'
}

one_thread() {
  local resolved=$1 outdated=$2 path=$3 id=$4 author=$5 body=$6 commit=$7
  jq -n \
    --argjson resolved "$resolved" --argjson outdated "$outdated" \
    --arg path "$path" --argjson id "$id" --arg author "$author" \
    --arg body "$body" --arg commit "$commit" \
    '{data:{repository:{pullRequest:{reviewThreads:{pageInfo:{hasNextPage:false},nodes:[{
      isResolved:$resolved, isOutdated:$outdated, path:$path,
      comments:{nodes:[{databaseId:$id, author:{login:$author}, body:$body, originalCommit:{oid:$commit}}]}
    }]}}}}}'
}

two_threads() {
  local id_a=$1 author_a=$2 body_a=$3 commit_a=$4
  local id_b=$5 author_b=$6 body_b=$7 commit_b=$8
  jq -n \
    --argjson ida "$id_a" --arg aa "$author_a" --arg ba "$body_a" --arg ca "$commit_a" \
    --argjson idb "$id_b" --arg ab "$author_b" --arg bb "$body_b" --arg cb "$commit_b" \
    '{data:{repository:{pullRequest:{reviewThreads:{pageInfo:{hasNextPage:false},nodes:[
      {isResolved:false, isOutdated:false, path:"scripts/a.sh",
        comments:{nodes:[{databaseId:$ida, author:{login:$aa}, body:$ba, originalCommit:{oid:$ca}}]}},
      {isResolved:false, isOutdated:false, path:"scripts/b.sh",
        comments:{nodes:[{databaseId:$idb, author:{login:$ab}, body:$bb, originalCommit:{oid:$cb}}]}}
    ]}}}}}'
}

one_comment() {
  local id=$1 author=$2 body=$3 original=$4 commit=$5 position=$6
  jq -n \
    --argjson id "$id" --arg author "$author" --arg body "$body" \
    --arg original "$original" --arg commit "$commit" --argjson position "$position" \
    '[{id:$id, user:{login:$author}, body:$body, original_commit_id:$original, commit_id:$commit, position:$position}]'
}

no_comments() { printf '%s\n' '[]'; }

one_review() {
  local author=$1 state=$2 commit=$3 body=$4 outdated=${5:-false}
  jq -n \
    --arg author "$author" --arg state "$state" --arg commit "$commit" \
    --arg body "$body" --argjson outdated "$outdated" \
    '[{user:{login:$author}, state:$state, commit_id:$commit, body:$body, outdated:$outdated}]'
}

no_reviews() { printf '%s\n' '[]'; }

write_result() {
  local dest=$1 verdict=$2 dismissed=$3 escalate=$4
  jq -n --arg sha "$HEAD" --arg verdict "$verdict" --argjson dismissed "$dismissed" --argjson escalate "$escalate" \
    '{verdict:$verdict, summary:"Meets the criteria.", agreed_behaviour:"do the thing",
      checks_ran:"tests passed", unasked_behaviour:"none", blast_radius:"one script",
      fix:[], dismissed:$dismissed, escalate:$escalate, sha:$sha, at:"2026-11-21T00:00:00Z"}' > "$dest"
}

# $1 case name. Reads the three payload files and writes the lane result.
apply_case() {
  local name=$1
  local norm=$work/${name}.norm.json block=$work/${name}.block.json dest=$work/${name}.result.json
  ir_normalize_open "$work/${name}.threads.json" "$work/${name}.comments.json" "$work/${name}.reviews.json" > "$norm"
  ir_blocking_findings "$HEAD" "$norm" > "$block"
  cp "$dest" "$work/${name}.before.json"
  ir_apply_open_coderabbit "$dest" "$block"
  cp "$dest" "$work/${name}.${LANE_NAME}.json"
  cp "$block" "$work/${name}.${LANE_NAME}.block"
}

assert_unchanged() {
  local name=$1
  cmp -s "$work/${name}.before.json" "$work/${name}.${LANE_NAME}.json" \
    || fail "$name ($LANE_NAME): PASS was rewritten"
  jq -e 'type == "array" and length == 0' "$work/${name}.${LANE_NAME}.block" >/dev/null \
    || fail "$name ($LANE_NAME): expected no blocking findings"
}

run_in() {
  local lane=$1 fn=$2 err=$work/stderr.txt
  if ! (
    export LANE_NAME=$lane
    export GH_BODY="$work/body.${fn}.${lane}"
    export GH_REPLIES="$work/replies.${fn}.${lane}"
    export GH_ALL="$work/all.${fn}.${lane}"
    : > "$GH_REPLIES"
    : > "$GH_ALL"
    # shellcheck disable=SC1090
    source "$root/scripts/watcher/${lane}.sh"
    "$fn"
  ) >"$work/stdout.txt" 2>"$err"; then
    printf 'FAIL: %s (%s)\n' "$fn" "$lane" >&2
    cat "$err" >&2
    exit 1
  fi
}

both_lanes() {
  local fn=$1
  local lane
  for lane in watch watch.new; do
    run_in "$lane" "$fn"
  done
  cmp -s "$work/${fn}.watch.json" "$work/${fn}.watch.new.json" || fail "$fn: lanes disagree on the saved verdict"
}

case_dismissed_thread() {
  local name=${FUNCNAME[0]} text="Rename the helper so the name matches the check."
  one_thread false false scripts/foo.sh 101 'coderabbitai[bot]' "$text" "$HEAD" > "$work/${name}.threads.json"
  one_comment 101 'coderabbitai[bot]' "$text" "$HEAD" "$HEAD" 12 > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS "$(jq -n --arg t "$text" '[$t + " - the name is internal"]')" '[]'
  apply_case "$name"
  jq -e --arg t "$text" --arg sha "$HEAD" '
    .verdict == "FIX"
    and .sha == $sha
    and (.outstanding | length) == 1
    and .outstanding[0].text == $t
    and .outstanding[0].disposition == "dismissed: the name is internal"
    and ([.fix[]? | select(. == "CodeRabbit: " + $t)] | length) == 1
    and ([.dismissed[]? | select(startswith($t))] | length) == 0
    and (.summary | contains("Open CodeRabbit findings on this head block PASS."))
  ' "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): dismissed finding still PASS or missing disposition"
}

case_addressed_thread() {
  local name=${FUNCNAME[0]} text="Use a named constant for the limit."
  one_thread false false scripts/foo.sh 102 'coderabbitai[bot]' "$text" "$HEAD" > "$work/${name}.threads.json"
  one_comment 102 'coderabbitai[bot]' "$text" "$HEAD" "$HEAD" 4 > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  jq -e --arg t "$text" '
    .verdict == "FIX"
    and .outstanding[0].text == $t
    and .outstanding[0].disposition == "addressed"
  ' "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): in-scope finding was not FIX/addressed"
}

case_secret_escalates() {
  local name=${FUNCNAME[0]} text="This change prints a secret in the log."
  one_thread false false scripts/foo.sh 103 'coderabbitai[bot]' "$text" "$HEAD" > "$work/${name}.threads.json"
  one_comment 103 'coderabbitai[bot]' "$text" "$HEAD" "$HEAD" 8 > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS "$(jq -n --arg t "$text" '[$t + " - not a real secret"]')" '[]'
  apply_case "$name"
  jq -e --arg t "$text" '
    .verdict == "ESCALATE"
    and .outstanding[0].text == $t
    and .outstanding[0].disposition == "escalated"
    and ([.escalate[]? | select(. == "CodeRabbit: " + $t)] | length) == 1
    and ([.fix[]? | select(startswith("CodeRabbit: "))] | length) == 0
  ' "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): a secret finding was not escalated"
}

case_comment_only() {
  local name=${FUNCNAME[0]} text="Handle the empty list before indexing."
  empty_threads > "$work/${name}.threads.json"
  one_comment 201 'coderabbitai' "$text" "$HEAD" "$HEAD" 6 > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  jq -e --arg t "$text" '
    .verdict == "FIX" and .outstanding[0].text == $t and .outstanding[0].disposition == "addressed"
  ' "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): an unresolved comment on the head stayed PASS"
}

case_commented_review() {
  local name=${FUNCNAME[0]} text="Walkthrough of the new check."
  empty_threads > "$work/${name}.threads.json"
  no_comments > "$work/${name}.comments.json"
  one_review 'coderabbitai[bot]' COMMENTED "$HEAD" "$text" false > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  jq -e --arg t "$text" '.verdict == "FIX" and .outstanding[0].text == $t' \
    "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): COMMENTED review on the head stayed PASS"
}

case_changes_requested() {
  local name=${FUNCNAME[0]} text="Please handle the empty list."
  empty_threads > "$work/${name}.threads.json"
  no_comments > "$work/${name}.comments.json"
  one_review 'coderabbitai[bot]' CHANGES_REQUESTED "$HEAD" "$text" false > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  jq -e --arg t "$text" '.verdict == "FIX" and .outstanding[0].text == $t' \
    "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): CHANGES_REQUESTED on the head stayed PASS"
}

case_outdated_thread() {
  local name=${FUNCNAME[0]} text="Outdated note about the helper."
  one_thread false true README.md 301 'coderabbitai[bot]' "$text" "$HEAD" > "$work/${name}.threads.json"
  one_comment 301 'coderabbitai[bot]' "$text" "$HEAD" "$HEAD" 9 > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  assert_unchanged "$name"
}

case_earlier_commit() {
  local name=${FUNCNAME[0]} text="Earlier head note."
  one_thread false false README.md 302 'coderabbitai[bot]' "$text" "$OLD" > "$work/${name}.threads.json"
  one_comment 302 'coderabbitai[bot]' "$text" "$OLD" "$HEAD" 5 > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  assert_unchanged "$name"
}

case_resolved_thread() {
  local name=${FUNCNAME[0]} text="Already fixed the helper name."
  one_thread true false scripts/foo.sh 303 'coderabbitai[bot]' "$text" "$HEAD" > "$work/${name}.threads.json"
  one_comment 303 'coderabbitai[bot]' "$text" "$HEAD" "$HEAD" 2 > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  assert_unchanged "$name"
}

case_human_comment() {
  local name=${FUNCNAME[0]} text="Please rename the helper." review="A walkthrough from octocat."
  empty_threads > "$work/${name}.threads.json"
  one_comment 304 octocat "$text" "$HEAD" "$HEAD" 3 > "$work/${name}.comments.json"
  one_review octocat COMMENTED "$HEAD" "$review" false > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  jq -e --arg t "$text" --arg r "$review" '
    .verdict == "FIX"
    and (.outstanding | length) == 2
    and .outstanding[0].text == $t
    and .outstanding[0].disposition == "addressed"
    and .outstanding[0].kind == "comment"
    and .outstanding[0].id == "304"
    and .outstanding[0].tag == "Review"
    and .outstanding[1].text == $r
    and .outstanding[1].disposition == "addressed"
    and .outstanding[1].kind == "review"
    and .outstanding[1].tag == "Review"
    and ([.fix[]? | select(. == "Review: " + $t or . == "Review: " + $r)] | length) == 2
  ' "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): an octocat comment or review on the head stayed PASS"
}

case_approved_review() {
  local name=${FUNCNAME[0]}
  empty_threads > "$work/${name}.threads.json"
  no_comments > "$work/${name}.comments.json"
  one_review 'coderabbitai[bot]' APPROVED "$HEAD" "Looks good." false > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  assert_unchanged "$name"
}

case_old_changes_requested() {
  local name=${FUNCNAME[0]}
  empty_threads > "$work/${name}.threads.json"
  no_comments > "$work/${name}.comments.json"
  one_review 'coderabbitai[bot]' CHANGES_REQUESTED "$OLD" "Old requested change." false > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  assert_unchanged "$name"
}

case_outdated_review() {
  local name=${FUNCNAME[0]}
  empty_threads > "$work/${name}.threads.json"
  no_comments > "$work/${name}.comments.json"
  one_review 'coderabbitai[bot]' COMMENTED "$HEAD" "Stale walkthrough." true > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  assert_unchanged "$name"
}

case_null_position_comment() {
  local name=${FUNCNAME[0]} text="Position was cleared."
  empty_threads > "$work/${name}.threads.json"
  one_comment 305 'coderabbitai[bot]' "$text" "$HEAD" "$HEAD" null > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  assert_unchanged "$name"
}

case_posts_dispositions() {
  local name=${FUNCNAME[0]}
  local small="Rename the helper so the name matches the check."
  local secret="This change prints a secret in the log."
  two_threads 401 'coderabbitai[bot]' "$small" "$HEAD" 402 'coderabbitai[bot]' "$secret" "$HEAD" > "$work/${name}.threads.json"
  jq -n --arg head "$HEAD" --arg small "$small" --arg secret "$secret" '[
    {id:401, user:{login:"coderabbitai[bot]"}, body:$small, original_commit_id:$head, commit_id:$head, position:1},
    {id:402, user:{login:"coderabbitai[bot]"}, body:$secret, original_commit_id:$head, commit_id:$head, position:2}
  ]' > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS "$(jq -n --arg t "$small" '[$t + " - the name is internal"]')" '[]'
  apply_case "$name"
  jq -e --arg small "$small" --arg secret "$secret" '
    .verdict == "ESCALATE"
    and (.outstanding | length) == 2
    and .outstanding[0].text == $small
    and .outstanding[0].disposition == "dismissed: the name is internal"
    and .outstanding[1].text == $secret
    and .outstanding[1].disposition == "escalated"
  ' "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): mixed findings were not escalated with both dispositions"
  rm -f "${STATE}/ireview-posted-acme_software-factory-7-${HEAD}" \
    "${STATE}/ireview-reply-acme_software-factory-7-401" \
    "${STATE}/ireview-reply-acme_software-factory-7-402"
  local f
  f=$(ir_result_file acme/software-factory 7 "$HEAD")
  cp "$work/${name}.${LANE_NAME}.json" "$f"
  ir_post_comment acme/software-factory 7 "$HEAD" || fail "$name ($LANE_NAME): ir_post_comment failed"
  [[ -s "$GH_BODY" ]] || fail "$name ($LANE_NAME): comment body was not recorded"
  grep -F -q '**Independent review (after CodeRabbit): ESCALATE**' "$GH_BODY" \
    || fail "$name ($LANE_NAME): posted verdict is not ESCALATE"
  grep -F -q 'Outstanding CodeRabbit findings:' "$GH_BODY" \
    || fail "$name ($LANE_NAME): comment has no outstanding list"
  grep -F -q "${small} — dismissed: the name is internal" "$GH_BODY" \
    || fail "$name ($LANE_NAME): comment lacks the dismissed disposition"
  grep -F -q "${secret} — escalated" "$GH_BODY" \
    || fail "$name ($LANE_NAME): comment lacks the escalated disposition"
  if grep -F -q 'CodeRabbit findings not blocking:' "$GH_BODY"; then
    fail "$name ($LANE_NAME): an open finding is still listed as not blocking"
  fi
  jq -e '
    length == 2
    and .[0].url == "repos/acme/software-factory/pulls/7/comments/401/replies"
    and .[0].body == "Independent review disposition: dismissed: the name is internal"
    and .[1].url == "repos/acme/software-factory/pulls/7/comments/402/replies"
    and .[1].body == "Independent review disposition: escalated"
    and ([.[].body | select(contains("@"))] | length) == 0
  ' <(jq -s '.' "$GH_REPLIES") >/dev/null || fail "$name ($LANE_NAME): thread replies missing or wrong"
  cp "$GH_BODY" "$work/${name}.${LANE_NAME}.comment"
  cp "$GH_REPLIES" "$work/${name}.${LANE_NAME}.replies"
}

case_human_thread_reply() {
  local name=${FUNCNAME[0]} text="Please rename the helper."
  one_thread false false scripts/foo.sh 501 octocat "$text" "$HEAD" > "$work/${name}.threads.json"
  one_comment 501 octocat "$text" "$HEAD" "$HEAD" 3 > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS "$(jq -n --arg t "$text" '[$t + " - not @coderabbitai"]')" '[]'
  apply_case "$name"
  jq -e --arg t "$text" '
    .verdict == "FIX"
    and .outstanding[0].kind == "thread"
    and .outstanding[0].id == "501"
    and .outstanding[0].tag == "Review"
    and .outstanding[0].text == $t
    and .outstanding[0].disposition == "dismissed: not @coderabbitai"
  ' "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): octocat thread was not blocking"
  rm -f "${STATE}/ireview-posted-acme_software-factory-7-${HEAD}" \
    "${STATE}/ireview-reply-acme_software-factory-7-501"
  local f
  f=$(ir_result_file acme/software-factory 7 "$HEAD")
  cp "$work/${name}.${LANE_NAME}.json" "$f"
  ir_post_comment acme/software-factory 7 "$HEAD" || fail "$name ($LANE_NAME): ir_post_comment failed"
  jq -e '
    length == 1
    and .[0].url == "repos/acme/software-factory/pulls/7/comments/501/replies"
    and .[0].body == "Independent review disposition: dismissed: not coderabbitai"
    and (.[0].body | contains("@") | not)
  ' <(jq -s '.' "$GH_REPLIES") >/dev/null || fail "$name ($LANE_NAME): disposition reply missing or still mentions @"
  ir_post_comment acme/software-factory 7 "$HEAD" || fail "$name ($LANE_NAME): second ir_post_comment failed"
  jq -e 'length == 1' <(jq -s '.' "$GH_REPLIES") >/dev/null \
    || fail "$name ($LANE_NAME): a second identical reply was posted"
  cp "$GH_REPLIES" "$work/${name}.${LANE_NAME}.replies"
}

case_reply_already_present() {
  local name=${FUNCNAME[0]}
  local text="Please rename the helper."
  local reply="Independent review disposition: addressed"
  jq -n --arg head "$HEAD" --arg text "$text" --arg reply "$reply" \
    '{data:{repository:{pullRequest:{reviewThreads:{pageInfo:{hasNextPage:false},nodes:[{
      isResolved:false, isOutdated:false, path:"scripts/foo.sh",
      comments:{nodes:[
        {databaseId:701, author:{login:"octocat"}, body:$text, originalCommit:{oid:$head}},
        {databaseId:702, author:{login:"factory-bot"}, body:$reply, originalCommit:{oid:$head}}
      ]}
    }]}}}}}' > "$work/${name}.threads.json"
  jq -n --arg head "$HEAD" --arg text "$text" --arg reply "$reply" '[
    {id:701, user:{login:"octocat"}, body:$text, original_commit_id:$head, commit_id:$head, position:4},
    {id:702, user:{login:"factory-bot"}, body:$reply, original_commit_id:$head, commit_id:$head, position:5}
  ]' > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  jq -e --arg t "$text" --arg reply "$reply" '
    .verdict == "FIX"
    and (.outstanding | length) == 1
    and .outstanding[0].text == $t
    and .outstanding[0].disposition == "addressed"
    and .outstanding[0].id == "701"
    and (.outstanding[0].seen | index($reply) != null)
  ' "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): existing reply changed the finding"
  rm -f "${STATE}/ireview-posted-acme_software-factory-7-${HEAD}" \
    "${STATE}/ireview-reply-acme_software-factory-7-701" \
    "${STATE}/ireview-reply-acme_software-factory-7-702"
  local f
  f=$(ir_result_file acme/software-factory 7 "$HEAD")
  cp "$work/${name}.${LANE_NAME}.json" "$f"
  ir_post_comment acme/software-factory 7 "$HEAD" || fail "$name ($LANE_NAME): ir_post_comment failed"
  [[ -s $GH_BODY ]] || fail "$name ($LANE_NAME): issue comment was not posted"
  jq -e 'length == 0' <(jq -s '.' "$GH_REPLIES") >/dev/null \
    || fail "$name ($LANE_NAME): posted a reply that was already on the thread"
  cp "$GH_REPLIES" "$work/${name}.${LANE_NAME}.replies"
}

threads_on_head() {
  local name=$1 prefix=$2 count=$3
  jq -n --arg sha "$HEAD" --arg prefix "$prefix" --argjson count "$count" '
    [range(1; $count + 1) | . as $n | {
      isResolved:false, isOutdated:false, path:"scripts/a.sh",
      comments:{nodes:[{
        databaseId:(1000 + $n),
        author:{login:"coderabbitai[bot]"},
        body:($prefix + (if $n < 10 then "0" else "" end) + ($n | tostring)),
        originalCommit:{oid:$sha}
      }]}
    }] as $nodes
    | {data:{repository:{pullRequest:{reviewThreads:{pageInfo:{hasNextPage:false},nodes:$nodes}}}}}
  ' > "$work/${name}.threads.json"
}

case_keep_model_fix() {
  local name=${FUNCNAME[0]}
  threads_on_head "$name" "coderabbit finding " 10
  no_comments > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  jq '.fix = ["Review: keep the model finding"]' "$work/${name}.result.json" > "$work/${name}.result.tmp"
  mv "$work/${name}.result.tmp" "$work/${name}.result.json"
  apply_case "$name"
  jq -e '
    (.fix | length) == 11
    and ([.fix[] | select(. == "Review: keep the model finding")] | length) == 1
    and ([.fix[] | select(startswith("CodeRabbit: coderabbit finding "))] | length) == 10
  ' "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): the model Review fix was dropped"
}

case_sixteen_outstanding() {
  local name=${FUNCNAME[0]} i f
  threads_on_head "$name" "outstanding finding " 16
  no_comments > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  jq -e '
    (.outstanding | length) == 16
    and (.fix | length) == 16
    and any(.outstanding[]; .text == "outstanding finding 16" and .disposition == "addressed")
  ' "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): a sixteenth outstanding finding was dropped"
  rm -f "${STATE}/ireview-posted-acme_software-factory-7-${HEAD}"
  f=$(ir_result_file acme/software-factory 7 "$HEAD")
  cp "$work/${name}.${LANE_NAME}.json" "$f"
  ir_post_comment acme/software-factory 7 "$HEAD" || fail "$name ($LANE_NAME): ir_post_comment failed"
  for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16; do
    grep -F -q -- "outstanding finding ${i} — addressed" "$GH_BODY" \
      || fail "$name ($LANE_NAME): posted comment lacks outstanding finding ${i}"
  done
}

case_split_outstanding() {
  local name=${FUNCNAME[0]} n f before after joined
  empty_threads > "$work/${name}.threads.json"
  no_comments > "$work/${name}.comments.json"
  jq -n --arg sha "$HEAD" '
    [range(1; 9) | . as $n | {
      user:{login:"octocat"},
      state:"COMMENTED",
      commit_id:$sha,
      body:("split finding " + (if $n < 10 then "0" else "" end) + ($n | tostring)),
      outdated:false
    }]
  ' > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  export IR_COMMENT_LIMIT=400
  rm -f "${STATE}/ireview-posted-acme_software-factory-8-${HEAD}"
  f=$(ir_result_file acme/software-factory 8 "$HEAD")
  cp "$work/${name}.${LANE_NAME}.json" "$f"
  ir_post_comment acme/software-factory 8 "$HEAD" || fail "$name ($LANE_NAME): split post failed"
  before=$(jq -s 'length' "$GH_ALL")
  [[ $before -gt 1 ]] || fail "$name ($LANE_NAME): report was not split (comments=${before})"
  joined=$(jq -rs '.[].body' "$GH_ALL")
  for n in 01 02 03 04 05 06 07 08; do
    grep -F -q -- "split finding ${n}" <<< "$joined" \
      || fail "$name ($LANE_NAME): split report dropped split finding ${n}"
  done
  [[ -e ${STATE}/ireview-posted-acme_software-factory-8-${HEAD} ]] \
    || fail "$name ($LANE_NAME): posted marker missing after the split"
  ir_post_comment acme/software-factory 8 "$HEAD" || fail "$name ($LANE_NAME): second post failed"
  after=$(jq -s 'length' "$GH_ALL")
  [[ $after -eq $before ]] || fail "$name ($LANE_NAME): second post added a comment (${before} -> ${after})"
  cp "$GH_ALL" "$work/${name}.${LANE_NAME}.all"
}

case_guard_fix_clears() {
  local name=${FUNCNAME[0]} text="Temporary open finding."
  one_thread false false scripts/foo.sh 901 'coderabbitai[bot]' "$text" "$HEAD" > "$work/${name}.threads.json"
  one_comment 901 'coderabbitai[bot]' "$text" "$HEAD" "$HEAD" 3 > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  jq -e --arg t "$text" '
    .verdict == "FIX"
    and .model_verdict == "PASS"
    and (.outstanding | length) == 1
    and .outstanding[0].text == $t
  ' "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): open finding did not become a guard FIX"
  printf '[]\n' > "$work/${name}.empty.json"
  ir_apply_open_coderabbit "$work/${name}.result.json" "$work/${name}.empty.json" \
    || fail "$name ($LANE_NAME): clearing an empty block failed"
  jq -e '
    .verdict == "PASS"
    and .model_verdict == "PASS"
    and (.outstanding | length) == 0
    and (.fix | length) == 0
  ' "$work/${name}.result.json" >/dev/null || fail "$name ($LANE_NAME): guard FIX stayed after the finding cleared"
  cp "$work/${name}.result.json" "$work/${name}.${LANE_NAME}.json"
}

case_factory_bot_empty_commented() {
  local name=${FUNCNAME[0]}
  empty_threads > "$work/${name}.threads.json"
  no_comments > "$work/${name}.comments.json"
  jq -n --arg sha "$HEAD" '[
    {user:{login:"software-factory-line[bot]"}, state:"COMMENTED", commit_id:$sha, body:"", outdated:false},
    {user:{login:"software-factory-line[bot]"}, state:"COMMENTED", commit_id:$sha, body:"  \n", outdated:false}
  ]' > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  assert_unchanged "$name"
}

case_factory_bot_real_body_blocks() {
  local name=${FUNCNAME[0]} text="The cap split is wrong."
  empty_threads > "$work/${name}.threads.json"
  no_comments > "$work/${name}.comments.json"
  one_review 'software-factory-line[bot]' COMMENTED "$HEAD" "$text" false > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  jq -e --arg t "$text" '.verdict == "FIX" and .outstanding[0].text == $t and .outstanding[0].kind == "review"' \
    "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): a factory-bot review with a real body stayed PASS"
}

case_real_reviews_block_beside_factory_wrapper() {
  local name=${FUNCNAME[0]} human="Please rename the helper." bot="Handle the empty list."
  empty_threads > "$work/${name}.threads.json"
  no_comments > "$work/${name}.comments.json"
  jq -n --arg sha "$HEAD" --arg human "$human" --arg bot "$bot" '[
    {user:{login:"software-factory-line[bot]"}, state:"COMMENTED", commit_id:$sha, body:"", outdated:false},
    {user:{login:"octocat"}, state:"COMMENTED", commit_id:$sha, body:$human, outdated:false},
    {user:{login:"coderabbitai[bot]"}, state:"CHANGES_REQUESTED", commit_id:$sha, body:$bot, outdated:false}
  ]' > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" PASS '[]' '[]'
  apply_case "$name"
  jq -e --arg human "$human" --arg bot "$bot" '
    .verdict == "FIX"
    and (.outstanding | length) == 2
    and .outstanding[0].text == $human
    and .outstanding[0].tag == "Review"
    and .outstanding[1].text == $bot
    and .outstanding[1].tag == "CodeRabbit"
    and ([.outstanding[].text | select(test("COMMENTED on this head"))] | length) == 0
  ' "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): empty factory wrapper blocked, or a real review did not"
}

case_model_fix_empty_stays() {
  local name=${FUNCNAME[0]} text="A guard finding that later clears."
  one_thread false false scripts/foo.sh 903 'coderabbitai[bot]' "$text" "$HEAD" > "$work/${name}.threads.json"
  one_comment 903 'coderabbitai[bot]' "$text" "$HEAD" "$HEAD" 5 > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" FIX '[]' '[]'
  apply_case "$name"
  jq -e '
    .verdict == "FIX"
    and .model_verdict == "FIX"
    and (.model_fix | length) == 0
    and ([.fix[] | select(startswith("CodeRabbit:"))] | length) == 1
  ' "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): guard did not keep an empty model fix list"
  printf '[]\n' > "$work/${name}.empty.json"
  ir_apply_open_coderabbit "$work/${name}.result.json" "$work/${name}.empty.json" \
    || fail "$name ($LANE_NAME): clearing an empty block failed"
  jq -e '
    .verdict == "FIX"
    and (.outstanding | length) == 0
    and (.fix | length) == 0
  ' "$work/${name}.result.json" >/dev/null || fail "$name ($LANE_NAME): empty model FIX was coerced away from FIX"
  cp "$work/${name}.result.json" "$work/${name}.${LANE_NAME}.json"
}

case_model_fix_stays() {
  local name=${FUNCNAME[0]} text="A guard finding that later clears."
  one_thread false false scripts/foo.sh 902 'coderabbitai[bot]' "$text" "$HEAD" > "$work/${name}.threads.json"
  one_comment 902 'coderabbitai[bot]' "$text" "$HEAD" "$HEAD" 4 > "$work/${name}.comments.json"
  no_reviews > "$work/${name}.reviews.json"
  write_result "$work/${name}.result.json" FIX '[]' '[]'
  jq '.fix = ["Review: keep the model finding"]' "$work/${name}.result.json" > "$work/${name}.result.tmp"
  mv "$work/${name}.result.tmp" "$work/${name}.result.json"
  apply_case "$name"
  jq -e '
    .verdict == "FIX"
    and .model_verdict == "FIX"
    and ([.fix[] | select(. == "Review: keep the model finding")] | length) == 1
    and ([.fix[] | select(startswith("CodeRabbit:"))] | length) == 1
  ' "$work/${name}.${LANE_NAME}.json" >/dev/null || fail "$name ($LANE_NAME): guard did not keep the model fix beside its own"
  printf '[]\n' > "$work/${name}.empty.json"
  ir_apply_open_coderabbit "$work/${name}.result.json" "$work/${name}.empty.json" \
    || fail "$name ($LANE_NAME): clearing an empty block failed"
  jq -e '
    .verdict == "FIX"
    and (.outstanding | length) == 0
    and .fix == ["Review: keep the model finding"]
  ' "$work/${name}.result.json" >/dev/null || fail "$name ($LANE_NAME): model FIX was cleared with the guard finding"
  cp "$work/${name}.result.json" "$work/${name}.${LANE_NAME}.json"
}

case_guard_read_failure() {
  local name=${FUNCNAME[0]} f rc=0
  f=$(ir_result_file acme/software-factory 9 "$HEAD")
  write_result "$f" PASS '[]' '[]'
  : > "$LOG"
  ir_guard_open_coderabbit acme/software-factory 9 "$f" "$HEAD" || rc=$?
  [[ $rc -ne 0 ]] || fail "$name ($LANE_NAME): a failed read returned success"
  jq -e '.verdict == "PASS" and ((.fix // []) | length) == 0' "$f" >/dev/null \
    || fail "$name ($LANE_NAME): a failed read changed the saved PASS"
  [[ ! -e ${STATE}/ireview-posted-acme_software-factory-9-${HEAD} ]] \
    || fail "$name ($LANE_NAME): a failed read wrote the posted marker"
  grep -F -q 'not posting' "$LOG" || fail "$name ($LANE_NAME): failed read was not logged as not posting"
  cp "$f" "$work/${name}.${LANE_NAME}.json"
}

for fn in \
  case_dismissed_thread \
  case_addressed_thread \
  case_secret_escalates \
  case_comment_only \
  case_commented_review \
  case_changes_requested \
  case_outdated_thread \
  case_earlier_commit \
  case_resolved_thread \
  case_human_comment \
  case_human_thread_reply \
  case_reply_already_present \
  case_approved_review \
  case_old_changes_requested \
  case_outdated_review \
  case_null_position_comment \
  case_posts_dispositions \
  case_keep_model_fix \
  case_sixteen_outstanding \
  case_split_outstanding \
  case_factory_bot_empty_commented \
  case_factory_bot_real_body_blocks \
  case_real_reviews_block_beside_factory_wrapper \
  case_guard_fix_clears \
  case_model_fix_empty_stays \
  case_model_fix_stays \
  case_guard_read_failure
do
  both_lanes "$fn"
  pass "$fn"
done

cmp -s "$work/case_posts_dispositions.watch.comment" "$work/case_posts_dispositions.watch.new.comment" \
  || fail "posted comments differ between lanes"
pass "posted comments match"
cmp -s "$work/case_posts_dispositions.watch.replies" "$work/case_posts_dispositions.watch.new.replies" \
  || fail "thread replies differ between lanes"
cmp -s "$work/case_human_thread_reply.watch.replies" "$work/case_human_thread_reply.watch.new.replies" \
  || fail "human thread replies differ between lanes"
cmp -s "$work/case_reply_already_present.watch.replies" "$work/case_reply_already_present.watch.new.replies" \
  || fail "already-present replies differ between lanes"
cmp -s "$work/case_split_outstanding.watch.all" "$work/case_split_outstanding.watch.new.all" \
  || fail "split reports differ between lanes"
pass "thread replies match"

echo "all open-coderabbit independent-review tests passed"
