#!/usr/bin/env bash
# Preflight for bringing up both watcher lanes on one machine (#390).
# Prints variable and key *names* only, never values (AGENTS.md §7).
# Exit 0 when the environment is prepared; non-zero with the missing item named.
set -euo pipefail

missing() { echo "watcher-preflight: missing $1" >&2; exit 1; }

# --- provider ---
provider=${FACTORY_PROVIDER:-grok}
case "$provider" in
  grok|claudecode|opencode) ;;
  *) missing "FACTORY_PROVIDER (must be grok, claudecode or opencode)" ;;
esac
echo "FACTORY_PROVIDER=$provider"

# --- gh login ---
command -v gh >/dev/null || missing "gh on PATH"
gh auth status >/dev/null 2>&1 || missing "gh login (gh auth status)"
echo "gh: logged in"

# --- provider CLI ---
case "$provider" in
  grok)
    if [[ -n ${FACTORY_GROK_BIN:-} ]]; then
      [[ -x "$FACTORY_GROK_BIN" ]] || missing "FACTORY_GROK_BIN (not executable)"
      echo "FACTORY_GROK_BIN set"
    else
      command -v grok >/dev/null || missing "grok on PATH (or FACTORY_GROK_BIN)"
      echo "grok: on PATH"
    fi
    ;;
  claudecode)
    command -v claude >/dev/null || missing "claude on PATH"
    echo "claude: on PATH"
    ;;
  opencode)
    command -v opencode >/dev/null || missing "opencode on PATH"
    echo "opencode: on PATH"
    ;;
esac

# --- credential name present (value never printed) ---
case "$provider" in
  grok)
    [[ -n ${XAI_API_KEY:-} || -n ${FACTORY_GROK_AUTH_FILE:-} ]] \
      || missing "XAI_API_KEY or FACTORY_GROK_AUTH_FILE"
    echo "credential: XAI_API_KEY or FACTORY_GROK_AUTH_FILE set"
    ;;
  claudecode)
    [[ -n ${CLAUDE_CODE_OAUTH_TOKEN:-} ]] || missing "CLAUDE_CODE_OAUTH_TOKEN"
    echo "credential: CLAUDE_CODE_OAUTH_TOKEN set"
    ;;
  opencode)
    if [[ -z ${OPENCODE_API_KEY:-} && -z ${OPENROUTER_API_KEY:-} && -z ${OPENAI_API_KEY:-} && -z ${ANTHROPIC_API_KEY:-} ]]; then
      missing "an opencode key (OPENCODE_API_KEY / OPENROUTER_API_KEY / OPENAI_API_KEY / ANTHROPIC_API_KEY)"
    fi
    echo "credential: opencode key set"
    ;;
esac

# --- container runtime (bypass with FACTORY_GROK_ON_HOST) ---
on_host=${FACTORY_GROK_ON_HOST:-}
if [[ "$on_host" == "host-is-a-disposable-sandbox" ]]; then
  echo "FACTORY_GROK_ON_HOST: host sandbox (container check skipped)"
else
  runtime=${FACTORY_CONTAINER_RUNTIME:-}
  if [[ -n "$runtime" ]]; then
    command -v "$runtime" >/dev/null || missing "FACTORY_CONTAINER_RUNTIME=$runtime"
    echo "FACTORY_CONTAINER_RUNTIME=$runtime"
  else
    found=
    for r in podman docker nerdctl; do
      if command -v "$r" >/dev/null; then
        found=$r
        break
      fi
    done
    [[ -n "$found" ]] || missing "container runtime (podman, docker or nerdctl on PATH, or FACTORY_CONTAINER_RUNTIME, or FACTORY_GROK_ON_HOST=host-is-a-disposable-sandbox)"
    echo "container runtime: $found"
  fi
  [[ -n ${FACTORY_CONTAINER_IMAGE:-} ]] || missing "FACTORY_CONTAINER_IMAGE"
  echo "FACTORY_CONTAINER_IMAGE set"
  [[ -n ${FACTORY_CONTAINER_NETWORK:-} ]] || missing "FACTORY_CONTAINER_NETWORK"
  echo "FACTORY_CONTAINER_NETWORK set"
fi

# --- state directory ---
state=${FACTORY_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/software-factory}
if [[ ! -d "$state" ]]; then
  mkdir -p "$state" 2>/dev/null || missing "state directory $state (not creatable)"
fi
[[ -w "$state" ]] || missing "state directory $state (not writable)"
echo "state directory: $state"

echo "watcher-preflight: ok"
exit 0
