#!/usr/bin/env bash
# Behaviour tests for scripts/protected-paths.sh (AGENTS.md section 5, #162).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
check="$here/protected-paths.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

out=$(printf '%s\n' agents/work-orders/a_b-1.md | "$check")
[[ -z "$out" ]] || fail "work order alone reported protected: $out"
echo "ok: work order alone is not protected"

for p in AGENTS.md agents/roles/reviewer.md agents/grok-build.md CODEOWNERS \
  .github/workflows/x.yml package-lock.json; do
  out=$(printf '%s\n' agents/work-orders/a_b-1.md "$p" | "$check")
  [[ "$out" == "$p" ]] || fail "$p not reported alone, got: $out"
done
echo "ok: protected paths still reported next to a work order"

out=$(printf '%s\n' scripts/foo.sh README.md | "$check")
[[ -z "$out" ]] || fail "ordinary paths reported: $out"
echo "ok: ordinary paths not protected"
