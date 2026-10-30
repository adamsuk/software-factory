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
  mkdir -p "$r/scripts" "$r/agents" "$r/stations"
  cp "$repo/AGENTS.md" "$r/"
  cp "$repo/scripts/run-work-order.sh" "$r/scripts/"
  cp -R "$repo/agents/roles" "$r/agents/roles"
  cp "$repo/agents/grok-build.md" "$r/agents/"
  cp "$repo/stations/README.md" "$r/stations/"
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

tname="fails on a non-canonical label in stations/README.md"
r=$(fresh_root stations-label)
printf '\n| factory:wip | made up | nobody |\n' >> "$r/stations/README.md"
status=0; out=$(bash "$script" "$r") || status=$?
[[ $status -eq 1 ]] || fail "expected exit 1, got $status: $out"
grep -qF 'stations/README.md names factory:wip' <<< "$out" || fail "output does not name stations/README.md: $out"
pass

tname="does not truncate a label to a canonical prefix"
r=$(fresh_root label-suffix)
printf '\nMove the issue to factory:done-v2 when done.\n' >> "$r/agents/roles/builder.md"
status=0; out=$(bash "$script" "$r") || status=$?
[[ $status -eq 1 ]] || fail "expected exit 1, got $status: $out"
grep -qF 'factory:done-v2' <<< "$out" || fail "output accepted factory:done-v2 as canonical factory:done: $out"
pass

tname="a canonical label elsewhere in AGENTS.md does not hide a missing section 9 row"
# factory:done appears exactly once in AGENTS.md today: the section 9 table
# row. Delete that row, then mention the label again outside section 9 (after
# ## 10) -- the old whole-file search would have been satisfied by that
# mention; restricting the search to section 9 must not be.
r=$(fresh_root section9)
# shellcheck disable=SC2016  # literal backticked label text, not expansion
sed '/| `factory:done` /d' "$r/AGENTS.md" > "$r/b" && mv "$r/b" "$r/AGENTS.md"
# shellcheck disable=SC2016  # literal backticked label text, not expansion
printf '\nSee `factory:done` in section 10, not section 9.\n' >> "$r/AGENTS.md"
status=0; out=$(bash "$script" "$r") || status=$?
[[ $status -eq 1 ]] || fail "expected exit 1, got $status: $out"
grep -qF 'does not list canonical label factory:done' <<< "$out" \
  || fail "a mention outside section 9 hid the missing row: $out"
pass

tname="recognises the 'exits with code N' wording"
r=$(fresh_root exits-with-code)
sed 's/Stops (exit 4) if the change/Exits with code 99 if the change/' "$r/agents/grok-build.md" > "$r/b" && mv "$r/b" "$r/agents/grok-build.md"
status=0; out=$(bash "$script" "$r") || status=$?
[[ $status -eq 1 ]] || fail "expected exit 1, got $status: $out"
grep -qF 'exit 99' <<< "$out" || fail "'exits with code N' wording was not recognised: $out"
pass
