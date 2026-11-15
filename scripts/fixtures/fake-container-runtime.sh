#!/usr/bin/env bash
# A stand-in container runtime for the station-run and adapter tests (#424).
# Install it on PATH as podman, docker or nerdctl. It starts no container: it
# answers `network inspect` the way a real runtime does, and for `run` it
# records its argv and then runs the command with the environment a container
# would have: only the --env names and values, plus PATH and whatever the
# harness lists in FAKE_RUNTIME_PASS (its own recording paths, not settings).
#
# FAKE_RUNTIME_LOG   file: one line per `run`, the full argv
# FAKE_RUNTIME_NET   internal (default) | external | missing
# FAKE_RUNTIME_PASS  space-separated names of harness variables to keep
set -euo pipefail

if [[ "${1:-}" == network && "${2:-}" == inspect ]]; then
  case "${FAKE_RUNTIME_NET:-internal}" in
    internal) printf '%s\n' "[{\"name\": \"${3:-}\", \"internal\": true}]" ;;
    external) printf '%s\n' "[{\"name\": \"${3:-}\", \"internal\": false}]" ;;
    *) exit 1 ;;
  esac
  exit 0
fi
[[ "${1:-}" == run ]] || exit 0
[[ -z "${FAKE_RUNTIME_LOG:-}" ]] || printf '%s\n' "$*" >> "$FAKE_RUNTIME_LOG"
shift

child_env=("PATH=$PATH")
for name in ${FAKE_RUNTIME_PASS:-}; do
  [[ -z ${!name+x} ]] || child_env+=("$name=${!name}")
done
workdir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rm | -i) shift ;;
    --env)
      if [[ "$2" == *=* ]]; then
        child_env+=("$2")
      elif [[ -n ${!2+x} ]]; then
        child_env+=("$2=${!2}")
      fi
      shift 2 ;;
    --workdir) workdir=$2; shift 2 ;;
    --volume | --tmpfs | --network | --user | --userns | --cap-drop | --security-opt) shift 2 ;;
    -*) echo "fake-container-runtime: unknown option $1" >&2; exit 125 ;;
    *) break ;;
  esac
done
[[ $# -ge 2 ]] || { echo "fake-container-runtime: no image and command" >&2; exit 125; }
shift # the image
[[ -z "$workdir" ]] || cd "$workdir"
# HOME and TMPDIR name tmpfs mounts that do not exist on this host.
for i in "${!child_env[@]}"; do
  case "${child_env[$i]}" in
    HOME=* | TMPDIR=*) unset "child_env[$i]" ;;
  esac
done
exec env -i "${child_env[@]}" "$@"
