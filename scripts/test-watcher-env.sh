#!/usr/bin/env bash
# Offline tests for the portable watcher defaults: the shared factory env block
# in every scripts/watcher/*.sh, path resolution from FACTORY_HOME and
# XDG_DATA_HOME, FACTORY_HOME_REPO / FACTORY_REPOS / FACTORY_APPROVER_LOGIN
# resolution, FACTORY_BLOCKED_OWNERS, board-sync configuration, and the
# push-protected.sh approval check. A fake gh is first on PATH and HOME is a
# temporary directory. This suite does not use the network.
# Subshells set env on purpose, and the sourced watcher assigns ROOT and reads
# LOG and the overridden focus functions.
# shellcheck disable=SC2030,SC2031,SC2153,SC2329,SC2034
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
watch=$root/scripts/watcher
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tname=startup
fail() { printf 'FAIL (%s): %s\n' "$tname" "$*" >&2; exit 1; }
pass() { printf 'ok: %s\n' "$tname"; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2] got [$1]"; }

# Private HOME and no inherited factory settings.
HOME=$work/home
mkdir -p "$HOME"
export HOME
unset FACTORY_HOME FACTORY_WATCH_ROOT FACTORY_BUDGET_FILE FACTORY_LEDGER_FILE \
  FACTORY_CLONE_ROOT FACTORY_WORKSPACE FACTORY_HOME_REPO FACTORY_REPOS \
  FACTORY_APPROVER_LOGIN FACTORY_BLOCKED_OWNERS XDG_DATA_HOME GITHUB_REPOSITORY \
  FACTORY_BOARD_OWNER FACTORY_BOARD_NUMBER FACTORY_BOARD_PROJECT_ID \
  FACTORY_BOARD_FIELD_ID FACTORY_BOARD_OPTIONS LANE

# Fake gh: logs every call; `repo view` fails unless GH_REPO_VIEW is set;
# `issue view --jq` applies the filter to $GH_COMMENTS; project and list calls
# answer from small fixtures.
mkdir -p "$work/bin"
cat > "$work/bin/gh" << 'ENDGH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_LOG:?}"
args=("$@")
filter=""
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ ${args[i]} == --jq ]] && filter=${args[i + 1]}
done
case "$1 $2" in
  "repo view")
    [[ -n ${GH_REPO_VIEW:-} ]] || exit 1
    printf '%s\n' "$GH_REPO_VIEW"
    ;;
  "issue view")
    jq -r "$filter" "${GH_COMMENTS:?}"
    ;;
  "project item-list")
    printf '%s\n' '{"items":[{"content":{"url":"https://github.com/acme/app/issues/1"},"id":"OLD","factory status":"Done"}]}' | jq -r "$filter"
    ;;
  "project item-add")
    printf '%s\n' 'ITEM_1'
    ;;
  "project item-edit")
    ;;
  "issue list"|"pr list")
    if [[ " $* " == *" --state open "* ]]; then
      printf '%s\n' '[]' | jq -r "$filter"
    else
      printf '%s\n' '[{"url":"https://github.com/acme/app/issues/5","state":"OPEN","labels":[{"name":"factory:ready"}]}]' | jq -r "$filter"
    fi
    ;;
  *)
    exit 99
    ;;
esac
ENDGH
chmod +x "$work/bin/gh"
PATH="$work/bin:$PATH"
export PATH
export GH_LOG=$work/gh.log
: > "$GH_LOG"

block_of() {
  sed -n '/^# >>> factory env/,/^# <<< factory env/p' "$1"
}

watcher_scripts=(autopush.sh board-sync.sh push-protected.sh swap-early.sh watch.new.sh watch.sh)

# --- the block is the same everywhere ---------------------------------------
tname="every watcher script inlines the same factory env block"
ref=$(block_of "$watch/watch.sh")
[[ -n $ref ]] || fail "watch.sh has no factory env block"
for s in "${watcher_scripts[@]}"; do
  got=$(block_of "$watch/$s")
  [[ -n $got ]] || fail "$s has no factory env block"
  [[ $got == "$ref" ]] || fail "$s factory env block differs from watch.sh"
  # A shell `source` or `. file` (jq's `. as $x` is not one).
  if grep -E -q '^[[:space:]]*(source[[:space:]]|\.[[:space:]]+["$/~])' "$watch/$s"; then
    fail "$s sources another file"
  fi
done
pass

printf '%s\n' "$ref" > "$work/block.sh"

# Prints the resolved paths, one per line, from the block alone.
resolve_paths() {
  (
    # shellcheck disable=SC1091
    source "$work/block.sh"
    printf '%s\n' "$FACTORY_HOME" "$FACTORY_WATCH_ROOT" "$FACTORY_BUDGET_FILE" \
      "$FACTORY_LEDGER_FILE" "$FACTORY_CLONE_ROOT" "$FACTORY_WORKSPACE"
  )
}

# --- portable defaults --------------------------------------------------------
tname="no vars set: every path is under HOME/.local/share/software-factory"
base=$HOME/.local/share/software-factory
assert_eq "$(resolve_paths)" "$(printf '%s\n' "$base" "$base/factory-watch" \
  "$base/factory-budget.json" "$base/factory-ledger.csv" "$base" "$base")"
pass

tname="XDG_DATA_HOME moves the default base"
xdg=$work/xdg
base=$xdg/software-factory
assert_eq "$(XDG_DATA_HOME=$xdg resolve_paths)" "$(printf '%s\n' "$base" "$base/factory-watch" \
  "$base/factory-budget.json" "$base/factory-ledger.csv" "$base" "$base")"
pass

tname="FACTORY_HOME=D resolves exactly"
d=$work/D
assert_eq "$(FACTORY_HOME=$d XDG_DATA_HOME=$work/ignored resolve_paths)" "$(printf '%s\n' "$d" \
  "$d/factory-watch" "$d/factory-budget.json" "$d/factory-ledger.csv" "$d" "$d")"
pass

tname="explicit path vars still win"
got=$(FACTORY_HOME=$d FACTORY_WATCH_ROOT=$work/w FACTORY_BUDGET_FILE=$work/b.json \
  FACTORY_LEDGER_FILE=$work/l.csv FACTORY_CLONE_ROOT=$work/c FACTORY_WORKSPACE=$work/ws resolve_paths)
assert_eq "$got" "$(printf '%s\n' "$d" "$work/w" "$work/b.json" "$work/l.csv" "$work/c" "$work/ws")"
pass

# --- the lanes use the resolved paths ------------------------------------------
# Prints ROOT BUDGET LEDGER, one per line, from a sourced lane script.
lane_paths() {
  local script=$1
  (
    cd "$work"
    # shellcheck disable=SC1090
    source "$script"
    printf '%s\n' "$ROOT" "$BUDGET" "$LEDGER"
  )
}

for lane in watch.sh watch.new.sh; do
  tname="$lane: defaults with no vars set"
  base=$HOME/.local/share/software-factory
  got=$(FACTORY_HOME_REPO=acme/home lane_paths "$watch/$lane")
  assert_eq "$got" "$(printf '%s\n' "$base/factory-watch" "$base/factory-budget.json" "$base/factory-ledger.csv")"
  pass

  tname="$lane: FACTORY_HOME=D"
  got=$(FACTORY_HOME=$d FACTORY_HOME_REPO=acme/home lane_paths "$watch/$lane")
  assert_eq "$got" "$(printf '%s\n' "$d/factory-watch" "$d/factory-budget.json" "$d/factory-ledger.csv")"
  pass
done

# --- home repo, repo list and approver ------------------------------------------
# Prints FACTORY_HOME_REPO, FACTORY_REPOS, FACTORY_APPROVER_LOGIN and the
# resolver's exit code, run from directory $1.
resolve_repos_in() {
  local dir=$1
  (
    cd "$dir"
    # shellcheck disable=SC1091
    source "$work/block.sh"
    rc=0
    factory_resolve_repos || rc=$?
    printf '%s\n' "$FACTORY_HOME_REPO" "$FACTORY_REPOS" "$FACTORY_APPROVER_LOGIN" "$rc"
  )
}

mkdir -p "$work/not-a-clone"

tname="FACTORY_HOME_REPO wins"
got=$(FACTORY_HOME_REPO=acme/home GITHUB_REPOSITORY=ci/repo resolve_repos_in "$work/not-a-clone")
assert_eq "$got" "$(printf '%s\n' acme/home acme/home acme 0)"
pass

tname="GITHUB_REPOSITORY is the next default"
got=$(GITHUB_REPOSITORY=ci/repo resolve_repos_in "$work/not-a-clone")
assert_eq "$got" "$(printf '%s\n' ci/repo ci/repo ci 0)"
pass

for url in https://github.com/origin-owner/origin.repo.git git@github.com:origin-owner/origin.repo.git \
  ssh://git@github.com/origin-owner/origin.repo; do
  tname="origin remote of the checkout: $url"
  clone=$work/clone-$RANDOM
  git init -q "$clone"
  git -C "$clone" remote add origin "$url"
  mkdir -p "$clone/sub"
  got=$(resolve_repos_in "$clone/sub")
  assert_eq "$got" "$(printf '%s\n' origin-owner/origin.repo origin-owner/origin.repo origin-owner 0)"
  pass
done

tname="gh repo view is the last default"
got=$(GH_REPO_VIEW=gh-owner/gh-repo resolve_repos_in "$work/not-a-clone")
assert_eq "$got" "$(printf '%s\n' gh-owner/gh-repo gh-owner/gh-repo gh-owner 0)"
pass

tname="nothing resolves: non-zero, empty values"
got=$(resolve_repos_in "$work/not-a-clone")
assert_eq "$got" "$(printf '%s\n' "" "" "" 1)"
pass

tname="FACTORY_REPOS and FACTORY_APPROVER_LOGIN override the defaults"
got=$(FACTORY_HOME_REPO=acme/home FACTORY_REPOS="acme/home other/x" FACTORY_APPROVER_LOGIN=reviewer \
  resolve_repos_in "$work/not-a-clone")
assert_eq "$got" "$(printf '%s\n' acme/home "acme/home other/x" reviewer 0)"
pass

for lane in watch.sh watch.new.sh; do
  tname="$lane: REPO_NAMES_ALT and REPOS_HUMAN keep each owner"
  got=$(
    cd "$work"
    export FACTORY_HOME=$work/fh FACTORY_HOME_REPO=Acme/Home.Repo FACTORY_REPOS="Acme/Home.Repo other/lib third/app"
    # shellcheck disable=SC1090
    source "$watch/$lane"
    printf '%s\n' "$REPO_NAMES_ALT" "$REPOS_HUMAN"
  )
  assert_eq "$got" "$(printf '%s\n' 'acme/home\.repo|other/lib|third/app' 'Acme/Home.Repo, other/lib or third/app')"
  pass

  tname="$lane: close refs and focus use FACTORY_HOME_REPO"
  (
    cd "$work"
    export FACTORY_HOME=$work/fh FACTORY_HOME_REPO=acme/home FACTORY_REPOS="acme/home other/lib"
    # shellcheck disable=SC1090
    source "$watch/$lane"
    LOG=$work/close.log
    got=$(parse_close_targets other/lib $'Closes #4\nCloses acme/home#7\nCloses other/lib#8\nCloses stranger/x#9')
    assert_eq "$got" "$(printf '%s\n' 'other/lib 4' 'acme/home 7' 'other/lib 8')"
    focus_is_set() { return 0; }
    focus_has() { [[ $1 == "acme/home#12" ]]; }
    pr_in_focus other/lib "t" "see https://github.com/acme/home/issues/12" || fail "issue url"
    pr_in_focus other/lib "t" "see acme/home#12" || fail "owner ref"
    pr_in_focus other/lib "t" "see home#12" || fail "short ref"
    pr_in_focus acme/home "t" "see #12" || fail "bare ref inside the home repo"
    if pr_in_focus other/lib "t" "see #12"; then fail "bare ref outside the home repo"; fi
    if pr_in_focus other/lib "t" "see xhome#12"; then fail "longer name matched"; fi
  ) || exit 1
  pass

  tname="$lane: main exits when no home repo resolves"
  rc=0
  (
    cd "$work/not-a-clone"
    export FACTORY_HOME=$work/fh-main
    # shellcheck disable=SC1090
    source "$watch/$lane"
    main --once
  ) > /dev/null 2> "$work/main.err" || rc=$?
  assert_eq "$rc" 2
  grep -F -q 'no home repo' "$work/main.err" || fail "missing message: $(cat "$work/main.err")"
  pass
done

# --- FACTORY_BLOCKED_OWNERS -----------------------------------------------------
# Prints "ok" or "blocked" for repo_ok $1 under the current environment.
repo_ok_says() {
  local lane=$1 repo=$2
  (
    cd "$work"
    export FACTORY_HOME=$work/fh FACTORY_HOME_REPO=acme/home
    export FACTORY_REPOS="acme/home blocked-org/app Other-Org/lib"
    # shellcheck disable=SC1090
    source "$watch/$lane"
    LOG=$work/blocked.log
    if repo_ok "$repo" 2> /dev/null; then echo ok; else echo blocked; fi
  )
}

for lane in watch.sh watch.new.sh; do
  tname="$lane: FACTORY_BLOCKED_OWNERS unset blocks nothing in the allowlist"
  unset FACTORY_BLOCKED_OWNERS
  assert_eq "$(repo_ok_says "$lane" blocked-org/app)" ok
  assert_eq "$(repo_ok_says "$lane" other-org/lib)" ok
  assert_eq "$(repo_ok_says "$lane" acme/home)" ok
  assert_eq "$(repo_ok_says "$lane" stranger/x)" blocked
  pass

  tname="$lane: FACTORY_BLOCKED_OWNERS blocks a listed owner, any case"
  export FACTORY_BLOCKED_OWNERS="Blocked-Org other-org"
  assert_eq "$(repo_ok_says "$lane" blocked-org/app)" blocked
  assert_eq "$(repo_ok_says "$lane" BLOCKED-ORG/app)" blocked
  assert_eq "$(repo_ok_says "$lane" Other-Org/lib)" blocked
  assert_eq "$(repo_ok_says "$lane" acme/home)" ok
  unset FACTORY_BLOCKED_OWNERS
  pass

  tname="$lane: prompts state the configured blocked owners"
  got=$(
    cd "$work"
    export FACTORY_HOME=$work/fh FACTORY_HOME_REPO=acme/home FACTORY_BLOCKED_OWNERS="org-a org-b"
    # shellcheck disable=SC1090
    source "$watch/$lane"
    printf '%s\n' "$BLOCKED_HUMAN"
  )
  assert_eq "$got" "org-a org-b"
  got=$(
    cd "$work"
    export FACTORY_HOME=$work/fh FACTORY_HOME_REPO=acme/home
    # shellcheck disable=SC1090
    source "$watch/$lane"
    printf '%s\n' "$BLOCKED_HUMAN"
  )
  assert_eq "$got" "none configured"
  # shellcheck disable=SC2016  # literal source text, not expansion
  [[ $(grep -c 'blocked owner (${BLOCKED_HUMAN})' "$watch/$lane") -ge 3 ]] \
    || fail "prompts do not name the blocked owners"
  pass
done

# --- board-sync.sh ----------------------------------------------------------------
board_env=(FACTORY_BOARD_OWNER=board-owner FACTORY_BOARD_NUMBER=7 FACTORY_BOARD_PROJECT_ID=PROJ_ID
  FACTORY_BOARD_FIELD_ID=FIELD_ID 'FACTORY_BOARD_OPTIONS={"Ready":"opt-ready","Done":"opt-done"}')

for missing in FACTORY_BOARD_OWNER FACTORY_BOARD_NUMBER FACTORY_BOARD_PROJECT_ID \
  FACTORY_BOARD_FIELD_ID FACTORY_BOARD_OPTIONS; do
  tname="board-sync.sh not configured without $missing"
  : > "$GH_LOG"
  rc=0
  partial=()
  for kv in "${board_env[@]}"; do
    [[ $kv == "$missing="* ]] || partial+=("$kv")
  done
  out=$(env "${partial[@]}" FACTORY_HOME="$work/board-home" bash "$watch/board-sync.sh" --once) || rc=$?
  assert_eq "$rc" 0
  [[ $out == *"board sync not configured"* ]] || fail "expected the not-configured message, got [$out]"
  [[ ! -s $GH_LOG ]] || fail "gh was called: $(cat "$GH_LOG")"
  pass
done

tname="board-sync.sh uses the configured board"
: > "$GH_LOG"
mkdir -p "$work/board-home/factory-watch"
out=$(env "${board_env[@]}" FACTORY_HOME="$work/board-home" FACTORY_REPOS="acme/app" bash "$watch/board-sync.sh" --once)
grep -F -q 'project item-list 7 --owner board-owner' "$GH_LOG" || fail "item-list does not use the board: $(cat "$GH_LOG")"
grep -F -q 'project item-add 7 --owner board-owner --url https://github.com/acme/app/issues/5' "$GH_LOG" \
  || fail "item-add does not use the board: $(cat "$GH_LOG")"
grep -F -q 'project item-edit --id ITEM_1 --project-id PROJ_ID --field-id FIELD_ID --single-select-option-id opt-ready' "$GH_LOG" \
  || fail "item-edit does not use the configured ids: $(cat "$GH_LOG")"
grep -F -q 'list -R acme/app' "$GH_LOG" || fail "did not list FACTORY_REPOS"
[[ $out == *"issues/5 -> Ready"* ]] || fail "missing sync line: [$out]"
pass

tname="board-sync.sh rejects options that are not a JSON object"
rc=0
env "${board_env[@]}" FACTORY_BOARD_OPTIONS='["x"]' FACTORY_HOME="$work/board-home" FACTORY_REPOS=acme/app \
  bash "$watch/board-sync.sh" --once > /dev/null 2>&1 || rc=$?
assert_eq "$rc" 2
pass

# --- push-protected.sh approval ---------------------------------------------------
# Exit 2: no approval. Exit 3: approved, then stops at "no clone" (no build clone here).
mkdir -p "$work/pp-home/factory-watch/orders"
approval_rc() {
  local comments=$1
  shift
  printf '%s\n' "$comments" > "$work/comments.json"
  local rc=0
  env GH_COMMENTS="$work/comments.json" FACTORY_HOME="$work/pp-home" "$@" \
    bash "$watch/push-protected.sh" acme/home 12 > "$work/pp.out" 2>&1 || rc=$?
  printf '%s\n' "$rc"
}

tname="push-protected.sh accepts the neutral marker from FACTORY_APPROVER_LOGIN"
c='{"comments":[{"author":{"login":"maint"},"body":"ok to push\n<!-- factory:approve -->"}]}'
assert_eq "$(approval_rc "$c" FACTORY_APPROVER_LOGIN=maint)" 3
pass

tname="push-protected.sh still accepts the legacy chat marker"
c='{"comments":[{"author":{"login":"maint"},"body":"Approved by Pat (via chat, 1 Nov)"}]}'
assert_eq "$(approval_rc "$c" FACTORY_APPROVER_LOGIN=maint)" 3
pass

tname="push-protected.sh ignores another login's approval"
c='{"comments":[{"author":{"login":"someone"},"body":"<!-- factory:approve -->"}]}'
assert_eq "$(approval_rc "$c" FACTORY_APPROVER_LOGIN=maint)" 2
grep -F -q 'no maintainer approval' "$work/pp.out" || fail "missing message: $(cat "$work/pp.out")"
pass

tname="push-protected.sh approver defaults to the FACTORY_HOME_REPO owner"
c='{"comments":[{"author":{"login":"acme"},"body":"<!-- factory:approve -->"}]}'
assert_eq "$(approval_rc "$c" FACTORY_HOME_REPO=acme/home)" 3
assert_eq "$(approval_rc "$c" FACTORY_HOME_REPO=other/home)" 2
pass

tname="push-protected.sh needs an approver"
assert_eq "$(cd "$work/not-a-clone" && approval_rc "$c")" 2
grep -F -q 'no approver' "$work/pp.out" || fail "missing message: $(cat "$work/pp.out")"
pass

# --- FACTORY_PROVIDER ------------------------------------------------------------
# Prints the resolved provider (and the function's exit status) from the block.
provider_of() {
  (
    # shellcheck disable=SC1091
    source "$work/block.sh"
    rc=0
    factory_resolve_provider 2> "$work/prov.err" || rc=$?
    printf '%s %s\n' "$rc" "${FACTORY_PROVIDER:-}"
  )
}

tname="FACTORY_PROVIDER defaults to grok"
unset FACTORY_PROVIDER
assert_eq "$(provider_of)" "0 grok"
pass

for p in grok claudecode opencode; do
  tname="FACTORY_PROVIDER=$p is accepted"
  assert_eq "$(FACTORY_PROVIDER=$p provider_of)" "0 $p"
  pass
done

tname="an invalid FACTORY_PROVIDER is rejected with a clear message"
assert_eq "$(FACTORY_PROVIDER=gemini provider_of)" "2 gemini"
grep -F -q 'FACTORY_PROVIDER=gemini is not valid' "$work/prov.err" || fail "missing message: $(cat "$work/prov.err")"
pass

tname="the watcher lanes stop on an invalid FACTORY_PROVIDER"
for s in watch.sh watch.new.sh; do
  rc=0
  FACTORY_PROVIDER=gemini timeout 20 bash "$watch/$s" > "$work/lane.out" 2>&1 || rc=$?
  assert_eq "$rc" 2
  grep -F -q 'is not valid' "$work/lane.out" || fail "$s: missing message: $(cat "$work/lane.out")"
done
pass

echo "ok  watcher env tests"
