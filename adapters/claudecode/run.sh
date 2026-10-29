#!/usr/bin/env bash
# Claude Code adapter. `claude` has no --prompt-file: the station bundle goes in
# on stdin in print mode (-p). AGENTS.md is appended to the system prompt, which
# is this CLI's equivalent of grok's --rules. GitHub writes go through
# scripts/station-post.sh, never through gh directly.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "claudecode-adapter: $2" >&2; exit "$1"; }

role=""
prompt_file=""
issue=""
workdir=""

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
    --workdir)
      [[ $# -ge 2 ]] || die 2 "missing value for --workdir"
      workdir="$2"; shift 2 ;;
    --work-order|--repo)
      [[ $# -ge 2 ]] || die 2 "missing value for $1"
      shift 2 ;;
    *) shift ;;
  esac
done

[[ -n "$role" ]] || die 2 "missing role"
[[ -n "$prompt_file" && -f "$prompt_file" ]] || die 2 "missing prompt"
[[ "$prompt_file" == /* ]] || prompt_file="$PWD/$prompt_file"

# Every role, builder included, runs from the composed bundle against the working
# tree; scripts/station-run.sh decides whether that tree is the real repo or a
# throwaway clone, and it already treats builder as writable.
#
# An earlier version refused builder here, on the grounds that
# scripts/run-work-order.sh calls the grok CLI directly. That reason was false:
# run-work-order.sh is reached only from adapters/grok/run.sh. The opencode
# adapter has no builder case at all and runs it as a prompted agent, which is
# what this adapter now does too (#158).
#
# The two builder paths are not equivalent and that is worth knowing: the grok
# builder clones, tests, squash-commits, pushes and opens the pull request, while
# this one only runs the prompt and leaves its edits in the tree.

command -v claude >/dev/null 2>&1 || die 2 "claude CLI not found in PATH"

claude_supports() {
  claude --help 2>&1 | grep -- "$1" >/dev/null
}

# Print mode is the non-interactive entry point. Without it this would open a
# session and hang a station run.
claude_supports --print || die 3 "claude CLI in PATH does not support --print, needed to run a station non-interactively"

args=(--print)

# Which model a station runs on is a factory decision, not a local accident.
# Default sonnet (Scott, 2026-10-28); FACTORY_MODEL overrides it. Probed, so an
# older CLI without --model still runs rather than failing.
model="${FACTORY_MODEL:-sonnet}"
if [[ -n "$model" ]] && claude_supports --model; then
  args+=(--model "$model")
fi

# grok gets AGENTS.md through --rules. The composed bundle already contains it,
# so this is belt and braces on the providers that allow it.
if claude_supports --append-system-prompt; then
  args+=(--append-system-prompt "$(cat "$here/AGENTS.md")")
fi

# Stations run unattended and must be able to execute scripts/station-post.sh.
# This is the same standing auto-approval the other two adapters use (opencode
# --auto, grok --always-approve), and it carries the same open risk recorded in
# the sandbox finding (#44): approval is removed, isolation is not yet in place.
if claude_supports --permission-mode; then
  args+=(--permission-mode bypassPermissions)
elif claude_supports --dangerously-skip-permissions; then
  args+=(--dangerously-skip-permissions)
else
  die 3 "claude CLI in PATH has no way to auto-approve tool use, needed for an unattended station"
fi

run_dir="${workdir:-$here}"
[[ -d "$run_dir" ]] || die 2 "working directory does not exist: $run_dir"
cd "$run_dir" || die 2 "cannot enter working directory: $run_dir"

# The bundle is the prompt. The trailing instruction mirrors the other adapters.
{
  cat "$prompt_file"
  printf '\n\n%s\n' "You are the ${role} station${issue:+ for issue #${issue}}. Carry out the prompt above. Post factory comments and move factory:* labels only by running scripts/station-post.sh in this repository. Do not call gh to comment, label, open a pull request, or merge. One issue, one factory/<issue>-<slug> branch, one open pull request."
} | exec claude "${args[@]}"
