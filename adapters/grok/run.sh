#!/usr/bin/env bash
# Grok adapter. Builder reuses scripts/run-work-order.sh. Other roles call grok.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "grok-adapter: $2" >&2; exit "$1"; }

role=""
prompt_file=""
work_order=""
workdir=""
push=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)
      [[ $# -ge 2 ]] || die 2 "missing value for --role"
      role="$2"; shift 2 ;;
    --prompt)
      [[ $# -ge 2 ]] || die 2 "missing value for --prompt"
      prompt_file="$2"; shift 2 ;;
    --work-order)
      [[ $# -ge 2 ]] || die 2 "missing value for --work-order"
      work_order="$2"; shift 2 ;;
    --workdir)
      [[ $# -ge 2 ]] || die 2 "missing value for --workdir"
      workdir="$2"; shift 2 ;;
    --issue|--repo)
      [[ $# -ge 2 ]] || die 2 "missing value for $1"
      shift 2 ;;
    --push)
      push=1; shift ;;
    *) shift ;;
  esac
done

if [[ "$role" == "builder" ]]; then
  [[ -n "$work_order" && -f "$work_order" ]] || die 2 "builder requires a work order file"
  if [[ "$push" -eq 1 ]]; then
    exec "$here/scripts/run-work-order.sh" --push "$work_order"
  fi
  exec "$here/scripts/run-work-order.sh" "$work_order"
fi

[[ -n "$prompt_file" && -f "$prompt_file" ]] || die 2 "missing prompt"

# Three distinct failures, three distinct messages. The old single message
# ("not supported or grok CLI not available") could not tell a missing binary
# from a CLI that lacks the flag, which cost a run on #140.
command -v grok >/dev/null 2>&1 || die 2 "grok CLI not found in PATH"
grok --help 2>&1 | grep -- "prompt-file" >/dev/null \
  || die 3 "grok CLI in PATH does not support --prompt-file, needed for role '$role'"

run_dir="${workdir:-$here}"
[[ -d "$run_dir" ]] || die 2 "working directory does not exist: $run_dir"
cd "$run_dir" || die 2 "cannot enter working directory: $run_dir"

exec grok --prompt-file "$prompt_file" --rules "$(cat "$here/AGENTS.md")"
