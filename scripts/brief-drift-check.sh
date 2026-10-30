#!/usr/bin/env bash
# Fails when a role brief drifts from the script or labels it describes. Read-only,
# offline and deterministic. Two checks:
#   1. agents/grok-build.md "What the wrapper does": every exit code and flag it
#      documents for scripts/run-work-order.sh exists in that script.
#   2. Every factory:* label named in AGENTS.md, agents/roles/*.md and the other
#      agent briefs is one of the nine canonical labels below (AGENTS.md section 9).
# Usage: brief-drift-check.sh [ROOT]   (ROOT defaults to the repo root; the tests
# point it at a copy with a deliberately broken brief.)
# Exit: 0 everything matches, 1 drift found, 2 an input file is missing.
set -euo pipefail

# The one canonical label list. AGENTS.md section 9 and stations/README.md describe it.
CANONICAL_LABELS=(
  factory:triage factory:ready factory:building factory:gate factory:review
  factory:merge factory:release factory:done factory:blocked
)

root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
brief=$root/agents/grok-build.md
wrapper=$root/scripts/run-work-order.sh
for f in "$brief" "$wrapper" "$root/AGENTS.md"; do
  [[ -f "$f" ]] || { echo "brief-drift-check: missing $f" >&2; exit 2; }
done

drift=0
report() { echo "DRIFT: $*"; drift=1; }

# --- 1. exit codes and flags --------------------------------------------------
section=$(awk '/^## What the wrapper does/ { on = 1; next } /^## / { on = 0 } on' "$brief")
[[ -n "$section" ]] || { echo "brief-drift-check: no 'What the wrapper does' section in $brief" >&2; exit 2; }

while read -r code; do
  [[ -n "$code" ]] || continue
  if ! grep -qE "(die|exit) $code( |\$)" "$wrapper"; then
    report "agents/grok-build.md documents exit $code but scripts/run-work-order.sh never uses it"
  fi
done < <(printf '%s\n' "$section" | grep -oiE 'exit( code)? [0-9]+' | grep -oE '[0-9]+$' | sort -un)

while read -r flag; do
  [[ -n "$flag" ]] || continue
  if ! grep -qF -- "\"$flag\"" "$wrapper"; then
    report "agents/grok-build.md documents flag $flag but scripts/run-work-order.sh does not parse it"
  fi
done < <(printf '%s\n' "$section" | grep -E 'run-work-order\.sh' | grep -oE '\-\-[a-z][a-z-]*' | sort -u)

# --- 2. label names -----------------------------------------------------------
shopt -s nullglob
files=("$root/AGENTS.md" "$root"/agents/*.md "$root"/agents/roles/*.md)
for f in "${files[@]}"; do
  while read -r label; do
    [[ -n "$label" ]] || continue
    known=no
    for c in "${CANONICAL_LABELS[@]}"; do [[ "$label" == "$c" ]] && known=yes; done
    [[ $known == yes ]] || report "${f#"$root"/} names $label, which is not one of the nine canonical labels"
  done < <(grep -oE 'factory:[a-z]+' "$f" | sort -u)
done

# AGENTS.md section 9 must still list every canonical label.
for c in "${CANONICAL_LABELS[@]}"; do
  grep -qF "\`$c\`" "$root/AGENTS.md" || report "AGENTS.md does not list canonical label $c"
done

if [[ $drift -eq 0 ]]; then echo "brief-drift-check: briefs match the script and labels"; fi
exit "$drift"
