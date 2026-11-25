#!/usr/bin/env bash
# Grok-free end-to-end smoke test (#391, part of #386): intake and a build for a
# fixture work order run through adapters/stub/run.sh with no grok on PATH. The
# network and gh are stubbed: a fake gh and curl on PATH record any call and the
# test fails if one happens.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# Stub bin: gh and curl record and fail; grok must not exist.
bin=$work/bin; mkdir -p "$bin"
for tool in gh curl wget; do
  cat > "$bin/$tool" <<STUB
#!/usr/bin/env bash
echo "$tool \$*" >> "$work/forbidden.log"
exit 99
STUB
  chmod +x "$bin/$tool"
done
export PATH="$bin:/usr/bin:/bin"
if command -v grok >/dev/null 2>&1; then fail "grok is on PATH; the smoke test needs it absent"; fi

export FACTORY_PROVIDER=stub
adapter="$root_dir/adapters/$FACTORY_PROVIDER/run.sh"
[[ -x "$adapter" ]] || fail "adapters/stub/run.sh missing or not executable"

# Fixture work order and prompt, created here.
wo=$work/wo.md
cat > "$wo" <<'WO'
---
repo: example/fixture
issue: 1
branch: factory/1-fixture
---
## Goal
Fixture work order for the stub provider.
WO
prompt=$work/PROMPT.md
printf 'station prompt body\n' > "$prompt"

# Intake
tree=$work/tree; mkdir -p "$tree"
"$adapter" --role intake --prompt "$prompt" --issue 1 --repo example/fixture --workdir "$tree" >/dev/null \
  || fail "intake run failed"
[[ -s "$tree/stub-intake.md" ]] || fail "intake made no output"
grep -q '^Target repo: example/fixture$' "$tree/stub-intake.md" || fail "intake brief lacks Target repo line"

# Build
"$adapter" --role builder --prompt "$prompt" --work-order "$wo" --issue 1 --repo example/fixture --workdir "$tree" >/dev/null \
  || fail "builder run failed"
[[ -s "$tree/stub-provider-change.txt" ]] || fail "builder made no change"
grep -q 'issue 1 in example/fixture' "$tree/stub-provider-change.txt" || fail "builder change is not the fixed one"

# Contract: bad arguments are refused
if "$adapter" --role builder --workdir "$tree" >/dev/null 2>&1; then fail "missing prompt was accepted"; fi
if "$adapter" --role builder --prompt "$prompt" --work-order "$work/nope" >/dev/null 2>&1; then fail "missing work order was accepted"; fi

[[ ! -e "$work/forbidden.log" ]] || fail "network or gh was reached: $(cat "$work/forbidden.log")"
echo "ok: stub provider smoke (intake + build, no grok, no network)"
