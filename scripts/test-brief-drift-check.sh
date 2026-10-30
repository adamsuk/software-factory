#!/usr/bin/env bash
# Behaviour tests for scripts/brief-drift-check.sh. ShellCheck covers this file.
# Each case copies the real briefs and script into a temp root and breaks one claim.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd)
script="$here/brief-drift-check.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
pass() { echo "ok: $tname"; }

fresh_root() {
  local r=$work/$1
  mkdir -p "$r/scripts" "$r/agents"
  cp "$repo/AGENTS.md" "$r/"
  cp "$repo/scripts/run-work-order.sh" "$r/scripts/"
  cp -R "$repo/agents/roles" "$r/agents/roles"
  cp "$repo/agents/grok-build.md" "$r/agents/"
  echo "$r"
}

tname="passes on the real repo"
out=$(bash "$script" "$repo") || fail "real repo reported drift: $out"
pass

tname="fails on a documented exit code the script never uses"
r=$(fresh_root code)
sed 's/Stops (exit 4) if the change/Stops (exit 99) if the change/' "$r/agents/grok-build.md" > "$r/b" && mv "$r/b" "$r/agents/grok-build.md"
status=0; out=$(bash "$script" "$r") || status=$?
[[ $status -eq 1 ]] || fail "expected exit 1, got $status: $out"
grep -qF 'exit 99' <<< "$out" || fail "output does not name exit 99: $out"
pass

tname="fails on a documented flag the script does not parse"
r=$(fresh_root flag)
sed 's/run-work-order.sh \[--push\]/run-work-order.sh [--push] [--nonsense]/' "$r/agents/grok-build.md" > "$r/b" && mv "$r/b" "$r/agents/grok-build.md"
status=0; out=$(bash "$script" "$r") || status=$?
[[ $status -eq 1 ]] || fail "expected exit 1, got $status: $out"
grep -qF -- '--nonsense' <<< "$out" || fail "output does not name --nonsense: $out"
pass

tname="fails on a role brief naming a non-canonical label"
r=$(fresh_root label)
printf '\nMove the issue to factory:shipped when done.\n' >> "$r/agents/roles/builder.md"
status=0; out=$(bash "$script" "$r") || status=$?
[[ $status -eq 1 ]] || fail "expected exit 1, got $status: $out"
grep -qF 'agents/roles/builder.md names factory:shipped' <<< "$out" || fail "output does not name the bad label: $out"
pass

tname="fails when AGENTS.md names a non-canonical label"
r=$(fresh_root agentslabel)
printf '\nUse factory:wip here.\n' >> "$r/AGENTS.md"
status=0; out=$(bash "$script" "$r") || status=$?
[[ $status -eq 1 ]] || fail "expected exit 1, got $status: $out"
pass

tname="exits 2 when an input file is missing"
r=$(fresh_root missing)
rm "$r/agents/grok-build.md"
status=0; bash "$script" "$r" > /dev/null 2>&1 || status=$?
[[ $status -eq 2 ]] || fail "expected exit 2, got $status"
pass
