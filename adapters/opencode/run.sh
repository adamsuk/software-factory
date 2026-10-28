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
[[ "$prompt_file" == /* ]] || prompt_file="$PWD/$prompt_file"
command -v opencode >/dev/null 2>&1 || die 2 "opencode CLI not found in PATH"

title="factory:${role}"
if [[ -n "$issue" ]]; then
  title="factory:${role}#${issue}"
fi

# opencode run has no stable way to set the working directory: v2.2.0 rejects
# --dir outright. Probe for it and fall back to entering the repo root, so the
# adapter works on versions either side of that change. The station always runs
# from the repo root, because the prompt tells it to call scripts/station-post.sh
# by relative path.
opencode_run_supports() {
  opencode run --help 2>&1 | grep -- "$1" >/dev/null
}

args=(run --auto --title "$title" --file "$prompt_file")
if opencode_run_supports --dir; then
  args+=(--dir "$here")
else
  cd "$here" || die 2 "cannot enter repo root: $here"
fi

exec opencode "${args[@]}" \
  "You are the ${role} station. Read the attached prompt and carry it out. Post factory comments and move factory:* labels only by running scripts/station-post.sh in this repository. Do not call gh to comment, label, open a pull request, or merge. One issue, one factory/<issue>-<slug> branch, one open pull request."
