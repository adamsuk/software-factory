#!/usr/bin/env bash
# Behaviour tests for scripts/protected-paths.sh (AGENTS.md section 5, #162).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
check="$here/protected-paths.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

nul_join() { printf '%s\0' "$@"; }

out=$(nul_join agents/work-orders/a_b-1.md | "$check")
[[ -z "$out" ]] || fail "work order alone reported protected: $out"
echo "ok: work order alone is not protected"

for p in AGENTS.md agents/roles/reviewer.md agents/grok-build.md CODEOWNERS \
  .github/workflows/x.yml package-lock.json; do
  out=$(nul_join agents/work-orders/a_b-1.md "$p" | "$check")
  [[ "$out" == "$p" ]] || fail "$p not reported alone, got: $out"
done
echo "ok: protected paths still reported next to a work order"

out=$(nul_join scripts/foo.sh README.md | "$check")
[[ -z "$out" ]] || fail "ordinary paths reported: $out"
echo "ok: ordinary paths not protected"

# A non-ASCII protected path, fed the way `git diff -z --name-only` would
# emit it: NUL-delimited, no quoting or C-escaping. Without `-z` (reading
# plain newline-delimited `git diff --name-only` output instead), git's
# default core.quotePath wraps this in double quotes and C-escapes the
# bytes, so the leading `"` hides it from the `agents/` pattern below.
out=$(nul_join 'agents/roles/révision.md' | "$check")
[[ "$out" == "agents/roles/révision.md" ]] || fail "non-ASCII protected path not reported, got: $out"
echo "ok: a non-ASCII protected path is still reported"
