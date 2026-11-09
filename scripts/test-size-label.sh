#!/usr/bin/env bash
# Offline check for the pull request size-label caller and the reviewer brief.
# Fails when the uses: ref is not the pinned commit SHA, when a threshold is
# missing or different, or when agents/roles/reviewer.md does not name both
# size/L and size/XL. ShellCheck covers this file.
# SIZE_LABEL_ROOT points the checks at another tree. SIZE_LABEL_SELFTEST skips
# the fixture run, so a nested call does not recurse.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ -n "${SIZE_LABEL_ROOT:-}" ]]; then
  root=$SIZE_LABEL_ROOT
else
  root=$(cd "$here/.." && pwd)
fi

wf="$root/.github/workflows/size-label.yml"
reviewer="$root/agents/roles/reviewer.md"
sha=09014a5d0c8641f246411a08f303c08cd7750e24
uses_exact="adamsuk/gh-factory/.github/workflows/size-label.yml@${sha}"

fail() { echo "FAIL: $*" >&2; exit 1; }

check_uses() {
  local lines count token
  lines=$(grep -E '^[[:space:]]*uses:' "$wf" || true)
  count=$(printf '%s\n' "$lines" | grep -c . || true)
  [[ "$count" -eq 1 ]] || fail "expected one uses: line, got ${count}"
  token=$(printf '%s\n' "$lines" | sed -E 's/^[[:space:]]*uses:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]]+$//')
  [[ "$token" == "$uses_exact" ]] || fail "uses: line is not the exact SHA ${uses_exact}, got: ${token}"
}

check_threshold() {
  local key=$1 want=$2 n got
  n=$(grep -cE "^[[:space:]]*${key}:" "$wf" || true)
  [[ "$n" -eq 1 ]] || fail "threshold ${key} is missing or repeated (found ${n})"
  got=$(grep -E "^[[:space:]]*${key}:" "$wf" | sed -E "s/^[[:space:]]*${key}:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]]+$//")
  [[ "$got" == "$want" ]] || fail "threshold ${key} is '${got}', want '${want}'"
}

check_permissions() {
  local result
  # A permissions entry stays in the block only while it is indented past the
  # permissions: key. The next sibling (uses:, jobs:, a blank-less following
  # key) closes the block, so a later grant cannot paper over a dropped one.
  result=$(awk '
    function ind(s) { match(s, /^[[:space:]]*/); return RLENGTH }
    function close_block() {
      if (!open) return
      open = 0
      blocks++
      if (!has_read) print "permissions block does not grant contents: read"
      if (!has_write) print "permissions block drops pull-requests: write"
    }
    BEGIN { blocks = 0 }
    /^[[:space:]]*permissions:[[:space:]]*$/ {
      close_block()
      open = 1
      base = ind($0)
      has_read = 0
      has_write = 0
      next
    }
    open && /^[[:space:]]*$/ { next }
    open && /^[[:space:]]*#/ { next }
    open {
      if (ind($0) <= base) close_block()
      else if ($0 ~ /^[[:space:]]+contents:[[:space:]]+read[[:space:]]*$/) { has_read = 1; next }
      else if ($0 ~ /^[[:space:]]+pull-requests:[[:space:]]+write[[:space:]]*$/) { has_write = 1; next }
      else next
    }
    END { close_block(); if (blocks < 1) print "no permissions block" }
  ' "$wf")
  [[ -z "$result" ]] || fail "$result"
  if grep -Eq '^[[:space:]]+pull-requests:[[:space:]]+read[[:space:]]*$' "$wf"; then
    fail "permissions block drops pull-requests: write"
  fi
  if ! awk '
    BEGIN { found = 0 }
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { injob = 1; next }
    injob && /^    permissions:[[:space:]]*$/ { found = 1; exit }
    injob && /^[^ ]/ { injob = 0 }
    END { exit found ? 0 : 1 }
  ' "$wf"; then
    fail "calling job does not set permissions"
  fi
}

check_triggers() {
  local on_block extra
  on_block=$(awk '/^on:/{on=1; next} /^(permissions|jobs):/{on=0} on' "$wf")
  [[ -n "$on_block" ]] || fail "workflow has no on: block"
  printf '%s\n' "$on_block" | grep -Eq '^[[:space:]]*pull_request:[[:space:]]*$' \
    || fail "workflow is not on pull_request"
  printf '%s\n' "$on_block" | grep -Eq '^[[:space:]]*types:[[:space:]]*\[opened, synchronize, reopened\][[:space:]]*$' \
    || fail "pull_request types must be opened, synchronize, reopened only"
  extra=$(printf '%s\n' "$on_block" | grep -E '^  [A-Za-z0-9_]+:' | grep -v 'pull_request:' || true)
  [[ -z "$extra" ]] || fail "pull_request is not the only trigger: ${extra}"
}

check_caller_shape() {
  local jobs
  jobs=$(awk '
    /^jobs:/ { injobs = 1; next }
    injobs && /^[^ ]/ { injobs = 0 }
    injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { n++ }
    END { print n + 0 }
  ' "$wf")
  [[ "$jobs" -eq 1 ]] || fail "expected one job, got ${jobs}"
  if grep -Eq '^[[:space:]]*steps:' "$wf"; then
    fail "caller copies steps; the callee shell stays in gh-factory"
  fi
  if grep -Eq '^[[:space:]]*(label_prefix|exclude_paths):' "$wf"; then
    fail "label_prefix and exclude_paths must stay at the callee defaults"
  fi
}

check_reviewer() {
  local station verdict
  [[ -f "$reviewer" ]] || fail "missing ${reviewer}"
  grep -Fq 'size/L' "$reviewer" || fail "agents/roles/reviewer.md does not name size/L"
  grep -Fq 'size/XL' "$reviewer" || fail "agents/roles/reviewer.md does not name size/XL"
  station=$(awk '/^## Station/{on=1; next} /^## /{on=0} on' "$reviewer")
  [[ -n "$station" ]] || fail "reviewer Station header not found"
  printf '%s\n' "$station" | grep -Fq 'size/L' || fail "Station header does not name size/L"
  printf '%s\n' "$station" | grep -Fq 'size/XL' || fail "Station header does not name size/XL"
  verdict=$(awk '/^6\. \*\*Independent verdict\.\*\*/{on=1} /^## Outputs/{on=0} on' "$reviewer")
  [[ -n "$verdict" ]] || fail "Independent verdict step not found"
  printf '%s\n' "$verdict" | grep -Fq 'size/L' || fail "Independent verdict step does not name size/L"
  printf '%s\n' "$verdict" | grep -Fq 'size/XL' || fail "Independent verdict step does not name size/XL"
  printf '%s\n' "$verdict" | grep -Fq 'The verdict names which of those two labels is on the head.' \
    || fail "Independent verdict step does not name which size label is on the head"
  if printf '%s\n' "$reviewer" | grep -Eq 'few hundred|~10 files|judge size from the diff|No CI size-label workflow runs'; then
    fail "reviewer brief still judges L/XL by eye"
  fi
}

[[ -f "$wf" ]] || fail "missing ${wf}"
check_uses
check_threshold xs_lines 10
check_threshold s_lines 50
check_threshold m_lines 200
check_threshold l_lines 500
check_permissions
check_triggers
check_caller_shape
check_reviewer
echo "ok: size-label workflow and reviewer brief"

if [[ -z "${SIZE_LABEL_SELFTEST:-}" ]]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  seed() {
    local dest=$1
    mkdir -p "$dest/.github/workflows" "$dest/agents/roles"
    cp "$wf" "$dest/.github/workflows/size-label.yml"
    cp "$reviewer" "$dest/agents/roles/reviewer.md"
  }

  expect_fail() {
    local name=$1 dir=$2 needle=$3 out
    if out=$(SIZE_LABEL_SELFTEST=1 SIZE_LABEL_ROOT="$dir" bash "${BASH_SOURCE[0]}" 2>&1); then
      fail "selftest ${name}: expected failure but the check passed"
    elif [[ "$out" != *"$needle"* ]]; then
      fail "selftest ${name}: failed without \"${needle}\": ${out}"
    fi
    echo "ok: selftest ${name}"
  }

  seed "$tmp/good"
  if ! SIZE_LABEL_SELFTEST=1 SIZE_LABEL_ROOT="$tmp/good" bash "${BASH_SOURCE[0]}" >/dev/null; then
    fail "selftest good fixture was rejected"
  fi
  echo "ok: selftest good fixture passes"

  seed "$tmp/sha"
  sed -i "s/${sha}/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/" "$tmp/sha/.github/workflows/size-label.yml"
  expect_fail "wrong sha" "$tmp/sha" "uses: line is not the exact SHA"

  seed "$tmp/threshold"
  sed -i 's/xs_lines: 10/xs_lines: 11/' "$tmp/threshold/.github/workflows/size-label.yml"
  expect_fail "different threshold" "$tmp/threshold" "threshold xs_lines is '11'"

  seed "$tmp/missing"
  sed -i '/s_lines: 50/d' "$tmp/missing/.github/workflows/size-label.yml"
  expect_fail "missing threshold" "$tmp/missing" "threshold s_lines is missing"

  seed "$tmp/reviewer"
  sed -i 's|size/XL|size/BIG|g' "$tmp/reviewer/agents/roles/reviewer.md"
  expect_fail "reviewer omits size/XL" "$tmp/reviewer" "does not name size/XL"
fi
