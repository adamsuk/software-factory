#!/usr/bin/env bash
# Offline tests for scripts/check-candidate-size.sh: the 60000-byte boundary.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$here/check-candidate-size.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
pass() { echo "ok: $tname"; }

tname="60000 bytes passes"
head -c 60000 /dev/zero | tr '\0' 'a' > "$work/ok.md"
bash "$script" "$work/ok.md" || fail "rejected 60000 bytes"
pass

tname="60001 bytes fails"
head -c 60001 /dev/zero | tr '\0' 'a' > "$work/big.md"
if out=$(bash "$script" "$work/big.md" 2>&1); then fail "accepted 60001 bytes"; fi
grep -q '60001 bytes' <<< "$out" || fail "message lacks size: $out"
pass

echo "all check-candidate-size tests passed"
