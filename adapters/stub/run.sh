#!/usr/bin/env bash
# Stub provider adapter (#391, part of #386). It starts no model CLI and makes no
# network call: each role gets one fixed, valid output, so a work order can run
# end to end with no Grok, OpenCode or Claude Code installed. It exists so the
# provider-agnostic design has a test that fails if the contract regresses.
#   intake/triage roles: write a fixed normalised brief to stub-intake.md
#   builder:             write a fixed change to stub-provider-change.txt
#   any other role:      write stub-<role>.md
# Output goes to --workdir, else the current directory.
set -euo pipefail

die() { echo "stub-adapter: $2" >&2; exit "$1"; }

role=""
prompt_file=""
work_order=""
issue=""
repo=""
workdir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)       [[ $# -ge 2 ]] || die 2 "missing value for --role"; role="$2"; shift 2 ;;
    --prompt)     [[ $# -ge 2 ]] || die 2 "missing value for --prompt"; prompt_file="$2"; shift 2 ;;
    --work-order) [[ $# -ge 2 ]] || die 2 "missing value for --work-order"; work_order="$2"; shift 2 ;;
    --issue)      [[ $# -ge 2 ]] || die 2 "missing value for --issue"; issue="$2"; shift 2 ;;
    --repo)       [[ $# -ge 2 ]] || die 2 "missing value for --repo"; repo="$2"; shift 2 ;;
    --workdir)    [[ $# -ge 2 ]] || die 2 "missing value for --workdir"; workdir="$2"; shift 2 ;;
    *) shift ;;
  esac
done

[[ -n "$role" ]] || die 2 "missing role"
[[ "$role" =~ ^[a-z0-9_-]+$ ]] || die 2 "invalid role"
[[ -n "$prompt_file" && -f "$prompt_file" ]] || die 2 "missing prompt"
if [[ -n "$work_order" ]]; then
  [[ -f "$work_order" ]] || die 2 "work order not found: $work_order"
fi
[[ -n "$workdir" ]] || workdir="$PWD"
[[ -d "$workdir" ]] || die 2 "workdir not found: $workdir"

case "$role" in
  builder)
    out="$workdir/stub-provider-change.txt"
    printf 'stub provider change for issue %s in %s\n' "${issue:-unknown}" "${repo:-unknown}" > "$out" ;;
  intake|signal-issues|triage)
    out="$workdir/stub-intake.md"
    printf 'Target repo: %s\n\nAcceptance criteria:\n- [ ] stub criterion\n\nSize: S\n' "${repo:-unknown}" > "$out" ;;
  *)
    out="$workdir/stub-$role.md"
    printf 'stub output for role %s\n' "$role" > "$out" ;;
esac

echo "stub-adapter: wrote $out"
