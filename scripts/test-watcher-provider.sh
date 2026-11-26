#!/usr/bin/env bash
# The watcher's triage call site runs the FACTORY_PROVIDER adapter, not grok
# (#398). Offline: a fake gh and a fake claude CLI, and NO grok on PATH.
# Covered for both lane scripts, plus the unchanged grok path when
# FACTORY_PROVIDER is unset or grok.
# Each case exports its environment inside a subshell on purpose, so nothing
# leaks into the next case.
# shellcheck disable=SC2030,SC2031
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# $1 lane name, $2 provider ("" = unset), $3 case tag, $4 grok on PATH (yes|no)
run_case() {
  local name=$1 provider=$2 tag=$3 with_grok=$4
  local w=$scratch/$tag-$name
  mkdir -p "$w/bin" "$w/home" "$w/tmp" "$w/cache" "$w/watch/state" "$w/watch/work" "$w/repo/scripts/watcher"
  cp "$root/scripts/watcher/${name}.sh" "$w/repo/scripts/watcher/${name}.sh"
  cp "$root/scripts/watcher/factory-env.sh" "$w/repo/scripts/watcher/factory-env.sh"
  cp "$root/scripts/fence-untrusted.sh" "$w/repo/scripts/fence-untrusted.sh"

  cat > "$w/bin/gh" << 'ENDGH'
#!/bin/bash
set -u
if [[ ${1:-} == repo && ${2:-} == clone ]]; then
  dest=${4:-}
  mkdir -p "$dest/agents/roles" "$dest/scripts"
  printf '%s\n' '# intake fixture' > "$dest/agents/roles/intake.md"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$dest/scripts/triage-ask.sh"
  cp "$REAL_ROOT/scripts/fence-untrusted.sh" "$dest/scripts/"
  cp "$REAL_ROOT/scripts/container-env.sh" "$REAL_ROOT/scripts/station-container.sh" "$dest/scripts/"
  cp -R "$REAL_ROOT/adapters" "$dest/adapters"
  cp "$REAL_ROOT/AGENTS.md" "$dest/AGENTS.md"
  git init -q -b main "$dest"
  git -C "$dest" add -A
  git -C "$dest" -c user.name=t -c user.email=t@example.com commit -q -m init
  exit 0
fi
if [[ ${1:-} == issue && ${2:-} == view ]]; then printf '%s\n' '{"comments":[]}'; exit 0; fi
exit 99
ENDGH
  # Fake CLIs record that they ran. claude advertises the flags the adapter probes.
  cat > "$w/bin/claude" << 'ENDCL'
#!/bin/bash
if [[ ${1:-} == --help ]]; then echo "--print --model --append-system-prompt --permission-mode"; exit 0; fi
cat > "$CALLS_DIR/claude.stdin"
echo ran >> "$CALLS_DIR/claude.calls"
ENDCL
  cat > "$w/bin/grok" << 'ENDGROK'
#!/bin/bash
echo ran >> "$CALLS_DIR/grok.calls"
printf '%s\n' '{"stopReason":"end_turn","total_cost_usd":0}'
ENDGROK
  chmod +x "$w/bin/gh" "$w/bin/claude"
  if [[ $with_grok == yes ]]; then
    chmod +x "$w/bin/grok"
  else
    rm -f "$w/bin/grok"
  fi
  mkdir -p "$w/calls"
  printf '%s\n' '{"max_grok_build_runs_per_week":20,"max_grok_build_runs_per_day":20,"max_runs_per_loop":5}' > "$w/budget.json"
  printf '%s\n' '{"repo":"acme/software-factory","number":398,"title":"t","body":"b","createdAt":"2026-11-13T00:00:00Z","labels":[{"name":"factory:triage"}]}' > "$w/issues.jsonl"

  (
    cd "$w"
    export HOME="$w/home" TMPDIR="$w/tmp" XDG_CACHE_HOME="$w/cache" XDG_DATA_HOME="$w/xdg"
    export FACTORY_HOME="$w/factory-home" FACTORY_WATCH_ROOT="$w/watch" FACTORY_BUDGET_FILE="$w/budget.json"
    export FACTORY_LEDGER_FILE="$w/ledger.csv" FACTORY_CLONE_ROOT="$w/clones" FACTORY_WORKSPACE="$w/workspace"
    export FACTORY_HOME_REPO=acme/software-factory FACTORY_REPOS=acme/software-factory
    export GIT_TERMINAL_PROMPT=0 REAL_ROOT="$root" CALLS_DIR="$w/calls"
    # The adapter runs in the station container (#424). The fake runtime starts
    # none: it runs the adapter with only the environment a container would get.
    cp "$root/scripts/fixtures/fake-container-runtime.sh" "$w/bin/podman" && chmod +x "$w/bin/podman"
    export FACTORY_CONTAINER_IMAGE=factory-station:test FACTORY_CONTAINER_NETWORK=factory-egress-test
    export FAKE_RUNTIME_LOG="$w/calls/runtime.log" FAKE_RUNTIME_PASS=CALLS_DIR CLAUDE_CODE_OAUTH_TOKEN=test-claude-token XAI_API_KEY=test-xai-key
    unset FACTORY_CONTAINER_RUNTIME FACTORY_CONTAINER_PROXY
    # Only the fakes and the system tools: no grok anywhere unless the case adds it.
    export PATH="$w/bin:/usr/bin:/bin"
    unset FACTORY_APPROVER_LOGIN FACTORY_BLOCKED_OWNERS FACTORY_PROVIDER GH_TOKEN GITHUB_TOKEN \
      FACTORY_GH_APP_ID FACTORY_GH_APP_INSTALLATION_ID FACTORY_GH_APP_KEY_FILE FACTORY_GH_APP_ENV_FILE \
      FACTORY_GH_APP_PRIVATE_KEY FACTORY_GH_APP_SLUG GH_APP_SLUG
    [[ -n $provider ]] && export FACTORY_PROVIDER=$provider
    if [[ $with_grok == no ]] && command -v grok > /dev/null 2>&1; then fail "grok is on the test PATH"; fi
    # shellcheck disable=SC1090
    source "$w/repo/scripts/watcher/${name}.sh"
    # shellcheck disable=SC2034
    DRY=0
    # shellcheck disable=SC2034
    ISSUE_CACHE=$w/issues.jsonl
    step_triage > "$w/out.log" 2>&1 || true
  )
  printf '%s' "$w"
}

for lane in watch watch.new; do
  w=$(run_case "$lane" claudecode cc no)
  [[ -s $w/calls/claude.calls ]] || fail "$lane: FACTORY_PROVIDER=claudecode did not run the claude adapter ($(cat "$w/out.log" 2>/dev/null | tail -3))"
  [[ ! -e $w/calls/grok.calls ]] || fail "$lane: grok ran under claudecode"
  grep -Fq 'intake fixture' "$w/calls/claude.stdin" || fail "$lane: the intake brief did not reach the provider"
  grep -Fq 'You are the intake station for issue #398' "$w/calls/claude.stdin" || fail "$lane: adapter role/issue not passed"
  # Through the station container, never straight on the host (#424).
  [[ $(wc -l < "$w/calls/runtime.log") -eq 1 ]] || fail "$lane: the adapter was not started through the container runtime"
  grep -Fq -- '--network factory-egress-test' "$w/calls/runtime.log" || fail "$lane: the adapter's container is not on the restricted network"
  if grep -Fq -e GH_TOKEN -e test-claude-token "$w/calls/runtime.log"; then fail "$lane: a GitHub token or a credential value is on the runtime argv"; fi
  echo "ok: $lane triage runs the claudecode adapter with no grok on PATH"

  for p in "" grok; do
    w=$(run_case "$lane" "$p" "g${p:-unset}" yes)
    [[ -s $w/calls/grok.calls ]] || fail "$lane: FACTORY_PROVIDER='${p}' did not call grok"
    [[ ! -e $w/calls/claude.calls ]] || fail "$lane: claude ran with FACTORY_PROVIDER='${p}'"
    # grok starts through the station container too, never on the host (#428).
    [[ $(wc -l < "$w/calls/runtime.log") -eq 1 ]] || fail "$lane: grok was not started through the container runtime (FACTORY_PROVIDER='${p}')"
    grep -Fq -- '--network factory-egress-test' "$w/calls/runtime.log" || fail "$lane: grok's container is not on the restricted network"
    grep -Fq -- '--env XAI_API_KEY' "$w/calls/runtime.log" || fail "$lane: XAI_API_KEY is not forwarded by name"
    if grep -Fq -e test-xai-key -e test-claude-token "$w/calls/runtime.log"; then fail "$lane: a credential value is on the runtime argv"; fi
    if grep -Fq -- 'CLAUDE_CODE_OAUTH_TOKEN' "$w/calls/runtime.log"; then fail "$lane: grok's container was given the claude credential"; fi
    echo "ok: $lane triage still calls grok with FACTORY_PROVIDER='${p:-unset}'"
  done
done
# Review and dependabot-triage call sites (#399). run_grok is called directly
# with a schema and a target-repo checkout that has no adapters/ of its own, so
# the adapter must come from the home-repo clone. $1 lane, $2 provider ("" =
# unset), $3 kind, $4 case tag, $5 grok on PATH (yes|no)
run_kind_case() {
  local name=$1 provider=$2 kind=$3 tag=$4 with_grok=$5
  local w=$scratch/$tag-$name
  mkdir -p "$w/bin" "$w/home" "$w/tmp" "$w/cache" "$w/watch/state" "$w/watch/work" "$w/repo/scripts/watcher" "$w/target" "$w/calls"
  cp "$root/scripts/watcher/${name}.sh" "$w/repo/scripts/watcher/${name}.sh"
  cp "$root/scripts/watcher/factory-env.sh" "$w/repo/scripts/watcher/factory-env.sh"
  cp "$root/scripts/fence-untrusted.sh" "$w/repo/scripts/fence-untrusted.sh"
  cat > "$w/bin/gh" << 'ENDGH'
#!/bin/bash
set -u
if [[ ${1:-} == repo && ${2:-} == clone ]]; then
  dest=${4:-}
  mkdir -p "$dest/agents/roles" "$dest/scripts"
  cp "$REAL_ROOT/scripts/container-env.sh" "$REAL_ROOT/scripts/station-container.sh" "$dest/scripts/"
  cp -R "$REAL_ROOT/adapters" "$dest/adapters"
  cp "$REAL_ROOT/AGENTS.md" "$dest/AGENTS.md"
  git init -q -b main "$dest"
  git -C "$dest" add -A
  git -C "$dest" -c user.name=t -c user.email=t@example.com commit -q -m init
  git -C "$dest" remote add origin "$dest"
  exit 0
fi
exit 99
ENDGH
  cat > "$w/bin/claude" << 'ENDCL'
#!/bin/bash
if [[ ${1:-} == --help ]]; then echo "--print --model --append-system-prompt --permission-mode"; exit 0; fi
cat > "$CALLS_DIR/claude.stdin"
echo ran >> "$CALLS_DIR/claude.calls"
echo "VERDICT: PASS"
ENDCL
  cat > "$w/bin/grok" << 'ENDGROK'
#!/bin/bash
printf '%s\n' "$*" > "$CALLS_DIR/grok.args"
# Names only, plus what GH_CONFIG_DIR points at: never a value that could be a credential.
{ env | cut -d= -f1 | grep -E '^(GH_TOKEN|GITHUB_TOKEN|GH_CONFIG_DIR|FACTORY_GH_APP_ID|FACTORY_GH_APP_KEY_FILE|FACTORY_STATION_CONTAINER)$' | sort | tr '\n' ' '; echo; } > "$CALLS_DIR/grok.env"
if [[ -n ${GH_CONFIG_DIR:-} && -d $GH_CONFIG_DIR ]]; then ls -A "$GH_CONFIG_DIR" | wc -l > "$CALLS_DIR/grok.ghcfg"; fi
echo ran >> "$CALLS_DIR/grok.calls"
printf '%s\n' '{"stopReason":"end_turn","total_cost_usd":0}'
ENDGROK
  chmod +x "$w/bin/gh" "$w/bin/claude"
  if [[ $with_grok == yes ]]; then chmod +x "$w/bin/grok"; else rm -f "$w/bin/grok"; fi
  printf '%s\n' '{"max_grok_build_runs_per_week":20,"max_grok_build_runs_per_day":20,"max_runs_per_loop":5}' > "$w/budget.json"
  printf '%s\n' 'review this' > "$w/prompt.txt"
  # The plan call site's cwd is a fresh home-repo clone (#404), so its adapter is
  # in cwd, unlike review's target checkout.
  if [[ $kind == plan ]]; then
    mkdir -p "$w/target/scripts" "$w/target/agents/roles"
    cp "$root/scripts/container-env.sh" "$root/scripts/station-container.sh" "$w/target/scripts/"
    cp -R "$root/adapters" "$w/target/adapters"
    cp "$root/AGENTS.md" "$w/target/AGENTS.md"
    printf '%s\n' '# foreman fixture' > "$w/target/agents/roles/foreman.md"
  fi
  (
    cd "$w"
    export HOME="$w/home" TMPDIR="$w/tmp" XDG_CACHE_HOME="$w/cache" XDG_DATA_HOME="$w/xdg"
    export FACTORY_HOME="$w/factory-home" FACTORY_WATCH_ROOT="$w/watch" FACTORY_BUDGET_FILE="$w/budget.json"
    export FACTORY_LEDGER_FILE="$w/ledger.csv" FACTORY_CLONE_ROOT="$w/clones" FACTORY_WORKSPACE="$w/workspace"
    export FACTORY_HOME_REPO=acme/software-factory FACTORY_REPOS=acme/software-factory
    export GIT_TERMINAL_PROMPT=0 REAL_ROOT="$root" CALLS_DIR="$w/calls"
    # The adapter runs in the station container (#424). The fake runtime starts
    # none: it runs the adapter with only the environment a container would get.
    cp "$root/scripts/fixtures/fake-container-runtime.sh" "$w/bin/podman" && chmod +x "$w/bin/podman"
    export FACTORY_CONTAINER_IMAGE=factory-station:test FACTORY_CONTAINER_NETWORK=factory-egress-test
    export FAKE_RUNTIME_LOG="$w/calls/runtime.log" FAKE_RUNTIME_PASS=CALLS_DIR CLAUDE_CODE_OAUTH_TOKEN=test-claude-token XAI_API_KEY=test-xai-key
    unset FACTORY_CONTAINER_RUNTIME FACTORY_CONTAINER_PROXY
    export PATH="$w/bin:/usr/bin:/bin"
    unset FACTORY_APPROVER_LOGIN FACTORY_BLOCKED_OWNERS FACTORY_PROVIDER GH_TOKEN GITHUB_TOKEN \
      FACTORY_GH_APP_ID FACTORY_GH_APP_INSTALLATION_ID FACTORY_GH_APP_KEY_FILE FACTORY_GH_APP_ENV_FILE \
      FACTORY_GH_APP_PRIVATE_KEY FACTORY_GH_APP_SLUG GH_APP_SLUG
    [[ -n $provider ]] && export FACTORY_PROVIDER=$provider
    [[ -z ${FACTORY_NO_IMAGE:-} ]] || unset FACTORY_CONTAINER_IMAGE
    # shellcheck disable=SC1090
    source "$w/repo/scripts/watcher/${name}.sh"
    # After the source: the watcher's own start-up applies or clears the token.
    [[ -z ${GROK_TEST_GH_TOKEN:-} ]] || export GH_TOKEN=$GROK_TEST_GH_TOKEN
    [[ -z ${GROK_TEST_APP_ID:-} ]] || export FACTORY_GH_APP_ID=$GROK_TEST_APP_ID
    [[ -z ${GROK_TEST_APP_ID:-} ]] || export FACTORY_GH_APP_KEY_FILE=/nonexistent/app-key.pem
    [[ -z ${GROK_TEST_ON_HOST:-} ]] || export FACTORY_GROK_ON_HOST=$GROK_TEST_ON_HOST
    # shellcheck disable=SC2034
    DRY=0
    run_grok "$kind" acme/software-factory 77 25 "$w/target" "$w/prompt.txt" '{"type":"object","required":["verdict"]}' > "$w/out.log" 2>&1 || true
  )
  printf '%s' "$w"
}

for lane in watch watch.new; do
  for kind in review dependabot-triage; do
    w=$(run_kind_case "$lane" claudecode "$kind" "cc-$kind" no)
    [[ -s $w/calls/claude.calls ]] || fail "$lane: $kind under claudecode did not run the adapter ($(tail -3 "$w/out.log" 2>/dev/null))"
    [[ ! -e $w/calls/grok.calls ]] || fail "$lane: grok ran for $kind under claudecode"
    grep -Fq 'You are the reviewer station' "$w/calls/claude.stdin" || fail "$lane: $kind did not use the reviewer role"
    grep -Fq 'review this' "$w/calls/claude.stdin" || fail "$lane: $kind prompt did not reach the provider"
    grep -Fq '"required":["verdict"]' "$w/calls/claude.stdin" || fail "$lane: $kind schema was not handed over in the prompt"
    grep -Fq 'JSON Schema' "$w/calls/claude.stdin" || fail "$lane: $kind schema instruction missing"
    [[ $(wc -l < "$w/calls/runtime.log") -eq 1 ]] || fail "$lane: $kind did not start the adapter through the container runtime"
    grep -Fq -- "--volume $w/target:$w/target " "$w/calls/runtime.log" || fail "$lane: $kind did not mount the target checkout"
    echo "ok: $lane $kind runs the claudecode adapter and hands the schema over in the prompt"

    for p in "" grok; do
      w=$(run_kind_case "$lane" "$p" "$kind" "g${p:-unset}-$kind" yes)
      [[ -s $w/calls/grok.calls ]] || fail "$lane: $kind with FACTORY_PROVIDER='${p}' did not call grok"
      [[ ! -e $w/calls/claude.calls ]] || fail "$lane: claude ran for $kind with FACTORY_PROVIDER='${p}'"
      grep -Fq -- '--json-schema' "$w/calls/grok.args" || fail "$lane: $kind lost --json-schema on grok"
      [[ $(wc -l < "$w/calls/runtime.log") -eq 1 ]] || fail "$lane: $kind did not start grok through the container runtime"
      grep -Fq -- "--volume $w/target:$w/target " "$w/calls/runtime.log" || fail "$lane: $kind did not mount the target checkout for grok"
      grep -Eq -- '--volume [^ ]*/grok-prompt\.[^ ]*:ro ' "$w/calls/runtime.log" || fail "$lane: $kind did not mount the prompt read-only"
      if grep -Fq -- "--volume $w/watch/work" "$w/calls/runtime.log"; then fail "$lane: $kind mounted the home-repo clone into grok's container"; fi
      echo "ok: $lane $kind still calls grok with --json-schema, FACTORY_PROVIDER='${p:-unset}'"
    done
  done
done
# Plan call site (#404). It is a write-access run in a home-repo clone, so the
# adapter is the one in cwd and the role is foreman, not intake.
for lane in watch watch.new; do
  w=$(GROK_TEST_GH_TOKEN=test-gh-token GROK_TEST_APP_ID=1 run_kind_case "$lane" claudecode plan "cc-plan" no)
  [[ -s $w/calls/claude.calls ]] || fail "$lane: plan under claudecode did not run the adapter ($(tail -3 "$w/out.log" 2>/dev/null))"
  [[ ! -e $w/calls/grok.calls ]] || fail "$lane: grok ran for plan under claudecode"
  grep -Fq 'You are the foreman station' "$w/calls/claude.stdin" || fail "$lane: plan did not use the foreman role"
  grep -Fq 'review this' "$w/calls/claude.stdin" || fail "$lane: plan prompt did not reach the provider"
  [[ $(wc -l < "$w/calls/runtime.log") -eq 1 ]] || fail "$lane: plan did not start the adapter through the container runtime"
  grep -Fq -- "--volume $w/target:$w/target " "$w/calls/runtime.log" || fail "$lane: plan did not mount the clone"
  grep -Fq -- '--env GH_TOKEN' "$w/calls/runtime.log" || fail "$lane: plan under claudecode did not get the bot token by name"
  if grep -Fq test-gh-token "$w/calls/runtime.log"; then fail "$lane: the token value is on the runtime argv"; fi
  w=$(GROK_TEST_GH_TOKEN=test-gh-token run_kind_case "$lane" claudecode plan "cc-plan-noapp" no)
  if grep -Fq -- 'GH_TOKEN' "$w/calls/runtime.log"; then fail "$lane: a token that is not the App's reached the plan provider"; fi
  echo "ok: $lane plan runs the claudecode adapter as foreman, with no grok on PATH"
  for p in "" grok; do
    w=$(GROK_TEST_GH_TOKEN=test-gh-token GROK_TEST_APP_ID=1 run_kind_case "$lane" "$p" plan "gplan-${p:-unset}" yes)
    [[ -s $w/calls/grok.calls ]] || fail "$lane: plan with FACTORY_PROVIDER='${p}' did not call grok"
    [[ ! -e $w/calls/claude.calls ]] || fail "$lane: claude ran for plan with FACTORY_PROVIDER='${p}'"
    expect="--prompt-file PROMPT --output-format json --max-turns 25 --always-approve --cwd $w/target --json-schema {\"type\":\"object\",\"required\":[\"verdict\"]}"
    got=$(sed -E 's#--prompt-file [^ ]+#--prompt-file PROMPT#' "$w/calls/grok.args")
    [[ $got == "$expect" ]] || fail "$lane: the grok command line for plan changed: [$got]"
    grep -Fq -- '--env GH_TOKEN' "$w/calls/runtime.log" || fail "$lane: plan on grok lost the bot token"
    echo "ok: $lane plan still calls grok with the same command line, FACTORY_PROVIDER='${p:-unset}'"
  done
done
# The GitHub token (#428). grok's container gets GH_TOKEN only for the kinds
# whose prompts call gh, and only when the App is configured, so the token is
# the bot's installation token and never the operator's own login.
for lane in watch watch.new; do
  w=$(GROK_TEST_GH_TOKEN=test-gh-token GROK_TEST_APP_ID=1 run_kind_case "$lane" grok dependabot-triage "tok-dep" yes)
  [[ -s $w/calls/grok.calls ]] || fail "$lane: dependabot-triage did not run grok ($(tail -3 "$w/out.log" 2>/dev/null))"
  grep -Fq -- '--env GH_TOKEN' "$w/calls/runtime.log" || fail "$lane: dependabot-triage did not get the bot token by name"
  if grep -Fq test-gh-token "$w/calls/runtime.log"; then fail "$lane: the token value is on the runtime argv"; fi
  w=$(GROK_TEST_GH_TOKEN=test-gh-token GROK_TEST_APP_ID=1 run_kind_case "$lane" grok review "tok-rev" yes)
  [[ -s $w/calls/grok.calls ]] || fail "$lane: review did not run grok"
  if grep -Fq -- 'GH_TOKEN' "$w/calls/runtime.log"; then fail "$lane: a review run was given a GitHub token"; fi
  w=$(GROK_TEST_GH_TOKEN=test-gh-token run_kind_case "$lane" grok dependabot-triage "tok-noapp" yes)
  [[ -s $w/calls/grok.calls ]] || fail "$lane: dependabot-triage without the App did not run grok"
  if grep -Fq -- 'GH_TOKEN' "$w/calls/runtime.log"; then fail "$lane: a token that is not the App's was handed to grok"; fi
  echo "ok: $lane gives grok the bot token only for the gh-calling kinds, and only with the App configured"
done

# FACTORY_GROK_ON_HOST (#440): the one explicit way to start grok outside the
# container, for a watcher host that is itself a sandbox.
for lane in watch watch.new; do
  w=$(GROK_TEST_ON_HOST=host-is-a-disposable-sandbox GROK_TEST_GH_TOKEN=test-gh-token GROK_TEST_APP_ID=1 \
    FACTORY_NO_IMAGE=1 run_kind_case "$lane" grok review "host-rev" yes)
  [[ -s $w/calls/grok.calls ]] || fail "$lane: grok did not run on the host with the phrase set ($(tail -3 "$w/out.log" 2>/dev/null))"
  [[ ! -s $w/calls/runtime.log ]] || fail "$lane: the container runtime was used although the host mode is set"
  grep -Fq 'grok uncontained kind=review' "$w/out.log" || fail "$lane: the uncontained run was not logged"
  read -r genv < "$w/calls/grok.env"
  [[ " $genv " == *" GH_CONFIG_DIR "* ]] || fail "$lane: grok on the host has no GH_CONFIG_DIR override: [$genv]"
  [[ $(cat "$w/calls/grok.ghcfg" 2>/dev/null) == 0 ]] || fail "$lane: grok's GH_CONFIG_DIR is not an empty directory"
  [[ " $genv " != *" GH_TOKEN "* && " $genv " != *" GITHUB_TOKEN "* ]] || fail "$lane: a review run on the host was given a GitHub token: [$genv]"
  [[ " $genv " != *" FACTORY_GH_APP_"* ]] || fail "$lane: the App settings reached grok on the host: [$genv]"
  [[ " $genv " != *" FACTORY_STATION_CONTAINER "* ]] || fail "$lane: the host run claims to be in the container"
  for rule in 'Read(' '.factory-secrets/**)' '.config/gh/**)' '.grok/auth.json)' 'Bash(*factory-secrets*)'; do
    grep -Fq -- "$rule" "$w/calls/grok.args" || fail "$lane: the host run is missing a deny rule containing $rule"
  done
  if grep -Fq -- 'Read(//' "$w/calls/grok.args"; then fail "$lane: a Read rule starts with //, which grok matches literally"; fi
  grep -Fq -- '--json-schema' "$w/calls/grok.args" || fail "$lane: the host run lost --json-schema"
  left=$(find "$w/watch/state" -maxdepth 1 -name 'grok-host.*' | wc -l)
  [[ $left -eq 0 ]] || fail "$lane: the empty gh config directory was left behind"

  w=$(GROK_TEST_ON_HOST=host-is-a-disposable-sandbox GROK_TEST_GH_TOKEN=test-gh-token GROK_TEST_APP_ID=1 \
    FACTORY_NO_IMAGE=1 run_kind_case "$lane" grok dependabot-triage "host-dep" yes)
  read -r genv < "$w/calls/grok.env"
  [[ " $genv " == *" GH_TOKEN "* ]] || fail "$lane: dependabot-triage on the host did not get the bot token: [$genv]"
  [[ " $genv " != *" FACTORY_GH_APP_"* ]] || fail "$lane: the App settings reached grok on the host: [$genv]"
  w=$(GROK_TEST_ON_HOST=host-is-a-disposable-sandbox GROK_TEST_GH_TOKEN=test-gh-token \
    FACTORY_NO_IMAGE=1 run_kind_case "$lane" grok dependabot-triage "host-dep-noapp" yes)
  read -r genv < "$w/calls/grok.env"
  [[ " $genv " != *" GH_TOKEN "* ]] || fail "$lane: a token that is not the App's reached grok on the host: [$genv]"

  for bad in 1 true yes host-is-a-sandbox; do
    w=$(GROK_TEST_ON_HOST=$bad FACTORY_NO_IMAGE=1 run_kind_case "$lane" grok review "host-bad-$bad" yes)
    [[ ! -e $w/calls/grok.calls ]] || fail "$lane: FACTORY_GROK_ON_HOST=$bad started grok on the host"
  done
  w=$(GROK_TEST_ON_HOST=host-is-a-disposable-sandbox run_kind_case "$lane" claudecode review "host-cc" no)
  [[ $(wc -l < "$w/calls/runtime.log") -eq 1 ]] || fail "$lane: the host mode took another provider out of the container"
  echo "ok: $lane starts grok on the host only with the exact phrase, logged, with gh and the App settings out of reach"
done

# With no image the watcher starts nothing: not grok on the host, not a container.
for lane in watch watch.new; do
  w=$(FACTORY_NO_IMAGE=1 run_kind_case "$lane" grok review "noimg" yes)
  [[ ! -e $w/calls/grok.calls ]] || fail "$lane: grok ran with no container image"
  [[ ! -s $w/calls/runtime.log ]] || fail "$lane: a container was started with no image"
  echo "ok: $lane starts no grok when the station container is not configured"
done
echo "all watcher provider tests passed"
