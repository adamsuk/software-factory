#!/usr/bin/env bash
# Lint role prompts and AGENTS.md for provider/harness-specific leakage
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0

# Patterns to flag as harness-specific (should be in adapters, not roles)
patterns=(
  "opencode.*subagent"
  "subagent.*tool"
  '"subagent"'
  "tools\.opencode"
  "grok.*CLI.*specific"  # be careful not to be too strict
)

echo "Linting prompts for harness leakage..."

# Check roles
for role in "$here"/agents/roles/*.md; do
  [[ -f "$role" ]] || continue
  basename_role=$(basename "$role")
  # Allow "subagent" in general delegation language? The instruction says avoid harness-specific
  # Check for OpenCode-specific tool references
  if grep -n "tools\.opencode\|@opencode" "$role" >/dev/null 2>&1; then
    echo "ERROR: $basename_role contains OpenCode-specific tool references"
    grep -n "tools\.opencode\|@opencode" "$role"
    errors=$((errors + 1))
  fi
  # Check for specific model names that are provider-specific
  if grep -n '"big-pickle"\|providerID.*opencode' "$role" >/dev/null 2>&1; then
    echo "ERROR: $basename_role contains provider-specific model references"
    grep -n '"big-pickle"\|providerID.*opencode' "$role"
    errors=$((errors + 1))
  fi
done

# Check AGENTS.md
if grep -n "tools\.opencode\|@opencode" "$here/AGENTS.md" >/dev/null 2>&1; then
  echo "ERROR: AGENTS.md contains OpenCode-specific references"
  grep -n "tools\.opencode\|@opencode" "$here/AGENTS.md"
  errors=$((errors + 1))
fi

if [[ $errors -eq 0 ]]; then
  echo "OK: No obvious harness-specific leakage found"
  exit 0
else
  echo "Found $errors error(s)"
  exit 1
fi
