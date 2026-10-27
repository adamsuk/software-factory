#!/usr/bin/env bash
# OpenCode adapter. opencode run takes the prompt as a message, not --prompt-file.
# The station bundle is attached with --file. GitHub writes go through station-post.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "opencode-adapter: $2" >&2; exit "$1"; }

role=""
prompt_file=""
issue=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)
      [[ $# -ge 2 ]] || die 2 "missing value for --role"
      role="$2"; shift 2 ;;
    --prompt)
      [[ $# -ge 2 ]] || die 2 "missing value for --prompt"
      prompt_file="$2"; shift 2 ;;
    --issue)
      [[ $# -ge 2 ]] || die 2 "missing value for --issue"
      issue="$2"; shift 2 ;;
    --work-order|--repo)
      [[ $# -ge 2 ]] || die 2 "missing value for $1"
      shift 2 ;;
    *) shift ;;
  esac
done

[[ -n "$role" && -n "$prompt_file" && -f "$prompt_file" ]] || die 2 "missing role or prompt"
command -v opencode >/dev/null 2>&1 || die 2 "opencode CLI not found in PATH"

title="factory:${role}"
if [[ -n "$issue" ]]; then
  title="factory:${role}#${issue}"
fi
exec opencode run \
  --auto \
  --dir "$here" \
  --title "$title" \
  --file "$prompt_file" \
  "You are the ${role} station. Read the attached prompt and carry it out. Post factory comments and move factory:* labels only by running scripts/station-post.sh in this repository. Do not call gh to comment, label, open a pull request, or merge. One issue, one factory/<issue>-<slug> branch, one open pull request."
