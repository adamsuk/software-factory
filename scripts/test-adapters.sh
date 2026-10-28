#!/usr/bin/env bash
# Behaviour tests for adapters/*/run.sh. ShellCheck covers this file.
# Fake provider CLIs on PATH record their argv under $MOCK; no CLI is invoked
# for real and nothing contacts GitHub.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
MOCK=$work/mock
BIN=$work/bin
mkdir -p "$MOCK" "$BIN"

tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
pass() { echo "ok: $tname"; }
assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "expected to contain [$2], got [$1]"
}
assert_not_contains() {
  [[ "$1" != *"$2"* ]] || fail "expected NOT to contain [$2], got [$1]"
}

prompt=$work/PROMPT.md
printf 'station prompt body\n' > "$prompt"

# A fake CLI that advertises the flags named in FAKE_HELP and logs its argv.
make_fake() {
  local name=$1 help=$2
  cat > "$BIN/$name" << FAKE
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == *--help* ]]; then
  printf '%s\n' "$help"
  if [[ "\${FAKE_LARGE_HELP:-0}" == 1 ]]; then
    head -c 1048576 /dev/zero
  fi
  exit 0
fi
printf '%s\0' "\$@" >> "$MOCK/$name.argv"
previous=""
for arg in "\$@"; do
  if [[ "\$previous" == --file ]]; then
    cat -- "\$arg" > "$MOCK/$name.prompt"
  fi
  previous="\$arg"
done
if [[ "$name" == claude ]]; then
  cat > "$MOCK/claude.stdin"
fi
exit 0
FAKE
  chmod +x "$BIN/$name"
}

argv_of() { tr '\0' ' ' < "$MOCK/$1.argv"; }

run_adapter() {
  local provider=$1; shift
  PATH="$BIN:$PATH" bash "$root_dir/adapters/$provider/run.sh" "$@" 2>&1
}

# --- contract: every adapter rejects a missing prompt -----------------------
for provider in opencode grok claudecode; do
  tname="$provider rejects a missing prompt"
  make_fake "$provider" "--prompt-file --print --dir"
  out=$(run_adapter "$provider" --role reviewer || true)
  assert_contains "$out" "missing"
  pass
done

# --- opencode: no --dir when the CLI does not advertise it ------------------
tname="opencode omits --dir on a CLI without it"
rm -f "$MOCK/opencode.argv"
make_fake opencode "--auto --title --file --model"
run_adapter opencode --role reviewer --prompt "$prompt" --issue 138 >/dev/null
[[ -f "$MOCK/opencode.argv" ]] || fail "opencode was never invoked"
got=$(argv_of opencode)
assert_not_contains "$got" "--dir"
assert_contains "$got" "run"
assert_contains "$got" "--file"
assert_contains "$got" "factory:reviewer#138"
pass

# --- opencode: uses --dir when the CLI does advertise it --------------------
tname="opencode passes --dir on a CLI that supports it"
rm -f "$MOCK/opencode.argv"
make_fake opencode "--auto --dir --title --file"
run_adapter opencode --role reviewer --prompt "$prompt" >/dev/null
assert_contains "$(argv_of opencode)" "--dir"
pass

# --- grok: a missing CLI and an unsupported CLI differ ----------------------
tname="grok reports a missing CLI distinctly"
out=$(PATH="$work/empty:/usr/bin:/bin" bash "$root_dir/adapters/grok/run.sh" \
  --role reviewer --prompt "$prompt" 2>&1 || true)
assert_contains "$out" "not found in PATH"
pass

tname="grok reports an unsupported CLI distinctly"
make_fake grok "--help --version"
out=$(run_adapter grok --role reviewer --prompt "$prompt" || true)
assert_contains "$out" "does not support --prompt-file"
assert_not_contains "$out" "not found in PATH"
pass

# --- claudecode: implemented, and refuses builder for a stated reason ------
tname="claudecode refuses the builder role with a reason"
make_fake claude "--print --append-system-prompt --permission-mode"
out=$(run_adapter claudecode --role builder --prompt "$prompt" || true)
assert_contains "$out" "builder is not supported on claudecode"
pass

tname="claudecode runs a non-builder role in print mode"
rm -f "$MOCK/claude.argv"
make_fake claude "--print --append-system-prompt --permission-mode"
run_adapter claudecode --role reviewer --prompt "$prompt" --issue 138 >/dev/null
[[ -f "$MOCK/claude.argv" ]] || fail "claude was never invoked"
got=$(argv_of claude)
assert_contains "$got" "--print"
assert_contains "$got" "--permission-mode"
# AGENTS.md is handed over as the system prompt: that is this CLI's equivalent
# of grok's --rules, so a station without it would run without the rules.
assert_contains "$got" "--append-system-prompt"
assert_contains "$got" "AGENTS.md: shared rules for the software factory"
assert_contains "$(cat "$MOCK/claude.stdin")" "station prompt body"
pass

tname="claudecode reports a missing CLI distinctly"
mkdir -p "$work/empty"
out=$(PATH="$work/empty:/usr/bin:/bin" bash "$root_dir/adapters/claudecode/run.sh" \
  --role reviewer --prompt "$prompt" 2>&1 || true)
assert_contains "$out" "not found in PATH"
pass

# Relative prompts must still identify the caller's file after changing directories.
mkdir -p "$work/caller dir/nested dir"
cp "$prompt" "$work/caller dir/nested dir/PROMPT.md"
for mode in opencode-cd opencode-dir claudecode; do
  tname="$mode reads a relative prompt from another directory"
  provider=opencode
  case "$mode" in
    opencode-cd) make_fake opencode "--auto --title --file" ;;
    opencode-dir) make_fake opencode "--auto --dir --title --file" ;;
    claudecode)
      provider=claudecode
      make_fake claude "--print --append-system-prompt --permission-mode"
      ;;
  esac
  (cd "$work/caller dir" && run_adapter "$provider" --role reviewer --prompt "nested dir/PROMPT.md") >/dev/null
  if [[ "$provider" == opencode ]]; then
    assert_contains "$(argv_of opencode)" "--file $work/caller dir/nested dir/PROMPT.md"
    cmp "$prompt" "$MOCK/opencode.prompt" || fail "wrong attached prompt"
  else
    assert_contains "$(cat "$MOCK/claude.stdin")" "station prompt body"
  fi
  pass
done

# Help larger than a pipe buffer must be drained even when a flag matches early.
for provider in opencode grok claudecode; do
  tname="$provider handles large help output"
  make_fake opencode "--auto --dir --title --file"
  make_fake grok "--prompt-file"
  make_fake claude "--print --append-system-prompt --permission-mode"
  rm -f "$MOCK/opencode.argv"
  FAKE_LARGE_HELP=1 run_adapter "$provider" --role reviewer --prompt "$prompt" >/dev/null
  if [[ "$provider" == opencode ]]; then
    assert_contains "$(argv_of opencode)" "--dir"
  fi
  pass
done

echo "all adapter tests passed"
