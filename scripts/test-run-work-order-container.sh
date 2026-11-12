#!/usr/bin/env bash
# Behaviour tests for the fresh-container grok child in
# scripts/run-work-order.sh (sandbox-no-secrets, #221). CI lints this file
# with shellcheck. It prints only pass/fail and never a sentinel value.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Private HOME before any factory script runs, so this suite never touches the
# box's real gh config, App key or secrets directory. Drop ambient secret
# names and the container settings, without printing their values.
HOME=$(mktemp -d)
export HOME
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN \
  FACTORY_GH_APP_ID FACTORY_GH_APP_INSTALLATION_ID FACTORY_GH_APP_KEY_FILE \
  FACTORY_GH_APP_ENV_FILE FACTORY_GH_APP_PRIVATE_KEY \
  AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN \
  GOOGLE_APPLICATION_CREDENTIALS CLOUDSDK_AUTH_ACCESS_TOKEN AZURE_CLIENT_SECRET \
  XAI_API_KEY FACTORY_CONTAINER_IMAGE FACTORY_CONTAINER_RUNTIME FACTORY_LLM
# shellcheck source=scripts/run-work-order.sh
source "$here/run-work-order.sh"

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT" "$HOME"' EXIT
ORIG_PATH=$PATH

tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2] got [$1]"; }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "$3"; }
assert_not_contains() { [[ "$1" != *"$2"* ]] || fail "$3"; }

# Sentinel values stand in for the box's real secrets. They never appear in
# the output text of this suite, only in the paths and file contents below.
sentinel_xai="sentinel-221-xai-key"
sentinel_gh_token="sentinel-221-gh-token"
sentinel_github_token="sentinel-221-github-token"
sentinel_aws="sentinel-221-aws-secret"
sentinel_key="sentinel-221-app-key"
sentinel_gh_config="sentinel-221-gh-config"

empty_bin=$ROOT/empty-bin
mkdir -p "$empty_bin"
clone=$ROOT/clone
mkdir -p "$clone"
fenced_order=$ROOT/fenced-order.md
printf '%s\n' 'fenced order' > "$fenced_order"

# --- runtime and image selection -------------------------------------------

tname="no-runtime"
code=0
out=$(PATH="$empty_bin" FACTORY_CONTAINER_IMAGE=factory-bench:test \
  build_container_command "$clone" "$fenced_order" 2>&1) || code=$?
assert_eq "$code" "9"
assert_contains "$out" "cannot start a container" "no-runtime error does not say it cannot start a container"
assert_contains "$out" "podman" "no-runtime error does not name the runtimes it tried"
assert_contains "$out" "FACTORY_CONTAINER_RUNTIME" "no-runtime error does not name the override"
[[ ${#container_cmd[@]} -eq 0 ]] || fail "container_cmd was built with no runtime"

tname="no-image"
podman_bin=$ROOT/podman-bin
mkdir -p "$podman_bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$podman_bin/podman"
chmod +x "$podman_bin/podman"
code=0
out=$(PATH="$podman_bin:$ORIG_PATH" FACTORY_CONTAINER_IMAGE='' \
  build_container_command "$clone" "$fenced_order" 2>&1) || code=$?
assert_eq "$code" "9"
assert_contains "$out" "cannot start a container" "no-image error does not say it cannot start a container"
assert_contains "$out" "FACTORY_CONTAINER_IMAGE" "no-image error does not name FACTORY_CONTAINER_IMAGE"

tname="runtime-override-missing"
code=0
out=$(PATH="$ORIG_PATH" FACTORY_CONTAINER_IMAGE=factory-bench:test \
  FACTORY_CONTAINER_RUNTIME=no-such-runtime-221 \
  build_container_command "$clone" "$fenced_order" 2>&1) || code=$?
assert_eq "$code" "9"
assert_contains "$out" "cannot start a container" "missing override runtime does not say it cannot start a container"

# --- the runtime invocation itself ------------------------------------------

tname="build-command"
XAI_API_KEY=$sentinel_xai
export XAI_API_KEY
FACTORY_CONTAINER_IMAGE=factory-bench:test
unset FACTORY_CONTAINER_RUNTIME
PATH="$podman_bin:$ORIG_PATH"
export PATH
build_container_command "$clone" "$fenced_order"
assert_eq "${container_cmd[0]}" "podman"
assert_eq "${container_cmd[1]}" "run"
assert_eq "${container_cmd[${#container_cmd[@]}-1]}" "factory-bench:test"
argv=$(printf '%s ' "${container_cmd[@]}")
assert_contains "$argv" "--volume $clone:$clone " "clone is not bind-mounted read-write at its host path"
assert_contains "$argv" "--volume $fenced_order:$fenced_order:ro " "fenced order is not bind-mounted read-only"
assert_contains "$argv" "--env HOME=/factory-home " "container HOME is not a fresh tmpfs path"
assert_contains "$argv" "--tmpfs /factory-home " "HOME tmpfs is missing"
assert_contains "$argv" "--env TMPDIR=/factory-tmp " "container TMPDIR is not a fresh tmpfs path"
assert_contains "$argv" "--tmpfs /factory-tmp " "TMPDIR tmpfs is missing"
assert_contains "$argv" " --env XAI_API_KEY " "XAI_API_KEY is not forwarded by name"
assert_not_contains "$argv" "XAI_API_KEY=" "XAI_API_KEY was forwarded with its value on argv"
assert_not_contains "$argv" "$sentinel_xai" "the XAI key value is on the runtime argv"
assert_not_contains "$argv" "$HOME" "the runtime argv names the box HOME"
assert_not_contains "$argv" "--always-approve" "the runtime argv still carries --always-approve"
[[ $(printf '%s\n' "${container_cmd[@]}" | grep -c -x -- '--volume') -eq 2 ]] \
  || fail "the runtime is given something other than exactly two bind mounts"

tname="runtime-override"
nerdctl_bin=$ROOT/nerdctl-bin
mkdir -p "$nerdctl_bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$nerdctl_bin/nerdctl"
chmod +x "$nerdctl_bin/nerdctl"
FACTORY_CONTAINER_RUNTIME=nerdctl
export FACTORY_CONTAINER_RUNTIME
PATH="$nerdctl_bin:$ORIG_PATH"
export PATH
build_container_command "$clone" "$fenced_order"
assert_eq "${container_cmd[0]}" "nerdctl"
argv=$(printf '%s ' "${container_cmd[@]}")
assert_contains "$argv" "--user $(id -u):$(id -g) " "docker/nerdctl does not run as the calling user"
unset FACTORY_CONTAINER_RUNTIME
PATH=$ORIG_PATH
export PATH

# --- the real launch, through a fake runtime -------------------------------
# The fake runtime records its argv, then runs the child command the way a
# container would: a fresh environment holding only the forwarded names (plus
# a deliberate worst-case leak of the scrub names), and stand-in directories
# for the two tmpfs mounts. The fake grok records what it can see.

tname="launch-through-container"
work=$ROOT/launch
mkdir -p "$work/bin"
cat > "$work/bin/podman" << 'MOCK'
#!/usr/bin/env bash
# Fake container runtime: record argv, then run the child command with a
# container-like environment and fresh stand-ins for the two tmpfs mounts.
printf '%s\n' "$@" > "$FAKE_RUNTIME_ARGV"
envs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    run | --rm | -i) shift ;;
    --volume)
      printf '%s\n' "$2" >> "$FAKE_RUNTIME_MOUNTS"
      shift 2
      ;;
    --env)
      envs+=("$2")
      shift 2
      ;;
    --tmpfs | --workdir | --user) shift 2 ;;
    *)
      shift
      break
      ;;
  esac
done
mkdir -p "$FAKE_HOME" "$FAKE_TMPDIR"
run_env=(
  env -i "PATH=$FAKE_CHILD_PATH" "HOME=$FAKE_HOME" "TMPDIR=$FAKE_TMPDIR"
  "GH_TOKEN=$FAKE_LEAK_GH_TOKEN" "GITHUB_TOKEN=$FAKE_LEAK_GITHUB_TOKEN"
  "FACTORY_GH_APP_KEY_FILE=$FAKE_LEAK_KEY_FILE" "AWS_SECRET_ACCESS_KEY=$FAKE_LEAK_AWS"
  "SSH_AUTH_SOCK=$FAKE_LEAK_SSH" "GIT_ASKPASS=$FAKE_LEAK_ASKPASS"
)
for name in "${envs[@]}"; do
  case "$name" in
    HOME=* | TMPDIR=*) continue ;;
    *=*) run_env+=("$name") ;;
    *)
      if [[ -n ${!name:-} ]]; then run_env+=("$name=${!name}"); fi
      ;;
  esac
done
# Harness plumbing: the fake grok's recording paths, not container settings.
run_env+=("FAKE_GROK_ARGV=$FAKE_GROK_ARGV" "FAKE_GROK_ENV=$FAKE_GROK_ENV"
  "FAKE_GROK_GH_CONFIG=$FAKE_GROK_GH_CONFIG")
exec "${run_env[@]}" "$@"
MOCK
cat > "$work/bin/grok" << 'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_GROK_ARGV"
env > "$FAKE_GROK_ENV"
if [[ -f "$HOME/.config/gh/hosts.yml" ]]; then
  printf '%s\n' readable > "$FAKE_GROK_GH_CONFIG"
else
  printf '%s\n' hidden > "$FAKE_GROK_GH_CONFIG"
fi
printf '%s\n' '{"stopReason":"end_turn"}'
MOCK
chmod +x "$work/bin/podman" "$work/bin/grok"

dir=$work/clone
clone=$dir
mkdir -p "$dir"
printf '%s\n' 'clone file' > "$dir/file.txt"
fenced_order=$work/fenced-order.md
printf '%s\n' 'fenced order' > "$fenced_order"
rules=$work/AGENTS.md
printf '%s\n' 'rules' > "$rules"
gh_config_dir=$work/ghconfig
mkdir -p "$gh_config_dir"
key_file=$work/app-key.pem
printf '%s\n' "$sentinel_key" > "$key_file"
mkdir -p "$HOME/.config/gh"
printf '%s\n' "$sentinel_gh_config" > "$HOME/.config/gh/hosts.yml"

# Extract the whole launch from main's source (declare -f strips comments and
# joins the continuations, so the prefix and the grok argv are one line).
main_src=$(declare -f main)
launch=$(printf '%s\n' "$main_src" | awk '/container_cmd\[@\]/ {on=1} on {print} on && />/ {exit}')
[[ -n "$launch" ]] || fail "could not extract the container launch from main"
assert_contains "$launch" "grok --no-auto-update" "the extracted launch does not run grok"
assert_not_contains "$launch" "--always-approve" "the grok argv still carries --always-approve"
assert_contains "$launch" "--sandbox workspace" "the grok argv lost --sandbox workspace"
assert_contains "$launch" "--disable-web-search" "the grok argv lost --disable-web-search"
assert_contains "$launch" "'Bash(git push*)'" "the grok argv lost the git push deny"
assert_contains "$launch" "'Bash(gh *)'" "the grok argv lost the gh deny"
assert_contains "$launch" "-u GIT_ASKPASS" "the grok argv lost the GIT_ASKPASS scrub"
assert_contains "$launch" "-u SSH_AUTH_SOCK" "the grok argv lost the SSH_AUTH_SOCK scrub"

(
  PATH="$work/bin:$ORIG_PATH"
  export PATH
  FAKE_RUNTIME_ARGV=$work/runtime-argv.txt
  FAKE_RUNTIME_MOUNTS=$work/runtime-mounts.txt
  FAKE_CHILD_PATH="$work/bin:$ORIG_PATH"
  FAKE_HOME=$work/container-home
  FAKE_TMPDIR=$work/container-tmp
  FAKE_GROK_ARGV=$work/grok-argv.txt
  FAKE_GROK_ENV=$work/grok-env.txt
  FAKE_GROK_GH_CONFIG=$work/grok-gh-config.txt
  FAKE_LEAK_GH_TOKEN=$sentinel_gh_token
  FAKE_LEAK_GITHUB_TOKEN=$sentinel_github_token
  FAKE_LEAK_KEY_FILE=$key_file
  FAKE_LEAK_AWS=$sentinel_aws
  FAKE_LEAK_SSH=$work/ssh-agent.sock
  FAKE_LEAK_ASKPASS=$work/askpass
  export FAKE_RUNTIME_ARGV FAKE_RUNTIME_MOUNTS FAKE_CHILD_PATH FAKE_HOME \
    FAKE_TMPDIR FAKE_GROK_ARGV FAKE_GROK_ENV FAKE_GROK_GH_CONFIG \
    FAKE_LEAK_GH_TOKEN FAKE_LEAK_GITHUB_TOKEN FAKE_LEAK_KEY_FILE FAKE_LEAK_AWS \
    FAKE_LEAK_SSH FAKE_LEAK_ASKPASS
  XAI_API_KEY=$sentinel_xai
  export XAI_API_KEY
  export GH_TOKEN=$sentinel_gh_token GITHUB_TOKEN=$sentinel_github_token
  export FACTORY_GH_APP_KEY_FILE=$key_file
  export AWS_SECRET_ACCESS_KEY=$sentinel_aws
  export SSH_AUTH_SOCK=$work/ssh-agent.sock GIT_ASKPASS=$work/askpass
  FACTORY_CONTAINER_IMAGE=factory-bench:test
  unset FACTORY_CONTAINER_RUNTIME
  build_container_command "$dir" "$fenced_order"
  status=0
  eval "$launch"
  printf '%s\n' "$status" > "$work/status.txt"
) || fail "the container launch did not run"

assert_eq "$(cat "$work/status.txt")" "0"
runtime_argv=$(tr '\n' ' ' < "$work/runtime-argv.txt")
grok_argv=$(tr '\n' ' ' < "$work/grok-argv.txt")
grok_env=$(cat "$work/grok-env.txt")

assert_contains "$runtime_argv" "factory-bench:test" "the runtime was not given the image"
assert_contains "$runtime_argv" "$clone:$clone" "the runtime argv lost the clone mount"
assert_contains "$runtime_argv" "$fenced_order:$fenced_order:ro" "the runtime argv lost the read-only order mount"
assert_contains "$(cat "$work/runtime-mounts.txt")" "$clone:$clone" "the clone was not bind-mounted"
assert_contains "$(cat "$work/runtime-mounts.txt")" "$fenced_order:$fenced_order:ro" "the order was not bind-mounted read-only"
for secret in "$sentinel_xai" "$sentinel_gh_token" "$sentinel_github_token" "$sentinel_aws" "$sentinel_key"; do
  assert_not_contains "$runtime_argv" "$secret" "a secret value is on the runtime argv"
done
assert_not_contains "$runtime_argv" "$HOME" "the runtime argv names the box HOME"
assert_not_contains "$runtime_argv" "$key_file" "the runtime argv names the App key file"

assert_contains "$grok_argv" "--sandbox workspace" "grok lost --sandbox workspace"
assert_contains "$grok_argv" "--disable-web-search" "grok lost --disable-web-search"
assert_contains "$grok_argv" "Bash(git push*)" "grok lost the git push deny"
assert_contains "$grok_argv" "Bash(gh *)" "grok lost the gh deny"
assert_contains "$grok_argv" "--prompt-file $fenced_order" "grok did not read the fenced order"
assert_not_contains "$grok_argv" "--always-approve" "grok still runs with --always-approve"

assert_contains "$grok_env" "XAI_API_KEY=$sentinel_xai" "the XAI key was not forwarded by name"
for scrub_name in GH_TOKEN GITHUB_TOKEN FACTORY_GH_APP_KEY_FILE AWS_SECRET_ACCESS_KEY \
  SSH_AUTH_SOCK GIT_ASKPASS; do
  assert_not_contains "$grok_env" "$scrub_name=" "the env scrub did not unset $scrub_name"
done
assert_not_contains "$grok_env" "$sentinel_gh_token" "the gh token value reached grok"
assert_not_contains "$grok_env" "$sentinel_aws" "the AWS secret value reached grok"
assert_not_contains "$grok_env" "$sentinel_gh_config" "the box gh config reached grok"
assert_contains "$grok_env" "HOME=$work/container-home" "grok's HOME is not the container's fresh directory"
assert_not_contains "$grok_env" "HOME=$HOME" "grok's HOME is the box HOME"
assert_eq "$(cat "$work/grok-gh-config.txt")" "hidden"

echo "ok: container bench tests passed"
