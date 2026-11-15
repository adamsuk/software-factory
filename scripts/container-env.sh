#!/usr/bin/env bash
# Shared container settings for anything that starts a model CLI (#221, #382,
# #418): the builder child in scripts/run-work-order.sh and every station in
# scripts/station-run.sh. Sourced, never run. The caller defines
# `die <code> <message>`; every failure here is exit 9, before any model call.
#
# FACTORY_CONTAINER_RUNTIME  optional: podman, docker or nerdctl, or a path
# FACTORY_CONTAINER_IMAGE    required, no default
# FACTORY_CONTAINER_NETWORK  required: none, or a network the runtime reports as internal
# FACTORY_CONTAINER_PROXY    optional: http(s)://host[:port], no credentials
#
# See docs/runbooks/work-order-container.md and docs/runbooks/station-container.md.

# The container runtime for the model child: FACTORY_CONTAINER_RUNTIME if set
# (it must exist), else the first of podman, docker, nerdctl on PATH. Dies 9
# rather than falling back to running on the shared box.
container_runtime() {
  local runtime=${FACTORY_CONTAINER_RUNTIME:-}
  if [[ -n $runtime ]]; then
    command -v "$runtime" > /dev/null \
      || die 9 "cannot start a container: FACTORY_CONTAINER_RUNTIME=$runtime not found"
    printf '%s\n' "$runtime"
    return 0
  fi
  for runtime in podman docker nerdctl; do
    if command -v "$runtime" > /dev/null; then
      printf '%s\n' "$runtime"
      return 0
    fi
  done
  die 9 "cannot start a container: no podman, docker or nerdctl on PATH (set FACTORY_CONTAINER_RUNTIME)"
}

# The image for the model child. There is no default: the image has to carry
# the model CLI and whatever the run needs, so guessing one would fail
# later and less clearly.
container_image() {
  [[ -n ${FACTORY_CONTAINER_IMAGE:-} ]] \
    || die 9 "cannot start a container: FACTORY_CONTAINER_IMAGE is not set"
  printf '%s\n' "$FACTORY_CONTAINER_IMAGE"
}

# The network for the model child (#382). There is no default, and the
# runtime's ordinary networks are refused, because they can reach any host.
# FACTORY_CONTAINER_NETWORK is either "none" or the name of a network the
# runtime reports as internal: no route out, so the only way to another host
# is whatever the operator attached to it (an allowlisting proxy for the model
# API host). Dies 9 rather than starting a container that can reach anything.
container_network() {
  local runtime=$1 net=${FACTORY_CONTAINER_NETWORK:-} info
  [[ -n $net ]] \
    || die 9 "cannot start a container: FACTORY_CONTAINER_NETWORK is not set (an internal network name, or none)"
  if [[ $net == none ]]; then
    printf 'none\n'
    return 0
  fi
  [[ $net =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] \
    || die 9 "cannot start a container: FACTORY_CONTAINER_NETWORK is not a network name"
  case "$net" in
    host | bridge | default | private | podman | slirp4netns | pasta)
      die 9 "cannot start a container: network $net does not restrict egress"
      ;;
  esac
  info=$("$runtime" network inspect "$net" 2> /dev/null) \
    || die 9 "cannot start a container: network $net was not found by $(basename -- "$runtime")"
  printf '%s' "$info" | grep -Eiq '"internal"[[:space:]]*:[[:space:]]*true' \
    || die 9 "cannot start a container: network $net is not internal, so it does not restrict egress"
  printf '%s\n' "$net"
}

# The optional proxy for the model child (#382): FACTORY_CONTAINER_PROXY, an
# http(s)://host[:port] URL reachable on the restricted network. Credentials
# in the URL are refused, because the value goes on the runtime argv.
container_proxy() {
  local proxy=${FACTORY_CONTAINER_PROXY:-}
  [[ -n $proxy ]] || return 0
  [[ $proxy =~ ^https?://[A-Za-z0-9.-]+(:[0-9]+)?/?$ ]] \
    || die 9 "cannot start a container: FACTORY_CONTAINER_PROXY must be http(s)://host[:port] with no credentials"
  printf '%s\n' "$proxy"
}

# The model credential each provider needs, by name. A custom provider gets
# none: add its name here when it has one.
provider_credentials() {
  case "$1" in
    claudecode) echo CLAUDE_CODE_OAUTH_TOKEN ;;
    grok) echo XAI_API_KEY ;;
    opencode) echo OPENCODE_API_KEY OPENROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY ;;
  esac
}

# station_container_command <provider> <workdir> <forward> [<read-only path>...]
#
# Sets the global station_cmd array: the runtime invocation that starts one
# provider adapter in a fresh, disposable container (#418, #424). Used by
# scripts/station-run.sh and by the watcher's provider seam, so a model CLI
# with tool approval off never starts on the host.
#
#   <workdir>  mounted read-write at its host path and made the working directory
#   <forward>  space-separated names of variables to forward when set, by name
#              only, so no value reaches argv (settings, and GH_TOKEN if the
#              caller wants the station to have one)
#   read-only  files or directories mounted read-only at their host paths; one
#              that is the workdir or inside it is already there and is skipped
#
# The provider's own model credential is always forwarded, and is required:
# the container has no login of its own. HOME and TMPDIR are empty tmpfs
# mounts. Nothing else of the host is visible. Returns 9, with the reason on
# stderr, when the runtime, image, restricted network or credential is missing.
station_cmd=()
station_container_command() {
  local provider=$1 workdir=$2 forward=$3 runtime image network proxy name path
  local -a names=()
  local have_credential=false
  shift 3
  station_cmd=()
  runtime=$(container_runtime) || return 9
  image=$(container_image) || return 9
  network=$(container_network "$runtime") || return 9
  proxy=$(container_proxy) || return 9

  read -r -a names <<< "$(provider_credentials "$provider")"
  for name in "${names[@]}"; do
    [[ -z ${!name:-} ]] || have_credential=true
  done
  if [[ ${#names[@]} -gt 0 ]] && ! $have_credential; then
    (die 9 "cannot start a container: ${names[*]} not set, and the container has no $provider login of its own (docs/runbooks/station-container.md)") || return 9
  fi

  station_cmd=(
    "$runtime" run --rm
    --cap-drop ALL
    --security-opt no-new-privileges
    --volume "$workdir:$workdir"
    --env HOME=/factory-home
    --env TMPDIR=/factory-tmp
    --tmpfs /factory-home
    --tmpfs /factory-tmp
    --workdir "$workdir"
    --network "$network"
    --env FACTORY_STATION_CONTAINER=1
    # git has no config file in the empty HOME: gh answers for github.com.
    --env GIT_CONFIG_COUNT=1
    --env GIT_CONFIG_KEY_0=credential.https://github.com.helper
    --env "GIT_CONFIG_VALUE_0=!gh auth git-credential"
  )
  for path in "$@"; do
    [[ -n "$path" && "$path" != "$workdir" && "$path" != "$workdir"/* ]] || continue
    station_cmd+=(--volume "$path:$path:ro")
  done
  if [[ -n $proxy ]]; then
    station_cmd+=(
      --env "HTTPS_PROXY=$proxy" --env "HTTP_PROXY=$proxy"
      --env "https_proxy=$proxy" --env "http_proxy=$proxy"
    )
  fi
  # Run as the calling user, never as root: files written in the working tree
  # stay ours, and Claude Code refuses to run with approval off as root (seen
  # on the first real run, 2026-11-15). Rootless podman would otherwise map
  # the caller to container root, so it also needs keep-id.
  station_cmd+=(--user "$(id -u):$(id -g)")
  [[ "$(basename -- "$runtime")" != podman ]] || station_cmd+=(--userns keep-id)
  # shellcheck disable=SC2086  # $forward is a list of names, split on purpose
  for name in $forward "${names[@]}"; do
    [[ -z ${!name:-} ]] || station_cmd+=(--env "$name")
  done
  station_cmd+=("$image")
}
