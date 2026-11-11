#!/usr/bin/env bash
# Offline tests for the watcher dismiss gate, focus list, and in-flight cap.
# A fake gh is first on PATH. This suite does not use the network.
# It sources scripts/watcher/watch.sh and scripts/watcher/watch.new.sh.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

export FACTORY_WATCH_ROOT="$work/root"
export FACTORY_BUDGET_FILE="$work/budget.json"
export FACTORY_LEDGER_FILE="$work/ledger.csv"
# Fixture repos. The watcher reads its allowlist and home repo from these.
export FACTORY_HOME_REPO=acme/software-factory
export FACTORY_REPOS="acme/software-factory acme/gh-factory acme/activity-feed acme/line acme/acme"
unset FACTORY_BLOCKED_OWNERS
export GH_ROOT="$work/gh"
export GH_LOG="$work/gh.log"
# The watcher sets these when sourced. t_budget also runs before that.
BUDGET="$FACTORY_BUDGET_FILE"
STATE="${FACTORY_WATCH_ROOT}/state"
WORK="${FACTORY_WATCH_ROOT}/work"
LOG="${FACTORY_WATCH_ROOT}/watch.log"

mkdir -p "$work/bin"
# ready-gate.sh has its own suite (test-ready-gate.sh). Here it is stubbed to
# pass so this suite keeps testing only its own script.
printf '#!/usr/bin/env bash\nexit 0\n' > "$work/ready-gate-stub.sh"
chmod +x "$work/ready-gate-stub.sh"
export READY_GATE_CMD="$work/ready-gate-stub.sh"
cat > "$work/bin/gh" << 'ENDGH'
#!/bin/bash
set -u
printf '%s\n' "$*" >> "${GH_LOG:?}"

seq_pick() {
  local base=$1 key cfile n=0
  key=$(printf '%s' "$base" | tr '/' '_')
  mkdir -p "${GH_ROOT}/counts"
  cfile="${GH_ROOT}/counts/${key}"
  if [[ -f $cfile ]]; then
    n=$(tr -cd '0-9' < "$cfile")
    n=${n:-0}
  fi
  n=$((n + 1))
  printf '%s\n' "$n" > "$cfile"
  if [[ -f ${base}.${n}.json ]]; then
    printf '%s\n' "${base}.${n}.json"
    return 0
  fi
  if [[ -f ${base}.json ]]; then
    printf '%s\n' "${base}.json"
    return 0
  fi
  return 1
}

emit() {
  local file=$1 filter=${2:-}
  if [[ -n $filter ]]; then
    jq -r "$filter" "$file"
  else
    cat "$file"
  fi
}

cmd=${1:-}
shift || true
case "$cmd" in
  pr)
    sub=${1:-}
    shift || true
    case "$sub" in
      view)
        num=${1:-}
        shift || true
        repo="" filter=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            -R|--repo) repo=$2; shift 2 ;;
            --jq) filter=$2; shift 2 ;;
            --json) shift; [[ $# -gt 0 ]] && shift ;;
            *) shift ;;
          esac
        done
        slug=${repo//\//_}
        file=$(seq_pick "$GH_ROOT/view/${slug}_${num}") || exit 1
        emit "$file" "$filter"
        ;;
      merge)
        [[ -f $GH_ROOT/fail-merge ]] && exit 1
        exit 0
        ;;
      list)
        repo=""
        author=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            -R|--repo) repo=$2; shift 2 ;;
            --author) author=$2; shift 2 ;;
            *) shift ;;
          esac
        done
        slug=${repo//\//_}
        if [[ $author == app/dependabot && -f $GH_ROOT/dependabot/${slug}.json ]]; then
          cat "$GH_ROOT/dependabot/${slug}.json"
        else
          printf '%s\n' '[]'
        fi
        ;;
      comment|checks|close) exit 0 ;;
      *) echo "fake gh: unhandled pr $sub" >&2; exit 99 ;;
    esac
    ;;
  issue)
    sub=${1:-}
    shift || true
    case "$sub" in
      list)
        repo=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            -R|--repo) repo=$2; shift 2 ;;
            *) shift ;;
          esac
        done
        slug=${repo//\//_}
        if [[ -f $GH_ROOT/issues/${slug}.json ]]; then
          cat "$GH_ROOT/issues/${slug}.json"
        else
          printf '%s\n' '[]'
        fi
        ;;
      view)
        num=${1:-}
        shift || true
        repo="" filter=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            -R|--repo) repo=$2; shift 2 ;;
            --jq) filter=$2; shift 2 ;;
            --json) shift; [[ $# -gt 0 ]] && shift ;;
            *) shift ;;
          esac
        done
        slug=${repo//\//_}
        file="$GH_ROOT/issue/${slug}_${num}.json"
        [[ -f $file ]] || exit 1
        emit "$file" "$filter"
        ;;
      edit) exit 0 ;;
      *) echo "fake gh: unhandled issue $sub" >&2; exit 99 ;;
    esac
    ;;
  api)
    method=GET
    filter=""
    path=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --paginate) shift ;;
        --method|-X) method=$2; shift 2 ;;
        --jq) filter=$2; shift 2 ;;
        -f|--raw-field) shift 2 ;;
        -H|--header) shift 2 ;;
        repos/*|user) path=$1; shift ;;
        *) shift ;;
      esac
    done
    if [[ $method == PUT || $method == put ]]; then
      if [[ -f $GH_ROOT/fail-dismiss ]]; then
        echo "dismiss failed" >&2
        exit 1
      fi
      printf '%s\n' '{}'
      exit 0
    fi
    if [[ $path == user ]]; then
      printf '%s\n' '{"login":"factory"}'
      exit 0
    fi
    if [[ $path =~ ^repos/([^/]+/[^/]+)/pulls/([0-9]+)/reviews$ ]]; then
      repo=${BASH_REMATCH[1]}
      num=${BASH_REMATCH[2]}
      slug=${repo//\//_}
      file=$(seq_pick "$GH_ROOT/reviews/${slug}_${num}") || exit 1
      emit "$file" "$filter"
      exit 0
    fi
    if [[ $path =~ ^repos/([^/]+/[^/]+)/pulls/([0-9]+)/files$ ]]; then
      repo=${BASH_REMATCH[1]}
      num=${BASH_REMATCH[2]}
      slug=${repo//\//_}
      file=$(seq_pick "$GH_ROOT/files/${slug}_${num}") || exit 1
      emit "$file" "$filter"
      exit 0
    fi
    if [[ $path =~ ^repos/([^/]+/[^/]+)/issues/([0-9]+)/comments$ ]]; then
      repo=${BASH_REMATCH[1]}
      num=${BASH_REMATCH[2]}
      slug=${repo//\//_}
      file="$GH_ROOT/comments/${slug}_${num}.json"
      if [[ ! -f $file ]]; then
        printf '%s\n' '[]' > "$GH_ROOT/empty.json"
        file="$GH_ROOT/empty.json"
      fi
      emit "$file" "$filter"
      exit 0
    fi
    if [[ $path =~ ^repos/([^/]+/[^/]+)/pulls/([0-9]+)/commits$ ]]; then
      printf '%s\n' '[]' > "$GH_ROOT/empty.json"
      emit "$GH_ROOT/empty.json" "$filter"
      exit 0
    fi
    echo "fake gh: unhandled api $path" >&2
    exit 99
    ;;
  repo)
    sub=${1:-}
    shift || true
    if [[ $sub == clone ]]; then
      dest=${2:-}
      [[ -n $dest ]] || exit 99
      mkdir -p "$dest"
      git init -q "$dest"
      git -C "$dest" checkout -q -B main
      git -C "$dest" -c user.email=factory@example.com -c user.name=factory commit --allow-empty -q -m init
      exit 0
    fi
    echo "fake gh: unhandled repo $sub" >&2
    exit 99
    ;;
  *)
    echo "fake gh: unhandled $cmd" >&2
    exit 99
    ;;
esac
ENDGH
chmod +x "$work/bin/gh"
for cmd in curl wget ssh; do
  cat > "$work/bin/$cmd" << EOF
#!/bin/sh
echo "refusing $cmd" >&2
exit 99
EOF
  chmod +x "$work/bin/$cmd"
done
export PATH="$work/bin:$PATH"

SHA_HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
SHA_BASE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
SHA_OLD=cccccccccccccccccccccccccccccccccccccccc
CHECKS_OK='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS","name":"tests"}]'
CHECKS_BAD='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE","name":"tests"}]'

t_slug() { printf '%s' "${1//\//_}"; }

t_budget() {
  local cap=$1 focus=$2 allow=$3
  if [[ $cap == unset ]]; then
    jq -n --argjson focus "$focus" --argjson allow "$allow" \
      '{max_grok_build_runs_per_week:20,max_grok_build_runs_per_day:20,max_runs_per_loop:5,max_coderabbit_requests_per_hour:8,focus_issues:$focus,merge_protected_issues:$allow}' \
      > "$BUDGET"
  else
    jq -n --argjson cap "$cap" --argjson focus "$focus" --argjson allow "$allow" \
      '{max_grok_build_runs_per_week:20,max_grok_build_runs_per_day:20,max_runs_per_loop:5,max_coderabbit_requests_per_hour:8,max_issues_in_flight:$cap,focus_issues:$focus,merge_protected_issues:$allow}' \
      > "$BUDGET"
  fi
}

t_fixture() {
  local kind=$1 repo=$2 pr=$3 seq=${4:-}
  local slug
  slug=$(t_slug "$repo")
  mkdir -p "$GH_ROOT/$kind"
  if [[ -n $seq ]]; then
    printf '%s\n' "$GH_ROOT/$kind/${slug}_${pr}.${seq}.json"
  else
    printf '%s\n' "$GH_ROOT/$kind/${slug}_${pr}.json"
  fi
}

t_view() {
  local repo=$1 pr=$2 sha=$3 merge=$4 body=$5 title=$6 branch=$7 checks=$8 seq=${9:-}
  local dest when
  dest=$(t_fixture view "$repo" "$pr" "$seq")
  when=${t_when:-2026-11-01T00:00:00Z}
  jq -n \
    --arg sha "$sha" --arg base "$SHA_BASE" --arg merge "$merge" \
    --arg body "$body" --arg title "$title" --arg branch "$branch" \
    --arg url "https://github.com/${repo}/pull/${pr}" \
    --arg when "$when" --argjson checks "$checks" \
    '{headRefOid:$sha,baseRefOid:$base,mergeStateStatus:$merge,statusCheckRollup:$checks,body:$body,title:$title,headRefName:$branch,url:$url,state:"OPEN",commits:[{oid:$sha,committedDate:$when}]}' \
    > "$dest"
}

t_files() {
  local repo=$1 pr=$2 name=$3
  local dest
  dest=$(t_fixture files "$repo" "$pr")
  jq -n --arg name "$name" '[{status:"modified",filename:$name,previous_filename:null}]' > "$dest"
}

t_ir() {
  local repo=$1 pr=$2 sha=$3 verdict=${4:-PASS}
  local slug
  slug=$(t_slug "$repo")
  printf '{"verdict":"%s","summary":"summary line","fix":[],"dismissed":[],"escalate":[]}\n' "$verdict" \
    > "${STATE}/ireview-result-${slug}-${pr}-${sha}.json"
}

t_gate() {
  local expect=$1 repo=$2 pr=$3 rc=0
  merge_gate "$repo" "$pr" || rc=$?
  [[ $rc == "$expect" ]] || fail "merge_gate ${repo}#${pr} rc=${rc} want ${expect} (${GATE_REASON})"
}

t_logged() {
  grep -F -q -- "$1" "$LOG" || fail "log missing: $1"
}

t_not_logged() {
  if grep -F -q -- "$1" "$LOG"; then
    fail "log unexpectedly has: $1"
  fi
}

t_has_dismiss() {
  grep -F -q -- "reviews/${1}/dismissals" "$GH_LOG" || fail "review ${1} was not dismissed"
}

t_no_dismiss() {
  if grep -F -q -- "reviews/${1}/dismissals" "$GH_LOG"; then
    fail "review ${1} was dismissed"
  fi
}

t_no_merge() {
  if grep -F -q -- "pr merge" "$GH_LOG"; then
    fail "pull request was merged"
  fi
}

t_yes_merge() {
  grep -F -q -- "pr merge" "$GH_LOG" || fail "pull request was not merged"
}

t_helpers() {
  local fn
  for fn in pr_in_focus cr_changes_block cr_dismiss_ids dismiss_cr_changes drop_gate_reads focus_is_set issue_in_focus max_issues_in_flight count_open_in_flight; do
    # shellcheck disable=SC2310
    declare -F "$fn" >/dev/null || fail "missing ${fn}"
  done
}

t_dismiss_set() {
  local f="$CYCLE_DIR/mapped-reviews.jsonl" ids
  jq -c '.[]' > "$f" << 'EOF'
[
  {"id":101,"user":"coderabbitai[bot]","state":"CHANGES_REQUESTED","commit_id":"old"},
  {"id":102,"user":"coderabbitai[bot]","state":"CHANGES_REQUESTED","commit_id":"head"},
  {"id":0,"user":"coderabbitai[bot]","state":"CHANGES_REQUESTED","commit_id":"head"},
  {"id":103,"user":"coderabbitai[bot]","state":"COMMENTED","commit_id":"head"},
  {"id":303,"user":"acme","state":"COMMENTED","commit_id":"head"}
]
EOF
  [[ $(cr_changes_block "$f") == bot ]] || fail "bot-only block kind"
  ids=$(cr_dismiss_ids "$f")
  printf '%s\n' "$ids" | grep -qx 101 || fail "dismiss set missing 101"
  printf '%s\n' "$ids" | grep -qx 102 || fail "dismiss set missing 102"
  printf '%s\n' "$ids" | grep -qx 103 && fail "commented review in dismiss set"
  printf '%s\n' "$ids" | grep -qx 303 && fail "human comment in dismiss set"
  printf '%s\n' "$ids" | grep -qx 0 && fail "id 0 in dismiss set"
  jq -c '.[]' > "$f" << 'EOF'
[
  {"id":101,"user":"coderabbitai[bot]","state":"CHANGES_REQUESTED","commit_id":"old"},
  {"id":404,"user":"acme","state":"CHANGES_REQUESTED","commit_id":"head"}
]
EOF
  [[ $(cr_changes_block "$f") == human ]] || fail "human block kind"
  [[ -z $(cr_dismiss_ids "$f") ]] || fail "human CHANGES_REQUESTED produced a dismiss set"
  : > "$f"
  [[ $(cr_changes_block "$f") == none ]] || fail "empty file block kind"
}

t_arm() {
  local repo=$1 pr=$2 merge=$3 file=$4 reviews=$5 body=$6 title=${7:-feat} branch=${8:-factory/199-test} checks=${9:-$CHECKS_OK} sha=${10:-$SHA_HEAD}
  t_view "$repo" "$pr" "$sha" "$merge" "$body" "$title" "$branch" "$checks"
  t_files "$repo" "$pr" "$file"
  printf '%s\n' "$reviews" > "$(t_fixture reviews "$repo" "$pr")"
  t_ir "$repo" "$pr" "$sha" PASS
}

bot() {
  local id=$1 state=$2 commit=$3
  printf '{"id":%s,"user":{"login":"coderabbitai[bot]"},"state":"%s","commit_id":"%s","submitted_at":"2026-11-01T00:00:00Z"}' "$id" "$state" "$commit"
}

human() {
  local id=$1 state=$2
  printf '{"id":%s,"user":{"login":"acme"},"state":"%s","commit_id":"%s","submitted_at":"2026-11-01T00:00:00Z"}' "$id" "$state" "$SHA_HEAD"
}

t_gate_matrix() {
  local repo=acme/software-factory
  t_budget 0 '[]' '["acme/software-factory#199"]'
  local one two
  one=$(bot 101 CHANGES_REQUESTED "$SHA_OLD")
  two="[${one},$(bot 102 CHANGES_REQUESTED "$SHA_HEAD"),$(bot 103 COMMENTED "$SHA_HEAD"),$(human 303 COMMENTED)]"
  t_arm "$repo" 11 BLOCKED README.md "[${one}]" "ordinary older review"
  t_gate 6 "$repo" 11
  t_arm "$repo" 12 BLOCKED README.md "$two" "ordinary two bot reviews"
  t_gate 6 "$repo" 12
  t_arm "$repo" 13 BLOCKED README.md "[$(human 404 CHANGES_REQUESTED)]" "human only"
  t_gate 1 "$repo" 13
  t_arm "$repo" 14 BLOCKED README.md "[${one},$(human 404 CHANGES_REQUESTED)]" "human and bot"
  t_gate 1 "$repo" 14
  t_arm "$repo" 15 BLOCKED AGENTS.md "[${one}]" "no close ref" "sensitive"
  t_gate 2 "$repo" 15
  t_arm "$repo" 16 BLOCKED AGENTS.md "[${one}]" $'Closes #199\n' "allow blocked"
  t_gate 6 "$repo" 16
  t_arm "$repo" 17 CLEAN AGENTS.md "[${one}]" $'Closes #199\n' "allow clean"
  t_gate 0 "$repo" 17
  t_arm "$repo" 18 CLEAN README.md "[${one}]" "ordinary clean"
  t_gate 0 "$repo" 18
  t_arm "$repo" 19 BLOCKED README.md "[$(bot 105 APPROVED "$SHA_HEAD")]" "approved only"
  t_gate 1 "$repo" 19
  t_arm "$repo" 20 BLOCKED README.md "[${one}]" "red checks" feat factory/199-test "$CHECKS_BAD"
  t_gate 1 "$repo" 20
  t_view "$repo" 21 "$SHA_HEAD" BLOCKED "no verdict" "no verdict" factory/199-test "$CHECKS_OK"
  t_files "$repo" 21 README.md
  printf '%s\n' "[${one}]" > "$(t_fixture reviews "$repo" 21)"
  t_gate 1 "$repo" 21
  t_arm "$repo" 22 BLOCKED README.md "[${one}]" "non factory" feat feature/199
  t_gate 1 "$repo" 22
}

t_prepare_merge() {
  local repo=$1 pr=$2 merge1=$3 merge2=$4 file=$5 body=$6 reviews1=$7 reviews2=$8
  t_view "$repo" "$pr" "$SHA_HEAD" "$merge1" "$body" "feat" factory/199-test "$CHECKS_OK" 1
  if [[ -n $merge2 ]]; then
    t_view "$repo" "$pr" "$SHA_HEAD" "$merge2" "$body" "feat" factory/199-test "$CHECKS_OK" 2
  fi
  t_files "$repo" "$pr" "$file"
  printf '%s\n' "$reviews1" > "$(t_fixture reviews "$repo" "$pr" 1)"
  if [[ -n $reviews2 ]]; then
    printf '%s\n' "$reviews2" > "$(t_fixture reviews "$repo" "$pr" 2)"
  fi
  t_ir "$repo" "$pr" "$SHA_HEAD" PASS
  PR_IDS=("${repo}|${pr}")
}

t_bot_pair() {
  printf '[%s,%s,%s,%s]' \
    "$(bot 101 CHANGES_REQUESTED "$SHA_OLD")" \
    "$(bot 102 CHANGES_REQUESTED "$SHA_HEAD")" \
    "$(bot 103 COMMENTED "$SHA_HEAD")" \
    "$(human 303 COMMENTED)"
}

t_bot_clear() {
  printf '[%s,%s,%s,%s]' \
    "$(bot 101 DISMISSED "$SHA_OLD")" \
    "$(bot 102 DISMISSED "$SHA_HEAD")" \
    "$(bot 103 COMMENTED "$SHA_HEAD")" \
    "$(human 303 COMMENTED)"
}

t_merge_ordinary() {
  local repo=acme/software-factory
  t_budget 0 '[]' '[]'
  t_prepare_merge "$repo" 7 BLOCKED CLEAN README.md "ordinary" "$(t_bot_pair)" "$(t_bot_clear)"
  step_merge
  t_has_dismiss 101
  t_has_dismiss 102
  t_no_dismiss 103
  t_no_dismiss 303
  t_yes_merge
  [[ ! -e ${STATE}/crblock-acme_software-factory-7-${SHA_HEAD} ]] || fail "ordinary dismiss reported to Scott"
  t_logged "recheck gate=merge"
}

t_merge_dismiss_fails() {
  local repo=acme/software-factory
  t_budget 0 '[]' '[]'
  t_prepare_merge "$repo" 7 BLOCKED CLEAN README.md "ordinary" "$(t_bot_pair)" "$(t_bot_clear)"
  : > "$GH_ROOT/fail-dismiss"
  step_merge
  t_no_merge
  [[ -e ${STATE}/crblock-acme_software-factory-7-${SHA_HEAD} ]] || fail "failed dismiss was not reported"
  t_not_logged "recheck gate="
}

t_merge_recheck_blocked() {
  local repo=acme/software-factory
  t_budget 0 '[]' '[]'
  t_prepare_merge "$repo" 7 BLOCKED BLOCKED README.md "ordinary" "$(t_bot_pair)" "$(t_bot_pair)"
  step_merge
  t_has_dismiss 101
  t_has_dismiss 102
  t_no_merge
  [[ ! -e ${STATE}/crblock-acme_software-factory-7-${SHA_HEAD} ]] || fail "recheck reported to Scott"
  t_logged "recheck returned 6; not merging"
}

t_merge_human() {
  local repo=acme/software-factory
  local reviews
  reviews="[$(bot 101 CHANGES_REQUESTED "$SHA_HEAD"),$(human 404 CHANGES_REQUESTED)]"
  t_budget 0 '[]' '[]'
  t_prepare_merge "$repo" 8 BLOCKED CLEAN README.md "human" "$reviews" ""
  step_merge
  t_no_dismiss 101
  t_no_dismiss 404
  t_no_merge
  [[ ! -e ${STATE}/crblock-acme_software-factory-8-${SHA_HEAD} ]] || fail "human review reported as crblock"
}

t_merge_sensitive() {
  local repo=acme/software-factory
  t_budget 0 '[]' '[]'
  t_prepare_merge "$repo" 9 BLOCKED CLEAN AGENTS.md "no close" "[$(bot 101 CHANGES_REQUESTED "$SHA_OLD")]" ""
  step_merge
  t_no_dismiss 101
  t_no_merge
  [[ -e ${STATE}/ready-acme_software-factory-9-${SHA_HEAD} ]] || fail "sensitive PR was not handed to Scott"
  [[ ! -e ${STATE}/crblock-acme_software-factory-9-${SHA_HEAD} ]] || fail "sensitive PR dismissed path"
}

t_merge_allow_blocked() {
  local repo=acme/software-factory
  t_budget 0 '[]' '["acme/software-factory#199"]'
  t_prepare_merge "$repo" 10 BLOCKED CLEAN AGENTS.md $'Closes #199\n' "[$(bot 101 CHANGES_REQUESTED "$SHA_OLD")]" "[$(bot 101 DISMISSED "$SHA_OLD")]"
  step_merge
  t_has_dismiss 101
  t_yes_merge
  t_logged "recheck gate=merge"
}

t_merge_allow_clean() {
  local repo=acme/software-factory
  t_budget 0 '[]' '["acme/software-factory#199"]'
  t_prepare_merge "$repo" 10 CLEAN "" AGENTS.md $'Closes #199\n' "[$(bot 101 CHANGES_REQUESTED "$SHA_HEAD")]" ""
  step_merge
  t_no_dismiss 101
  t_yes_merge
}

t_focus_rules() {
  local rc=0
  t_budget 0 '["acme/software-factory#199","acme/gh-factory#10"]' '[]'
  pr_in_focus acme/software-factory "feat" $'Closes #199\n' || fail "close ref"
  pr_in_focus acme/gh-factory "fix (#10)" "nothing" || fail "title (#N)"
  pr_in_focus acme/gh-factory "elsewhere" "see https://github.com/acme/software-factory/issues/199" || fail "issue url"
  pr_in_focus acme/activity-feed "elsewhere" "see acme/software-factory#199" || fail "owner ref"
  pr_in_focus acme/line "elsewhere" "see software-factory#199" || fail "short ref"
  pr_in_focus acme/software-factory "note" "see #199 please" || fail "bare ref inside software-factory"
  pr_in_focus acme/gh-factory "bump" "see #199" && fail "bare ref outside software-factory"
  pr_in_focus acme/gh-factory "bump" "no refs here" && fail "unrelated"
  pr_in_focus acme/software-factory "x" $'Closes acme/gh-factory#10\n' && fail "other repo close is not a bare software-factory ref"
  t_budget unset '[]' '[]'
  pr_in_focus acme/gh-factory "bump" "no refs here" || fail "empty focus should accept"
  t_budget unset '[]' '[]'
  jq 'del(.focus_issues)' "$BUDGET" > "$BUDGET.tmp"
  mv "$BUDGET.tmp" "$BUDGET"
  pr_in_focus acme/gh-factory "bump" "no refs here" || fail "missing focus should accept"
  rc=0
  : "$rc"
}

t_issue_line() {
  local repo=$1 num=$2 label=$3 body=$4
  jq -nc --arg repo "$repo" --argjson num "$num" --arg label "$label" --arg body "$body" \
    '{repo:$repo,number:$num,title:"t",body:$body,createdAt:"2026-11-01T00:00:00Z",labels:[{name:$label}]}'
}

t_steps_focus() {
  local line_a line_b
  DRY=1
  # Fixture only: step_build reads the approver's comments with gh issue view,
  # and a failed read skips the issue. These two issues have no comments.
  mkdir -p "$GH_ROOT/issue"
  jq -n '{comments:[]}' > "$GH_ROOT/issue/$(t_slug acme/software-factory)_199.json"
  jq -n '{comments:[]}' > "$GH_ROOT/issue/$(t_slug acme/gh-factory)_10.json"
  t_budget 0 '["acme/software-factory#199"]' '[]'
  line_a=$(t_issue_line acme/software-factory 199 factory:ready $'Target repo: acme/software-factory\n')
  line_b=$(t_issue_line acme/gh-factory 10 factory:ready "no target")
  ISSUE_CACHE="$STATE/issues.jsonl"
  printf '%s\n%s\n' "$line_a" "$line_b" > "$ISSUE_CACHE"
  step_build
  t_logged "DRY-RUN would build acme/software-factory#199"
  t_logged "build skip acme/gh-factory#10: not in focus_issues"
  t_not_logged "factory:blocked"
  : > "$LOG"
  t_reset_grok
  line_a=$(t_issue_line acme/software-factory 199 factory:triage "body")
  line_b=$(t_issue_line acme/gh-factory 10 factory:triage "body")
  printf '%s\n%s\n' "$line_a" "$line_b" > "$ISSUE_CACHE"
  step_triage
  t_logged "DRY-RUN would triage acme/software-factory#199"
  t_logged "triage skip acme/gh-factory#10: not in focus_issues"
  : > "$LOG"
  t_reset_grok
  t_budget 0 '[]' '[]'
  line_a=$(t_issue_line acme/software-factory 199 factory:ready $'Target repo: acme/software-factory\n')
  line_b=$(t_issue_line acme/gh-factory 10 factory:ready $'Target repo: acme/gh-factory\n')
  printf '%s\n%s\n' "$line_a" "$line_b" > "$ISSUE_CACHE"
  step_build
  t_logged "DRY-RUN would build acme/software-factory#199"
  t_logged "DRY-RUN would build acme/gh-factory#10"
}

t_plan_focus() {
  t_budget 0 '["acme/software-factory#199"]' '[]'
  READY_COUNT=0
  step_plan
  t_logged "plan skip: focus_issues is set"
  [[ ! -s $GH_LOG ]] || fail "focused plan called gh"
  : > "$LOG"
  t_budget 0 '[]' '[]'
  READY_COUNT=5
  step_plan
  t_logged "plan skip: ready=5"
  t_not_logged "focus_issues is set"
}

t_inflight_file() {
  local dest
  dest="$GH_ROOT/issues/$(t_slug acme/software-factory).json"
  mkdir -p "$GH_ROOT/issues"
  jq -n '[
    {number:1,labels:[{name:"factory:building"}]},
    {number:2,labels:[{name:"factory:gate"}]},
    {number:3,labels:[{name:"factory:review"}]},
    {number:4,labels:[{name:"factory:ready"}]},
    {number:5,labels:[{name:"factory:ready"}]}
  ]' > "$dest"
  mkdir -p "$GH_ROOT/issue"
  jq -n '{labels:[{name:"factory:ready"}]}' > "$GH_ROOT/issue/$(t_slug acme/software-factory)_199.json"
}

t_ready_cache() {
  ISSUE_CACHE="$STATE/issues.jsonl"
  t_issue_line acme/software-factory 199 factory:ready $'Target repo: acme/software-factory\n' > "$ISSUE_CACHE"
}

t_claimed() {
  grep -F -q -- "--add-label factory:building" "$GH_LOG" || fail "expected a build claim (${1})"
}

t_not_claimed() {
  if grep -F -q -- "--add-label factory:building" "$GH_LOG"; then
    fail "build claimed despite the cap (${1})"
  fi
  t_logged "max_issues_in_flight"
}

# A full cap still clones software-factory before the claim, then must remove it.
t_no_abandoned_clone() {
  local matches
  matches=$(compgen -G "${WORK}/sf-main.*" || true)
  [[ -z $matches ]] || fail "in-flight cap left a software-factory clone: ${matches}"
}

t_cap() {
  DRY=0
  t_inflight_file
  t_ready_cache
  t_budget 3 '[]' '[]'
  : > "$GH_LOG"
  : > "$LOG"
  step_build
  t_not_claimed "cap 3 with 3 in flight"
  t_logged "build stop acme/software-factory#199: in-flight cap"
  t_no_abandoned_clone
  t_budget 4 '[]' '[]'
  : > "$GH_LOG"
  : > "$LOG"
  step_build
  t_claimed "cap 4 with 3 in flight"
  t_budget 0 '[]' '[]'
  : > "$GH_LOG"
  : > "$LOG"
  step_build
  t_claimed "cap 0"
  t_budget unset '[]' '[]'
  : > "$GH_LOG"
  : > "$LOG"
  step_build
  t_claimed "cap unset"
}

t_recent() {
  t_when=$(date -u +%Y-%m-%dT%H:%M:%SZ)
}

t_gate_work_focus() {
  local repo_a=acme/gh-factory repo_b=acme/software-factory
  local commented
  t_budget 0 '["acme/software-factory#199"]' '[]'
  t_recent
  commented="[$(bot 501 COMMENTED "$SHA_HEAD")]"
  t_arm "$repo_a" 31 CLEAN README.md "$commented" "no refs" "bump deps"
  t_arm "$repo_b" 32 CLEAN README.md "$commented" $'Closes #199\n' "focused"
  # No saved verdict yet: the in-focus pull request should wait on head age.
  rm -f "${STATE}/ireview-result-$(t_slug "$repo_a")-31-${SHA_HEAD}.json" \
    "${STATE}/ireview-result-$(t_slug "$repo_b")-32-${SHA_HEAD}.json"
  PR_IDS=("${repo_a}|31" "${repo_b}|32")
  step_independent_review
  t_logged "independent review skip ${repo_a}#31: not in focus"
  t_logged "independent review wait ${repo_b}#32"
  t_not_logged "independent review skip ${repo_b}#32: not in focus"
  t_not_logged "grok start"
  : > "$LOG"
  t_ir "$repo_a" 31 "$SHA_HEAD" FIX
  t_ir "$repo_b" 32 "$SHA_HEAD" FIX
  printf '%s\n' 3 > "${STATE}/rounds-$(t_slug "$repo_a")-31"
  printf '%s\n' 3 > "${STATE}/rounds-$(t_slug "$repo_b")-32"
  step_fix_fallback
  t_logged "fix fallback skip ${repo_a}#31: not in focus"
  t_logged "fix fallback skip ${repo_b}#32: round cap"
  t_not_logged "fix fallback skip ${repo_b}#32: not in focus"
  : > "$LOG"
  t_view "$repo_a" 41 "$SHA_HEAD" DIRTY "no refs" "dirty" factory/41-test "$CHECKS_OK"
  t_files "$repo_a" 41 AGENTS.md
  printf '%s\n' '[]' > "$(t_fixture reviews "$repo_a" 41)"
  t_ir "$repo_a" 41 "$SHA_HEAD" PASS
  t_view "$repo_b" 42 "$SHA_HEAD" DIRTY $'Closes #199\n' "dirty focused" factory/42-test "$CHECKS_OK"
  t_files "$repo_b" 42 AGENTS.md
  printf '%s\n' '[]' > "$(t_fixture reviews "$repo_b" 42)"
  t_ir "$repo_b" 42 "$SHA_HEAD" PASS
  PR_IDS=("${repo_a}|41" "${repo_b}|42")
  step_conflict_fallback
  t_logged "conflict fallback skip ${repo_a}#41: not in focus"
  [[ -e ${STATE}/crconflict-sens-$(t_slug "$repo_b")-42-${SHA_HEAD}-${SHA_BASE} ]] || fail "in-focus conflict was not handed to Scott"
  [[ ! -e ${STATE}/crconflict-sens-$(t_slug "$repo_a")-41-${SHA_HEAD}-${SHA_BASE} ]] || fail "out-of-focus conflict was handed to Scott"
  : > "$LOG"
  : > "$GH_LOG"
  DRY=1
  mkdir -p "$GH_ROOT/dependabot" "$GH_ROOT/view"
  jq -n --arg sha "$SHA_HEAD" '[
    {number:61,headRefOid:$sha,headRefName:"dependabot/npm/left",createdAt:"2026-11-01T00:00:00Z",files:[{path:"package.json"}]},
    {number:62,headRefOid:$sha,headRefName:"dependabot/npm/right",createdAt:"2026-11-01T01:00:00Z",files:[{path:"package.json"}]}
  ]' > "$GH_ROOT/dependabot/$(t_slug "$repo_b").json"
  t_view "$repo_b" 61 "$SHA_HEAD" CLEAN "no refs" "dep old" dependabot/npm/left "$CHECKS_OK"
  t_view "$repo_b" 62 "$SHA_HEAD" CLEAN $'Closes #199\n' "dep focus" dependabot/npm/right "$CHECKS_OK"
  step_dependabot_triage
  t_logged "dependabot triage skip ${repo_b}#61: not in focus"
  t_logged "would dependabot-triage ${repo_b}#62"
  t_not_logged "would dependabot-triage ${repo_b}#61"
  : > "$LOG"
  : > "$GH_LOG"
  rm -rf "$CYCLE_DIR"
  CYCLE_DIR=$(mktemp -d "${STATE}/cycle.XXXXXX")
  t_reset_grok
  t_budget 0 '[]' '[]'
  step_dependabot_triage
  t_logged "would dependabot-triage ${repo_b}#61"
  t_logged "would dependabot-triage ${repo_b}#62"
}

# The sourced watcher reads these. A read here keeps shellcheck from
# treating the assignments as unused.
t_watcher_globals() {
  : "${READY_COUNT-0}" "${DRY-0}" "${WINDOW_OPEN-0}" "${PR_IDS[*]-}" "${ISSUE_CACHE-}" "${CYCLE_DIR-}" "${t_when-}" "${GROK_USED-0}" "${GROK_RESERVED-0}" "${GROK_BLOCK-}"
}

# step_build and step_triage share one cycle's grok slot. The cases below
# are separate, so clear that slot between them.
t_reset_grok() {
  local k
  GROK_USED=0
  GROK_RESERVED=0
  GROK_BLOCK=""
  for k in "${!GROK_TARGETS[@]}"; do
    unset "GROK_TARGETS[$k]"
  done
}

run_case() {
  local script=$1 name=$2 err out
  err="$work/stderr.txt"
  out="$work/stdout.txt"
  : > "$GH_LOG"
  rm -rf "$GH_ROOT" "$FACTORY_WATCH_ROOT"
  mkdir -p "$GH_ROOT/counts" "$FACTORY_WATCH_ROOT/state" "$FACTORY_WATCH_ROOT/work" "$FACTORY_WATCH_ROOT/orders"
  t_budget 0 '[]' '[]'
  if ! (
    # shellcheck disable=SC1090
    source "$script"
    WINDOW_OPEN=0
    DRY=0
    CYCLE_DIR=$(mktemp -d "${STATE}/cycle.XXXXXX")
    t_watcher_globals
    "$name"
  ) >"$out" 2>"$err"; then
    printf 'FAIL: %s (%s)\n' "$name" "$(basename "$script")" >&2
    cat "$err" >&2
    exit 1
  fi
  printf 'ok: %s (%s)\n' "$name" "$(basename "$script")"
}

t_lanes() {
  local w="$root/scripts/watcher/watch.sh"
  local n="$root/scripts/watcher/watch.new.sh"
  grep -F -q 'Never re-request a head CodeRabbit already reviewed' "$w" \
    || fail "watch.sh lost the already-reviewed skip"
  awk '
    $0 ~ /Never re-request a head CodeRabbit already reviewed/ { c = 1 }
    c && /GATE_CR_COUNT > 0/ { g = 1 }
    c && g && /if \(\( ! paused \)\)/ { ok = 1; exit }
    END { exit (ok ? 0 : 1) }
  ' "$w" || fail "watch.sh already-reviewed skip is not before the not-paused branch"
  if grep -F -q 'Never re-request a head CodeRabbit already reviewed' "$n"; then
    fail "watch.new.sh picked up watch.sh already-reviewed comment"
  fi
  awk '
    /if \(\( ! paused \)\)/ { p = 1 }
    p && /GATE_CR_COUNT > 0/ { ok = 1; exit }
    END { exit (ok ? 0 : 1) }
  ' "$n" || fail "watch.new.sh already-reviewed skip is not inside the not-paused branch"
  grep -F -q 'step_build || log "build step error"' "$w" || fail "watch.sh does not call step_build"
  if grep -F -q 'if build_lane_alive; then' "$w"; then
    fail "watch.sh skips step_build while the build lock is held"
  fi
  grep -F -q 'if build_lane_alive; then' "$n" || fail "watch.new.sh does not guard step_build"
  grep -F -q 'skip step_build: build lane holds' "$n" || fail "watch.new.sh lost the build-lane skip"
}

# The independent-review comment carries the four review-record fields and
# the full head SHA. A fake result file stands in for the Grok output.
t_ir_record() {
  local repo=acme/software-factory pr=7 sha f body
  sha=0123456789abcdef0123456789abcdef01234567
  f=$(ir_result_file "$repo" "$pr" "$sha")
  jq -nc --arg sha "$sha" '{verdict:"PASS", summary:"Looks fine.",
    agreed_behaviour:"AGREED-TEXT", checks_ran:"CHECKS-TEXT",
    unasked_behaviour:"none", blast_radius:"BLAST-TEXT",
    fix:[], dismissed:[], escalate:[], sha:$sha, at:"2026-11-03T00:00:00Z"}' > "$f"
  ir_post_comment "$repo" "$pr" "$sha" || fail "ir_post_comment failed"
  body=$(cat "$GH_LOG")
  for want in "$sha" "Agreed behaviour:" "AGREED-TEXT" "Checks that ran:" "CHECKS-TEXT" \
    "Behaviour nobody asked for:" "Blast radius:" "BLAST-TEXT"; do
    grep -F -q -- "$want" <<< "$body" || fail "comment lacks: $want"
  done
  grep -F -q -- "Behaviour nobody asked for:** none" <<< "$body" || fail "unasked behaviour not rendered as none"
  grep -E -q -i 'ghp_|gho_|ghs_|github_pat_|xai-|sk-[A-Za-z0-9]|BEGIN [A-Z ]*PRIVATE KEY|token=' <<< "$body" && fail "comment looks like it carries a secret"
  # A result saved by an older watcher has no record fields: the comment still posts.
  sha=fedcba9876543210fedcba9876543210fedcba98
  f=$(ir_result_file "$repo" "$pr" "$sha")
  jq -nc --arg sha "$sha" '{verdict:"PASS",summary:"Old.",fix:[],dismissed:[],escalate:[],sha:$sha}' > "$f"
  ir_post_comment "$repo" "$pr" "$sha" || fail "old-format result did not post"
  grep -F -q -- "$sha" "$GH_LOG" || fail "old-format comment lacks full sha"
  # A token-shaped string in a field is redacted; @org/package stays readable.
  sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  f=$(ir_result_file "$repo" "$pr" "$sha")
  local tok
  tok="ghp_$(printf 'A1b2%.0s' {1..9})"
  jq -nc --arg sha "$sha" --arg tok "$tok" '{verdict:"PASS",summary:"S.",
    agreed_behaviour:"uses @org/package", checks_ran:("CI printed " + $tok),
    unasked_behaviour:"none", blast_radius:"x", fix:[],dismissed:[],escalate:[],sha:$sha}' > "$f"
  : > "$GH_LOG"
  ir_post_comment "$repo" "$pr" "$sha" || fail "redaction case did not post"
  grep -F -q -- "$tok" "$GH_LOG" && fail "token reached the posted comment"
  grep -F -q -- "[redacted]" "$GH_LOG" || fail "token not shown as [redacted]"
  grep -F -q -- "org/package" "$GH_LOG" || fail "@org/package lost its name"
  grep -F -q -- "@org/package" "$GH_LOG" && fail "bare mention left in comment"
  # The exact escape is @ + U+200B + org/package; stripping @ outright must fail.
  grep -F -q -- "$(printf '@\xe2\x80\x8borg/package')" "$GH_LOG" \
    || fail "@org/package not escaped with a zero-width space"
  # The full head SHA is inline code, so GitHub shows all 40 characters.
  grep -F -q -- "Head: \`$sha\`" "$GH_LOG" || fail "head sha is not backtick-wrapped"
  # sk-/xai- shaped keys are redacted; ordinary hyphenated words are not.
  sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  f=$(ir_result_file "$repo" "$pr" "$sha")
  local sk="sk-Test_0123456789abcdef" xai="xai-Test_0123456789abcdef"
  jq -nc --arg sha "$sha" --arg sk "$sk" --arg xai "$xai" '{verdict:"PASS",summary:"S.",
    agreed_behaviour:"risk-based review", checks_ran:("keys " + $sk + " and " + $xai),
    unasked_behaviour:"", blast_radius:"   ", fix:[],dismissed:[],escalate:[],sha:$sha}' > "$f"
  : > "$GH_LOG"
  ir_post_comment "$repo" "$pr" "$sha" || fail "key redaction case did not post"
  grep -F -q -- "$sk" "$GH_LOG" && fail "sk- key reached the posted comment"
  grep -F -q -- "$xai" "$GH_LOG" && fail "xai- key reached the posted comment"
  grep -F -q -- "keys [redacted] and [redacted]" "$GH_LOG" || fail "sk-/xai- keys not shown as [redacted]"
  grep -F -q -- "risk-based review" "$GH_LOG" || fail "risk-based was swallowed by redaction"
  # Empty and whitespace-only fields read as not available, not a blank line.
  grep -F -q -- "Behaviour nobody asked for:** not available" "$GH_LOG" || fail "empty field not rendered as not available"
  grep -F -q -- "Blast radius:** not available" "$GH_LOG" || fail "blank field not rendered as not available"
  # The 600-character cap counts original characters: escaping @ must not push the last one out.
  sha=cccccccccccccccccccccccccccccccccccccccc
  f=$(ir_result_file "$repo" "$pr" "$sha")
  local long
  long="$(printf 'a%.0s' {1..598})@Z"
  jq -nc --arg sha "$sha" --arg long "$long" '{verdict:"PASS",summary:"S.",
    agreed_behaviour:$long, checks_ran:"c", unasked_behaviour:"none", blast_radius:"x",
    fix:[],dismissed:[],escalate:[],sha:$sha}' > "$f"
  : > "$GH_LOG"
  ir_post_comment "$repo" "$pr" "$sha" || fail "600-character case did not post"
  grep -F -q -- "$(printf '@\xe2\x80\x8bZ')" "$GH_LOG" || fail "600-character field lost its last character to @ escaping"
  # A verdict-only parse falls back to placeholders.
  local out="$work/out.json" dest="$work/dest.json"
  printf '%s' '{"result":"VERDICT: PASS"}' > "$out"
  ir_save_result "$out" "$dest" "$sha"
  [[ $(jq -r '.blast_radius' "$dest") == "not available" ]] || fail "fallback lacks placeholder"
  ir_save_result "$work/missing.json" "$dest" "$sha"
  [[ $(jq -r '.agreed_behaviour' "$dest") == "not available" ]] || fail "missing-output fallback lacks placeholder"
}

# The watcher's ready bit (green checks plus independent PASS) is not enough:
# scripts/ready-gate.sh refuses first. A refused or unreadable gate means no
# merge, no "Ready for the maintainer" note, and the missing items in the
# reason. Ordinary and sensitive pull requests both stop.
t_ready_gate_refuses() {
  local repo=acme/software-factory real=$READY_GATE_CMD
  t_budget 0 '[]' '[]'
  printf '#!/usr/bin/env bash\necho "%s"\nexit 1\n' \
    "unresolved review thread (not outdated) on README.md by coderabbitai: Minor" \
    > "$work/ready-gate-refuse.sh"
  chmod +x "$work/ready-gate-refuse.sh"
  READY_GATE_CMD="$work/ready-gate-refuse.sh"
  t_prepare_merge "$repo" 21 CLEAN "" README.md "ordinary" "[]" ""
  t_gate 1 "$repo" 21
  [[ $GATE_REASON == *"ready-gate refused"*"unresolved review thread"* ]] || fail "reason lacks the missing items: ${GATE_REASON}"
  step_merge
  t_no_merge
  t_prepare_merge "$repo" 22 CLEAN "" AGENTS.md "no close" "[]" ""
  t_gate 1 "$repo" 22
  step_merge
  t_no_merge
  [[ ! -e ${STATE}/ready-acme_software-factory-22-${SHA_HEAD} ]] || fail "refused head was announced as ready"
  # A gate that cannot read is a failed read, never a pass.
  printf '#!/usr/bin/env bash\nexit 7\n' > "$work/ready-gate-unreadable.sh"
  chmod +x "$work/ready-gate-unreadable.sh"
  READY_GATE_CMD="$work/ready-gate-unreadable.sh"
  t_prepare_merge "$repo" 23 CLEAN "" README.md "ordinary" "[]" ""
  t_gate 3 "$repo" 23
  step_merge
  t_no_merge
  # The gate is handed the exact head and the watcher's per-head result file.
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" > "%s/ready-gate-args.txt"\nexit 0\n' "$work" \
    > "$work/ready-gate-args.sh"
  chmod +x "$work/ready-gate-args.sh"
  READY_GATE_CMD="$work/ready-gate-args.sh"
  t_prepare_merge "$repo" 24 CLEAN "" README.md "ordinary" "[]" ""
  t_gate 0 "$repo" 24
  grep -F -q -- "--repo ${repo} --pr 24 --sha ${SHA_HEAD} --ir-result ${STATE}/ireview-result-" "$work/ready-gate-args.txt" \
    || fail "gate not called with head and result file: $(cat "$work/ready-gate-args.txt")"
  READY_GATE_CMD=$real
}

cases=(
  t_helpers
  t_dismiss_set
  t_gate_matrix
  t_merge_ordinary
  t_merge_dismiss_fails
  t_merge_recheck_blocked
  t_merge_human
  t_merge_sensitive
  t_merge_allow_blocked
  t_merge_allow_clean
  t_ready_gate_refuses
  t_focus_rules
  t_steps_focus
  t_plan_focus
  t_cap
  t_gate_work_focus
  t_ir_record
)
for script in "$root/scripts/watcher/watch.sh" "$root/scripts/watcher/watch.new.sh"; do
  for name in "${cases[@]}"; do
    run_case "$script" "$name"
  done
done
t_lanes
printf 'ok: lane split\n'
