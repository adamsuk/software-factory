#!/usr/bin/env bash
# Behaviour tests for scripts/station-run.sh --read-only. ShellCheck covers this
# file. A fake provider records where it ran and tries to write; no real
# provider is invoked and nothing contacts GitHub.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
pass() { echo "ok: $tname"; }

BIN=$work/bin
mkdir -p "$BIN"
OUT=$work/out

# Behaves like the reviewer did on #141: edits a test, stages it, commits it,
# then tries to push.
cat > "$BIN/opencode" << 'FAKE'
#!/usr/bin/env bash
if [[ "$*" == *--help* ]]; then printf '%s\n' "--auto --title --file"; exit 0; fi
{
  echo "cwd=$PWD"
  echo "origin=$(git remote get-url origin 2>&1 | head -1)"
  if sed -i.bak 's/^set -euo pipefail$/set -u/' scripts/station-run.sh 2>/dev/null; then
    echo "edited=yes"
  else
    echo "edited=no"
  fi
  git add -A > /dev/null 2>&1 && echo "staged=yes"
  git -c user.email=t@e.com -c user.name=t commit -q -m tamper > /dev/null 2>&1 && echo "committed=yes"
  git push origin HEAD > /dev/null 2>&1 && echo "pushed=yes" || echo "pushed=no"
} > "$FAKE_OUT"
exit 0
FAKE
chmod +x "$BIN/opencode"

run_ro() {
  PATH="$BIN:$PATH" FACTORY_PROVIDER=opencode FAKE_OUT="$OUT" \
    bash "$root_dir/scripts/station-run.sh" --read-only "$@" 2>&1
}

# Recorded before any station runs, so the origin check below can tell "the
# station removed it" from "there was never one here".
had_origin=no
if git -C "$root_dir" remote get-url origin > /dev/null 2>&1; then
  had_origin=yes
fi

tname="builder is refused --read-only"
out=$(PATH="$BIN:$PATH" FACTORY_PROVIDER=opencode \
  bash "$root_dir/scripts/station-run.sh" --read-only builder /dev/null 2>&1 || true)
[[ "$out" == *"builder cannot run --read-only"* ]] || fail "expected a refusal, got [$out]"
pass

tname="a read-only station runs outside the repo"
run_ro reviewer /dev/null > /dev/null
grep -q "^cwd=" "$OUT" || fail "fake provider never ran"
cwd=$(grep '^cwd=' "$OUT" | cut -d= -f2-)
[[ "$cwd" != "$root_dir" ]] || fail "station ran in the real repo: $cwd"
pass

tname="the read-only clone has no origin"
grep -q "^origin=.*No such remote" "$OUT" || fail "clone still has an origin: $(grep '^origin=' "$OUT")"
pass

tname="a write inside it cannot be pushed"
grep -qx "pushed=no" "$OUT" || fail "push was not refused"
pass

tname="its edits do not reach the repo"
grep -qx "edited=yes" "$OUT" || fail "the fake provider did not write, so this proves nothing"
grep -q '^set -euo pipefail$' "$root_dir/scripts/station-run.sh" \
  || fail "station-run.sh was modified by the station"
pass

# Regression: a linked worktree shares .git/config, so removing the worktree's
# origin removed the real repository's remote. That broke push while building
# #142. A clone keeps its own config.
tname="the repo keeps its own origin afterwards"
if [[ "$had_origin" == "yes" ]]; then
  git -C "$root_dir" remote get-url origin > /dev/null 2>&1 \
    || fail "the real repository lost its origin remote"
  pass
else
  # The suite itself can run inside a read-only sandbox, which has no origin by
  # design, so there is nothing to lose. Checked before the station ran rather
  # than assumed.
  echo "skip: $tname (this checkout has no origin to begin with)"
fi

tname="the sandbox is cleaned up"
[[ ! -d "$cwd" ]] || fail "sandbox left behind at $cwd"
pass

echo "all station-run read-only tests passed"
