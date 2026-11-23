#!/usr/bin/env bash
# Preflight for the main lane (scripts/watcher/watch.sh) and the build lane
# (scripts/watcher/watch.new.sh with LANE=build) (#390).
#
# Prints names only. A missing variable, command or path is reported as
# "watcher-preflight: missing <name>". Values, tokens and keys are never printed.
# The only external command is "gh auth status", and its output is discarded.
# Nothing is started and no directory is created.
set -euo pipefail

missing=()
note_missing() { missing+=("$1"); }

# FACTORY_PROVIDER: grok (default), claudecode or opencode. The value is not printed.
provider=${FACTORY_PROVIDER:-grok}
case $provider in
  grok | claudecode | opencode) ;;
  *) note_missing "FACTORY_PROVIDER" ;;
esac

if ! command -v gh > /dev/null 2>&1; then
  note_missing "gh"
elif ! gh auth status > /dev/null 2>&1; then
  note_missing "gh auth status"
fi

# The provider CLI is on PATH, or (grok) an executable FACTORY_GROK_BIN, or
# the CLI shipped in FACTORY_CONTAINER_IMAGE. stations/run-factory.md: the
# container image supplies the CLI; FACTORY_GROK_BIN is the host binary.
image_set=0
[[ -z ${FACTORY_CONTAINER_IMAGE:-} ]] || image_set=1

# Grok credential: XAI_API_KEY, or FACTORY_GROK_AUTH_FILE on its own when the
# key is unset (scripts/container-env.sh). FACTORY_GROK_BIN is checked only
# when it is set, and the auth file does not require it.
check_grok() {
  if [[ -n ${FACTORY_GROK_BIN:-} ]]; then
    [[ -f "$FACTORY_GROK_BIN" && -x "$FACTORY_GROK_BIN" ]] || note_missing "FACTORY_GROK_BIN"
  elif ! command -v grok > /dev/null 2>&1 && [[ $image_set -eq 0 ]]; then
    note_missing "grok"
  fi
  if [[ -z ${XAI_API_KEY:-} ]]; then
    if [[ -n ${FACTORY_GROK_AUTH_FILE:-} ]]; then
      # Same stand-in as scripts/container-env.sh: a readable absolute file,
      # and only the name is reported when it is not.
      [[ "$FACTORY_GROK_AUTH_FILE" == /* && -f "$FACTORY_GROK_AUTH_FILE" && -r "$FACTORY_GROK_AUTH_FILE" ]] \
        || note_missing "FACTORY_GROK_AUTH_FILE"
    else
      note_missing "XAI_API_KEY or FACTORY_GROK_AUTH_FILE"
    fi
  fi
}

# The build foreman always calls grok, whatever FACTORY_PROVIDER is. When
# FACTORY_WATCHER_BUILDS=off that step does not run, so a non-grok provider
# does not need the grok CLI or credential. A grok provider still does.
grok_for_builds=1
if [[ ${FACTORY_WATCHER_BUILDS:-} == off ]]; then
  grok_for_builds=0
fi

case $provider in
  grok)
    check_grok
    ;;
  claudecode)
    if ! command -v claude > /dev/null 2>&1 && [[ $image_set -eq 0 ]]; then
      note_missing "claude"
    fi
    [[ -n ${CLAUDE_CODE_OAUTH_TOKEN:-} ]] || note_missing "CLAUDE_CODE_OAUTH_TOKEN"
    if [[ $grok_for_builds -eq 1 ]]; then
      check_grok
    fi
    ;;
  opencode)
    if ! command -v opencode > /dev/null 2>&1 && [[ $image_set -eq 0 ]]; then
      note_missing "opencode"
    fi
    if [[ -z ${OPENCODE_API_KEY:-} && -z ${OPENROUTER_API_KEY:-} && -z ${OPENAI_API_KEY:-} && -z ${ANTHROPIC_API_KEY:-} ]]; then
      note_missing "OPENCODE_API_KEY, OPENROUTER_API_KEY, OPENAI_API_KEY or ANTHROPIC_API_KEY"
    fi
    if [[ $grok_for_builds -eq 1 ]]; then
      check_grok
    fi
    ;;
esac

# Runtime: FACTORY_CONTAINER_RUNTIME if set (it must exist), else the first of
# podman, docker, nerdctl on PATH. Same order as scripts/container-env.sh.
# command -v output is discarded so a path is never printed.
if [[ -n ${FACTORY_CONTAINER_RUNTIME:-} ]]; then
  command -v "$FACTORY_CONTAINER_RUNTIME" > /dev/null 2>&1 || note_missing "FACTORY_CONTAINER_RUNTIME"
else
  found=0
  for runtime in podman docker nerdctl; do
    if command -v "$runtime" > /dev/null 2>&1; then
      found=1
      break
    fi
  done
  [[ $found -eq 1 ]] || note_missing "FACTORY_CONTAINER_RUNTIME, podman, docker or nerdctl"
fi

[[ -n ${FACTORY_CONTAINER_IMAGE:-} ]] || note_missing "FACTORY_CONTAINER_IMAGE"

# State directory. Defaults match scripts/watcher/factory-env.sh and are
# duplicated here so this script does not source that file (the lane loader
# can call gh while resolving the home repo). The path is never printed.
if [[ -n ${FACTORY_WATCH_ROOT:-} ]]; then
  state=${FACTORY_WATCH_ROOT}/state
else
  factory_home=${FACTORY_HOME:-${XDG_DATA_HOME:-${HOME:-}/.local/share}/software-factory}
  state=${factory_home}/factory-watch/state
fi
# Write alone is not enough: without search permission a non-root watcher
# cannot open files inside the directory. Mode 0600 fails; mode 0700 passes.
[[ -d "$state" && -w "$state" && -x "$state" ]] || note_missing "FACTORY_WATCH_ROOT/state"

if [[ ${#missing[@]} -gt 0 ]]; then
  for item in "${missing[@]}"; do
    printf 'watcher-preflight: missing %s\n' "$item" >&2
  done
  exit 1
fi

printf 'watcher-preflight: ok\n'
exit 0
