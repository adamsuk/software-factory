---
repo: adamsuk/software-factory
issue: 51
issue_repo: adamsuk/software-factory
title: "fix: stop invocation extraction at the first block; require stations/README.md"
branch: factory/51-brief-drift-check
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-brief-drift-check.sh"
setup_command: ""
changelog: false
merge_allowed: false
review_bot: coderabbit
attempt: 4
created: 2026-10-30
---

## Goal

Two more precision findings from CodeRabbit's full-review round on PR #187:

1. **The invocation extraction doesn't stop at the first block.**
   `sed -n '/run-work-order\.sh/,/^$/p'` restarts its range at *every*
   later line matching `run-work-order.sh`, not just the first. If a later
   paragraph in the section mentions the wrapper again and shows an
   unrelated flag (e.g. a setup-command option) on the next line, that
   flag gets pulled into the invocation text and checked as if it were a
   documented `run-work-order.sh` flag — a false drift report if the
   wrapper doesn't parse it.
2. **`stations/README.md` is scanned for labels but not required to
   exist.** The file-existence check near the top of the script (`for f in
   "$brief" "$wrapper" "$root/AGENTS.md"`) doesn't include it, so if it's
   missing, the label scan loop's own `[[ -f "$f" ]] || continue` silently
   skips it instead of the script exiting 2 as its own documented contract
   says ("Exit: ... 2 an input file is missing"). `agents/roles/*.md` stays
   optional (a glob, not every repo needs it) — only `stations/README.md`
   needs to move to the required list, since it's load-bearing for the
   label check the same way `AGENTS.md` is.

## What to change, in `scripts/brief-drift-check.sh`

1. Replace the `sed` range extraction with something that stops after the
   *first* matched block:
   ```diff
   -invocation=$(printf '%s\n' "$section" | sed -n '/run-work-order\.sh/,/^$/p')
   +invocation=$(printf '%s\n' "$section" | awk '
   +  /run-work-order\.sh/ && !found { found = 1 }
   +  found { print; if (/^$/) exit }
   +')
   ```
   (Exact approach is yours — the point is: only the first invocation
   block is captured, any later mention of `run-work-order.sh` elsewhere
   in the section is ignored.)
2. Add `stations/README.md` to the required-input file list near the top:
   ```diff
   -for f in "$brief" "$wrapper" "$root/AGENTS.md"; do
   +for f in "$brief" "$wrapper" "$root/AGENTS.md" "$root/stations/README.md"; do
   ```

## Tests to add in `scripts/test-brief-drift-check.sh`

- A fixture where the "What the wrapper does" section has two paragraphs
  mentioning `run-work-order.sh` — the first with the real, supported
  flags; the second (an unrelated later mention) followed by an
  unsupported flag on the next line. Confirm the check does **not** report
  drift for that second, unrelated flag (prove it only reads the first
  block).
- A fixture with `stations/README.md` removed from the root — confirm the
  script now exits 2 (currently it would silently skip the label check
  for that file instead).
- Confirm both are non-vacuous: fail against the pre-fix script, pass
  against the fix.

## Out of scope

- Everything else already fixed in earlier rounds (flag truncation,
  separate-line flags, exit-code wording, section-9 scoping, label-token
  truncation) — don't touch.
- The still-skipped "match executable behavior, not arbitrary text"
  Heavy-lift finding — still out of scope.

## Acceptance criteria

- [ ] A later, unrelated mention of `run-work-order.sh` in the section no
      longer contributes flags to the check
- [ ] A missing `stations/README.md` makes the script exit 2, not silently
      skip that file
- [ ] All existing cases in `scripts/test-brief-drift-check.sh` still pass
- [ ] `shellcheck` stays clean

## Report back

No changelog entry needed. Show the non-vacuity check for both new tests.
