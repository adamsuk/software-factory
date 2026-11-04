#!/usr/bin/env bash
# Behaviour tests for the FACTORY_LLM backend switch in scripts/run-work-order.sh
# (grok, the default, or claude). The CI lint job shellchecks this file.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Private HOME before any factory script runs, so this suite never opens
# /home/box/.factory-secrets or a real key. Drop ambient secret names and the
# backend switch too, without printing their values.
HOME=$(mktemp -d)
export HOME
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN \
  FACTORY_GH_APP_ID FACTORY_GH_APP_INSTALLATION_ID FACTORY_GH_APP_KEY_FILE \
  FACTORY_GH_APP_ENV_FILE FACTORY_GH_APP_PRIVATE_KEY \
  AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN \
  GOOGLE_APPLICATION_CREDENTIALS CLOUDSDK_AUTH_ACCESS_TOKEN AZURE_CLIENT_SECRET \
  ANTHROPIC_API_KEY FACTORY_LLM CLAUDE_BIN CLAUDE_MAX_TURNS GROK_MAX_TURNS
# shellcheck source=scripts/run-work-order.sh
source "$here/run-work-order.sh"

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT" "$HOME"' EXIT
ORIG_PATH=$PATH
MOCK_BIN=$ROOT/mockbin
mkdir -p "$MOCK_BIN"

tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2] got [$1]"; }

case "$HOME" in
  /tmp/*|/var/tmp/*|"${TMPDIR:-/tmp}"/*) ;;
  *) fail "HOME is not a mktemp directory" ;;
esac
[[ "$HOME" != /home/box ]] || fail "HOME is the box home"
[[ ! -e "$HOME/.factory-secrets" ]] || fail "fake HOME contains factory-secrets"
[[ ! -e /home/box/.factory-secrets ]] || true # never read below, regardless

run_fail() {
  local want=$1
  shift
  local code=0 out
  out=$("$@" 2>&1) || code=$?
  assert_eq "$code" "$want"
  captured=$out
}

mkfake() {
  local name=$1 dir=$2
  mkdir -p "$dir"
  cat > "$dir/$name" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$dir/$name"
}

# --- resolve_llm_backend: pure unit tests, no clone or network -------------

tname="llm-default-is-grok"
unset FACTORY_LLM CLAUDE_BIN
grok_only=$ROOT/grok-only
mkfake grok "$grok_only"
PATH="$grok_only:$ORIG_PATH"
resolve_llm_backend
assert_eq "$llm_backend" "grok"
PATH=$ORIG_PATH

tname="llm-default-grok-missing-binary"
unset FACTORY_LLM
empty_bin=$ROOT/empty-bin
mkdir -p "$empty_bin"
PATH="$empty_bin"
run_fail 2 resolve_llm_backend
[[ "$captured" == *"grok not found"* ]] || fail "missing grok not found message: $captured"
PATH=$ORIG_PATH

tname="llm-explicit-grok"
FACTORY_LLM=grok
export FACTORY_LLM
PATH="$grok_only:$ORIG_PATH"
resolve_llm_backend
assert_eq "$llm_backend" "grok"
PATH=$ORIG_PATH
unset FACTORY_LLM

tname="llm-claude-selected"
FACTORY_LLM=claude
export FACTORY_LLM
claude_only=$ROOT/claude-only
mkfake claude "$claude_only"
PATH="$claude_only:$ORIG_PATH"
resolve_llm_backend
assert_eq "$llm_backend" "claude"
assert_eq "$claude_bin" "claude"
PATH=$ORIG_PATH
unset FACTORY_LLM

tname="llm-claude-missing-binary"
FACTORY_LLM=claude
export FACTORY_LLM
PATH="$empty_bin"
run_fail 2 resolve_llm_backend
[[ "$captured" == *"claude not found"* ]] || fail "missing claude not found message: $captured"
PATH=$ORIG_PATH
unset FACTORY_LLM

tname="llm-claude-bin-override"
FACTORY_LLM=claude
custom_dir=$ROOT/custom-claude-bin
mkfake my-claude-cli "$custom_dir"
CLAUDE_BIN=my-claude-cli
export FACTORY_LLM CLAUDE_BIN
PATH="$custom_dir:$ORIG_PATH"
resolve_llm_backend
assert_eq "$llm_backend" "claude"
assert_eq "$claude_bin" "my-claude-cli"
PATH=$ORIG_PATH
unset FACTORY_LLM CLAUDE_BIN

tname="llm-unknown-backend"
FACTORY_LLM=chatgpt
export FACTORY_LLM
run_fail 2 resolve_llm_backend
[[ "$captured" == *"FACTORY_LLM must be grok or claude"* ]] || fail "missing bad-backend message: $captured"
unset FACTORY_LLM

# --- main() source: the claude branch exists, is gated on FACTORY_LLM, and -
# never runs unless selected. Confirm via declare -f main, without calling
# main (clone, gh and a real grok/claude are not mocked for a full run).

tname="claude-branch-in-main"
main_src=$(declare -f main)
if_line=$(printf '%s\n' "$main_src" | awk '/if \[\[ "\$llm_backend" != "claude" \]\]; then/ { print NR; exit }')
[[ -n "$if_line" ]] || fail "main does not branch on llm_backend"
else_line=$(printf '%s\n' "$main_src" | awk -v s="$if_line" 'NR>s && /^[[:space:]]*else[[:space:]]*$/ { print NR; exit }')
[[ -n "$else_line" ]] || fail "could not find the else for the llm_backend if"
fi_line=$(printf '%s\n' "$main_src" | awk -v s="$else_line" 'NR>s && /^[[:space:]]*fi;?[[:space:]]*$/ { print NR; exit }')
[[ -n "$fi_line" ]] || fail "could not find the fi for the llm_backend if"

grok_block=$(printf '%s\n' "$main_src" | awk -v a="$if_line" -v b="$else_line" 'NR>a && NR<b')
claude_block=$(printf '%s\n' "$main_src" | awk -v a="$else_line" -v b="$fi_line" 'NR>a && NR<b')
[[ -n "$grok_block" ]] || fail "grok block is empty"
[[ -n "$claude_block" ]] || fail "claude block is empty"

# The default branch (llm_backend != claude) is still the unchanged grok call.
[[ "$grok_block" == *"grok --no-auto-update"* ]] || fail "default branch does not run grok"
[[ "$grok_block" != *"claude"* ]] || fail "default branch mentions claude"

# The claude branch runs claude, not grok, with its own max-turns and cwd.
[[ "$claude_block" != *"grok --no-auto-update"* ]] || fail "claude branch still runs grok"
# shellcheck disable=SC2016  # literal source text, not expansion
[[ "$claude_block" == *'"$claude_bin"'* ]] || fail "claude branch does not invoke \$claude_bin"
[[ "$claude_block" == *"-p"* ]] || fail "claude branch is missing -p"
[[ "$claude_block" == *"--output-format json"* ]] || fail "claude branch is missing --output-format json"
[[ "$claude_block" == *"--max-turns"* ]] || fail "claude branch is missing --max-turns"
# shellcheck disable=SC2016  # literal source text, not expansion
[[ "$claude_block" == *'${CLAUDE_MAX_TURNS:-${GROK_MAX_TURNS:-60}}'* ]] \
  || fail "claude branch does not fall back from CLAUDE_MAX_TURNS to GROK_MAX_TURNS"
[[ "$claude_block" == *"cd "* ]] || fail "claude branch does not cd (claude has no --cwd)"
[[ "$claude_block" == *"--permission-mode bypassPermissions"* ]] \
  || fail "claude branch does not bypass permissions (parity with --always-approve)"
[[ "$claude_block" == *"factory-secrets"* ]] || fail "claude branch does not guard /home/box/.factory-secrets"
[[ "$claude_block" == *"WebSearch"* && "$claude_block" == *"WebFetch"* ]] \
  || fail "claude branch does not disallow WebSearch/WebFetch (parity with --disable-web-search)"
[[ "$claude_block" == *"-u ANTHROPIC_API_KEY"* ]] || fail "claude branch does not scrub ANTHROPIC_API_KEY"
[[ "$claude_block" == *"-u GH_TOKEN"* && "$claude_block" == *"-u GITHUB_TOKEN"* ]] \
  || fail "claude branch does not scrub GH_TOKEN/GITHUB_TOKEN"
for scrub_name in GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN FACTORY_GH_APP_ID \
  FACTORY_GH_APP_INSTALLATION_ID FACTORY_GH_APP_KEY_FILE FACTORY_GH_APP_ENV_FILE \
  FACTORY_GH_APP_PRIVATE_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN \
  AWS_SECURITY_TOKEN GOOGLE_APPLICATION_CREDENTIALS CLOUDSDK_AUTH_ACCESS_TOKEN AZURE_CLIENT_SECRET; do
  [[ "$claude_block" == *"-u ${scrub_name}"* ]] || fail "claude branch does not scrub ${scrub_name}"
done
[[ "$main_src" != *"export GH_TOKEN"* && "$main_src" != *"export GITHUB_TOKEN"* ]] \
  || fail "main re-exports a token"
# Both backends land in the same file: callers that read it for cost are unaffected.
# shellcheck disable=SC2016  # literal source text, not expansion
[[ "$claude_block" == *'"$dir.grok.json"'* ]] || fail "claude branch does not write \$dir.grok.json"
# shellcheck disable=SC2016  # literal source text, not expansion
[[ "$main_src" == *'die 3 "$llm_backend exit'* ]] || fail "the end_turn check is not backend-generic"

# --- run the extracted claude branch for real, against a mock claude -------
# Same technique scripts/test-run-work-order.sh uses for grok-token-scrub:
# the block is real code, evaluated with order/rules/dir/claude_bin set and a
# mock claude on PATH that records its environment, args, cwd and stdin.

run_claude_block() {
  local subtype=$1 is_error=$2 want_stop=$3
  tname="claude-run-${subtype}-${is_error}"
  local work=$ROOT/claude-run-$subtype-$is_error
  mkdir -p "$work/bin"
  dir=$work/clone
  mkdir -p "$dir"
  order=$work/order.md
  printf '%s\n' '---' 'repo: acme/widgets' '---' 'do the thing' > "$order"
  rules=$work/AGENTS.md
  printf '%s\n' 'RULES_MARKER_TEXT' > "$rules"

  cat > "$work/bin/claude" << MOCK
#!/usr/bin/env bash
env > "\$CLAUDE_ENV_DUMP"
printf '%s\n' "\$*" > "\$CLAUDE_ARGS_DUMP"
pwd > "\$CLAUDE_PWD_DUMP"
cat > "\$CLAUDE_STDIN_DUMP"
printf '%s\n' '{"type":"result","subtype":"$subtype","is_error":$is_error,"num_turns":5,"total_cost_usd":0.42,"result":"ok"}'
MOCK
  chmod +x "$work/bin/claude"

  CLAUDE_ENV_DUMP=$work/env.txt
  CLAUDE_ARGS_DUMP=$work/args.txt
  CLAUDE_PWD_DUMP=$work/pwd.txt
  CLAUDE_STDIN_DUMP=$work/stdin.txt
  export CLAUDE_ENV_DUMP CLAUDE_ARGS_DUMP CLAUDE_PWD_DUMP CLAUDE_STDIN_DUMP
  local gh_config_dir=$work/ghconfig
  mkdir -p "$gh_config_dir"

  (
    export GH_TOKEN=sentinel-gh-token GITHUB_TOKEN=sentinel-github-token
    export ANTHROPIC_API_KEY=sentinel-anthropic-key
    export GH_ENTERPRISE_TOKEN=sentinel-ghe GITHUB_ENTERPRISE_TOKEN=sentinel-githubent
    export FACTORY_GH_APP_ID=sentinel-app-id FACTORY_GH_APP_INSTALLATION_ID=sentinel-app-install
    export FACTORY_GH_APP_KEY_FILE=sentinel-app-key-file FACTORY_GH_APP_ENV_FILE=sentinel-app-env-file
    export FACTORY_GH_APP_PRIVATE_KEY=sentinel-app-private-key
    export AWS_ACCESS_KEY_ID=sentinel-aws-key AWS_SECRET_ACCESS_KEY=sentinel-aws-secret
    export AWS_SESSION_TOKEN=sentinel-aws-session AWS_SECURITY_TOKEN=sentinel-aws-security
    export GOOGLE_APPLICATION_CREDENTIALS=sentinel-google-creds
    export CLOUDSDK_AUTH_ACCESS_TOKEN=sentinel-cloudsdk CLOUDSDK_AUTH_ACCESS_TOKEN=sentinel-cloudsdk
    export AZURE_CLIENT_SECRET=sentinel-azure-secret
    export GIT_ASKPASS=sentinel-git-askpass SSH_AUTH_SOCK=sentinel-ssh-auth-sock
    export GH_REPO=acme/widgets GH_HOST=github.example
    claude_bin=claude
    PATH="$work/bin:$ORIG_PATH"
    export PATH
    status=0
    eval "$claude_block"
    printf '%s\n' "$status" > "$work/status.txt"
  ) || fail "claude block eval failed"

  [[ -s "$work/env.txt" ]] || fail "mock claude did not run"
  if grep -qE '^(GH_TOKEN|GITHUB_TOKEN|ANTHROPIC_API_KEY)=' "$work/env.txt"; then
    fail "a scrubbed token reached claude's environment"
  fi
  ! grep -qE 'sentinel-(gh-token|github-token|anthropic-key)' "$work/env.txt" \
    || fail "a scrubbed token value leaked into claude's environment"
  grep -qxF 'GH_REPO=acme/widgets' "$work/env.txt" || fail "GH_REPO missing from claude's environment"
  grep -qxF 'GH_HOST=github.example' "$work/env.txt" || fail "GH_HOST missing from claude's environment"
  grep -qxF "GH_CONFIG_DIR=$gh_config_dir" "$work/env.txt" || fail "GH_CONFIG_DIR not passed to claude"
  grep -qxF 'GIT_TERMINAL_PROMPT=0' "$work/env.txt" || fail "GIT_TERMINAL_PROMPT not set to 0 for claude"
  if grep -qE '^GIT_ASKPASS=' "$work/env.txt"; then
    fail "GIT_ASKPASS leaked into claude's environment"
  fi
  if grep -qE '^SSH_AUTH_SOCK=' "$work/env.txt"; then
    fail "SSH_AUTH_SOCK leaked into claude's environment"
  fi
  ! grep -qE 'sentinel-(git-askpass|ssh-auth-sock)' "$work/env.txt" \
    || fail "a scrubbed GIT_ASKPASS/SSH_AUTH_SOCK value leaked into claude's environment"

  grep -qF -- "--max-turns" "$work/args.txt" || fail "--max-turns was not passed to claude"
  grep -qF -- "--permission-mode bypassPermissions" "$work/args.txt" || fail "permission mode missing"
  grep -qF -- "Read(//home/box/.factory-secrets/**)" "$work/args.txt" \
    || fail "claude branch does not //-anchor the factory-secrets Read deny"
  grep -qF -- "Bash(*factory-secrets*)" "$work/args.txt" || fail "factory-secrets Bash guard missing from args"
  grep -qF -- "Bash(git push*)" "$work/args.txt" || fail "git push deny missing from disallowedTools"
  grep -qF -- "Bash(gh *)" "$work/args.txt" || fail "gh deny missing from disallowedTools"
  grep -qF -- "Bash(gh)" "$work/args.txt" || fail "bare gh deny missing from disallowedTools"
  grep -qF -- "WebSearch" "$work/args.txt" || fail "WebSearch not disallowed"
  grep -qF -- "WebFetch" "$work/args.txt" || fail "WebFetch not disallowed"

  assert_eq "$(cat "$work/pwd.txt")" "$(cd "$dir" && pwd)"
  grep -qF "RULES_MARKER_TEXT" "$work/stdin.txt" || fail "prompt on stdin is missing the rules text"
  grep -qF "do the thing" "$work/stdin.txt" || fail "prompt on stdin is missing the work order text"

  [[ -f "$dir.grok.json" ]] || fail "claude branch did not write \$dir.grok.json"
  got_stop=$(jq -r '.stopReason' "$dir.grok.json")
  assert_eq "$got_stop" "$want_stop"
  assert_eq "$(jq -r '.total_cost_usd' "$dir.grok.json")" "0.42"
  assert_eq "$(jq -r '.num_turns' "$dir.grok.json")" "5"

  unset CLAUDE_ENV_DUMP CLAUDE_ARGS_DUMP CLAUDE_PWD_DUMP CLAUDE_STDIN_DUMP
}

run_claude_block success false end_turn
run_claude_block error_max_turns false max_turn_requests
run_claude_block error_during_execution true error_during_execution

tname="claude-max-turns-env"
work=$ROOT/claude-max-turns
mkdir -p "$work/bin"
dir=$work/clone
mkdir -p "$dir"
order=$work/order.md
printf '%s\n' '---' 'repo: acme/widgets' '---' > "$order"
rules=$work/AGENTS.md
printf '%s\n' 'rules' > "$rules"
cat > "$work/bin/claude" << 'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CLAUDE_ARGS_DUMP"
cat > /dev/null
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
MOCK
chmod +x "$work/bin/claude"
CLAUDE_ARGS_DUMP=$work/args.txt
export CLAUDE_ARGS_DUMP
(
  claude_bin=claude
  gh_config_dir=$work/ghconfig
  CLAUDE_MAX_TURNS=17
  export CLAUDE_MAX_TURNS
  GROK_MAX_TURNS=99
  export GROK_MAX_TURNS
  PATH="$work/bin:$ORIG_PATH"
  export PATH
  status=0
  eval "$claude_block"
)
args=$(cat "$work/args.txt")
[[ "$args" == *"--max-turns 17"* ]] || fail "CLAUDE_MAX_TURNS was not used: $args"
unset CLAUDE_ARGS_DUMP

tname="claude-max-turns-falls-back-to-grok"
work=$ROOT/claude-max-turns-fallback
mkdir -p "$work/bin"
dir=$work/clone
mkdir -p "$dir"
order=$work/order.md
printf '%s\n' '---' 'repo: acme/widgets' '---' > "$order"
rules=$work/AGENTS.md
printf '%s\n' 'rules' > "$rules"
cp "$ROOT/claude-max-turns/bin/claude" "$work/bin/claude"
CLAUDE_ARGS_DUMP=$work/args.txt
export CLAUDE_ARGS_DUMP
(
  unset CLAUDE_MAX_TURNS
  claude_bin=claude
  gh_config_dir=$work/ghconfig
  GROK_MAX_TURNS=33
  export GROK_MAX_TURNS
  PATH="$work/bin:$ORIG_PATH"
  export PATH
  status=0
  eval "$claude_block"
)
args=$(cat "$work/args.txt")
[[ "$args" == *"--max-turns 33"* ]] || fail "GROK_MAX_TURNS fallback was not used: $args"
unset CLAUDE_ARGS_DUMP

# --- gh_config_dir: created fresh, exported as GH_CONFIG_DIR, removed after -
# the run, for both backends (and its INT/TERM/EXIT cleanup trap). Extract the
# whole dispatch block, from where gh_config_dir is created to the final
# restore_traps call, out of declare -f main and eval it for real, same
# technique as run_claude_block above.

main_src=$(declare -f main)
dispatch_block=$(printf '%s\n' "$main_src" | awk '
  /gh_config_dir=\$\(mktemp -d\)/ { on = 1 }
  on { print }
  on && /restore_traps "\$prev_llm_traps"/ { exit }
')
[[ -n "$dispatch_block" ]] || fail "could not extract the gh_config_dir dispatch block from main"
# shellcheck disable=SC2016  # literal source text, not expansion
[[ "$dispatch_block" == *'GH_CONFIG_DIR="$gh_config_dir"'* ]] \
  || fail "dispatch block does not export GH_CONFIG_DIR"
grok_dispatch=$(printf '%s\n' "$dispatch_block" | awk '/if \[\[ "\$llm_backend" != "claude" \]\]; then/,/^[[:space:]]*else[[:space:]]*$/')
# shellcheck disable=SC2016  # literal source text, not expansion
[[ "$grok_dispatch" == *'GH_CONFIG_DIR="$gh_config_dir"'* ]] \
  || fail "grok branch does not export GH_CONFIG_DIR"

run_dispatch_block() {
  local backend=$1 bin_name=$2
  tname="gh-config-dir-$backend"
  local work=$ROOT/gh-config-dir-$backend
  mkdir -p "$work/bin"
  dir=$work/clone
  mkdir -p "$dir"
  order=$work/order.md
  printf '%s\n' '---' 'repo: acme/widgets' '---' 'do the thing' > "$order"
  rules=$work/AGENTS.md
  printf '%s\n' 'rules' > "$rules"

  if [[ "$backend" == grok ]]; then
    cat > "$work/bin/$bin_name" << MOCK
#!/usr/bin/env bash
env > "\$LLM_ENV_DUMP"
[[ -d "\$GH_CONFIG_DIR" ]] && echo exists > "\$LLM_DIR_CHECK" || echo missing > "\$LLM_DIR_CHECK"
printf '%s\n' '{"stopReason":"end_turn"}'
MOCK
  else
    cat > "$work/bin/$bin_name" << MOCK
#!/usr/bin/env bash
env > "\$LLM_ENV_DUMP"
[[ -d "\$GH_CONFIG_DIR" ]] && echo exists > "\$LLM_DIR_CHECK" || echo missing > "\$LLM_DIR_CHECK"
cat > /dev/null
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
MOCK
  fi
  chmod +x "$work/bin/$bin_name"

  LLM_ENV_DUMP=$work/env.txt
  LLM_DIR_CHECK=$work/dircheck.txt
  export LLM_ENV_DUMP LLM_DIR_CHECK

  (
    llm_backend=$backend
    claude_bin=$bin_name
    PATH="$work/bin:$ORIG_PATH"
    export PATH
    status=0
    eval "$dispatch_block"
  ) || fail "dispatch block eval failed for $backend"

  [[ -s "$work/env.txt" ]] || fail "mock $bin_name did not run"
  assert_eq "$(cat "$work/dircheck.txt")" "exists"
  local gh_config_line captured_dir
  gh_config_line=$(grep '^GH_CONFIG_DIR=' "$work/env.txt") || fail "GH_CONFIG_DIR not set for $backend"
  captured_dir=${gh_config_line#GH_CONFIG_DIR=}
  [[ -n "$captured_dir" ]] || fail "GH_CONFIG_DIR was empty for $backend"
  [[ "$captured_dir" == /* ]] || fail "GH_CONFIG_DIR ($captured_dir) is not an absolute path for $backend"
  [[ "$captured_dir" != "$HOME/.config/gh" && "$captured_dir" != "${XDG_CONFIG_HOME:-}/gh" ]] \
    || fail "GH_CONFIG_DIR points at the real gh config for $backend"
  [[ ! -e "$captured_dir" ]] || fail "GH_CONFIG_DIR ($captured_dir) was not removed after the $backend run"

  unset LLM_ENV_DUMP LLM_DIR_CHECK
}

run_dispatch_block grok grok
run_dispatch_block claude claude

# --- check_secrets_dir_perms: tightens a loose secrets dir, leaves a tight --
# one alone, and is a no-op when the directory does not exist.

tname="secrets-dir-perms-tightened"
loose_dir=$ROOT/loose-secrets
mkdir -p "$loose_dir"
chmod 0755 "$loose_dir"
FACTORY_SECRETS_DIR=$loose_dir check_secrets_dir_perms
assert_eq "$(stat -c '%a' "$loose_dir")" "700"

tname="secrets-dir-perms-already-tight"
tight_dir=$ROOT/tight-secrets
mkdir -p "$tight_dir"
chmod 0700 "$tight_dir"
FACTORY_SECRETS_DIR=$tight_dir check_secrets_dir_perms
assert_eq "$(stat -c '%a' "$tight_dir")" "700"

tname="secrets-dir-perms-missing-is-noop"
missing_dir=$ROOT/no-such-secrets-dir
FACTORY_SECRETS_DIR=$missing_dir check_secrets_dir_perms
[[ ! -e "$missing_dir" ]] || fail "check_secrets_dir_perms created $missing_dir"

PATH=$ORIG_PATH
echo "ok  run-work-order llm backend tests"
