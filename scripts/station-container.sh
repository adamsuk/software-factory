#!/usr/bin/env bash
# Run one command in the station container (#418, #424). For a caller that
# starts a provider adapter without going through scripts/station-run.sh: the
# watcher's provider seam runs this by path from its home-repo clone.
#
# Usage: scripts/station-container.sh --provider <name> --workdir <dir>
#          [--forward <NAME>]... [--ro <path>]... [--rw <path>]...
#          -- <command> [<arg>...]
#   --workdir  mounted read-write and made the working directory
#   --forward  a variable to forward by name when it is set
#   --ro       a file or directory to mount read-only
#   --rw       a directory outside the workdir to mount read-write
#
# The container, its network and what it may see are decided in
# scripts/container-env.sh (station_container_command), the same code
# scripts/station-run.sh uses.
#
# Exit codes: 2 usage, 9 no runtime, image, restricted network or provider
# credential (nothing was started); otherwise the command's own exit code.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "station-container: $2" >&2; exit "$1"; }

provider=""
workdir=""
forward=()
ro=()
rw=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider | --workdir | --forward | --ro | --rw)
      [[ $# -ge 2 ]] || die 2 "missing value for $1"
      case "$1" in
        --provider) provider=$2 ;;
        --workdir) workdir=$2 ;;
        --forward) forward+=("$2") ;;
        --ro) ro+=("$2") ;;
        --rw) rw+=("$2") ;;
      esac
      shift 2 ;;
    --) shift; break ;;
    *) die 2 "unknown argument: $1" ;;
  esac
done
[[ -n "$provider" ]] || die 2 "missing --provider"
[[ -n "$workdir" && -d "$workdir" ]] || die 2 "--workdir is not a directory: $workdir"
[[ "$workdir" == /* ]] || die 2 "--workdir must be an absolute path"
[[ $# -ge 1 ]] || die 2 "no command after --"
for name in "${forward[@]}"; do
  [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die 2 "--forward takes a variable name, got: $name"
done
for path in "${ro[@]}"; do
  [[ "$path" == /* && -e "$path" ]] || die 2 "--ro takes an existing absolute path, got: $path"
done
mounts=("${ro[@]}")
for path in "${rw[@]}"; do
  [[ "$path" == /* && -d "$path" ]] || die 2 "--rw takes an existing absolute directory, got: $path"
  mounts+=("rw:$path")
done

# shellcheck source=scripts/container-env.sh
source "$here/container-env.sh"
station_container_command "$provider" "$workdir" "${forward[*]}" "${mounts[@]}" || exit 9
exec "${station_cmd[@]}" "$@"
